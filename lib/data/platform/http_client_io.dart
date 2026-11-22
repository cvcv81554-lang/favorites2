import 'dart:io' show Platform;

import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;

http.Client newHttpClient() {
  if (Platform.isIOS || Platform.isMacOS) {
    try { return CupertinoClient.defaultSessionConfiguration(); } catch (_) {}   // احتياط: لو تعذّر لأي سبب
  }
  return http.Client();
}
