// البحث الشامل: يجمع الممثلات والأعمال والاستوديوهات والوسوم من صندوق واحد، والفلاتر تعمل.
import 'package:favorites2/data/library_repo.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/ui/core/state.dart';
import 'package:favorites2/ui/features/find/find_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  Future<void> open(WidgetTester t) async {
    final repo = LibraryRepo.withDb((await t.runAsync(() => databaseFactoryMemory.openDatabase('f${DateTime.now().microsecondsSinceEpoch}')))!);
    final y = DateTime.now().year;
    await t.runAsync(() => repo.save([
      Performer({'id': 'a', 'name': 'Luna Sample', 'birth': '${y - 25}-01-01', 'country': 'CZ', 'fav': true, 'rating': 5, 'tags': ['Petite'],
        'works': [{'t': 'Sunset Story', 's': 'Golden Studio', 'd': '2024-01-01', 'tg': ['Outdoor']}]}),
      Performer({'id': 'b', 'name': 'Maya Example', 'birth': '${y - 40}-01-01', 'country': 'US', 'rating': 3,
        'works': [{'t': 'City Lights', 's': 'Golden Studio', 'd': '2023-01-01', 'tg': ['Outdoor']}]}),
    ]));
    final router = GoRouter(initialLocation: '/find', routes: [
      GoRoute(path: '/find', builder: (_, _) => const FindScreen()),
      GoRoute(path: '/p/:id', builder: (_, s) => Text('profile:${s.pathParameters['id']}')),
      GoRoute(path: '/works', builder: (_, _) => const Text('works')),
    ]);
    await t.pumpWidget(ProviderScope(overrides: [repoProvider.overrideWith((ref) async => repo)], child: MaterialApp.router(routerConfig: router)));
    for (var i = 0; i < 10; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20))); await t.pump(const Duration(milliseconds: 50)); }
  }

  testWidgets('اسم ⇒ الممثلة؛ استوديو ⇒ أعماله والاستوديو؛ الضغط يفتح الملف', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField), 'luna'); await t.pump();
    expect(find.text('Luna Sample'), findsOneWidget); expect(find.text('Maya Example'), findsNothing);
    await t.enterText(find.byType(TextField), 'golden'); await t.pump();
    expect(find.textContaining('الأعمال (2)'), findsOneWidget);
    expect(find.text('Golden Studio · 2'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'luna'); await t.pump();
    await t.tap(find.text('Luna Sample')); await t.pumpAndSettle();
    expect(find.text('profile:a'), findsOneWidget);
  });

  testWidgets('الوسم: الضغط عليه يعرض كل ما يحمله؛ وفلتر العمر والمفضلة', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField), 'outdo'); await t.pump();
    await t.tap(find.text('Outdoor · 2')); await t.pump();
    expect(find.textContaining('الوسم: Outdoor'), findsOneWidget);
    expect(find.textContaining('الأعمال (2)'), findsOneWidget);
    // فلتر المفضلة فقط
    await t.tap(find.byTooltip('الفلاتر')); await t.pump();
    await t.tap(find.text('المفضلة فقط')); await t.pump();
    await t.tap(find.byIcon(Icons.close_rounded).first); await t.pump();   // مسح البحث: الفلاتر وحدها تعرض الممثلات
    expect(find.text('Luna Sample'), findsOneWidget); expect(find.text('Maya Example'), findsNothing);
  });
}
