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

// لا مهام خلفية على الويب.
Future<void> bgWrite(String name, String text) async {}
Future<String?> bgRead(String name) async => null;
Future<List<String>> bgList(String prefix) async => const [];
Future<void> bgRemove(String name) async {}

// خط المستخدم: غير متاح في نسخة الويب التجريبية.
Future<List<Uint8List>> readUserFonts() async => const [];
Future<void> saveUserFont(String name, Uint8List bytes) async {}
Future<void> clearUserFonts() async {}
