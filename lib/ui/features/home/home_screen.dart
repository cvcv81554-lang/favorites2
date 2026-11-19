import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// الرئيسية: بطاقة «نجمة اليوم» بملء العرض ثم رفوف أفقية.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    return Scaffold(
      body: lib.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(title: 'تعذّر فتح المكتبة', body: '$e'),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(title: 'مكتبتك الخاصة', body: 'كل شيء يبقى على جهازك.\nابدأ باستيراد نسختك الاحتياطية من التطبيق السابق، أو أضف أول ممثلة.',
              actions: [FilledButton.icon(onPressed: () => context.go('/more'), icon: const Icon(Icons.download_rounded), label: const Text('استيراد نسخة احتياطية'))]);
          }
          final day = DateTime.now(); final seed = day.year * 1000 + day.month * 40 + day.day;
          final favs = all.where((p) => p.fav).toList();
          final pool = (favs.isNotEmpty ? favs : all).where((p) => p.cover.isNotEmpty).toList();
          final spot = pool.isEmpty ? all.first : pool[Random(seed).nextInt(pool.length)];
          final recent = [...all]..sort((a, b) => b.added.compareTo(a.added));
          final top = all.where((p) => p.rating >= 4).toList()..sort((a, b) => b.rating.compareTo(a.rating));
          final upc = all.where((p) => p.works.any(isUpcoming)).toList();
          final bday = all.where(smartFilters['bday']!.$2).toList();
          final viewed = all.where((p) => p.views > 0).toList()..sort((a, b) => ((b.raw['lastView'] as num?) ?? 0).compareTo((a.raw['lastView'] as num?) ?? 0));
          final works = all.fold<int>(0, (s, p) => s + p.works.length);
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _Spotlight(p: spot)),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Row(children: [
              _Stat('${all.length}', 'ممثلة'), _Stat('${favs.length}', 'مفضلة'), _Stat('$works', 'عمل'), _Stat('${upc.length}', 'لها جديد قادم'),
            ]))),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: OutlinedButton.icon(onPressed: () => context.push('/stats'), icon: const Icon(Icons.insights_rounded, color: C.gold), label: Text('ملخّص ${DateTime.now().year} والإحصائيات')))),
            if (viewed.isNotEmpty) _row(context, 'تابعتِ مؤخرًا', viewed.take(16).toList()),
            _row(context, 'أُضيفت حديثًا', recent.take(16).toList()),
            if (bday.isNotEmpty) _row(context, '🎂 أعياد ميلاد هذا الشهر', bday),
            if (top.isNotEmpty) _row(context, 'الأعلى تقييمًا', top.take(16).toList()),
            if (upc.isNotEmpty) _row(context, 'لها أعمال قادمة', upc.take(16).toList()),
            if (favs.isNotEmpty) _row(context, 'المفضلات', favs.take(20).toList()),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ]);
        },
      ),
    );
  }

  Widget _row(BuildContext context, String title, List<Performer> ps) => SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHeader(title),
    SizedBox(height: 230, child: ListView.separated(
      scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), itemCount: ps.length,
      separatorBuilder: (_, _) => const SizedBox(width: S.s3),
      itemBuilder: (c, i) => SizedBox(width: 156, child: PosterCard(p: ps[i], heroTag: 'h-$title-${ps[i].id}', onTap: () => c.push('/p/${ps[i].id}'))),
    )),
  ]));
}

class _Stat extends StatelessWidget {
  const _Stat(this.v, this.l);
  final String v, l;
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    margin: const EdgeInsetsDirectional.only(end: S.s2), padding: const EdgeInsets.symmetric(vertical: S.s3),
    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rMd), border: Border.all(color: C.line)),
    child: Column(children: [GradientText(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), Text(l, style: const TextStyle(color: C.muted, fontSize: 11.5), textAlign: TextAlign.center)]),
  ));
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.p});
  final Performer p;
  @override
  Widget build(BuildContext context) {
    final h = min(MediaQuery.sizeOf(context).height * .58, 560.0);
    return GestureDetector(
      onTap: () => context.push('/p/${p.id}'),
      child: SizedBox(height: h, child: Stack(fit: StackFit.expand, children: [
        Hero(tag: 'spot-${p.id}', child: Photo(p.photos.isNotEmpty ? p.photos.first : p.cover, name: p.name, alignment: const Alignment(0, -.6))),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, .35, 1], colors: [Color(0x990A0810), Color(0x000A0810), C.bg]))),
        Align(alignment: AlignmentDirectional.topStart, child: SafeArea(child: Padding(padding: const EdgeInsets.all(S.s4), child: Row(mainAxisSize: MainAxisSize.min, children: [const AppLogo(size: 34), const SizedBox(width: S.s2), Text('المفضلة', style: Theme.of(context).textTheme.titleLarge)])))),
        Positioned(left: S.s4, right: S.s4, bottom: S.s4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('نجمة اليوم', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w600, letterSpacing: .3)),
          Text(p.name, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: S.s1),
          Row(children: [if (p.rating > 0) Stars(p.rating, size: 16), const SizedBox(width: S.s2),
            Text([if (p.age != null) '${p.age} سنة', if (p.country.isNotEmpty) p.country, '${p.works.length} عمل'].join(' · '), style: const TextStyle(color: C.muted))]),
        ])),
      ])),
    );
  }
}
