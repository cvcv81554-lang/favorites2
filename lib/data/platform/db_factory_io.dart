import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

const bool isWebBuild = false;

Future<Database> openAppDb(String name) async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return databaseFactoryIo.openDatabase('${dir.path}${Platform.pathSeparator}$name.db');
}

Future<Directory> _photoDir() async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}photos');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// يحفظ صورة (data URI) ملفًا على الجهاز ويعيد مرجعها `file:<name>`.
Future<String> storePhotoBytes(String name, Uint8List bytes) async {
  final f = File('${(await _photoDir()).path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(bytes, flush: true);
  return 'file:$name';
}

Future<Uint8List?> readPhotoBytes(String ref) async {
  if (!ref.startsWith('file:')) return null;
  final f = File('${(await _photoDir()).path}${Platform.pathSeparator}${ref.substring(5)}');
  return await f.exists() ? f.readAsBytes() : null;
}

String? _photoDirPath;
Future<void> warmPhotoDir() async { _photoDirPath = (await _photoDir()).path; }
/// مسار الملف لعرضه مباشرة (Image.file) بلا قراءة غير متزامنة.
File? photoFile(String ref) => (ref.startsWith('file:') && _photoDirPath != null) ? File('$_photoDirPath${Platform.pathSeparator}${ref.substring(5)}') : null;

/// مزوّد صورة لملف على الجهاز (للعرض).
ImageProvider? fileImageProvider(String ref) { final f = photoFile(ref); return f == null ? null : FileImage(f); }

Future<void> deletePhoto(String ref) async { final f = photoFile(ref); if (f != null && await f.exists()) await f.delete(); }

String b64(Uint8List b) => base64Encode(b);

// ---------- ملفات تبادل مهمة الخلفية (لا تلمس قاعدة البيانات من عزلة أخرى) ----------
Future<Directory> _bgDir() async { final d = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}bg'); if (!await d.exists()) await d.create(recursive: true); return d; }
/// كتابة ذرّية: ملف مؤقت ثم إعادة تسمية.
Future<void> bgWrite(String name, String text) async { final d = await _bgDir(); final t = File('${d.path}${Platform.pathSeparator}$name.tmp'); await t.writeAsString(text, flush: true); await t.rename('${d.path}${Platform.pathSeparator}$name'); }
Future<String?> bgRead(String name) async { final f = File('${(await _bgDir()).path}${Platform.pathSeparator}$name'); return await f.exists() ? f.readAsString() : null; }
Future<List<String>> bgList(String prefix) async => [for (final e in (await _bgDir()).listSync()) if (e is File && e.uri.pathSegments.last.startsWith(prefix) && !e.path.endsWith('.tmp')) e.uri.pathSegments.last];
Future<void> bgRemove(String name) async { final f = File('${(await _bgDir()).path}${Platform.pathSeparator}$name'); if (await f.exists()) await f.delete(); }

// ===== خط المستخدم (يستورده بنفسه من مصدره الرسمي — لا يُضمَّن في التطبيق ولا المستودع) =====
Future<Directory> _fontDir() async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}fonts');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}
Future<List<Uint8List>> readUserFonts() async {
  final out = <Uint8List>[];
  await for (final e in (await _fontDir()).list()) { if (e is File && RegExp(r'\.(otf|ttf)$', caseSensitive: false).hasMatch(e.path)) out.add(await e.readAsBytes()); }
  return out;
}
Future<void> saveUserFont(String name, Uint8List bytes) async {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  await File('${(await _fontDir()).path}${Platform.pathSeparator}$safe').writeAsBytes(bytes, flush: true);
}
Future<void> clearUserFonts() async { await for (final e in (await _fontDir()).list()) { if (e is File) await e.delete(); } }
