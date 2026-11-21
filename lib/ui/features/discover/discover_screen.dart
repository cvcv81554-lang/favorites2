import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/demo.dart';
import '../../../data/keys.dart';
import '../../../data/sources.dart';
import '../../../domain/performer.dart';
import '../../../domain/recs.dart';
import '../../../domain/taste.dart' show catFields, numFields, fieldNames;
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../sources/source_search.dart' show syncFromSources;
import 'taste_state.dart';

/// مخزون الاقتراحات (محفوظ على الجهاز) + المخفيات.
class RecsState { final List<RecCand> pool; final int at; final Set<String> hidden; final bool busy; final String msg, err;
  const RecsState({this.pool = const [], this.at = 0, this.hidden = const {}, this.busy = false, this.msg = '', this.err = ''});
  RecsState copy({List<RecCand>? pool, int? at, Set<String>? hidden, bool? busy, String? msg, String? err}) => RecsState(pool: pool ?? this.pool, at: at ?? this.at, hidden: hidden ?? this.hidden, busy: busy ?? this.busy, msg: msg ?? this.msg, err: err ?? this.err); }

class Recs extends AsyncNotifier<RecsState> {
  @override
  Future<RecsState> build() async {
    final repo = await ref.watch(repoProvider.future);
    if (kIsWeb && Uri.base.queryParameters['demo'] == '1') return RecsState(pool: [for (final x in demoRecPool()) RecCand.fromJson(x)], at: DateTime.now().millisecondsSinceEpoch);
    final j = await repo.kvGet('recs_pool') as Map?;
    final h = (await repo.kvGet('recs_hidden') as List?)?.cast<String>().toSet() ?? <String>{};
    return RecsState(pool: [for (final x in (j?['list'] as List? ?? const [])) RecCand.fromJson(Map<String, dynamic>.from(x as Map))], at: (j?['at'] as num?)?.toInt() ?? 0, hidden: h);
  }
  RecsState get s => state.value ?? const RecsState();

  Future<void> refresh() async {
    if (s.busy) return;
    if (!await ApiKeys.has(ApiKeys.stash)) { state = AsyncData(s.copy(err: 'أضف مفتاح StashDB من «المزيد» لتعمل الاقتراحات.')); return; }
    final lib = ref.read(libraryProvider).value ?? const [];
    final seeds = (lib.where((p) => p.stashId.isNotEmpty && !p.isMinor).toList()..sort((a, b) => seedWeight(b).compareTo(seedWeight(a)))).take(12).map((p) => (p.stashId, seedWeight(p))).toList();
    final cc = <String, int>{}; for (final p in lib) { if (p.country.length == 2) cc[p.country.toUpperCase()] = (cc[p.country.toUpperCase()] ?? 0) + 1; }
    final countries = (cc.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).toList();
    state = AsyncData(s.copy(busy: true, err: '', msg: 'بدء التحليل…'));
    try {
      final raw = await stashRecPool(seeds: seeds, countries: countries, progress: (m) => state = AsyncData(s.copy(msg: m)));
      final pool = [for (final x in raw) RecCand.fromJson(x)];
      final now = DateTime.now().millisecondsSinceEpoch;
      final repo = await ref.read(repoProvider.future);
      await repo.kvSet('recs_pool', {'at': now, 'list': [for (final c in pool) c.toJson()]});
      state = AsyncData(s.copy(pool: pool, at: now, busy: false, msg: ''));
    } catch (e) { state = AsyncData(s.copy(busy: false, msg: '', err: '$e')); }
  }

  Future<void> hide(String id) async {
    final h = {...s.hidden, id};
    await (await ref.read(repoProvider.future)).kvSet('recs_hidden', h.toList());
    state = AsyncData(s.copy(hidden: h));
  }
}
final recsProvider = AsyncNotifierProvider<Recs, RecsState>(Recs.new);

final rankedRecsProvider = Provider<List<RecCand>>((ref) {
  final st = ref.watch(recsProvider).value; if (st == null) return const [];
  return rankRecs(st.pool, ref.watch(libraryProvider).value ?? const [], hidden: st.hidden);
});

