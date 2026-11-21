import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'platform/db_factory.dart';
import 'sources.dart' show sourceClient;

/// بصمة مرئية للصورة (dHash 64 بت): نفس الصورة بمقاسات/ضغط مختلف من StashDB وThePornDB تعطي بصمة متقاربة.
/// تُحسب على الجهاز من البايتات فقط — لا ترسل أي شيء لأي خدمة، ولا تحلل الوجوه.
Future<List<bool>?> photoHash(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 9, targetHeight: 8);
    final f = await codec.getNextFrame();
    final bd = await f.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    f.image.dispose(); codec.dispose();
    if (bd == null) return null;
    double g(int x, int y) { final o = (y * 9 + x) * 4; return bd.getUint8(o) * .299 + bd.getUint8(o + 1) * .587 + bd.getUint8(o + 2) * .114; }
    return [for (var y = 0; y < 8; y++) for (var x = 0; x < 8; x++) g(x, y) < g(x + 1, y)];
  } catch (_) { return null; }
}

int hamming(List<bool> a, List<bool> b) { var d = 0; for (var i = 0; i < 64; i++) { if (a[i] != b[i]) d++; } return d; }

/// عتبة التكرار: ≤ 6 بتات مختلفة من 64 = نفس الصورة تقريبًا.
const dupThreshold = 6;

/// بايتات صورة محفوظة (ملف على الجهاز أو data URI).
Future<Uint8List?> storedPhotoBytes(String ref) async {
  if (ref.startsWith('data:image/')) { try { return base64Decode(ref.substring(ref.indexOf(',') + 1)); } catch (_) { return null; } }
  return readPhotoBytes(ref);
}

String? imageExt(Uint8List b) {
  if (b.length < 12) return null;
  if (b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
  return null;
}

/// تنزيل صورة https والتحقق أنها صورة فعلًا (لا صفحة حجب) وبحجم معقول.
Future<Uint8List?> fetchImageBytes(String url, {http.Client? client}) async {
  if (!url.startsWith('https://')) return null;
  try {
    final r = await (client ?? sourceClient).get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200 || r.bodyBytes.length < 64 || r.bodyBytes.length > 25 * 1024 * 1024) return null;
    return imageExt(r.bodyBytes) == null ? null : r.bodyBytes;
  } catch (_) { return null; }
}

/// إضافة صور جديدة لممثلة **بلا تكرار**: يُتخطى الرابط المكرر، والصورة المطابقة بايتًا، والمتقاربة بصريًا لصورة موجودة.
/// إن كانت المكررة الجديدة أعلى دقة بوضوح (أكبر بـ 1.6× على الأقل) تحل محل القديمة في مكانها.
/// يعيد (القائمة الجديدة، عدد المضاف، عدد المتخطى كمكرر، الصور المستبدلة لحذف ملفاتها).
Future<(List<String>, int, int, List<String>)> addPhotosNoDup(List<String> existing, List<String> urls, String idPrefix, {int max = 30, int maxNew = 8}) async {
  final out = [...existing]; final replaced = <String>[];
  final hashes = <String, (List<bool>?, int)>{};
  for (final r in out) { final b = await storedPhotoBytes(r); hashes[r] = b == null ? (null, 0) : (await photoHash(b), b.length); }
  var added = 0, dup = 0; final seenUrls = <String>{};
  for (final u in urls) {
    if (added >= maxNew || !seenUrls.add(u)) { continue; }
    final b = await fetchImageBytes(u); if (b == null) continue;
    final h = await photoHash(b);
    String? same;
    if (h != null) { for (final e in hashes.entries) { if (e.value.$1 != null && hamming(e.value.$1!, h) <= dupThreshold) { same = e.key; break; } } }
    if (same != null) {
      dup++;
      if (b.length > hashes[same]!.$2 * 1.6) {   // نسخة أوضح من نفس الصورة ⇒ تستبدلها في مكانها
        final ref = await storePhotoBytes('${idPrefix}_${DateTime.now().microsecondsSinceEpoch}.${imageExt(b)}', b);
        out[out.indexOf(same)] = ref; replaced.add(same); hashes.remove(same); hashes[ref] = (h, b.length);
      }
      continue;
    }
    if (out.length >= max) break;
    final ref = await storePhotoBytes('${idPrefix}_${DateTime.now().microsecondsSinceEpoch}.${imageExt(b)}', b);
    out.add(ref); hashes[ref] = (h, b.length); added++;
  }
  return (out, added, dup, replaced);
}

/// إزالة الصور المكررة الموجودة (المتطابقة أو المتقاربة بصريًا) مع إبقاء الأعلى دقة في مكان الأولى.
/// يعيد (القائمة، الصور المحذوفة لحذف ملفاتها).
Future<(List<String>, List<String>)> dedupePhotos(List<String> refs) async {
  final info = <(String, List<bool>?, int)>[];
  for (final r in refs) { final b = await storedPhotoBytes(r); info.add((r, b == null ? null : await photoHash(b), b?.length ?? 0)); }
  final keep = <(String, List<bool>?, int)>[]; final removed = <String>[];
  for (final x in info) {
    final i = x.$2 == null ? -1 : keep.indexWhere((k) => k.$2 != null && hamming(k.$2!, x.$2!) <= dupThreshold);
    if (i < 0) { if (!keep.any((k) => k.$1 == x.$1)) { keep.add(x); } else { removed.add(x.$1); } continue; }
    if (x.$3 > keep[i].$3) { removed.add(keep[i].$1); keep[i] = x; } else { removed.add(x.$1); }
  }
  return ([for (final k in keep) k.$1], removed);
}
