// مكتبة Stash: بوابة +18 على تواريخ الخادم، اختيار البث المتكيّف للصيغ التي لا يشغّلها الآيفون، والبحث والتصفية.
import 'dart:convert';

import 'package:favorites2/data/sources.dart';
import 'package:favorites2/data/stash_server.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> scene(String id, {List<Map<String, dynamic>> ps = const [], String fmt = 'mp4', String vc = 'h264'}) => {
  'id': id, 'title': 'T$id', 'files': [{'duration': 600.0, 'height': 1080, 'format': fmt, 'video_codec': vc}],
  'paths': {'stream': 'http://s/scene/$id/stream', 'screenshot': 'http://s/scene/$id/screenshot'}, 'performers': ps};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stashapp_url': 'http://s', 'stashapp_key': 'K'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });
  final y = DateTime.now().year;

  test('بوابة +18: مشهد فيه ممثلة تاريخها أقل من 18 أو غير صالح يُستبعد كله، وبلا تاريخ يُقبل', () {
    expect(StashServer.parseScene(scene('1', ps: [{'id': '1', 'name': 'A', 'birthdate': '1995-01-01'}, {'id': '2', 'name': 'B', 'birthdate': '${y - 17}-06-01'}]), 'K', const {}), isNull);
    expect(StashServer.parseScene(scene('2', ps: [{'id': '1', 'name': 'A', 'birthdate': '2001-02-30'}]), 'K', const {}), isNull);
    expect(StashServer.parseScene(scene('3', ps: [{'id': '1', 'name': 'A', 'birthdate': '${y - 18}'}]), 'K', const {}), isNull);   // سنة فقط ⇒ أسوأ حالة
    final g = StashServer.parseScene(scene('4', ps: [{'id': '9', 'name': 'NoDate'}]), 'K', const {})!;
    expect(g.who.single.id, 'stashp:9'); expect(g.tr, 'http://s/scene/4/stream?apikey=K');
    expect(StashServer.parseScene(scene('5', ps: [{'id': '9', 'name': 'NoDate'}]), 'K', const {}, libraryOnly: true), isNull);   // الخلاصة: ممثلات مكتبتك فقط
    final lib = Performer({'id': 'L', 'name': 'Mine', 'birth': '1990-01-01'});
    expect(StashServer.parseScene(scene('6', ps: [{'id': '9', 'name': 'Mine'}]), 'K', {'9': lib}, libraryOnly: true)!.who.single.id, 'L');
  });

  test('الصيغ: mp4/H.264 مباشر، وmkv أو wmv أو ترميز غير مدعوم ⇒ HLS', () {
    StashServer.parseScene(scene('10'), 'K', const {});
    StashServer.parseScene(scene('11', fmt: 'mkv'), 'K', const {});
    StashServer.parseScene(scene('12', fmt: 'mp4', vc: 'vc1'), 'K', const {});
    StashServer.parseScene(scene('13', fmt: 'mov', vc: 'hevc'), 'K', const {});
    expect(StashServer.extra['stash:10']!.direct, isTrue);
    expect(StashServer.extra['stash:11']!.direct, isFalse);
    expect(StashServer.extra['stash:12']!.direct, isFalse);
    expect(StashServer.extra['stash:13']!.direct, isTrue);
    expect(StashServer.extra['stash:10']!.withResume(30).resume, 30);
  });

  test('رابط HLS من sceneStreams (مع المفتاح)، ولا شيء إن لم يوجد', () async {
    sourceClient = MockClient((r) async => http.Response(jsonEncode({'data': {'sceneStreams': [
      {'url': 'http://s/scene/1/stream', 'mime_type': 'video/mp4', 'label': 'Direct stream'},
      {'url': 'http://s/scene/1/stream.m3u8?resolution=STANDARD', 'mime_type': 'application/vnd.apple.mpegurl', 'label': 'HLS'},
    ]}}), 200));
    expect(await StashServer.hls('1'), 'http://s/scene/1/stream.m3u8?resolution=STANDARD&apikey=K');
    sourceClient = MockClient((r) async => http.Response(jsonEncode({'data': {'sceneStreams': [{'url': 'x', 'mime_type': 'video/mp4', 'label': 'Direct'}]}}), 200));
    expect(await StashServer.hls('1'), isNull);
  });

  test('التصفح: البحث والترتيب و«ممثلاتي فقط» و«تابع المشاهدة» تصل للخادم، وممثلات الخادم تمر ببوابة +18', () async {
    final sent = <Map>[];
    sourceClient = MockClient((r) async {
      final b = jsonDecode(r.body) as Map; sent.add(b);
      if ('${b['query']}'.contains('findPerformers')) {
        return http.Response(jsonEncode({'data': {'findPerformers': {'count': 2, 'performers': [
          {'id': '1', 'name': 'Adult', 'birthdate': '1990-01-01', 'image_path': 'http://s/p/1/image', 'scene_count': 5, 'favorite': true},
          {'id': '2', 'name': 'Minor', 'birthdate': '${y - 16}-01-01', 'scene_count': 3}]}}}), 200);
      }
      return http.Response(jsonEncode({'data': {'findScenes': {'count': 1, 'scenes': [scene('20', ps: [{'id': '1', 'name': 'Adult', 'birthdate': '1990-01-01'}])]}}}), 200);
    });
    final r = await StashServer.browse(query: 'beach', sort: 'date', page: 2, mine: ['7', '8']);
    expect(r.$2, 1); expect(r.$1.single.key, 'stash:20');
    final v = sent.last['variables'] as Map;
    expect(v['q'], 'beach'); expect(v['p'], 2); expect(v['s'], 'date'); expect(v['dir'], 'DESC'); expect(v['ids'], ['7', '8']);
    expect('${sent.last['query']}', contains('performers:{value:\$ids'));
    await StashServer.browse(mode: 'resume');
    expect('${sent.last['query']}', contains('resume_time:{value:10,modifier:GREATER_THAN}'));
    expect((sent.last['variables'] as Map).containsKey('ids'), isFalse);
    final ps = await StashServer.performers();
    expect(ps.$1.map((p) => p.name), ['Adult']); expect(ps.$1.single.image, 'http://s/p/1/image?apikey=K');
  });
}
