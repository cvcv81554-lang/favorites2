import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../sources.dart' show sourceClient;

/// ينزّل [url] إلى المجلد المؤقت باسم [name] (يكتمل أولًا في ‎.part ثم يُعاد تسميته). يعيد المسار أو null.
Future<String?> downloadModelFile(String url, String name, {void Function(double)? onProgress}) async {
  final dir = await getTemporaryDirectory();
  final out = File('${dir.path}/$name'), part = File('${out.path}.part');
  IOSink? sink;
  try {
    final res = await sourceClient.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return null;
    final total = res.contentLength ?? 0;
    final w = part.openWrite(); sink = w; var got = 0;
    await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
      w.add(chunk); got += chunk.length;
      if (total > 0) onProgress?.call(got / total);
    }
    await w.close(); sink = null;
    if (got < 1 << 20 || (total > 0 && got != total)) return null;   // ناقص أو ليس نموذجًا
    if (await out.exists()) await out.delete();
    await part.rename(out.path);
    return out.path;
  } catch (_) {
    try { await sink?.close(); } catch (_) {}
    return null;
  }
}
