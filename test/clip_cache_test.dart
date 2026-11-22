// ذاكرة المقاطع: تنزيل عبر عميل المصادر مع التقدم، إعادة الاستخدام، رفض صفحات الويب والأخطاء، ودمج الطلبات المتزامنة.
import 'dart:io';
import 'dart:typed_data';

import 'package:favorites2/data/platform/clip_cache_io.dart';
import 'package:favorites2/data/sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('تنزيل، تقدم، إعادة استخدام، ودمج الطلبات', () async {
    clipCacheDirForTest = await Directory.systemTemp.createTemp('clips');
    var calls = 0;
    sourceClient = MockClient.streaming((r, _) async {
      calls++;
      if (r.url.path.endsWith('page')) return http.StreamedResponse(Stream.value(Uint8List.fromList('<html>'.codeUnits)), 200, headers: {'content-type': 'text/html'});
      if (r.url.path.endsWith('gone')) return http.StreamedResponse(const Stream.empty(), 404);
      final bytes = Uint8List(5000);
      return http.StreamedResponse(Stream.fromIterable([bytes.sublist(0, 2500), bytes.sublist(2500)]), 200, contentLength: 5000, headers: {'content-type': 'video/mp4'});
    });
    final progress = <double>[];
    final r = await Future.wait([downloadClip('https://cdn.test/a.mp4', onProgress: progress.add), downloadClip('https://cdn.test/a.mp4')]);
    expect(r[0], isNotNull); expect(r[0], r[1]); expect(calls, 1);
    expect(progress.last, 1.0);
    expect(await File(r[0]!).length(), 5000);
    expect(await cachedClipPath('https://cdn.test/a.mp4'), r[0]);
    expect(await downloadClip('https://cdn.test/a.mp4'), r[0]); expect(calls, 1);   // من الجهاز
    expect(await downloadClip('https://cdn.test/page'), isNull);
    expect(await downloadClip('https://cdn.test/gone'), isNull);
    expect(Directory(r[0]!).parent.listSync().any((f) => f.path.endsWith('.part')), isFalse);
  });
}
