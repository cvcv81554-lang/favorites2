import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../performer/edit_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _q = TextEditingController();
  @override void dispose() { _q.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(libQueryProvider);
    final n = ref.read(libQueryProvider.notifier);
    final list = ref.watch(filteredLibraryProvider);
    final total = ref.watch(libraryProvider).value?.length ?? 0;
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 1400 ? 7 : w >= 1100 ? 6 : w >= 860 ? 5 : w >= 600 ? 4 : 2;
    return Scaffold(
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: w < 760 ? 84 : 0),   // فوق الشريط السفلي على الجوال
        child: FloatingActionButton(
          tooltip: 'إضافة ممثلة', onPressed: () => showEditSheet(context, ref),
          backgroundColor: C.gold, foregroundColor: C.onAccent, child: const Icon(Icons.add_rounded))),
      body: SafeArea(bottom: false, child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('المكتبة', style: Theme.of(context).textTheme.headlineSmall),
            Text(list.length == total ? '$total ممثلة' : '${list.length} من $total', style: const TextStyle(color: C.muted)),
          ])),
          IconButton(tooltip: 'بحث شامل (ممثلات، أعمال، استوديوهات، وسوم)', onPressed: () => context.push('/find'), icon: const Icon(Icons.manage_search_rounded)),
          PopupMenuButton<SortBy>(
            tooltip: 'الترتيب', icon: const Icon(Icons.sort_rounded), initialValue: q.sort, onSelected: (s) => n.set(q.copy(sort: s)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortBy.updated, child: Text('آخر تعديل')), PopupMenuItem(value: SortBy.added, child: Text('الأحدث إضافة')),
              PopupMenuItem(value: SortBy.rating, child: Text('الأعلى تقييمًا')), PopupMenuItem(value: SortBy.name, child: Text('الاسم')),
              PopupMenuItem(value: SortBy.age, child: Text('الأصغر سنًا')), PopupMenuItem(value: SortBy.works, child: Text('الأكثر أعمالًا')),
            ]),
          IconButton(tooltip: 'إضافة من المصادر', onPressed: () => context.push('/search'), icon: const Icon(Icons.travel_explore_rounded)),
          IconButton(tooltip: 'المفضلات فقط', onPressed: () => n.set(q.copy(favOnly: !q.favOnly)), icon: Icon(q.favOnly ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: q.favOnly ? C.rose : null)),
        ]))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(S.s4), child: SearchBar(
          controller: _q, hintText: 'ابحث بالاسم أو الوسم أو البلد أو عنوان عمل…', leading: const Icon(Icons.search_rounded),
          onChanged: (v) => n.set(q.copy(q: v)),
          trailing: [if (q.q.isNotEmpty) IconButton(onPressed: () { _q.clear(); n.set(q.copy(q: '')); }, icon: const Icon(Icons.close_rounded))],
          backgroundColor: const WidgetStatePropertyAll(C.surface), elevation: const WidgetStatePropertyAll(0),
          side: const WidgetStatePropertyAll(BorderSide(color: C.line2)),
        ))),
        SliverToBoxAdapter(child: SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), children: [
          for (final e in smartFilters.entries) Padding(padding: const EdgeInsetsDirectional.only(end: S.s2), child: FilterChip(
            label: Text(e.value.$1), selected: q.smart == e.key, showCheckmark: false,
            onSelected: (v) => n.set(q.copy(smart: v ? e.key : '')))),
        ]))),
        if (list.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: total == 0 ? 'المكتبة فارغة' : 'لا نتائج', body: total == 0 ? 'استورد نسختك الاحتياطية أو أضف أول ممثلة.' : 'جرّب كلمة أخرى أو ألغِ الفلتر.',
            actions: [if (total == 0) OutlinedButton(onPressed: () => context.go('/more'), child: const Text('استيراد'))]))
        else
          SliverPadding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 140), sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, childAspectRatio: 3 / 4.3, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3),
            itemCount: list.length,
            itemBuilder: (c, i) => PosterCard(p: list[i], onTap: () => c.push('/p/${list[i].id}')),
          )),
      ])),
    );
  }
}