/// «اكتشف» مبني بالكامل على تحليل ذوقك: ملف الذوق (أشرطة) ← مسارات من التحليل (كل اسم يظهر مرة واحدة) ← ضبط التحليل.
/// إن لم يُحلَّل بعد أو كانت البيانات غير كافية: شرح واضح + ربط المفضلات + اقتراحات عامة مؤقتة.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tasteProvider).value ?? const TasteState();
    final tn = ref.read(tasteProvider.notifier);
    final lib = ref.watch(libraryProvider).value ?? const [];
    final unlinkedFavs = lib.where((p) => p.fav && p.stashId.isEmpty && p.pdbId.isEmpty && !p.isMinor).toList();
    final ready = t.at > 0 && !t.insufficient && t.recs.isNotEmpty;

    // المسارات: كل اسم مرة واحدة فقط في الصفحة
    final shown = <String>{};
    List<TasteRec> take(Iterable<TasteRec> src, int n) { final out = <TasteRec>[]; for (final r in src) { if (out.length >= n) break; if (shown.add(r.id)) out.add(r); } return out; }
    final d = DateTime.now();
    final daily = () { final l = t.recs.take(60).toList()..shuffle(Random(d.year * 400 + d.month * 32 + d.day)); final cc = <String, int>{};
      return l.where((r) => (cc[r.country] = (cc[r.country] ?? 0) + 1) <= 3); }();
    final topCountry = t.bars.where((b) => b.field == 'country' && b.strong).firstOrNull?.items.first.$1;
    final lanes = <(String, String, List<TasteRec>, bool)>[];
    if (ready) {
      lanes.add(('☀️ اختيار اليوم', 'يتجدد كل يوم · متنوّع البلدان', take(daily, 12), false));
      for (final w in t.withNames) { lanes.add(('👯 لأنك تحب ${w.$2}', 'عملن معها، ويشبهن ذوقك', take(t.recs.where((r) => r.tags.contains('with:${w.$1}')), 12), false)); }
      lanes.add(('✨ وجوه جديدة تناسبك', 'بدأن خلال آخر 3 سنوات', take(t.recs.where((r) => r.tags.contains('debut')), 12), false));
      lanes.add(('🌱 18–21 تناسب ذوقك', 'تاريخ ميلاد كامل من StashDB · العمر محسوب اليوم', take(t.recs.where((r) => r.tags.contains('young')), 12), true));
      if (topCountry != null) lanes.add(('🌍 من $topCountry', 'البلد الأكثر بين مفضلاتك', take(t.recs.where((r) => r.tags.contains('country')), 12), false));
      lanes.add(('🧭 خارج المألوف', 'تشبه ذوقك مع اختلاف واضح — للتنويع', take(t.recs.where((r) => r.tags.contains('explore')), 12), false));
      lanes.add(('🎯 الأقرب لذوقك', 'الأعلى توافقًا مع ملفك', take(t.recs, 20), false));
    }
    if (ready) WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen(ref, [for (final l in lanes) ...l.$3.take(4)]));

    return Scaffold(body: SafeArea(bottom: false, child: RefreshIndicator(onRefresh: tn.analyze, child: CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('اكتشف', style: Theme.of(context).textTheme.headlineSmall),
          Text(t.busy ? t.msg : t.at == 0 ? 'اقتراحات مبنية على تحليل ذوقك' : 'حسب تحليل ذوقك · ${_ago(t.at)} · ${t.recs.length} مرشحة', style: const TextStyle(color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        IconButton.filledTonal(tooltip: 'ضبط التحليل', onPressed: () => _settings(context, ref), icon: const Icon(Icons.tune_rounded)),
        const SizedBox(width: 6),
        IconButton.filled(tooltip: 'حدّث التحليل', onPressed: t.busy ? null : tn.analyze, icon: t.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded)),
      ]))),
      if (t.busy) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: ClipRRect(borderRadius: BorderRadius.circular(99), child: const LinearProgressIndicator(minHeight: 4)))),
      if (t.err.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: Row(children: [
        Expanded(child: Text(t.err, style: const TextStyle(color: C.danger))),
        if (t.err.contains('مفتاح')) TextButton.icon(onPressed: () => context.go('/more'), icon: const Icon(Icons.key_rounded), label: const Text('المفتاح')),
      ]))),
      SliverToBoxAdapter(child: TasteCard(unlinked: unlinkedFavs.length)),
      if (t.at > 0 && (t.insufficient || unlinkedFavs.isNotEmpty) && unlinkedFavs.isNotEmpty) SliverToBoxAdapter(child: _LinkFavs(l: unlinkedFavs)),
      for (final l in lanes) if (l.$3.isNotEmpty) _lane(l.$1, l.$2, l.$3, l.$4),
      if (!ready) ..._fallback(context, ref, t),
      const SliverToBoxAdapter(child: SizedBox(height: 140)),
    ]))));
  }

  static int _seenDay = 0;
  static void _markSeen(WidgetRef ref, List<TasteRec> l) { final d = DateTime.now().day; if (_seenDay == d) return; _seenDay = d; ref.read(tasteProvider.notifier).seen(l.map((r) => r.id)); }

  static String _ago(int t) { final m = (DateTime.now().millisecondsSinceEpoch - t) ~/ 60000; return m < 1 ? 'الآن' : m < 60 ? 'قبل $m د' : m < 1440 ? 'قبل ${m ~/ 60} س' : 'قبل ${m ~/ 1440} يوم'; }

  static Widget _lane(String title, String sub, List<TasteRec> l, bool showAge) => SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHeader(title, sub: sub.isEmpty ? null : sub),
    SizedBox(height: 286, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), itemCount: l.length,
      separatorBuilder: (_, _) => const SizedBox(width: S.s3), itemBuilder: (c, i) => SizedBox(width: 156, child: TasteRecCard(r: l[i], showAge: showAge)))),
  ]));

  /// قبل التحليل أو عند نقص البيانات: الاقتراحات العامة القديمة (من «عملن مع» مكتبتك) — مؤقتًا وبعنوان واضح.
  List<Widget> _fallback(BuildContext context, WidgetRef ref, TasteState t) {
    final ranked = ref.watch(rankedRecsProvider);
    final st = ref.watch(recsProvider).value ?? const RecsState();
    if (t.busy) return const [];
    if (ranked.isEmpty) {
      return [SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(S.s4), child: OutlinedButton.icon(onPressed: st.busy ? null : () => ref.read(recsProvider.notifier).refresh(),
        icon: st.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.people_alt_rounded),
        label: Text(st.busy ? st.msg : 'اقتراحات عامة من مكتبتك (حتى يكتمل التحليل)'))))];
    }
    return [
      const SliverToBoxAdapter(child: SectionHeader('اقتراحات عامة', sub: 'من «عملن مع» ممثلات مكتبتك — ستُستبدل باقتراحات ذوقك بعد التحليل')),
      SliverToBoxAdapter(child: SizedBox(height: 262, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), itemCount: min(20, ranked.length),
        separatorBuilder: (_, _) => const SizedBox(width: S.s3), itemBuilder: (c, i) => SizedBox(width: 150, child: _RecCard(c: ranked[i]))))),
    ];
  }

  /// ضبط التحليل: اختر الخصائص التي تهمك (تُطبَّق عند «حدّث»).
  static void _settings(BuildContext context, WidgetRef ref) => showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (c) => Consumer(builder: (c, ref, _) {
    final t = ref.watch(tasteProvider).value ?? const TasteState();
    return ListView(padding: const EdgeInsets.all(S.s4), shrinkWrap: true, children: [
      Text('ضبط التحليل', style: Theme.of(c).textTheme.titleLarge),
      const Text('اختر ما يُحسب في ذوقك. البيانات من StashDB الموثّقة فقط، ولا شيء يُستنتج من الصور.', style: TextStyle(color: C.muted)),
      const SizedBox(height: S.s2),
      for (final f in [...catFields, ...numFields]) SwitchListTile(dense: true, value: !t.ignore.contains(f), title: Text(fieldNames[f] ?? f), onChanged: (_) => ref.read(tasteProvider.notifier).toggleField(f)),
      const SizedBox(height: S.s2),
      FilledButton.icon(onPressed: () { Navigator.pop(c); ref.read(tasteProvider.notifier).analyze(); }, icon: const Icon(Icons.auto_awesome_rounded), label: const Text('حدّث التحليل الآن')),
      const SizedBox(height: S.s3),
      const Text('التعلّم: كل «إضافة لمكتبتي» تقوّي خصائصها، وكل «ليست ذوقي» تُضعفها وتُخفيها. المرشحة التي تتكرر دون تفاعل تتراجع تدريجيًا.', style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.6)),
    ]);
  }));
}

