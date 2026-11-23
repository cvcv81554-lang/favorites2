// خادم Stash الخاص بك: اختبار الاتصال والمفتاح، ربط الممثلة (StashDB ثم الاسم)، تحويل المقاطع، المقطع القصير، والدمج.
import 'dart:convert';

import 'package:favorites2/data/sources.dart';
import 'package:favorites2/data/stash_server.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/reels.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stashapp_url': '192.168.1.10:9999/', 'stashapp_key': 'K'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  test('العنوان يُطبَّع، والمفتاح يُرسل، والرفض برسالة واضحة', () async {
    expect(StashServer.normalize('192.168.1.10:9999/'), 'http://192.168.1.10:9999');
    expect(StashServer.normalize('https://stash.local'), 'https://stash.local');
    sourceClient = MockClient((r) async {
      expect(r.url.toString(), 'http://192.168.1.10:9999/graphql');
      return r.headers['ApiKey'] == 'K' ? http.Response(jsonEncode({'data': {'version': {'version': 'v0.27.0'}}}), 200) : http.Response('', 401);
    });
    expect(await StashServer.test('192.168.1.10:9999', 'K'), 'v0.27.0');
    await expectLater(StashServer.test('192.168.1.10:9999', 'wrong'), throwsA(isA<SourceError>().having((e) => e.msg, 'msg', contains('API Key'))));
  });

  test('ربط الممثلة: بمعرّف StashDB أولًا، ثم بالاسم أو الاسم البديل المطابق فقط', () async {
    sourceClient = MockClient((r) async {
      final b = jsonDecode(r.body) as Map; final v = (b['variables'] as Map?) ?? {};
      if ('${b['query']}'.contains('stash_id_endpoint')) return http.Response(jsonEncode({'data': {'findPerformers': {'performers': v['id'] == 'S1' ? [{'id': '7', 'name': 'Jane'}] : []}}}), 200);
      return http.Response(jsonEncode({'data': {'findPerformers': {'performers': [{'id': '9', 'name': 'Janet Other', 'alias_list': []}, {'id': '11', 'name': 'J. Sample', 'alias_list': ['Mia Sample']}]}}}), 200);
    });
    expect(await StashServer.localPerformer(Performer({'id': 'a', 'name': 'Jane', 'stashId': 'S1'})), '7');
    expect(await StashServer.localPerformer(Performer({'id': 'b', 'name': 'Mia Sample'})), '11');
    expect(await StashServer.localPerformer(Performer({'id': 'c', 'name': 'Janet'})), isNull);   // لا مطابقة تقريبية
  });

  test('المقاطع: رابط البث والصورة يحملان المفتاح، وممثلات المكتبة فقط، ومدة الفيديو', () async {
    sourceClient = MockClient((r) async => http.Response(jsonEncode({'data': {'findScenes': {'count': 2, 'scenes': [
      {'id': '100', 'title': 'Home Scene', 'date': '2023-04-05', 'files': [{'duration': 1800.0, 'width': 1920, 'height': 1080}], 'paths': {'stream': 'http://192.168.1.10:9999/scene/100/stream', 'screenshot': 'http://192.168.1.10:9999/scene/100/screenshot'},
        'performers': [{'id': '7', 'name': 'Jane'}, {'id': '99', 'name': 'Not In Library'}], 'studio': {'name': 'Studio Z'}},
      {'id': '101', 'title': '', 'files': [], 'paths': {'stream': 'http://192.168.1.10:9999/scene/101/stream'}, 'performers': [{'id': '99'}]},
    ]}}}), 200));
    final jane = Performer({'id': 'a', 'name': 'Jane', 'birth': '1995-01-01'});
    final l = await StashServer.scenes({'7': jane});
    expect(l.length, 1);
    final g = l.single;
    expect(g.key, 'stash:100'); expect(g.tr, 'http://192.168.1.10:9999/scene/100/stream?apikey=K'); expect(g.p, contains('apikey=K'));
    expect(g.du, 30); expect(g.s, 'Studio Z'); expect(g.y, '2023'); expect(g.who.single.id, 'a');
  });

  test('المقطع القصير: داخل الفيديو، ثابت لنفس الفيديو، ولا شيء لفيديو قصير جدًا', () {
    final a = shortSegment('stash:1', 1800), b = shortSegment('stash:1', 1800);
    expect(a, b); expect(a.$2, 45); expect(a.$1 >= 180 && a.$1 + a.$2 <= 1800, isTrue);
    expect(shortSegment('stash:2', 50), (0, 0));
  });

  test('الدمج: مقطعان من الخادم لكل إعلان، بلا تكرار، ولا يضيع شيء', () {
    final g = WorkGroup('w');
    Reel r(String k, int s) => Reel(WorkGroup(k), 'u$k', '', start: s, len: s > 0 ? 45 : 0);
    final out = weave([r('t1', 0), r('t2', 0)], [r('s1', 10), r('s2', 20), r('s3', 30), r('s4', 40), r('s5', 50)]);
    expect(out.map((x) => x.g.key), ['t1', 's1', 's2', 't2', 's3', 's4', 's5']);
    expect(Reel(g, 'u', '').variant(start: 10, len: 45).key, 'w@10');
    expect(Reel(g, 'u', '').variant(full: true).key, 'w#full');
  });
}
