import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/demo.dart';
import '../../../data/keys.dart';
import '../../../data/sources.dart';
import '../../../domain/recs.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

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

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(recsProvider).value ?? const RecsState();
    final ranked = ref.watch(rankedRecsProvider);
    final lib = ref.watch(libraryProvider).value ?? const [];
    final seeds = {for (final p in lib) if (p.stashId.isNotEmpty) p.stashId: p};
    final topSeeds = (seeds.values.toList()..sort((a, b) => seedWeight(b).compareTo(seedWeight(a)))).take(3).toList();
    final age = st.at == 0 ? '' : _ago(st.at);
    return Scaffold(body: SafeArea(bottom: false, child: RefreshIndicator(onRefresh: () => ref.read(recsProvider.notifier).refresh(), child: CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('اكتشف', style: Theme.of(context).textTheme.headlineSmall),
          Text(st.busy ? st.msg : (age.isEmpty ? 'اقتراحات من StashDB مبنية على مكتبتك' : 'آخر تحديث $age · ${ranked.length} مرشحة'), style: const TextStyle(color: C.muted)),
        ])),
        IconButton.filledTonal(tooltip: 'تجديد', onPressed: st.busy ? null : () => ref.read(recsProvider.notifier).refresh(), icon: st.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded)),
      ]))),
      if (st.err.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(st.err, style: const TextStyle(color: C.danger)),
        if (st.err.contains('مفتاح')) Padding(padding: const EdgeInsets.only(top: S.s2), child: FilledButton.icon(onPressed: () => context.go('/more'), icon: const Icon(Icons.key_rounded), label: const Text('أضيفي مفتاح StashDB (من «المزيد»)'))),
      ]))),
      if (ranked.isEmpty && !st.busy)
        SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'اقتراحات تعرف ذوقك',
          body: seeds.isEmpty ? 'اربطي بعض ممثلات مكتبتك بـ StashDB (من صفحتها ⋮ ← ربط بمصدر) ليبدأ التحليل.' : 'اضغطي «تجديد» لتحليل ${seeds.length} ممثلة مرتبطة في مكتبتك.\nكل اقتراح يأتي مع سببه، والأعمار تُتحقق قبل عرض أي صورة.',
          actions: [FilledButton.icon(onPressed: () => ref.read(recsProvider.notifier).refresh(), icon: const Icon(Icons.auto_awesome_rounded), label: const Text('ابدأ'))]))
      else ...[
        _lane(context, ref, '☀️ اكتشاف اليوم', 'تتجدد كل يوم، متنوعة البلدان', dailyPick(ranked)),
        for (final sp in topSeeds) _lane(context, ref, '👯 لأنك تحبين ${sp.name}', 'عملن معها في مشاهد مشتركة', ranked.where((c) => c.withSeeds.contains(sp.stashId)).toList()),
        _lane(context, ref, '🌱 اكتشافات 18–21', 'تاريخ ميلاد كامل من StashDB · العمر محسوب اليوم', ranked.where((c) => c.young18to21).toList(), showAge: true),
        _lane(context, ref, '✨ وجوه جديدة', 'الأحدث ظهورًا في المجال', ranked.where((c) => c.lanes.contains('debut')).toList()),
        _lane(context, ref, '🌍 من بلدانك المفضلة', '', ranked.where((c) => c.lanes.contains('country')).toList()),
        _lane(context, ref, '📈 الأعلى توافقًا', '', ranked.take(20).toList()),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 140)),
    ]))));
  }

  static String _ago(int t) { final m = (DateTime.now().millisecondsSinceEpoch - t) ~/ 60000; return m < 1 ? 'الآن' : m < 60 ? 'قبل $m د' : m < 1440 ? 'قبل ${m ~/ 60} س' : 'قبل ${m ~/ 1440} يوم'; }

  Widget _lane(BuildContext context, WidgetRef ref, String title, String sub, List<RecCand> l, {bool showAge = false}) {
    if (l.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title, sub: sub.isEmpty ? null : sub),
      SizedBox(height: 262, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), itemCount: l.length,
        separatorBuilder: (_, _) => const SizedBox(width: S.s3), itemBuilder: (c, i) => SizedBox(width: 150, child: _RecCard(c: l[i], showAge: showAge)))),
    ]));
  }
}

class _RecCard extends ConsumerWidget {
  const _RecCard({required this.c, this.showAge = false});
  final RecCand c; final bool showAge;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!c.adult) return const SizedBox.shrink(); // حارس إضافي: لا صورة لغير البالغة
    final pct = (40 + c.score * 58).round().clamp(40, 98);
    return Semantics(button: true, label: c.name, child: GestureDetector(onTap: () => _sheet(context, ref), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(aspectRatio: 3 / 4, child: ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: Stack(fit: StackFit.expand, children: [
        Photo(c.image, name: c.name, cacheWidth: 360),
        Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xCC0A0810), borderRadius: BorderRadius.circular(99)), child: Text('$pct٪', style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 12)))),
      ]))),
      const SizedBox(height: 6),
      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text([if (c.age != null) '${c.age} سنة', if (c.country.isNotEmpty) c.country].join(' · '), style: const TextStyle(color: C.muted, fontSize: 12)),
      if (showAge && c.young18to21) Text('✓ موثّق: ${c.birth}', style: const TextStyle(color: C.ok, fontSize: 11)),
      if (c.reasons.isNotEmpty) Text(c.reasons.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.gold, fontSize: 11.5)),
    ])));
  }

  void _sheet(BuildContext context, WidgetRef ref) => showModalBottomSheet(context: context, builder: (sc) => Padding(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s5), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(S.rMd), child: SizedBox(width: 90, height: 120, child: Photo(c.image, name: c.name, cacheWidth: 240))),
      const SizedBox(width: S.s3),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name, style: Theme.of(sc).textTheme.titleLarge),
        Text([if (c.age != null) '${c.age} سنة', if (c.country.isNotEmpty) c.country, if (c.scenes != null) '${c.scenes} مشهد'].join(' · '), style: const TextStyle(color: C.muted)),
      ])),
    ]),
    const SizedBox(height: S.s3),
    const Text('لماذا هذا الاقتراح؟', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700)),
    for (final r in c.reasons.isEmpty ? ['شائعة في StashDB'] : c.reasons) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $r')),
    const SizedBox(height: S.s4),
    Row(children: [
      Expanded(child: FilledButton.icon(onPressed: () { Navigator.pop(sc); context.push('/search?q=${Uri.encodeQueryComponent(c.name)}'); }, icon: const Icon(Icons.add_rounded), label: const Text('إضافة لمكتبتي'))),
      const SizedBox(width: S.s2),
      OutlinedButton.icon(onPressed: () { ref.read(recsProvider.notifier).hide(c.id); Navigator.pop(sc); }, icon: const Icon(Icons.visibility_off_rounded), label: const Text('ليست ذوقي')),
    ]),
  ])));
}