/// مفضلات غير مرتبطة بأي مصدر ⇒ لا تدخل التحليل. ربط تلقائي بالمصدرين معًا (لمن لها تاريخ ميلاد كامل) أو ربط يدوي لكل واحدة.
class _LinkFavs extends ConsumerStatefulWidget {
  const _LinkFavs({required this.l});
  final List<Performer> l;
  @override ConsumerState<_LinkFavs> createState() => _LinkFavsState();
}
class _LinkFavsState extends ConsumerState<_LinkFavs> {
  String _msg = ''; bool _busy = false;
  Future<void> _auto() async {
    final auto = widget.l.where((p) => RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(p.birth)).toList();
    if (auto.isEmpty) { setState(() => _msg = 'لا توجد مفضلة بتاريخ ميلاد كامل — اربطها يدويًا من الأزرار.'); return; }
    setState(() => _busy = true); var ok = 0;
    for (final p in auto) {
      if (!mounted) return;
      setState(() => _msg = 'ربط ${p.name}…');
      try { final r = await syncFromSources(ref, existing: p); if (r.$1 != null && (r.$1!.stashId.isNotEmpty || r.$1!.pdbId.isNotEmpty)) ok++; } catch (_) {}
    }
    if (mounted) setState(() { _busy = false; _msg = 'رُبطت $ok من ${auto.length} — اضغط ✨ لتحديث التحليل.'; });
  }
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: Container(
    padding: const EdgeInsets.all(S.s3), decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.l.length} من مفضلاتك خارج التحليل', style: const TextStyle(fontWeight: FontWeight.w700)),
      const Text('غير مرتبطة بـ StashDB ولا ThePornDB. اربطها ليصبح التحليل أدق.', style: TextStyle(color: C.muted, fontSize: 12.5)),
      const SizedBox(height: S.s2),
      FilledButton.tonalIcon(onPressed: _busy ? null : _auto, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.merge_rounded),
        label: const Text('ربط تلقائي بالمصدرين (لمن لها تاريخ ميلاد كامل)')),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_msg, style: const TextStyle(color: C.muted, fontSize: 12))),
      const SizedBox(height: S.s2),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final p in widget.l.take(20)) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ActionChip(avatar: const Icon(Icons.link_rounded, size: 16), label: Text(p.name),
          onPressed: () => context.push('/search?q=${Uri.encodeQueryComponent(p.name)}&link=${p.id}'))),
      ])),
    ])));
}

