// تحليل الذوق يقترح من المصدرين: مرشحة موجودة في ThePornDB فقط (عملت مع مفضلاتك هناك) تظهر في الاقتراحات بسببها.
import 'dart:convert';

import 'package:favorites2/data/library_repo.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/ui/core/state.dart';
import 'package:favorites2/ui/features/discover/taste_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stash_key': 'S', 'tpdb_key': 'T'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  test('مرشحة من ThePornDB فقط تظهر بسبب «عملت مع» ومصدرها ThePornDB', () async {
    const attrs = {'ethnicity': 'CAUCASIAN', 'hair_color': 'BRUNETTE', 'eye_color': 'BROWN', 'height': 165, 'birth_date': '1995-05-05', 'gender': 'FEMALE'};
    sourceClient = MockClient((r) async {
      if (r.url.host == 'stashdb.org') {
        final q = '${jsonDecode(r.body)['query']}';
        if (q.contains('findPerformer')) return http.Response(jsonEncode({'data': {'findPerformer': {'id': 'x', 'name': 'Fav', ...attrs, 'images': []}}}), 200);
        return http.Response(jsonEncode({'data': {'queryPerformers': {'performers': []}}}), 200);   // لا مرشحات من StashDB هنا
      }
      final seg = r.url.pathSegments;
      if (seg.length == 3 && seg[2] == 'scenes') {
        return http.Response(jsonEncode({'data': [{'id': 's', 'performers': [{'id': seg[1], 'name': 'Fav'}, {'id': 'C1', 'name': 'Cora Sample', 'extra': {'gender': 'Female'}}]}], 'meta': {'last_page': 1}}), 200);
      }
      if (seg.length == 2 && seg[1] == 'C1') {
        return http.Response(jsonEncode({'data': {'id': 'C1', 'name': 'Cora Sample', 'extras': {'gender': 'Female', 'birthday': '1996-01-01', 'ethnicity': 'Caucasian', 'hair_colour': 'Brunette', 'eye_colour': 'Brown', 'height': '166cm'}, 'image': 'https://img.test/c1.jpg'}}), 200);
      }
      return http.Response(jsonEncode({'data': {'id': seg.last, 'name': 'Fav', 'extras': {'gender': 'Female', 'birthday': '1995-05-05'}}}), 200);
    });
    final repo = LibraryRepo.withDb(await databaseFactoryMemory.openDatabase('tt${DateTime.now().microsecondsSinceEpoch}'));
    await repo.save([for (var i = 1; i <= 3; i++) Performer({'id': 'f$i', 'name': 'Fav $i', 'fav': true, 'rating': 5, 'stashId': 'F$i', 'pdbId': 'P$i', 'birth': '1995-05-05'})]);
    final c = ProviderContainer(overrides: [repoProvider.overrideWith((ref) async => repo)]);
    await c.read(libraryProvider.future); await c.read(tasteProvider.future);
    await c.read(tasteProvider.notifier).analyze();
    final st = c.read(tasteProvider).value!;
    expect(st.err, isEmpty);
    final r = st.recs.where((x) => x.id == 'tp:C1').firstOrNull;
    expect(r, isNotNull);
    expect(r!.sources, 'ThePornDB');
    expect(r.why.first, contains('عملت مع'));
    expect(r.tags.any((t) => t.startsWith('with:')), isTrue);
    expect(st.withNames, isNotEmpty);
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
