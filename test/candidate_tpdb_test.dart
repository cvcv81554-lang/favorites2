// مرشحة من ThePornDB في «اكتشف»: تُفتح من المصدر الثاني، تُدمج مع سجلها في StashDB، وتحترم بوابة +18.
import 'dart:convert';

import 'package:favorites2/data/dual_source.dart';
import 'package:favorites2/data/library_repo.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/ui/core/state.dart';
import 'package:favorites2/ui/features/discover/candidate_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stash_key': 'S', 'tpdb_key': 'T'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  final calls = <String>[];
  void mock(String birth) {
    calls.clear();
    sourceClient = MockClient((r) async {
      if (r.url.host == 'stashdb.org') {
        final q = '${jsonDecode(r.body)['query']}';
        calls.add('stash:${q.contains('searchPerformer') ? 'search' : q.contains('findPerformer') ? 'performer' : 'scenes'}');
        if (q.contains('searchPerformer')) return http.Response(jsonEncode({'data': {'searchPerformer': [{'id': 'S9', 'name': 'Tess Sample', 'birth_date': birth, 'gender': 'FEMALE', 'images': []}]}}), 200);
        if (q.contains('findPerformer')) return http.Response(jsonEncode({'data': {'findPerformer': {'id': 'S9', 'name': 'Tess Sample', 'birth_date': birth, 'hair_color': 'BRUNETTE', 'images': []}}}), 200);
        return http.Response(jsonEncode({'data': {'queryScenes': {'count': 1, 'scenes': [{'id': 'SS', 'title': 'Stash Only Scene', 'release_date': '2023-03-03', 'studio': {'name': 'A'}, 'images': []}]}}}), 200);
      }
      final path = r.url.path;
      calls.add('tpdb:${path.endsWith('/scenes') ? 'scenes' : path == '/performers' ? 'search' : 'performer'}');
      if (path == '/performers') return http.Response(jsonEncode({'data': [{'id': 'T7', 'name': 'Tess Sample', 'extras': {'gender': 'Female', 'birthday': birth}}]}), 200);
      if (path.endsWith('/scenes')) return http.Response(jsonEncode({'data': [{'id': 'X1', 'title': 'TPDB Scene', 'date': '2024-04-04', 'site': {'name': 'B'}, 'performers': []}], 'meta': {'last_page': 1}}), 200);
      return http.Response(jsonEncode({'data': {'id': 'T7', 'name': 'Tess Sample', 'aliases': ['T. S.'], 'extras': {'gender': 'Female', 'birthday': birth, 'height': '170cm', 'hair_colour': 'Brunette'}, 'image': 'https://img.test/t.jpg'}}), 200);
    });
  }

  Future<void> open(WidgetTester t) async {
    final repo = LibraryRepo.withDb((await t.runAsync(() => databaseFactoryMemory.openDatabase('ct${DateTime.now().microsecondsSinceEpoch}')))!);
    final router = GoRouter(initialLocation: '/c/tp:T7', routes: [
      GoRoute(path: '/c/:sid', builder: (_, s) => CandidateScreen(stashId: s.pathParameters['sid']!)),
      GoRoute(path: '/p/:id', builder: (_, s) => Text('profile:${s.pathParameters['id']}')),
    ]);
    await t.pumpWidget(ProviderScope(overrides: [repoProvider.overrideWith((ref) async => repo)], child: MaterialApp.router(routerConfig: router)));
    for (var i = 0; i < 30; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20))); await t.pump(const Duration(milliseconds: 50)); }
  }

  testWidgets('مرشحة من ThePornDB: تُفتح ببياناتها، وتُدمج أعمالها مع سجلها في StashDB', (t) async {
    mock('1996-06-06');
    await open(t);
    expect(find.text('Tess Sample'), findsOneWidget);
    expect(find.text('170 سم'), findsOneWidget);
    expect(find.text('إضافة لمكتبتي'), findsOneWidget);
    expect(find.textContaining('StashDB + ThePornDB'), findsOneWidget);    // المصدران
    await t.scrollUntilVisible(find.text('Stash Only Scene'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Stash Only Scene'), findsOneWidget);                  // عمل من المصدر الآخر
  });

  testWidgets('قاصر في ThePornDB ⇒ لا عرض ولا طلب أعمال', (t) async {
    mock('${DateTime.now().year - 16}-01-01');
    await open(t);
    expect(find.text('لا يمكن عرض هذا الملف.'), findsOneWidget);
    expect(calls, ['tpdb:performer']);
  });

  test('من عمل معها في ThePornDB: يُقرأ من مشاهدها (بما فيها parent)، ويُستبعد غير الإناث ونفسها', () async {
    sourceClient = MockClient((r) async => http.Response(jsonEncode({'data': [
      {'id': 's1', 'performers': [{'id': 'ME', 'name': 'Me'}, {'id': 'a', 'name': 'Anna', 'extra': {'gender': 'Female'}}, {'id': 'm', 'name': 'Mark', 'extra': {'gender': 'Male'}}]},
      {'id': 's2', 'performers': [{'id': 'child', 'name': 'Anna B', 'parent': {'id': 'a', 'name': 'Anna', 'extras': {'gender': 'Female'}}}]},
    ], 'meta': {'last_page': 1}}), 200));
    final m = await tpdbCoStars('ME');
    expect(m.keys.toSet(), {'a'}); expect(m['a']!.$2, 2);
  });
}