/// بطاقة مرشحة: نسبة التوافق + الاسم + العمر والبلد + السبب الأول. الضغط يفتح ملفها الكامل.
class TasteRecCard extends ConsumerWidget {
  const TasteRecCard({super.key, required this.r, this.showAge = false});
  final TasteRec r; final bool showAge;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(button: true, label: r.name, child: GestureDetector(
    onTap: () => openCandidate(context, ref, r.id, [...r.why, for (final d in r.diff) 'يختلف: $d']),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(aspectRatio: 3 / 4, child: ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: Stack(fit: StackFit.expand, children: [
        Photo(r.image, name: r.name),
        Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xCC0A0810), borderRadius: BorderRadius.circular(99)),
          child: Text('${r.pct}٪', style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w800, fontSize: 12)))),
        if (r.tags.any((x) => x.startsWith('with:'))) const Positioned(top: 8, right: 8, child: Icon(Icons.people_alt_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 4)])),
      ]))),
      const SizedBox(height: 6),
      Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text([if (r.age != null) '${r.age} سنة', if (r.country.isNotEmpty) r.country].join(' · '), style: const TextStyle(color: C.muted, fontSize: 12)),
      if (showAge && r.birth.length >= 10) Text('✓ موثّق: ${r.birth}', style: const TextStyle(color: C.ok, fontSize: 11)),
      if (r.why.isNotEmpty) Text(r.why.first, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.gold, fontSize: 11.5, height: 1.3)),
    ])));
}

