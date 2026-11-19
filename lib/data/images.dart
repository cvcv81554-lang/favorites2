import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'platform/db_factory.dart';

/// ينزّل صورة من رابط https ويحفظها ملفًا على الجهاز (تعمل بلا اتصال بعدها). على الويب يبقى الرابط.
/// يتحقق من أن المحتوى صورة فعلًا (البايتات الأولى) وحجمها معقول.
Future<String> downloadPhoto(String url, String name) async {
  if (kIsWeb || !url.startsWith('https://')) return url;
  try {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200 || r.bodyBytes.length < 64 || r.bodyBytes.length > 25 * 1024 * 1024) return url;
    final b = r.bodyBytes; final ext = _ext(b);
    if (ext == null) return url;
    return await storePhotoBytes('$name.$ext', Uint8List.fromList(b));
  } catch (_) { return url; }
}

String? _ext(Uint8List b) {
  if (b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
  return null;
}
