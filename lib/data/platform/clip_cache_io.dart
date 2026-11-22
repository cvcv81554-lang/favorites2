import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../sources.dart' show sourceClient;

/// ذاكرة المقاطع: مجلد Caches الخاص بالتطبيق (على الجهاز فقط، خارج iCloud، والنظام قد يفرّغه عند امتلاء الجهاز).
/// حد كلي 800MB (الأقدم استخدامًا يُحذف أولًا)، وحد للمقطع 150MB.
const _maxTotal = 800 << 20, _maxOne = 150 << 20;
bool get clipCacheSupported => true;

Directory? _dir;
/// للاختبارات فقط: مجلد مؤقت بدل مجلد التطبيق.
set clipCacheDirForTest(Directory d) => _dir = d;
Future<Directory> _cacheDir() async {
  if (_dir != null) return _dir!;
  final d = Directory('${(await getApplicationCacheDirectory()).path}/clips');
  if (!await d.exists()) await d.create(recursive: true);
  return _dir = d;
}
String _name(String url) { final ext = RegExp(r'\.(mp4|m4v|mov)(\?|$)', caseSensitive: false).firstMatch(url)?.group(1)?.toLowerCase() ?? 'mp4'; return '${sha1.convert(url.codeUnits)}.$ext'; }

/// مسار المقطع المحفوظ (إن وُجد كاملًا) — ويُحدَّث وقت استخدامه لترتيب الحذف.
Future<String?> cachedClipPath(String url) async {
  final f = File('${(await _cacheDir()).path}/${_name(url)}');
  if (await f.exists() && await f.length() > 1024) { try { await f.setLastModified(DateTime.now()); } catch (_) {} return f.path; }
  return null;
}

final _inflight = <String, Future<String?>>{};

/// تنزيل المقطع عبر عميل المصادر (iPhone: شبكات Apple الأصلية) إلى الجهاز، مع التقدم. يعيد المسار أو null عند الفشل.
Future<String?> downloadClip(String url, {void Function(double)? onProgress}) {
  final existing = _inflight[url];
  if (existing != null) return existing;
  final f = _download(url, onProgress).whenComplete(() { _inflight.remove(url); });
  _inflight[url] = f;
  return f;
}

Future<String?> _download(String url, void Function(double)? onProgress) async {
  final hit = await cachedClipPath(url); if (hit != null) return hit;
  final dir = await _cacheDir();
  final out = File('${dir.path}/${_name(url)}'), part = File('${out.path}.part');
  IOSink? sink;
  try {
    final res = await sourceClient.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 25));
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
    for (final x in files) { if (total <= _maxTotal * .8) break; try { await x.$1.delete(); total -= x.$2; } catch (_) {} }
  } catch (_) {}
}

/// مصدر ملف محفوظ على الجهاز للمشغّل.
Object? fileVideoSource(String path) => File(path);
