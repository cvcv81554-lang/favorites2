// ذاكرة الصور على القرص: تنزيل مرة واحدة، دمج الطلبات المتزامنة، ورفض الردود غير الصالحة.
import 'dart:io';
import 'dart:typed_data';

import 'package:favorites2/ui/core/net_image/net_image_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('الصورة تُنزّل مرة واحدة ثم تُقرأ من القرص، والطلبات المتزامنة تُدمج', () async {
    final dir = await Directory.systemTemp.createTemp('imgcache');
    diskImageDir = dir;
    var calls = 0;
    diskImageClient = MockClient((r) async {
      calls++;
      if (r.url.path.endsWith('bad')) return http.Response('<html>blocked</html>', 200, headers: {'content-type': 'text/html'});
      if (r.url.path.endsWith('gone')) return http.Response('', 404);
      return http.Response.bytes(Uint8List.fromList(List.filled(100, 7)), 200, headers: {'content-type': 'image/jpeg'});
    });
    final r = await Future.wait([diskImageBytes('https://img.test/a.jpg'), diskImageBytes('https://img.test/a.jpg')]);
    expect(r[0].length, 100); expect(calls, 1);
    expect((await diskImageBytes('https://img.test/a.jpg')).length, 100);
    expect(calls, 1);                                            // من القرص، بلا طلب جديد
    expect(dir.listSync().whereType<File>().where((f) => !f.path.endsWith('.part')).length, 1);
    await expectLater(diskImageBytes('https://img.test/bad'), throwsException);   // صفحة حجب ليست صورة
    await expectLater(diskImageBytes('https://img.test/gone'), throwsException);
    expect(dir.listSync().length, 1);                            // لا يُحفظ شيء غير صالح
  });
}
