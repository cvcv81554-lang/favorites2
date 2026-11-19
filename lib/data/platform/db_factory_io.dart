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