class _RecCard extends ConsumerWidget {
  const _RecCard({required this.c});
  final RecCand c;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!c.adult) return const SizedBox.shrink(); // حارس إضافي: لا صورة لغير البالغة
    final pct = (40 + c.score * 58).round().clamp(40, 98);
    return Semantics(button: true, label: c.name, child: GestureDetector(onTap: () => openCandidate(context, ref, c.id, c.reasons), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(aspectRatio: 3 / 4, child: ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: Stack(fit: StackFit.expand, children: [
        Photo(c.image, name: c.name),
        Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xCC0A0810), borderRadius: BorderRadius.circular(99)), child: Text('$pct٪', style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 12)))),
      ]))),
      const SizedBox(height: 6),
      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text([if (c.age != null) '${c.age} سنة', if (c.country.isNotEmpty) c.country].join(' · '), style: const TextStyle(color: C.muted, fontSize: 12)),
      if (c.reasons.isNotEmpty) Text(c.reasons.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.gold, fontSize: 11.5)),
    ])));
  }
}


/// فتح مرشحة: إن كانت في المكتبة ⇒ ملفها، وإلا ⇒ ملف المرشحة من StashDB (مع أسباب الاقتراح).
void openCandidate(BuildContext context, WidgetRef ref, String stashId, List<String> why) {
  final have = ref.read(libraryProvider).value?.where((p) => p.stashId == stashId).firstOrNull;
  if (have != null) { context.push('/p/${have.id}'); return; }
  context.push('/c/$stashId', extra: why);
}

