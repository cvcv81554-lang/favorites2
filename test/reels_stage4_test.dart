// المرحلة 4 لـ«مقاطع»: علامات Stash، مصغرات VTT، مزامنة المشاهدة، وقت المشاهدة بالثواني، والتعلم حسب فترة اليوم.
import 'dart:convert';

import 'package:favorites2/data/sources.dart';
import 'package:favorites2/data/stash_server.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/reels.dart';
import 'package:favorites2/domain/work_taste.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stashapp_url': 'http://192.168.1.10:9999', 'stashapp_key': 'K'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  test('مقاطع العلامات: الطول من النهاية أو 30 ث، بين 8 و90، بلا تداخل، 3 كحد، ولا تتجاوز الفيديو', () {
    final ms = [const StashMarker(600, 640, 'A'), const StashMarker(100, null, 'B'), const StashMarker(110, 115, 'تداخل'), const StashMarker(900, 1200, 'C'), const StashMarker(1500, null, 'D'), const StashMarker(1795, null, 'آخر')];
    final s = markerSegments(ms, 1800);
    expect(s, [(100, 30, 'B'), (600, 40, 'A'), (900, 90, 'C')]);
    expect(markerSegments([const StashMarker(1797, null, 'x')], 1800), isEmpty);   // قرب النهاية تمامًا
    expect(markerSegments([const StashMarker(1780, null, 'x')], 1800), [(1780, 20, 'x')]);   // تُقص عند النهاية
    expect(markerSegments([const StashMarker(1770, null, 'x')], 1800), [(1770, 30, 'x')]);
    expect(markerSegments([const StashMarker(10, 12, 'قصير')], 0), [(10, 8, 'قصير')]);
  });

  test('VTT: قراءة المصغرات، حل الرابط النسبي مع المفتاح، والبحث بالزمن', () {
    const vtt = 'WEBVTT\n\n00:00:00.000 --> 00:00:05.000\n100_sprite.jpg#xywh=0,0,160,90\n\n00:00:05.000 --> 00:01:10.500\n100_sprite.jpg#xywh=160,0,160,90\n';
    final c = parseVtt(vtt, 'http://192.168.1.10:9999/scene/100_thumbs.vtt?apikey=K');
    expect(c.length, 2);
    expect(c[1].start, 5); expect(c[1].end, 70.5); expect(c[1].x, 160); expect(c[1].w, 160);
    expect(c[0].url, 'http://192.168.1.10:9999/scene/100_sprite.jpg?apikey=K');
    expect(cueAt(c, 3)!.x, 0); expect(cueAt(c, 20)!.x, 160); expect(cueAt(c, 999)!.x, 160); expect(cueAt(const [], 1), isNull);
  });

  test('المقاطع تحمل العلامات ومكان التوقف وعدد المشاهدات، والمزامنة ترسل الطفرات الرسمية', () async {
    final sent = <String>[];
    sourceClient = MockClient((r) async {
      final q = '${(jsonDecode(r.body) as Map)['query']}'; sent.add(q);
      if (q.contains('findScenes')) {
        return http.Response(jsonEncode({'data': {'findScenes': {'count': 1, 'scenes': [{'id': '100', 'title': 'S', 'play_count': 3, 'resume_time': 412.5, 'files': [{'duration': 1800.0}],
          'paths': {'stream': 'http://192.168.1.10:9999/scene/100/stream', 'vtt': 'http://192.168.1.10:9999/scene/100_thumbs.vtt'},
          'scene_markers': [{'id': 'm1', 'title': '', 'seconds': 300.5, 'end_seconds': 345.0, 'primary_tag': {'name': 'Best'}}], 'performers': [{'id': '7'}]}]}}}), 200);
      }
      return http.Response(jsonEncode({'data': {'ok': true}}), 200);
    });
    final g = (await StashServer.scenes({'7': Performer({'id': 'a', 'name': 'Jane', 'birth': '1995-01-01'})})).single;
    final ex = StashServer.extra[g.key]!;
    expect(ex.id, '100'); expect(ex.resume, 412.5); expect(ex.plays, 3); expect(ex.vtt, contains('apikey=K'));
    expect(ex.markers.single.label, 'Best'); expect(markerSegments(ex.markers, 1800), [(300, 45, 'Best')]);
    await StashServer.saveActivity('100', resume: 500, played: 90); await StashServer.addPlay('100');
    expect(sent.any((q) => q.contains('sceneSaveActivity')), isTrue); expect(sent.any((q) => q.contains('sceneAddPlay')), isTrue);
  });

  test('وقت المشاهدة بالثواني: 3 دقائق من فيديو طويل ليست تخطيًا، والإعادة أقوى إشارة', () {
    expect(viewSignal(.08, 180), greaterThan(.5));   // نسبة صغيرة لكن مشاهدة حقيقية
    expect(viewSignal(.08, 2), -.35);                 // تخطٍّ سريع فعلي
    expect(viewSignal(.08, -1), -.35);                // ثوانٍ غير معروفة ⇒ النسبة فقط
    expect(viewSignal(2.0, 30), 1.0);                 // إعادة
    expect(viewSignal(2.0, 30) > viewSignal(.95, 30), isTrue);
  });

  test('التعلم حسب فترة اليوم: ما تشاهده ليلًا يتقدم ليلًا', () {
    final perf = [for (var k = 0; k < 4; k++) Performer({'id': 'p$k', 'name': 'P$k', 'fav': true, 'works': [for (var j = 0; j < 3; j++) {'t': 'W$k-$j', 's': 'S$k', 'd': '2024-01-01', 'ip': 'W$k-$j', 'tr': 'https://cdn.test/$k-$j.mp4'}]})];
    final gs = groupWorks(perf); final t = buildWorkTaste(gs);
    var s = const ReelSignals({}, {});
    for (var i = 0; i < 4; i++) { s = recordView(s, gs.firstWhere((x) => x.t == 'W3-$i' || x.t == 'W3-0'), frac: 1.0, secs: 40, hour: 1); }
    expect(dayPart(1), 3); expect(dayPart(9), 0); expect(dayPart(15), 1); expect(dayPart(20), 2);
    expect(s.aff['d3|pf:p3']! > 1, isTrue); expect(s.aff['d1|pf:p3'], isNull);
    final night = rankReels(gs, t, s, seed: 1, hour: 1), noon = rankReels(gs, t, s, seed: 1, hour: 14);
    expect(night.first.g.who.first.id, 'p3');
    expect(night.first.why, anyOf(contains('عادةً ليلًا'), contains('P3')));
    expect(noon.where((r) => r.why.contains('عادةً ليلًا')), isEmpty);
  });
}
