import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../sources.dart' show sourceClient;

/// ذاكرة المقاطع: مجلد Caches الخاص بالتطبيق (على الجهاز فقط، خارج iCloud، والنظام قد يفرّغه عند امتلاء الجهاز الشديد).
/// الحد الكلي قابل للضبط (افتراضي 3GB، الأقدم استخدامًا يُحذف أولًا)، وحد للمقطع 250MB.
int _maxTotal = 3 << 30;
const _maxOne = 250 << 20;
bool get clipCacheSupported => true;
void setClipCacheLimit(int bytes) => _maxTotal = bytes;

Directory? _dir;
/// للاختبارات فقط: مجلد مؤقت بدل مجلد التطبيق.
set clipCacheDirForTest(Directory d) => _dir = d;
Future<Directory> _cacheDir() async {
  if (_dir != null) return _dir!;
  final d = Directory('${(await getApplicationCacheDirectory()).path}/clips');
  if (!await d.exists()) await d.create(recursive: true);
  return _dir = d;
}
/// مفتاح المقطع (اسم ملفه بلا امتداد) — يُستخدم لمعرفة المحفوظ بلا قراءة القرص لكل مقطع.
String clipKeyOf(String url) => sha1.convert(url.codeUnits).toString();
String _name(String url) => '${clipKeyOf(url)}.mp4';

/// مسار المقطع المحفوظ (إن وُجد كاملًا) — ويُحدَّث وقت استخدامه لترتيب الحذف.
Future<String?> cachedClipPath(String url) async {
  final f = File('${(await _cacheDir()).path}/${_name(url)}');
  if (await f.exists() && await f.length() > 1024) { try { await f.setLastModified(DateTime.now()); } catch (_) {} return f.path; }
  return null;
}

/// مفاتيح كل المقاطع المحفوظة + حجمها الكلي.
Future<(Set<String>, int)> clipCacheStats() async {
  final keys = <String>{}; var total = 0;
  try {
    await for (final e in (await _cacheDir()).list()) {
      if (e is File && e.path.endsWith('.mp4')) { keys.add(e.uri.pathSegments.last.replaceAll('.mp4', '')); total += await e.length(); }
    }
  } catch (_) {}
  return (keys, total);
}

/// مسح المقاطع المحفوظة (بطلب المستخدم).
Future<void> clearClipCache() async { try { await for (final e in (await _cacheDir()).list()) { if (e is File) await e.delete(); } } catch (_) {} }

final _inflight = <String, Future<String?>>{};
/// خوادم جُرّبت لرفع الجودة: الخادم ⇒ نجح أم لا (لا يُعاد التجريب الفاشل).
final _hqHosts = <String, bool>{};

/// تنزيل المقطع عبر عميل المصادر (iPhone: شبكات Apple الأصلية) إلى الجهاز، مع التقدم. يعيد المسار أو null عند الفشل.
/// الجودة: إن كان الرابط بجودة أقل من 1080p (مثل _720p) تُجرَّب نسخة 1080p من نفس الخادم أولًا.
Future<String?> downloadClip(String url, {void Function(double)? onProgress}) {
  final existing = _inflight[url];
  if (existing != null) return existing;
  final f = _download(url, onProgress).whenComplete(() { _inflight.remove(url); });
  _inflight[url] = f;
  return f;
}

/// نسخة أعلى جودة محتملة من الرابط (1080p) — أو null.
String? higherQuality(String url) {
  final m = RegExp(r'(?<![0-9])(240|360|480|540|576|720)p(?![0-9])', caseSensitive: false).firstMatch(url);
  return m == null ? null : url.replaceRange(m.start, m.end, '1080p');
}

Future<String?> _download(String url, void Function(double)? onProgress) async {
  final hit = await cachedClipPath(url); if (hit != null) return hit;
  final host = Uri.tryParse(url)?.host ?? '';
  final hq = higherQuality(url);
  if (hq != null && _hqHosts[host] != false) {
    final r = await _fetchTo(url, hq, onProgress);   // يُحفظ باسم الرابط الأصلي
    _hqHosts[host] = r != null;
    if (r != null) return r;
  }
  return _fetchTo(url, url, onProgress);
}

Future<String?> _fetchTo(String key, String src, void Function(double)? onProgress) async {
  final dir = await _cacheDir();
  final out = File('${dir.path}/${_name(key)}'), part = File('${out.path}.part');
  IOSink? sink;
  try {
    final res = await sourceClient.send(http.Request('GET', Uri.parse(src))).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200 && res.statusCode != 206) return null;
    final ct = res.headers['content-type'] ?? '';
    if (ct.contains('text/html')) return null;
    final total = res.contentLength ?? 0;
    if (total > _maxOne) return null;
    final w = part.openWrite(); sink = w; var got = 0;
    await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
      w.add(chunk); got += chunk.length;
      if (got > _maxOne) { await w.close(); sink = null; await part.delete(); return null; }
      if (total > 0) onProgress?.call(got / total);
    }
    await w.close(); sink = null;
    if (got < 1024) { await part.delete(); return null; }
    await part.rename(out.path);
    unawaited(_prune(dir));
    return out.path;
  } catch (_) {
    try { await sink?.close(); } catch (_) {}
    try { if (await part.exists()) await part.delete(); } catch (_) {}
    return null;
  }
}

Future<void> _prune(Directory dir) async {
  try {
    final files = <(File, int, DateTime)>[]; var total = 0;
    await for (final e in dir.list()) { if (e is File && !e.path.endsWith('.part')) { final s = await e.stat(); total += s.size; files.add((e, s.size, s.modified)); } }
    if (total <= _maxTotal) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final x in files) { if (total <= _maxTotal * .9) break; try { await x.$1.delete(); total -= x.$2; } catch (_) {} }
  } catch (_) {}
}

/// مصدر ملف محفوظ على الجهاز للمشغّل.
Object? fileVideoSource(String path) => File(path);
