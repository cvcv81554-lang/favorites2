import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../domain/sanitize.dart';
import '../works/works_screen.dart';
import '../sources/source_search.dart';
import 'edit_sheet.dart';

class PerformerScreen extends ConsumerStatefulWidget {
  const PerformerScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<PerformerScreen> createState() => _PerformerScreenState();
}

class _PerformerScreenState extends ConsumerState<PerformerScreen> {
  final _pc = PageController(viewportFraction: .86);
  int _page = 0;
  bool _counted = false;

  @override void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = performerById(ref, widget.id);
    if (p == null) return const Scaffold(body: EmptyState(title: 'غير موجودة', body: 'ربما حُذفت هذه الممثلة.'));
    if (!_counted) { _counted = true; WidgetsBinding.instance.addPostFrameCallback((_) => _countView(p)); }
    final photos = p.photos.isNotEmpty ? p.photos : [p.cover];
    final works = [...p.works]..sort((a, b) => ((b['d'] ?? b['y'] ?? '') as Object).toString().compareTo(((a['d'] ?? a['y'] ?? '') as Object).toString()));
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: (h * .62).clamp(360, 640), pinned: true, stretch: true, backgroundColor: C.bg,
          actions: [
            IconButton(tooltip: p.fav ? 'إزالة من المفضلة' : 'إلى المفضلة', onPressed: () => ref.read(libraryProvider.notifier).upsert(p.copyWith({'fav': !p.fav})),
              icon: Icon(p.fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: p.fav ? C.rose : null)),
            IconButton(tooltip: 'تعديل', onPressed: () => showEditSheet(context, ref, p: p), icon: const Icon(Icons.edit_rounded)),
            PopupMenuButton<String>(onSelected: (v) async {
              if (v == 'del') { _delete(p); return; }
              if (v == 'link') { context.push('/search?q=${Uri.encodeQueryComponent(p.name)}&link=${p.id}'); return; }
              if (v == 'sync') {
                final m = ScaffoldMessenger.of(context);
                m.showSnackBar(const SnackBar(content: Text('جارٍ التحديث من المصادر…')));
                final r = await refreshFromSources(ref, p);
                m.hideCurrentSnackBar(); m.showSnackBar(SnackBar(content: Text(r)));
              }
            }, itemBuilder: (_) => [
              if (p.stashId.isNotEmpty || p.pdbId.isNotEmpty) const PopupMenuItem(value: 'sync', child: Text('تحديث الأعمال من المصادر')),
              PopupMenuItem(value: 'link', child: Text(p.stashId.isEmpty && p.pdbId.isEmpty ? 'ربط بمصدر رسمي' : 'ربط بمصدر آخر')),
              const PopupMenuItem(value: 'del', child: Text('حذف')),
            ]),
          ],
          flexibleSpace: FlexibleSpaceBar(stretchModes: const [StretchMode.zoomBackground], background: Stack(fit: StackFit.expand, children: [
            Positioned.fill(child: ImageFiltered(imageFilter: ColorFilter.mode(Colors.black.withValues(alpha: .55), BlendMode.darken), child: Photo(photos[_page.clamp(0, photos.length - 1)], name: p.name))),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xAA0A0810), Color(0x330A0810), C.bg], stops: [0, .5, 1]))),
            Padding(padding: const EdgeInsets.only(top: 90, bottom: 70), child: PageView.builder(
              controller: _pc, itemCount: photos.length, onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (c, i) => AnimatedBuilder(animation: _pc, builder: (c, child) {
                final v = _pc.hasClients && _pc.position.haveDimensions ? (1 - ((_pc.page ?? 0) - i).abs() * .08).clamp(.9, 1.0) : (i == 0 ? 1.0 : .92);
                return Transform.scale(scale: v, child: child);
              }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: ClipRRect(borderRadius: BorderRadius.circular(S.rXl),
                child: i == 0 ? Hero(tag: 'p-${p.id}', child: Photo(photos[i], name: p.name)) : Photo(photos[i], name: p.name)))),
            )),
            if (photos.length > 1) Positioned(bottom: 48, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < photos.length && i < 12; i++) AnimatedContainer(duration: S.fast, margin: const EdgeInsets.symmetric(horizontal: 3), width: i == _page ? 18 : 6, height: 6,
                decoration: BoxDecoration(color: i == _page ? C.gold2 : C.line2, borderRadius: BorderRadius.circular(3))),
            ])),
          ])),
        ),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: Theme.of(context).textTheme.displaySmall),
          if (p.aliases.isNotEmpty) Text(p.aliases, style: const TextStyle(color: C.muted)),
          const SizedBox(height: S.s2),
          Wrap(spacing: S.s2, runSpacing: S.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (p.rating > 0) Row(mainAxisSize: MainAxisSize.min, children: [Stars(p.rating, size: 18), const SizedBox(width: 6), Text(p.rating.toStringAsFixed(1), style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700))]),
            if (p.tier.isNotEmpty) _chip('المستوى ${p.tier}', gold: true),
          ]),
          const SizedBox(height: S.s4),
          _facts(p),
          if (p.tags.isNotEmpty) ...[const SizedBox(height: S.s4), Wrap(spacing: S.s2, runSpacing: S.s2, children: [for (final t in p.tags) _chip('#$t')])],
          if (p.notes.isNotEmpty) ...[const SizedBox(height: S.s4), Container(width: double.infinity, padding: const EdgeInsets.all(S.s4), decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rMd), border: Border.all(color: C.line)), child: Text(p.notes, style: const TextStyle(height: 1.7)))],
        ]))),
        SliverToBoxAdapter(child: SectionHeader('الأعمال', sub: '${works.length} عمل · شاهدتِ ${p.watchedCount}')),
        if (works.isEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(S.s4), child: Text('لا أعمال مسجلة بعد.', style: TextStyle(color: C.muted)))),
        SliverList.builder(itemCount: works.length, itemBuilder: (c, i) => _WorkTile(w: works[i])),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ]),
    );
  }

  Widget _facts(Performer p) {
    final f = <(IconData, String, String)>[
      if (p.age != null) (Icons.cake_rounded, 'العمر', '${p.age} سنة'),
      if (p.country.isNotEmpty) (Icons.public_rounded, 'البلد', p.country),
      if (p.raw['height'] is num) (Icons.height_rounded, 'الطول', '${p.raw['height']} سم'),
      if (p.raw['cs'] is num) (Icons.flag_rounded, 'بدأت', '${p.raw['cs']}${p.raw['ce'] is num ? ' – ${p.raw['ce']}' : ''}'),
      (Icons.photo_rounded, 'الصور', '${p.photos.length}'),
    ];
    return Wrap(spacing: S.s3, runSpacing: S.s3, children: [for (final x in f) Container(
      padding: const EdgeInsets.symmetric(horizontal: S.s3, vertical: S.s2), decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rMd), border: Border.all(color: C.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(x.$1, size: 18, color: C.gold), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x.$2, style: const TextStyle(color: C.muted, fontSize: 11)), Text(x.$3, style: const TextStyle(fontWeight: FontWeight.w600))])]),
    )]);
  }

  Widget _chip(String t, {bool gold = false}) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(color: gold ? C.gold.withValues(alpha: .16) : C.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: gold ? C.gold.withValues(alpha: .5) : C.line2)),
    child: Text(t, style: TextStyle(color: gold ? C.gold2 : C.text, fontSize: 13)));

  Future<void> _countView(Performer p) async {
    await ref.read(libraryProvider.notifier).upsert(Performer({...p.raw, 'views': p.views + 1, 'lastView': DateTime.now().millisecondsSinceEpoch}));
  }

  Future<void> _delete(Performer p) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('حذف الممثلة؟'), content: Text('سيُحذف «${p.name}» وصورها من هذا الجهاز.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger, foregroundColor: Colors.white), onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
    if (ok != true || !mounted) return;
    await ref.read(libraryProvider.notifier).remove(p.id);
    if (mounted) context.pop();
  }
}

class _WorkTile extends ConsumerWidget {
  const _WorkTile({required this.w});
  final Map<String, dynamic> w;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = w['w'] == 1 || w['w'] == true, upc = isUpcoming(w);
    final sub = [if ((w['s'] ?? '').toString().isNotEmpty) w['s'], if ((w['d'] ?? w['y'] ?? '').toString().isNotEmpty) (w['d'] ?? w['y'])].join(' · ');
    return ListTile(
      onTap: () => showWorkSheet(context, ref, wKeyOf(w)),
      contentPadding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: 2),
      leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 72, height: 44, child: Photo((w['p'] ?? '').toString(), name: (w['s'] ?? w['t'] ?? '').toString(), cacheWidth: 200))),
      title: Text((w['t'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: const TextStyle(color: C.muted, fontSize: 12.5)),
      trailing: upc ? const Chip(label: Text('قادم'), visualDensity: VisualDensity.compact) : seen ? const Icon(Icons.check_circle_rounded, color: C.ok) : (w['q'] == 1 ? const Icon(Icons.bookmark_rounded, color: C.gold) : null),
    );
  }
}
