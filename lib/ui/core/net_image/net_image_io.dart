import 'dart:async';
import 'dart:io' show Directory, File, FileSystemEntity;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// صورة شبكة بذاكرة على القرص (مجلد Caches الخاص بالتطبيق — على الجهاز فقط، خارج نسخ iCloud، والنظام قد يفرّغه عند امتلاء الجهاز).
/// - تُنزّل مرة واحدة ثم تُقرأ من الجهاز في كل فتح لاحق (لا طلبات متكررة).
/// - تنزيلان متزامنان لنفس الرابط يُدمجان في طلب واحد.
/// - حد أقصى للحجم: عند تجاوز 400MB تُحذف الأقدم حتى 300MB.
class DiskImage extends ImageProvider<DiskImage> {
  const DiskImage(this.url);
  final String url;

  @override Future<DiskImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<DiskImage>(this);

  @override
  ImageStreamCompleter loadImage(DiskImage key, ImageDecoderCallback decode) =>
    MultiFrameImageStreamCompleter(codec: _codec(decode), scale: 1.0, debugLabel: url);

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    final bytes = await diskImageBytes(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override bool operator ==(Object other) => other is DiskImage && other.url == url;
  @override int get hashCode => url.hashCode;
}

Directory? _dir; bool _pruned = false;
final _inflight = <String, Future<Uint8List>>{};
http.Client _client = http.Client();
@visibleForTesting set diskImageClient(http.Client c) => _client = c;
@visibleForTesting set diskImageDir(Directory d) => _dir = d;

Future<Directory> _cacheDir() async {
  if (_dir != null) return _dir!;
  final d = Directory('${(await getApplicationCacheDirectory()).path}/img');
  if (!await d.exists()) await d.create(recursive: true);
  return _dir = d;
}

/// بايتات الصورة: من القرص إن وُجدت، وإلا تُنزّل وتُحفظ.
Future<Uint8List> diskImageBytes(String url) => _inflight[url] ??= _get(url).whenComplete(() { _inflight.remove(url); });   // بلا إرجاع: whenComplete ينتظر أي Future يُرجَع (كان سينتظر نفسه)

Future<Uint8List> _get(String url) async {
  final dir = await _cacheDir();
  final f = File('${dir.path}/${sha1.convert(url.codeUnits)}');
  if (await f.exists()) {
    final b = await f.readAsBytes();
    if (b.isNotEmpty) return b;
  }
  final r = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
  final ct = r.headers['content-type'] ?? '';
  if (r.statusCode != 200 || r.bodyBytes.isEmpty || (ct.isNotEmpty && !ct.startsWith('image/') && !ct.contains('octet-stream'))) {
    throw Exception('صورة غير صالحة (${r.statusCode})');
  }
  if (r.bodyBytes.length > 30 * 1024 * 1024) throw Exception('الصورة أكبر من الحد');
  try {
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(r.bodyBytes, flush: true);
    await tmp.rename(f.path);
  } catch (_) {}   // فشل الحفظ لا يمنع العرض
  if (!_pruned) { _pruned = true; unawaited(_prune(dir)); }
  return r.bodyBytes;
}

Future<void> _prune(Directory dir, {int max = 400 << 20, int target = 300 << 20}) async {
  try {
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is! File) continue;
      final s = await e.stat(); total += s.size; files.add((e, s.size, s.modified));
    }
    if (total <= max) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final x in files) { if (total <= target) break; try { await x.$1.delete(); total -= x.$2; } catch (_) {} }
  } catch (_) {}
}

/// مزوّد صورة الشبكة على الجوال: بذاكرة قرص.
ImageProvider netImage(String url) => DiskImage(url);
