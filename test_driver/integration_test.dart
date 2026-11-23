import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// يحفظ لقطات محاكي الآيفون في screenshots/ (تُرفع في GitHub مع نتيجة الاختبار).
Future<void> main() => integrationDriver(onScreenshot: (name, bytes, [args]) async {
  final f = File('screenshots/$name.png');
  await f.create(recursive: true);
  await f.writeAsBytes(bytes);
  return true;
});
