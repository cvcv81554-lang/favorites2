// خطأ حقيقي سابق: فشل ThePornDB (محجوب) كان يغلق الاتصال المشترك فيقطع طلب StashDB الجاري معه.
import 'dart:convert';

import 'package:favorites2/data/sources.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// عميل وهمي يحاكي الواقع: إغلاقه يقطع كل طلباته الجارية.
class FakePooled extends http.BaseClient {
  static int stashTries = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    if (r.url.host.contains('theporndb')) throw http.ClientException('Connection reset by peer');   // محجوب فورًا
    stashTries++;
    await Future<void>.delayed(const Duration(milliseconds: 400));                                  // StashDB أبطأ
    if (closed) throw http.ClientException('Connection closed while receiving data');
    final body = utf8.encode(jsonEncode({'data': {'me': {'name': 'x'}}}));
    return http.StreamedResponse(Stream.value(body), 200);
  }
  @override void close() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stash_key': 'S', 'tpdb_key': 'T'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  test('ThePornDB المحجوب لا يقطع طلب StashDB الجاري معه في نفس اللحظة', () async {
    FakePooled.stashTries = 0;
    usePooledClientForTest(FakePooled.new);
    final r = await Future.wait([
      checkSource(() => StashDB.test('S')),
      checkSource(() => TPDB.test('T')),
    ]);
    expect(r[0].$1, isTrue, reason: 'StashDB يجب أن يعمل: ${r[0].$2}');
    expect(FakePooled.stashTries, 1, reason: 'طلب StashDB لا يُقطع فيُعاد');
    expect(r[1].$1, isFalse);
    expect(r[1].$2, contains('غير متاح على شبكتك'));
  });
}