/// «ملف ذوقك»: ما تشترك فيه مفضلاتك (أشرطة بنسب حقيقية من بيانات StashDB الموثّقة فقط)، أو دعوة للتحليل.
class TasteCard extends ConsumerWidget {
  const TasteCard({super.key, this.unlinked = 0});
  final int unlinked;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tasteProvider).value ?? const TasteState();
    final n = ref.read(tasteProvider.notifier);
    final deco = BoxDecoration(borderRadius: BorderRadius.circular(S.rXl), gradient: const LinearGradient(colors: [Color(0xFF2E1830), Color(0xFF15101E)], begin: Alignment.topRight, end: Alignment.bottomLeft), border: Border.all(color: C.gold.withValues(alpha: .35)));
    Widget head(String sub) => Row(children: [
      const Text('🧬', style: TextStyle(fontSize: 22)), const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ملف ذوقك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.gold2)),
        if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: C.muted, fontSize: 12)),
      ])),
    ]);
    if (t.at == 0) {
      return Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Container(padding: const EdgeInsets.all(S.s4), decoration: deco, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        head(''),
        const SizedBox(height: S.s2),
        const Text('«اكتشف» كله مبني على ذوقك: أحلل مفضلاتك من بياناتهن المهنية الموثّقة في StashDB (العرق، الشعر، العيون، الطول، العمر، بداية المسيرة، الوشوم…) — المفضلة الأعلى تقييمًا تزن أكثر — ثم أقترح ممثلات يشبهنها، ولكل اقتراح سببه. لا يُستنتج شيء من الصور.', style: TextStyle(color: C.muted, height: 1.6)),
        if (unlinked > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('ملاحظة: $unlinked من مفضلاتك غير مرتبطة بـ StashDB ولن تدخل التحليل.', style: const TextStyle(color: C.gold, fontSize: 12.5))),
        const SizedBox(height: S.s3),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: t.busy ? null : n.analyze, icon: const Icon(Icons.auto_awesome_rounded), label: Text(t.busy ? t.msg : 'حلّل ذوقي'))),
      ])));
    }
    final strong = t.bars.where((b) => b.strong).toList();
    final show = (strong.isNotEmpty ? strong : t.bars).take(4).toList();
    return Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: InkWell(borderRadius: BorderRadius.circular(S.rXl), onTap: () => _details(context, t), child: Container(padding: const EdgeInsets.all(S.s4), decoration: deco, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      head('من ${t.analyzed} من ${t.total} · ${t.basis}'),
      const SizedBox(height: S.s3),
      if (t.insufficient) const Padding(padding: EdgeInsets.only(bottom: S.s2), child: Text('البيانات غير كافية لتحليل دقيق: أحتاج 3 مفضلات على الأقل مرتبطة بـ StashDB. اربط مفضلاتك من الأسفل ثم حدّث.', style: TextStyle(color: C.gold, height: 1.6))),
      for (final b in show) _bar(b),
      if (!t.insufficient && show.isEmpty) const Text('لا نمط واضح: ذوقك متنوع جدًا في الخصائص الموثّقة.', style: TextStyle(color: C.muted)),
      const SizedBox(height: 4),
      const Align(alignment: AlignmentDirectional.centerEnd, child: Text('التفاصيل ›', style: TextStyle(color: C.gold, fontSize: 12.5, fontWeight: FontWeight.w600))),
    ]))));
  }

  static Widget _bar(TraitBar b) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const Spacer(),
      Text('${b.items.first.$1} ${(b.items.first.$2 * 100).round()}٪', style: const TextStyle(color: C.gold2, fontSize: 12.5, fontWeight: FontWeight.w700))]),
    const SizedBox(height: 4),
    ClipRRect(borderRadius: BorderRadius.circular(99), child: SizedBox(height: 8, child: Row(children: [
      for (final (k, x) in b.items.indexed) Expanded(flex: max(1, (x.$2 * 1000).round()), child: Container(color: [C.gold, C.rose, const Color(0xFF8E7CC3)][k % 3])),
      if (b.items.fold<double>(0, (s, x) => s + x.$2) < .999) Expanded(flex: max(1, ((1 - b.items.fold<double>(0, (s, x) => s + x.$2)) * 1000).round()), child: Container(color: C.surface2)),
    ]))),
    if (b.items.length > 1) Padding(padding: const EdgeInsets.only(top: 3), child: Text(b.items.skip(1).map((x) => '${x.$1} ${(x.$2 * 100).round()}٪').join(' · '), style: const TextStyle(color: C.muted, fontSize: 11.5))),
  ]));

  static void _details(BuildContext context, TasteState t) => showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (c) => DraggableScrollableSheet(expand: false, initialChildSize: .75, builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.all(S.s4), children: [
    Text('ملف ذوقك بالتفصيل', style: Theme.of(c).textTheme.titleLarge),
    Text('من ${t.analyzed} ممثلة لها بيانات موثّقة (من ${t.total}) · ${t.basis}', style: const TextStyle(color: C.muted)),
    const SizedBox(height: S.s3),
    for (final b in t.bars) _bar(b),
    const Divider(color: C.line),
    for (final l in t.lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $l', style: const TextStyle(height: 1.5))),
    const SizedBox(height: S.s3),
    const Text('المصدر: حقول StashDB الوصفية لمفضلاتك فقط. الشريط يُظهر النسبة الموزونة بتقييمك (المفضلة الأعلى تقييمًا تزن أكثر).', style: TextStyle(color: C.muted, fontSize: 12)),
  ])));
}
