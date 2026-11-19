// اختبارات إصلاحات المراجعة: عناوين الشبكة المحلية، تطبيع تواريخ الأعمال، ومدخلات/جلب الخلفية (بلا قاعدة بيانات).
import 'dart:convert';

import 'package:favorites2/data/background.dart';
import 'package:favorites2/data/keys.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/data/studio_repo.dart';
import 'package:favorites2/data/sync_io.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/sanitize.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    switch (c.method) { case 'read': return store[a['key']]; case 'write': store[a['key']] = a['value']; return null; case 'delete': store.remove(a['key']); return null; }
    return null;
  });

  test('عناوين الشبكة المحلية: 10.x و 192.168 و 172.16–31 فقط', () {
    for (final ok in ['10.0.1.5', '10.0.1.5:8787', '192.168.1.20:8787', '172.16.0.9', '172.31.255.1:80']) { expect(isLanHost(ok), isTrue, reason: ok); }
    for (final bad in ['8.8.8.8', '172.32.0.1', '10.0.1', 'example.com', '192.168.1.20.5']) { expect(isLanHost(bad), isFalse, reason: bad); }
  });

  test('تواريخ الأعمال الواردة تُطبَّع ولا تكسر الشاشات', () {
    final w = safeWorks([{'t': 'A', 'd': '5-3-2024', 'wd': '2024/1/2'}, {'t': 'B', 'd': 'garbage', 'y': 'x'}, {'t': 'C', 'd': '2024', 'wd': '2024-02-03'}]);
    expect(w[0]['d'], '2024-03-05'); expect(w[0]['y'], '2024'); expect(w[0].containsKey('wd'), isFalse);
    expect(w[1].containsKey('d'), isFalse); expect(w[1].containsKey('y'), isFalse);
    expect(w[2].containsKey('d'), isFalse); expect(w[2]['y'], '2024'); expect(w[2]['wd'], '2024-02-03');
  });

  test('مدخلات الخلفية: البالغات المرتبطات فقط', () {
    final lib = [Performer({'id': 'a', 'name': 'A', 'birth': '1990-01-01', 'stashId': 'S1', 'works': [{'t': 'Old', 's': 'X'}]}), Performer({'id': 'm', 'name': 'M', 'birth': '2015-01-01', 'stashId': 'S2'}), Performer({'id': 'n', 'name': 'N'})];
    final inp = buildBgInput(const BgSettings(on: true), lib, {'img1'});
    expect((inp['ids'] as List).map((e) => e['id']), ['a']);
    expect((inp['ids'] as List).first['k'], [wKeyOf({'t': 'Old', 's': 'X'})]);
  });

  test('الجلب: أعمال جديدة فقط، وصور غير معروفة فقط، وبلا قاعدة بيانات، والمؤشر يدور', () async {
    await ApiKeys.set(ApiKeys.stash, 'K');
    sourceClient = MockClient((r) async {
      final q = jsonDecode(r.body)['query'] as String;
      if (q.contains('queryScenes')) return http.Response(jsonEncode({'data': {'queryScenes': {'count': 2, 'scenes': [{'id': '1', 'title': 'Old', 'studio': {'name': 'X'}}, {'id': '2', 'title': 'New One', 'studio': {'name': 'Y'}, 'release_date': '2026-01-01'}]}}}), 200);
      return http.Response(jsonEncode({'data': {'findPerformer': {'images': [{'url': 'https://stashdb.org/images/known', 'width': 10, 'height': 10}, {'url': 'https://stashdb.org/images/new', 'width': 10, 'height': 10}]}}}), 200);
    });
    final lib = [Performer({'id': 'a', 'name': 'A', 'birth': '1990-01-01', 'stashId': 'S1', 'works': [{'t': 'Old', 's': 'X'}]})];
    final known = {'5f9d'}; // معرّف آخر
    final inp = buildBgInput(const BgSettings(on: true), lib, {...known, ...[ for (final u in ['https://stashdb.org/images/known']) _id(u) ]});
    final r = await fetchUpdates(inp, limit: 15);
    expect(r.works['a']!.map((w) => w['t']), ['New One']);
    expect(r.images.map((x) => x.url), ['https://stashdb.org/images/new']);
    expect(r.nextCursor, 0);
  });
}

String _id(String u) => StudioRepo.idOf(u);
