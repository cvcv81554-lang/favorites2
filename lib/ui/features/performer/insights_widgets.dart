import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/dual_source.dart' show tpdbPerformer, tpdbAsStash;
import '../../../data/sources.dart';
import '../../../domain/insights.dart';
import '../../../domain/performer.dart';
import '../../../domain/taste.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../discover/discover_screen.dart' show openCandidate;
import '../discover/taste_state.dart';

/// ذاكرة البيانات الوصفية الموثّقة (تبنيها «تحليل ذوقي»): مفتاح StashDB أو «tp:معرّف_ThePornDB» ⇒ الخصائص.
final attrFeatsProvider = FutureProvider<Map<String, Map<String, Object>>>((ref) async {
  final repo = await ref.watch(repoProvider.future);
  final c = Map<String, dynamic>.from(await repo.kvGet('attr_cache') as Map? ?? {});
  return {for (final e in c.entries) if (e.value is Map && (e.value as Map)['d'] is Map) e.key: featuresOf(Map<String, dynamic>.from((e.value as Map)['d'] as Map))};
});
String attrKey(Performer p) => p.stashId.isNotEmpty ? p.stashId : p.pdbId.isNotEmpty ? 'tp:${p.pdbId}' : '';

/// مسيرتها: مخطط سنوي + أول/آخر/ذروة + أكثر الاستوديوهات + اتجاه تقييمك.
class CareerSection extends StatelessWidget {
  const CareerSection({super.key, required this.p});
  final Performer p;
  @override
  Widget build(BuildContext context) {
    final c = careerOf(p);
    if (c.isEmpty || c.years.length < 2) return const SizedBox.shrink();
    final maxN = c.years.map((y) => y.count).reduce((a, b) => a > b ? a : b);
    String trend() => c.trend == null ? '' : c.trend! > .3 ? 'تقييمك لأعمالها في صعود ↑' : c.trend! < -.3 ? 'تقييمك لأعمالها في نزول ↓' : 'تقييمك لأعمالها ثابت';
    return Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: Container(padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Text('مسيرتها', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 15)), const Spacer(),
          TextButton(onPressed: () => _details(context, c), child: const Text('سنة بسنة ›'))]),
        Text(['${c.first}–${c.last}', if (c.start != null && c.start! < c.first!) 'بدأت ${c.start}', 'الذروة ${c.peak}', if (trend().isNotEmpty) trend()].join(' · '), style: const TextStyle(color: C.muted, fontSize: 12.5)),
        const SizedBox(height: S.s3),
        SizedBox(height: 74, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final y in c.years) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1.5), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Tooltip(message: '${y.year}: ${y.count} عمل · شاهدت ${y.seen}', child: Container(height: 52 * y.count / maxN + 2,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: y.year == c.peak ? C.gold : C.gold.withValues(alpha: .45)),
              alignment: Alignment.bottomCenter, child: FractionallySizedBox(heightFactor: y.count == 0 ? 0 : y.seen / y.count, child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: C.ok))))),
            const SizedBox(height: 3),
            if (c.years.length <= 12 || y.year % 2 == 0) Text('${y.year % 100}'.padLeft(2, '0'), style: const TextStyle(color: C.muted, fontSize: 9.5)) else const SizedBox(height: 12),
          ]))),
        ])),
        const SizedBox(height: 4),
        const Text('الذهبي: أعمالها · الأخضر: ما شاهدته', style: TextStyle(color: C.muted, fontSize: 11)),
        if (c.topStudios.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in c.topStudios) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(99)), child: Text('${s.$1} · ${s.$2}', style: const TextStyle(fontSize: 12))),
        ])),
      ])));
  }

  static void _details(BuildContext context, Career c) => showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: .7,
    builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(S.s4), children: [
      Text('مسيرتها سنة بسنة', style: Theme.of(ctx).textTheme.titleLarge),
      for (final y in c.years.reversed) ListTile(contentPadding: EdgeInsets.zero,
        leading: Text('${y.year}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: y.year == c.peak ? C.gold : C.text)),
        title: Text('${y.count} عمل · شاهدت ${y.seen}${y.avgR > 0 ? ' · ★${y.avgR.toStringAsFixed(1)}' : ''}'),
        subtitle: y.studios.isEmpty ? null : Text(y.studios.join('، '), style: const TextStyle(color: C.muted))),
    ])));
}

/// «لماذا تحبها؟»: ما تشترك فيه مع مفضلاتك (بيانات موثّقة)، ومن عملت معهن منهن، والأقرب إليها من المرشحات.
class WhyLikeSection extends ConsumerStatefulWidget {
  const WhyLikeSection({super.key, required this.p});
  final Performer p;
  @override ConsumerState<WhyLikeSection> createState() => _WhyLikeState();
}
class _WhyLikeState extends ConsumerState<WhyLikeSection> {
  bool _busy = false; String _err = '';

