// فحص روابط المقاطع: يحدد السبب بدقة (محجوب، مرفوض، محذوف، صفحة ويب، WebM، يعمل).
import 'dart:typed_data';

import 'package:favorites2/data/sources.dart';
import 'package:favorites2/ui/features/reels/reels_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('كل حالة لها سببها الواضح', () async {
    sourceClient = MockClient((r) async {
      switch (r.url.host) {
        case 'mp4.test': expect(r.headers['Range'], 'bytes=0-1023'); return http.Response.bytes(Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 1, 2]), 206, headers: {'content-type': 'video/mp4'});
        case 'hls.test': return http.Response('#EXTM3U\n#EXT-X-VERSION:3', 200, headers: {'content-type': 'application/vnd.apple.mpegurl'});
        case 'webm.test': return http.Response.bytes(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 1, 2]), 200, headers: {'content-type': 'video/webm'});
        case 'page.test': return http.Response('<html>', 200, headers: {'content-type': 'text/html'});
        case 'denied.test': return http.Response('', 403);
        case 'gone.test': return http.Response('', 404);
        default: throw http.ClientException('Connection reset by peer');
      }
    });
    Future<String> p(String h) async { final r = await probeVideoUrl('https://$h/v'); return '${r.$1}:${r.$2}'; }
    expect(await p('mp4.test'), startsWith('true:يعمل (MP4'));
    expect(await p('hls.test'), startsWith('true:يعمل (HLS'));
    expect(await p('webm.test'), contains('WebM'));
    expect(await p('page.test'), contains('صفحة ويب'));
    expect(await p('denied.test'), contains('يرفض (403)'));
    expect(await p('gone.test'), contains('حُذف'));
    expect(await p('blocked.test'), contains('محجوب'));
  });
}
