// مواقع التضمين الرسمية: قراءة كل واجهة بتسامح، مطابقة محافظة بالاسم الكامل، بوابة +18 قبل أي طلب، والمحجوب = غير متاح.
import 'dart:convert';

import 'package:favorites2/data/embed_sources.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final jane = Performer({'id': 'j', 'name': 'Jane Sample', 'birth': '1995-01-01', 'aliases': 'Janey S, JS'});

  test('Pornhub: قائمة الممثلات في الفيديو هي الأساس، والرابط رابط التضمين الرسمي', () async {
    sourceClient = MockClient((r) async {
      expect(r.url.host, 'www.pornhub.com'); expect(r.url.queryParameters['search'], 'Jane Sample');
      return http.Response(jsonEncode({'videos': [
        {'video_id': 'ph1', 'title': 'Untitled', 'duration': '12:30', 'default_thumb': 'https://ci.test/1.jpg', 'pornstars': [{'pornstar_name': 'Jane Sample'}]},
        {'video_id': 'ph2', 'title': 'Jane Samples party', 'duration': '5:00', 'pornstars': [{'pornstar_name': 'Other'}]},
      ]}), 200);
    });
    final l = await searchEmbeds(embedSources.firstWhere((s) => s.id == 'ph'), jane);
    expect(l.length, 1); expect(l.single.tr, 'https://www.pornhub.com/embed/ph1'); expect(l.single.du, 13); expect(l.single.key, 'emb:ph:ph1');
    expect(embedSourceName(l.single.key), 'Pornhub');
  });

  test('RedTube وEporner: صيغتا الرد، والمطابقة بالاسم الكامل كلمةً في العنوان أو الوسوم', () async {
    sourceClient = MockClient((r) async {
      if (r.url.host == 'api.redtube.com') {
        return http.Response(jsonEncode({'videos': [{'video': {'video_id': '55', 'title': 'Best of Jane Sample', 'duration': '1:02:00', 'default_thumb': 'https://t.test/a.jpg'}}, {'video': {'video_id': '56', 'title': 'Janet Samplehouse'}}]}), 200);
      }
      return http.Response(jsonEncode({'videos': [{'id': 'EP1', 'title': 'Scene', 'keywords': 'brunette, Jane Sample, hd', 'length_sec': 900, 'embed': 'https://www.eporner.com/embed/EP1/', 'default_thumb': {'src': 'https://t.test/e.jpg'}}]}), 200);
    });
    final rt = await searchEmbeds(embedSources.firstWhere((s) => s.id == 'rt'), jane);
    expect(rt.map((g) => g.key), ['emb:rt:55']); expect(rt.single.tr, 'https://embed.redtube.com/?id=55'); expect(rt.single.du, 62);
    final ep = await searchEmbeds(embedSources.firstWhere((s) => s.id == 'ep'), jane);
    expect(ep.single.tr, 'https://www.eporner.com/embed/EP1/'); expect(ep.single.du, 15); expect(ep.single.p, 'https://t.test/e.jpg');
  });

  test('المطابقة: الاسم البديل المكوّن من كلمتين يُقبل، والقصير لا', () {
    expect(embedMatches(jane, 'Janey S solo', const []), isTrue);
    expect(embedMatches(jane, 'JS and friends', const []), isFalse);
    expect(embedMatches(jane, 'x', const ['jane sample']), isTrue);
  });

  test('بوابة +18: لا طلب لقاصر؛ والموقع المحجوب = غير متاح وبلا نتائج', () async {
    var n = 0;
    sourceClient = MockClient((r) async { n++; throw http.ClientException('Failed host lookup'); });
    final y = DateTime.now().year;
    expect(await searchEmbeds(embedSources.first, Performer({'id': 'm', 'name': 'Minor Person', 'birth': '${y - 16}-01-01'})), isEmpty);
    expect(n, 0);
    expect(await searchEmbeds(embedSources.first, jane), isEmpty);
    expect(await embedReachable(embedSources.first), isFalse);
  });
}
