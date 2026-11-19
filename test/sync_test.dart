// المزامنة الجوال ← الشاشة عبر خادم HTTP محلي حقيقي (127.0.0.1): الرمز، البوابة، قواعد الدمج.
import 'dart:convert';
import 'dart:io';

import 'package:favorites2/data/backup.dart';
import 'package:favorites2/data/library_repo.dart';
import 'package:favorites2/data/sync_io.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

Future<(int, String)> post(int port, String code, String body) async {
  final c = HttpClient(); final r = await c.postUrl(Uri.parse('http://127.0.0.1:$port/v1/push'));
  r.headers.set('x-code', code); r.add(utf8.encode(body)); final res = await r.close(); final t = await utf8.decodeStream(res); c.close(); return (res.statusCode, t);
}

void main() {
  test('رمز خاطئ يُرفض، والصحيح يطبّق الاستيراد (والقاصر تُرفض)', () async {
    final repo = LibraryRepo.withDb(await databaseFactoryMemory.openDatabase('sync1'));
    final tv = SyncServer(); final events = <String>[];
    await tv.start(repo: repo, current: () => repo.loadAll(), onEvent: events.add);
    final port = int.parse(tv.address.split(':').last);
    final json = await Backup.export([Performer({'id': 'a1', 'name': 'Adult', 'birth': '1990-01-01'})]);
    final withMinor = (jsonDecode(json) as Map)..['items'] = [...(jsonDecode(json)['items'] as List), {'id': 'm1', 'name': 'Minor', 'birth': '2015-01-01'}];
    final bad = await post(port, '000000' == tv.code ? '111111' : '000000', json);
    expect(bad.$1, 403);
    final ok = await post(port, tv.code, jsonEncode(withMinor));
    expect(ok.$1, 200);
    final j = jsonDecode(ok.$2); expect(j['added'], 1); expect(j['skippedMinors'], 1);
    expect((await repo.loadAll()).map((p) => p.name), ['Adult']);
    await tv.stop();
  });

  test('5 محاولات خاطئة توقف الخادم', () async {
    final repo = LibraryRepo.withDb(await databaseFactoryMemory.openDatabase('sync2'));
    final tv = SyncServer(); await tv.start(repo: repo, current: () => repo.loadAll(), onEvent: (_) {});
    final port = int.parse(tv.address.split(':').last); final wrong = tv.code == '999999' ? '888888' : '999999';
    for (var i = 0; i < 5; i++) { await post(port, wrong, '{}'); }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(tv.running, isFalse);
  });

  test('الجوال يرفض العناوين خارج الشبكة المحلية', () async {
    expect(() => pushToTv(host: 'example.com', code: '123456', json: '{}'), throwsA(isA<ArgumentError>()));
    expect(() => pushToTv(host: '8.8.8.8:8787', code: '123456', json: '{}'), throwsA(isA<ArgumentError>()));
  });
}