  Future<void> _fetch() async {
    final p = widget.p; setState(() { _busy = true; _err = ''; });
    try {
      Map<String, dynamic>? d;
      if (p.stashId.isNotEmpty) d = await stashPerformer(p.stashId);
      if (d == null && p.pdbId.isNotEmpty) { final t = await tpdbPerformer(p.pdbId); if (t != null) d = tpdbAsStash(t); }
      if (d == null) { setState(() { _busy = false; _err = 'لم تُعثر على بياناتها'; }); return; }
      final repo = await ref.read(repoProvider.future);
      final c = Map<String, dynamic>.from(await repo.kvGet('attr_cache') as Map? ?? {});
      c[attrKey(p)] = {'t': DateTime.now().millisecondsSinceEpoch, 'd': d};
      await repo.kvSet('attr_cache', c);
      ref.invalidate(attrFeatsProvider);
    } catch (e) { _err = '$e'; }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    if (!(p.fav || p.rating >= 4) || p.isMinor) return const SizedBox.shrink();
    final feats = ref.watch(attrFeatsProvider).value ?? const {};
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    final others = [for (final o in lib) if (o.id != p.id && (o.fav || o.rating >= 4) && feats[attrKey(o)] != null) feats[attrKey(o)]!];
    final her = feats[attrKey(p)];
    // من عملت معهن من مفضلاتك (أعمال مشتركة في مكتبتك)
    final myKeys = {for (final w in p.works) '${w['t']}|${w['s']}'.toLowerCase()};
    final costars = <(Performer, int)>[];
    for (final o in lib) {
      if (o.id == p.id || !(o.fav || o.rating >= 4)) continue;
      final n = o.works.where((w) => myKeys.contains('${w['t']}|${w['s']}'.toLowerCase())).length;
      if (n > 0) costars.add((o, n));
    }
    costars.sort((a, b) => b.$2.compareTo(a.$2));
    final recs = ref.watch(tasteProvider).value?.recs ?? const <TasteRec>[];
    final closest = her == null ? const <(TasteRec, double)>[] : closestTo<TasteRec>(her, [for (final r in recs) (r, r.feats)], k: 10);
    final shared = her == null ? const <(String, int, double)>[] : sharedTraits(her, others).take(5).toList();

    return Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: Container(padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.gold.withValues(alpha: .35)), gradient: const LinearGradient(colors: [Color(0xFF241425), Color(0xFF15101E)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('لماذا تحبها؟', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        if (her == null) ...[
          Text(p.stashId.isEmpty && p.pdbId.isEmpty ? 'اربطها بمصدر لأقارنها بمفضلاتك.' : 'لا بيانات موثّقة لها بعد على جهازك.', style: const TextStyle(color: C.muted)),
          if (p.stashId.isNotEmpty || p.pdbId.isNotEmpty) TextButton.icon(onPressed: _busy ? null : _fetch, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded), label: const Text('جلب بياناتها للمقارنة')),
          if (_err.isNotEmpty) Text(_err, style: const TextStyle(color: C.danger, fontSize: 12)),
        ] else if (shared.isEmpty && others.isNotEmpty) const Text('لا تشترك بخصائص موثّقة واضحة مع مفضلاتك — هي اختيار مختلف عن نمطك.', style: TextStyle(color: C.muted))
        else if (others.isEmpty) const Text('حلّل ذوقك في «اكتشف» أولًا لأقارنها بمفضلاتك الأخرى.', style: TextStyle(color: C.muted))
        else for (final s in shared) Padding(padding: const EdgeInsets.only(top: 3), child: Text('• ${s.$1} — مثل ${s.$2} من ${others.length} مفضلة (${(s.$3 * 100).round()}٪)', style: const TextStyle(height: 1.4))),
        if (costars.isNotEmpty) ...[
          const SizedBox(height: S.s2),
          Text('عملت مع ${costars.length} من مفضلاتك: ${costars.take(4).map((c) => '${c.$1.name} (${c.$2})').join('، ')}', style: const TextStyle(color: C.muted, fontSize: 12.5, height: 1.4)),
        ],
        if (closest.isNotEmpty) ...[
          const SizedBox(height: S.s3),
          const Text('الأقرب إليها هي تحديدًا', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SizedBox(height: 150, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: closest.length, separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (c, i) { final r = closest[i].$1;
              return GestureDetector(onTap: () => openCandidate(context, ref, r.id, ['تشبه ${p.name} (${(closest[i].$2 * 100).round()}٪)', ...r.why]), child: SizedBox(width: 90, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AspectRatio(aspectRatio: 3 / 4, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Photo(r.image, name: r.name))),
                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('${(closest[i].$2 * 100).round()}٪', style: const TextStyle(color: C.gold, fontSize: 11)),
              ]))); })),
        ] else if (her != null && recs.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('حلّل ذوقك في «اكتشف» لترى الأقرب إليها.', style: TextStyle(color: C.muted, fontSize: 12))),
      ])));
  }
}
