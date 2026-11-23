// التحميل المسبق، مقاطع الصور البديلة، تفضيل المحفوظ، رفع الجودة، والإعدادات.
import 'dart:io';
import 'dart:typed_data';

import 'package:favorites2/data/clip_prefetch.dart';
import 'package:favorites2/data/platform/clip_cache_io.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/reels.dart';
import 'package:favorites2/domain/work_taste.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.StreamedResponse video([int n = 4000]) => http.StreamedResponse(Stream.value(Uint8List(n)), 200, contentLength: n, headers: {'content-type': 'video/mp4'});

void main() {
  test('الإعدادات الافتراضية: 100 مقطع، تحميل ليلي، صوت، لحاق، 3GB', () {
    final c = ReelsCfg.fromJson(null);
    expect(c.count, 100); expect(c.night, isTrue); expect(c.sound, isTrue); expect(c.catchUp, isTrue); expect(c.gb, 3); expect(c.prefetch, isTrue);
    expect(ReelsCfg.fromJson(c.copy(count: 200, sound: false).toJson()).count, 200);
  });

  test('المحجوب يصبح «صورًا» (لا يختفي) والمحفوظ يُفضَّل', () {
    final p = Performer({'id': 'a', 'name': 'A', 'fav': true, 'photos': ['file:a.jpg'], 'works': [
      {'t': 'Blocked', 's': 'S', 'd': '2024-01-01', 'ip': '1', 'tr': 'https://blocked.test/1.mp4', 'p': 'https://img.test/1.jpg'},
      {'t': 'Open', 's': 'S', 'd': '2024-01-01', 'ip': '2', 'tr': 'https://open.test/2.mp4', 'p': 'https://img.test/2.jpg'},
      {'t': 'Saved', 's': 'S', 'd': '2020-01-01', 'ip': '3', 'tr': 'https://blocked.test/3.mp4', 'p': 'https://img.test/3.jpg'},
    ]});
    final g = groupWorks([p]);
    final hosts = <String, dynamic>{'blocked.test': {'ok': false, 't': DateTime.now().millisecondsSinceEpoch}};
    bool cached(String u) => u.endsWith('/3.mp4');
    final f = rankReels(g, buildWorkTaste(g), const ReelSignals({}, {}), playable: (u) => hostUsable(hosts, u) || cached(u), isCached: cached, photoFallback: true);
    expect(f.length, 3);
    final ph = f.firstWhere((r) => r.g.t == 'Blocked');
    expect(ph.photo, isTrue); expect(ph.images, contains('https://img.test/1.jpg')); expect(ph.why, contains('صور'));
    expect(f.firstWhere((r) => r.g.t == 'Saved').photo, isFalse);          // محفوظ على الجهاز ⇒ يعمل رغم حجب خادمه
    expect(f.last.photo, isTrue);                                           // الحقيقية أولًا
    expect(prefetchOrder(f).any((u) => u.contains('/1.mp4')), isFalse);    // لا يُحمَّل ما هو صور
  });

  test('رفع الجودة: 720p ⇒ 1080p، ولا تغيير لما هو 1080p أو بلا رقم', () {
    expect(higherQuality('https://cdn.test/v/clip_720p.mp4'), 'https://cdn.test/v/clip_1080p.mp4');
    expect(higherQuality('https://cdn.test/480p/x.mp4'), 'https://cdn.test/1080p/x.mp4');
    expect(higherQuality('https://cdn.test/clip_1080p.mp4'), isNull);
    expect(higherQuality('https://cdn.test/clip.mp4'), isNull);
  });

  test('التنزيل: يجرّب 1080p أولًا ويرجع للأصل إن لم يوجد، ويحفظه باسم الرابط الأصلي', () async {
    clipCacheDirForTest = await Directory.systemTemp.createTemp('hq');
    final asked = <String>[];
    sourceClient = MockClient.streaming((r, _) async { asked.add(r.url.path); return r.url.path.contains('1080p') ? http.StreamedResponse(const Stream.empty(), 404) : video(); });
    final path = await downloadClip('https://hq.test/a_720p.mp4');
    expect(path, isNotNull); expect(asked, ['/a_1080p.mp4', '/a_720p.mp4']);
    expect(await cachedClipPath('https://hq.test/a_720p.mp4'), path);
    asked.clear();
    await downloadClip('https://hq.test/b_720p.mp4');
    expect(asked, ['/b_720p.mp4']);                                         // الخادم تعلّم أنه بلا 1080p
  });

  test('التحميل المسبق: حتى العدد المطلوب، يحسب المحفوظ، ويتوقف عند الطلب', () async {
    clipCacheDirForTest = await Directory.systemTemp.createTemp('pf');
    var n = 0;
    sourceClient = MockClient.streaming((r, _) async { n++; return video(); });
    final urls = [for (var i = 0; i < 10; i++) 'https://pf.test/$i.mp4'];
    final r = await prefetchClips(urls, max: 4);
    expect(r, (4, 4)); expect(n, 4);
    final again = await prefetchClips(urls, max: 6);
    expect(again, (6, 6)); expect(n, 6);                                    // لا يُعاد تنزيل المحفوظ
    var calls = 0;
    final stopped = await prefetchClips(urls, max: 10, cancelled: () => ++calls > 1);
    expect(stopped.$1 < 10, isTrue);
    expect((await clipCacheStats()).$1.length, stopped.$1);
  });
}
