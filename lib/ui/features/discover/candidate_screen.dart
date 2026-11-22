import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/dual_source.dart';
import '../../../data/photo_hash.dart';
import '../../../data/sources.dart';
import '../../../domain/age_gate.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../sources/source_search.dart';
import 'discover_screen.dart' show recsProvider;
import '../../../domain/taste.dart' show attrLabel;
import 'taste_state.dart';

/// الملف الشخصي لمرشحة من «اكتشف» (ليست في مكتبتك بعد): بياناتها وصورها وأعمالها من StashDB وThePornDB معًا (كل سجلاتها)،
/// مع «إضافة لمكتبتي» و«ليست ذوقي». إن كانت في المكتبة يُفتح ملفها مباشرة.
/// البوابة: إن قال التاريخ أقل من 18 أو كان غير صالح ⇒ لا صور ولا أعمال ولا إضافة.
class CandidateScreen extends ConsumerStatefulWidget {
  const CandidateScreen({super.key, required this.stashId, this.why = const []});
  final String stashId; final List<String> why;
  @override ConsumerState<CandidateScreen> createState() => _CandidateScreenState();
}

class _CandidateScreenState extends ConsumerState<CandidateScreen> {
  Map<String, dynamic>? _p; List<Map<String, dynamic>> _works = []; List<String> _extra = []; String _pdb = '', _sid = ''; int _records = 1; String _err = ''; bool _loading = true, _adding = false;
  final _pc = PageController(viewportFraction: .86); int _page = 0;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _pc.dispose(); super.dispose(); }

  bool get _isT => widget.stashId.startsWith('tp:');
  String get _rid => _isT ? widget.stashId.substring(3) : widget.stashId;
  String _srcLabel = '';

  Future<void> _load() async {
    // في المكتبة (بأي سجل من سجلاتها)؟ افتح ملفها الحقيقي
    final lib = await ref.read(libraryProvider.future);   // تُنتظر المكتبة (فتح مباشر قبل تحميلها لا يتجاوز الفحص)
    final have = lib.where((p) => _isT ? p.pdbIds.contains(_rid) : p.stashIds.contains(_rid)).firstOrNull;
    if (have != null) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.pushReplacement('/p/${have.id}'); }); return; }
    try {
      Map<String, dynamic>? p;
      if (_isT) { final t = await tpdbPerformer(_rid); if (t != null) p = tpdbProfile(t); }
      else { p = await stashPerformer(_rid); }
      if (p == null) { setState(() { _loading = false; _err = 'لم تُعثر عليها في ${_isT ? 'ThePornDB' : 'StashDB'} (ربما حُذفت أو دُمجت).'; }); return; }
      if (!adultOk({'birth': p['birth_date']})) { setState(() { _loading = false; _err = 'لا يمكن عرض هذا الملف.'; }); return; }   // بوابة +18 قبل الصور والأعمال
      setState(() { _p = p; _loading = false; _srcLabel = _isT ? 'ThePornDB' : 'StashDB'; });
      var w = _isT ? await TPDB.scenes(_rid, maxPages: 1) : await StashDB.scenes(_rid, maxPages: 1);
      if (mounted) setState(() => _works = w);
      // كل سجلاتها في المصدرين (بكل أسمائها) ⇒ كل معلوماتها وأعمالها وصورها، مدمجة بلا تكرار
      final all = await findAllRecords(Candidate(source: _isT ? 'tpdb' : 'stash', id: _rid, name: '${p['name']}', aliases: ((p['aliases'] as List?) ?? const []).join(', '), birth: '${p['birth_date'] ?? ''}', country: '${p['country'] ?? ''}'));
      if (!mounted || all.stash.length + all.tpdb.length <= 1) return;
      final sMain = _isT ? (all.stash.firstOrNull?.id ?? '') : _rid, tMain = _isT ? _rid : (all.tpdb.firstOrNull?.id ?? '');
      final d = await fetchBoth(stashId: sMain, pdbId: tMain, moreStash: [for (final x in all.stash) x.id], morePdb: [for (final x in all.tpdb) x.id], maxPages: 3);
      if (d.minor) { if (mounted) setState(() { _p = null; _err = 'لا يمكن عرض هذا الملف.'; }); return; }   // البوابة على كل السجلات
      w = mergeWorks(w, d.works).list..sort((a, b) => '${b['d'] ?? b['y'] ?? ''}'.compareTo('${a['d'] ?? a['y'] ?? ''}'));
      // معلومات ناقصة تُملأ من المصدر الآخر
      Map<String, dynamic> merged = p;
      if (_isT && sMain.isNotEmpty) { try { final sp = await stashPerformer(sMain); if (sp != null) merged = {...fillFrom(sp, p), 'images': p['images']}; } catch (_) {} }
      if (mounted) setState(() { _works = w; _p = merged; _pdb = d.pdbIds.join(','); _sid = d.stashIds.firstOrNull ?? ''; _records = d.stashIds.length + d.pdbIds.length; _srcLabel = d.sources.join(' + '); });
      // الصور الإضافية غير المكررة بصريًا
      final mine = stashImages(p);
      final base = <List<bool>>[];
      for (final u in mine.take(6)) { final b = await fetchImageBytes(u); final h = b == null ? null : await photoHash(b); if (h != null) base.add(h); }
      final extra = <String>[];
      for (final u in d.images.where((u) => !mine.contains(u)).take(10)) {
        final b = await fetchImageBytes(u); final h = b == null ? null : await photoHash(b); if (h == null) continue;
        if (base.any((x) => hamming(x, h) <= dupThreshold)) continue;
        base.add(h); extra.add(u);
      }
      if (mounted && extra.isNotEmpty) setState(() => _extra = extra);
    } catch (e) { if (mounted) setState(() { _loading = false; _err = '$e'; }); }
  }

  Future<void> _add() async {
    final p = _p!; setState(() => _adding = true);
    final imgs = [...stashImages(p), ..._extra];
    final c = Candidate(source: _isT ? 'tpdb' : 'stash', id: _rid, name: '${p['name']}', aliases: ((p['aliases'] as List?) ?? const []).join(', '), birth: '${p['birth_date'] ?? ''}',
      country: '${p['country'] ?? ''}', image: imgs.isEmpty ? '' : imgs.first, height: (p['height'] as num?)?.toInt(), careerStart: (p['career_start_year'] as num?)?.toInt());
    final twin = _isT ? (_sid.isEmpty ? null : Candidate(source: 'stash', id: _sid, name: c.name, birth: c.birth)) : (_pdb.isEmpty ? null : Candidate(source: 'tpdb', id: _pdb.split(',').first, name: c.name, birth: c.birth));
    try {
      final r = await addCandidate(ref, c, twin: twin, extraImages: imgs.skip(1).take(3).toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.$2)));
      if (r.$1 != null) { ref.read(tasteProvider.notifier).feedback(widget.stashId, 1); context.pushReplacement('/p/${r.$1!.id}'); }   // تعلّم: أعجبتها
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _adding = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (_p == null) return Scaffold(appBar: AppBar(), body: EmptyState(title: 'تعذّر فتح الملف', body: _err, actions: [if (_err.contains('مفتاح')) FilledButton.icon(onPressed: () => context.go('/more'), icon: const Icon(Icons.key_rounded), label: const Text('أضف المفتاح')), OutlinedButton(onPressed: () { setState(() { _loading = true; _err = ''; }); _load(); }, child: const Text('إعادة المحاولة'))]));
    final p = _p!; final imgs = [...stashImages(p), ..._extra]; final age = sdAge(p['birth_date']).age;
    final facts = <(String, String)>[
      if (age != null) ('العمر', '$age سنة'), if ('${p['country'] ?? ''}'.isNotEmpty) ('البلد', '${p['country']}'),
      if (p['height'] != null) ('الطول', '${p['height']} سم'), if (p['ethnicity'] != null) ('العرق', attrLabel('ethnicity', '${p['ethnicity']}')),
      if (p['hair_color'] != null) ('الشعر', attrLabel('hair_color', '${p['hair_color']}')), if (p['eye_color'] != null) ('العيون', attrLabel('eye_color', '${p['eye_color']}')),
      if ('${p['cup_size'] ?? ''}'.isNotEmpty || p['waist_size'] != null) ('المقاسات', [p['band_size'] != null ? '${p['band_size']}${p['cup_size'] ?? ''}' : '${p['cup_size'] ?? ''}', '${p['waist_size'] ?? '?'}', '${p['hip_size'] ?? '?'}'].join('-')),
      if (p['breast_type'] != null) ('الصدر', attrLabel('breast_type', '${p['breast_type']}')),
      if (p['career_start_year'] != null) ('المسيرة', '${p['career_start_year']}${p['career_end_year'] != null ? '–${p['career_end_year']}' : ' – الآن'}'),
      ('المشاهد', '${p['scene_count'] ?? 0}'),
    ];
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(S.s3), child: Row(children: [
        Expanded(child: FilledButton.icon(onPressed: _adding ? null : _add, icon: _adding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_rounded), label: Text(_adding ? 'جارٍ الإضافة…' : 'إضافة لمكتبتي'))),
        const SizedBox(width: S.s2),
        OutlinedButton.icon(onPressed: () async { await ref.read(tasteProvider.notifier).feedback(widget.stashId, -1); await ref.read(recsProvider.notifier).hide(widget.stashId); if (context.mounted) context.pop(); }, icon: const Icon(Icons.visibility_off_rounded), label: const Text('ليست ذوقي')),
      ]))),
      body: CustomScrollView(slivers: [
        SliverAppBar(pinned: true, expandedHeight: (h * .55).clamp(320, 560), backgroundColor: C.bg,
          flexibleSpace: FlexibleSpaceBar(background: imgs.isEmpty ? Initials('${p['name']}') : Stack(fit: StackFit.expand, children: [
            Padding(padding: const EdgeInsets.only(top: 90, bottom: 40), child: PageView.builder(controller: _pc, itemCount: imgs.length, onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (c, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: ClipRRect(borderRadius: BorderRadius.circular(S.rXl),
                child: Photo(imgs[i], name: '${p['name']}', fit: BoxFit.contain, alignment: Alignment.center))))),
            if (imgs.length > 1) Positioned(bottom: 16, left: 0, right: 0, child: Center(child: Text('${_page + 1} / ${imgs.length}', style: const TextStyle(color: C.muted)))),
          ]))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name']}', style: Theme.of(context).textTheme.displaySmall),
          if (((p['aliases'] as List?) ?? const []).isNotEmpty) Text(((p['aliases'] as List)).take(4).join('، '), style: const TextStyle(color: C.muted)),
          const SizedBox(height: S.s3),
          if (widget.why.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(S.s3), decoration: BoxDecoration(color: C.gold.withValues(alpha: .1), borderRadius: BorderRadius.circular(S.rMd), border: Border.all(color: C.gold.withValues(alpha: .4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('لماذا اقتُرحت لك', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700)), for (final w in widget.why) Text('• $w')])),
          const SizedBox(height: S.s3),
          Wrap(spacing: S.s2, runSpacing: S.s2, children: [for (final f in facts) Container(padding: const EdgeInsets.symmetric(horizontal: S.s3, vertical: S.s2),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rMd), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(f.$1, style: const TextStyle(color: C.muted, fontSize: 11)), Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w600))]))]),
          const SizedBox(height: S.s2),
          Text('المصدر: ${_srcLabel.isEmpty ? 'StashDB' : _srcLabel}${_records > 1 ? ' · $_records سجلات مدمجة بلا تكرار' : ''}', style: const TextStyle(color: C.muted, fontSize: 12)),
        ]))),
        SliverToBoxAdapter(child: SectionHeader('أحدث أعمالها', sub: _works.isEmpty ? 'جارٍ التحميل…' : '${_works.length} عمل')),
        SliverList.builder(itemCount: _works.length, itemBuilder: (c, i) {
          final w = _works[i];
          return ListTile(
            leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 96, height: 56, child: WorkImage('${w['p'] ?? ''}', name: '${w['s'] ?? w['t']}'))),
            title: Text('${w['t']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([if ('${w['s'] ?? ''}'.isNotEmpty) w['s'], if ('${w['d'] ?? w['y'] ?? ''}'.isNotEmpty) w['d'] ?? w['y']].join(' · '), style: const TextStyle(color: C.muted)));
        }),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]),
    );
  }
}
