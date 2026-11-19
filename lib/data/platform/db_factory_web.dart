import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:sembast_web/sembast_web.dart';

const bool isWebBuild = true;

Future<Database> openAppDb(String name) => databaseFactoryWeb.openDatabase(name);

// في نسخة الويب (للتجربة فقط) تبقى الصور data URI داخل السجل.
Future<String> storePhotoBytes(String name, Uint8List bytes) async {
  final ext = name.split('.').last.toLowerCase();
  final mime = ext == 'png' ? 'png' : ext == 'webp' ? 'webp' : 'jpeg';
  return 'data:image/$mime;base64,${base64Encode(bytes)}';
}

Future<Uint8List?> readPhotoBytes(String ref) async => null;
Future<void> warmPhotoDir() async {}
Object? photoFile(String ref) => null;
ImageProvider? fileImageProvider(String ref) => null;
Future<void> deletePhoto(String ref) async {}
String b64(Uint8List b) => base64Encode(b);
