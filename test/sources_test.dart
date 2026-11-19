// المصادر الرسمية بلا شبكة حقيقية (MockClient): بوابة +18 للمرشحين، تحويل الأعمال، الدمج، والأخطاء.
import 'dart:convert';

import 'package:favorites2/data/keys.dart';
import 'package:favorites2/data/sources.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // مخزن آمن وهمي في الاختبار
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    switch (c.method) { case 'read': return store[a['key']]; case 'write': store[a['key']] = a['value']; return null; case 'delete': store.remove(a['key']); return null; }
    return null;
  });

  setUp(() async { await ApiKeys.set(ApiKeys.stash, 'S-KEY'); await ApiKeys.set(ApiKeys.tpdb, 'T-KEY'); });

  test('StashDB: البالغة تُقبل، القاصر والتاريخ غير الصالح يُستبعدان، والذكور لا يظهرون', () async {
    sourceClient = MockClient((r) async {
      expect(r.headers['ApiKey'], 'S-KEY');
      return http.Response(jsonEncode({'data': {'searchPerformer': [
        {'id': '1', 'name': 'Adult A', 'birth_date': '1995-02-02', 'gender': 'FEMALE', 'images': [{'url': 'https://img.test/a.jpg', 'width': 600, 'height': 900}]},
        {'id': '2', 'name': 'Minor B', 'birth_date': '2012-01-01', 'gender': 'FEMALE', 'images': []},
        {'id': '3', 'name': 'Bad C', 'birth_date': 'soon', 'gender': 'FEMALE'},
        {'id': '4', 'name': 'Male D', 'birth_date': '1990-01-01', 'gender': 'MALE'},
        {'id': '5', 'name': 'NoDate E', 'gender': 'FEMALE'},
      ]}}), 200);
    });
    final r = await StashDB.search('x');
    expect(r.map((c) => c.name), ['Adult A', 'Minor B', 'Bad C', 'NoDate E']);
    expect(r.where((c) => c.adult).map((c) => c.name), ['Adult A', 'NoDate E']);
    expect(r.first.image, 'https://img.test/a.jpg');
  });

  test('StashDB: مفتاح غير صالح ⇒ رسالة عربية واضحة', () async {
    sourceClient = MockClient((r) async => http.Response('unauthorized', 401));
    expect(() => StashDB.search('x'), throwsA(isA<SourceError>().having((e) => e.msg, 'msg', contains('غير صالح'))));
  });

  test('StashDB: الأعمال تتحول للصيغة المحلية (المدة بالدقائق، روابط https، الوسوم)', () async {
    sourceClient = MockClient((r) async => http.Response(jsonEncode({'data': {'queryScenes': {'count': 1, 'scenes': [
      {'id': 'sc-1', 'title': 'Scene One', 'release_date': '2024-03-05', 'duration': 1800, 'details': 'desc', 'studio': {'name': 'St'}, 'images': [{'url': 'https://img.test/w.jpg', 'width': 1280, 'height': 720}], 'tags': [{'name': 'tag1'}]},
    ]}}}), 200));
    final w = await StashDB.scenes('pid');
    expect(w.single['t'], 'Scene One'); expect(w.single['d'], '2024-03-05'); expect(w.single['du'], 30);
    expect(w.single['p'], 'https://img.test/w.jpg'); expect(w.single['is'], 'sc-1'); expect(w.single['tg'], ['tag1']);
  });

  test('StashDB: إن رفض الخادم حقلًا (إصدار أقدم) يُستخدم استعلام بديل ولا يفشل الجلب', () async {
    var calls = 0;
    sourceClient = MockClient((r) async {
      calls++; final q = jsonDecode(r.body)['query'] as String;
      if (q.contains('release_date')) return http.Response(jsonEncode({'errors': [{'message': 'Cannot query field "release_date" on type "Scene".'}]}), 422);
      return http.Response(jsonEncode({'data': {'queryScenes': {'count': 1, 'scenes': [{'id': 's1', 'title': 'Old Server Scene', 'date': '2020-02-03', 'studio': {'name': 'St'}}]}}}), 200);
    });
    final w = await StashDB.scenes('pid', maxPages: 1);
    expect(w.single['t'], 'Old Server Scene'); expect(w.single['d'], '2020-02-03'); expect(calls, 2);
  });

  test('ThePornDB: البحث بالمفتاح، والبوابة على تاريخ الميلاد', () async {
    sourceClient = MockClient((r) async {
      expect(r.headers['Authorization'], 'Bearer T-KEY');
      return http.Response(jsonEncode({'data': [
        {'id': 'p1', 'name': 'Adult T', 'image': 'https://img.test/t.jpg', 'extras': {'birthday': '1993-07-07', 'gender': 'Female', 'nationality': 'US', 'height': '165cm'}},
        {'id': 'p2', 'name': 'Minor T', 'extras': {'birthday': '2011-01-01', 'gender': 'Female'}},
      ]}), 200);
    });
    final r = await TPDB.search('x');
    expect(r.where((c) => c.adult).single.name, 'Adult T');
    expect(r.first.height, 165);
  });

  test('دمج الأعمال: الموجود تُملأ حقوله الفارغة فقط، والجديد يُضاف بتاريخ إضافة، ولا يُحذف شيء', () {
    final cur = [{'t': 'Scene One', 's': 'St', 'r': 5, 'n': 'ملاحظتي'}, {'t': 'Old', 's': 'X'}];
    final m = mergeWorks(cur, [{'t': 'scene one', 's': 'st', 'd': '2024-03-05', 'r': 1, 'p': 'https://img.test/p.jpg'}, {'t': 'Brand New', 's': 'Y'}]);
    expect(m.list.length, 3); expect(m.added, 1); expect(m.filled, 1);
    expect(m.list[0]['r'], 5); expect(m.list[0]['n'], 'ملاحظتي'); expect(m.list[0]['d'], '2024-03-05'); expect(m.list[0]['p'], 'https://img.test/p.jpg');
    expect(m.list[2]['a'], isA<int>());
  });

  test('بلا مفتاح ⇒ لا طلب شبكة', () async {
    var called = false; sourceClient = MockClient((r) async { called = true; return http.Response('{}', 200); });
    await ApiKeys.set(ApiKeys.stash, '');
    expect(() => StashDB.search('x'), throwsA(isA<SourceError>()));
    expect(called, isFalse);
  });
}
