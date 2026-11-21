// صور الأعمال الناقصة: تُجلب بمعرّف المشهد فقط، وتُكتب في كل نسخ العمل، ولا تُكرَّر الطلبات.
import 'dart:convert';

import 'package:favorites2/data/keys.dart';
import 'package:favorites2/data/library_repo.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/ui/core/posters.dart';
import 'package:favorites2/ui/core/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    switch (c.method) { case 'read': return store[a['key']]; case 'write': store[a['key']] = a['value']; return null; case 'delete': store.remove(a['key']); return null; }
    return null;
  });

  test('صورة العمل تُجلب بمعرّفه وتُكتب في نسخه عند كل الممثلات، مرة واحدة فقط', () async {
    await ApiKeys.set(ApiKeys.stash, 'K');
    var calls = 0;
    sourceClient = MockClient((r) async {
      calls++;
      final q = jsonDecode(r.body);
      expect(q['variables']['id'], 'S1');
      return http.Response(jsonEncode({'data': {'findScene': {'images': [{'url': 'https://img.test/small.jpg', 'width': 320, 'height': 180}, {'url': 'https://img.test/big.jpg', 'width': 1920, 'height': 1080}]}}}), 200);
    });
    final repo = LibraryRepo.withDb(await databaseFactoryMemory.openDatabase('posters1'));
    await repo.save([
      Performer({'id': 'a', 'name': 'A', 'works': [{'t': 'Scene', 's': 'St', 'is': 'S1'}, {'t': 'Other', 's': 'St'}]}),
      Performer({'id': 'b', 'name': 'B', 'works': [{'t': 'Scene', 's': 'St', 'is': 'S1'}]}),
    ]);
    final c = ProviderContainer(overrides: [repoProvider.overrideWith((ref) async => repo)]);
    await c.read(libraryProvider.future);
    final r = c.read(posterResolverProvider.notifier);
    r.want('is:S1'); r.want('is:S1'); r.want('bad-id');
    for (var k = 0; k < 100; k++) { await Future<void>.delayed(const Duration(milliseconds: 200)); if (c.read(libraryProvider).value!.every((p) => p.works.first['p'] != null)) break; }
    final lib = c.read(libraryProvider).value!;
    expect(lib.firstWhere((p) => p.id == 'a').works.first['p'], 'https://img.test/big.jpg');
    expect(lib.firstWhere((p) => p.id == 'b').works.first['p'], 'https://img.test/big.jpg');
    expect(lib.firstWhere((p) => p.id == 'a').works[1].containsKey('p'), isFalse);   // عمل بلا معرّف لا يُمس
    expect(calls, 1);
    c.dispose();
  });
}
