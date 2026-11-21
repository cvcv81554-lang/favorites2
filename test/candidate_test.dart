// صفحة المرشحة من «اكتشف»: تعرض الملف الصحيح ببياناته وأعماله، تحترم بوابة +18 قبل أي طلب أعمال/صور، وتحوّل لملف المكتبة إن كانت موجودة.
import 'dart:convert';

import 'package:favorites2/data/library_repo.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
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
  final store = <String, String>{'stash_key': 'K'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    switch (c.method) { case 'read': return store[a['key']]; case 'write': store[a['key']] = a['value']; return null; case 'containsKey': return store.containsKey(a['key']); }
    return null;
  });

  final calls = <String>[];
  void mockStash(String birth) {
    calls.clear();
    sourceClient = MockClient((r) async {
      final q = '${jsonDecode(r.body)['query']}';
      calls.add(q.contains('findPerformer') ? 'performer' : q.contains('queryScenes') ? 'scenes' : 'other');
      if (q.contains('findPerformer')) {
        return http.Response(jsonEncode({'data': {'findPerformer': {'id': 'S1', 'name': 'Sample One', 'aliases': ['S. One'], 'gender': 'FEMALE', 'birth_date': birth, 'country': 'CZ',
          'ethnicity': 'CAUCASIAN', 'hair_color': 'BRUNETTE', 'eye_color': 'BLUE', 'height': 165, 'career_start_year': 2019, 'scene_count': 42,
          'images': [{'url': 'https://img.test/small.jpg', 'width': 300, 'height': 400}, {'url': 'https://img.test/big.jpg', 'width': 1200, 'height': 1600}]}}}), 200);
      }
      return http.Response(jsonEncode({'data': {'queryScenes': {'count': 1, 'scenes': [{'id': 'SC1', 'title': 'Neutral Scene Title', 'release_date': '2024-02-02', 'studio': {'name': 'Studio X'}, 'images': []}]}}}), 200);
    });
  }

  Future<void> open(WidgetTester t, {List<Performer> lib = const []}) async {
    final repo = LibraryRepo.withDb((await t.runAsync(() => databaseFactoryMemory.openDatabase('cand${DateTime.now().microsecondsSinceEpoch}')))!);
    if (lib.isNotEmpty) await t.runAsync(() => repo.save(lib));
    final router = GoRouter(initialLocation: '/c/S1', routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('home')),
      GoRoute(path: '/c/:sid', builder: (_, s) => CandidateScreen(stashId: s.pathParameters['sid']!, why: const ['لون الشعر بني مثل 75٪ من مفضلاتك'])),
      GoRoute(path: '/p/:id', builder: (_, s) => Text('profile:${s.pathParameters['id']}')),
    ]);
    await t.pumpWidget(ProviderScope(overrides: [repoProvider.overrideWith((ref) async => repo)], child: MaterialApp.router(routerConfig: router)));
    for (var i = 0; i < 20; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20))); await t.pump(const Duration(milliseconds: 50)); }
  }

  testWidgets('بالغة: الاسم والبيانات وسبب الاقتراح والأعمال وزر الإضافة', (t) async {
    mockStash('1998-03-03');
    await open(t);
    expect(find.text('Sample One'), findsOneWidget);
    expect(find.text('165 سم'), findsOneWidget);
    expect(find.text('بني'), findsOneWidget);                       // ترجمة لون الشعر
    expect(find.textContaining('مثل 75٪'), findsOneWidget);
    expect(find.text('إضافة لمكتبتي'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Neutral Scene Title'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Neutral Scene Title'), findsOneWidget);
    expect(calls, containsAll(['performer', 'scenes']));
  });

  testWidgets('قاصر (أو تاريخ غير صالح): لا عرض ولا طلب أعمال ولا صور', (t) async {
    mockStash('${DateTime.now().year - 16}-01-01');
    await open(t);
    expect(find.text('لا يمكن عرض هذا الملف.'), findsOneWidget);
    expect(find.text('Sample One'), findsNothing);
    expect(calls, ['performer']);                                    // البوابة قبل طلب الأعمال
  });

  testWidgets('موجودة في المكتبة ⇒ يُفتح ملفها مباشرة بلا طلب شبكة', (t) async {
    mockStash('1998-03-03');
    await open(t, lib: [Performer({'id': 'mine', 'name': 'Sample One', 'stashId': 'S1', 'birth': '1998-03-03'})]);
    expect(find.text('profile:mine'), findsOneWidget);
    expect(calls, isEmpty);
  });
}
