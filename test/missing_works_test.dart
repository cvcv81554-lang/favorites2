// «الأعمال الناقصة»: المطابقة بالمعرّف ثم العنوان/الاستوديو/التاريخ، القادمة لا تُحسب، وتحويل مشاهد الخادم.
import 'dart:convert';

import 'package:favorites2/data/sources.dart';
import 'package:favorites2/data/stash_server.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stashapp_url': 'http://s', 'stashapp_key': 'K'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  final works = <Map<String, dynamic>>[
    {'t': 'Sunny Day', 's': 'Studio A', 'd': '2023-05-01', 'is': 'S1'},
    {'t': 'Night Out', 's': 'Studio B', 'd': '2024-01-10', 'ip': 'P2'},
    {'t': 'Beach Trip', 's': 'Studio A', 'd': '2022-07-07'},
    {'t': 'Lost One', 's': 'Studio C', 'd': '2021-03-03'},
    {'t': 'Coming Soon', 's': 'Studio A', 'd': '2099-01-01'},
  ];

  test('المطابقة: معرّف StashDB أو ThePornDB، أو العنوان + الاستوديو + التاريخ (±3 أيام)؛ والقادمة لا تُحسب', () {
    final owned = <Map<String, dynamic>>[
      {'t': 'Totally different title', 'is': 'S1'},                  // معرّف StashDB
      {'t': 'whatever', 'ip': 'P2'},                                  // معرّف ThePornDB
      {'t': 'beach trip', 's': 'studio a', 'd': '2022-07-09'},       // العنوان والاستوديو والتاريخ
      {'t': 'Lost One', 's': 'Studio C', 'd': '2021-06-03'},         // نفس العنوان لكن التاريخ بعيد ⇒ عمل آخر
    ];
    final m = missingWorks(works, owned, now: DateTime(2026, 1, 1));
    expect(m.total, 4); expect(m.have, 3); expect(m.missing.map((w) => w['t']), ['Lost One']);
    expect(missingWorks(works, const [], now: DateTime(2026, 1, 1)).missing.map((w) => w['t']), ['Night Out', 'Sunny Day', 'Beach Trip', 'Lost One']);   // الأحدث أولًا
  });

  test('مشاهد الخادم: معرّفا StashDB وThePornDB من stash_ids، وتوزيعها على ممثلاتها', () async {
    sourceClient = MockClient((r) async => http.Response(jsonEncode({'data': {'findScenes': {'scenes': [
      {'id': '1', 'title': 'A', 'date': '2023-05-01', 'studio': {'name': 'Studio A'}, 'stash_ids': [{'endpoint': 'https://stashdb.org/graphql', 'stash_id': 'S1'}, {'endpoint': 'https://theporndb.net/graphql', 'stash_id': 'P9'}], 'performers': [{'id': '7'}, {'id': '8'}]},
      {'id': '2', 'title': 'B', 'stash_ids': [], 'performers': [{'id': '8'}]},
    ]}}}), 200));
    final o = await StashServer.owned(['7', '8']);
    expect(o['7']!.length, 1); expect(o['8']!.length, 2);
    expect(o['7']!.single['is'], 'S1'); expect(o['7']!.single['ip'], 'P9'); expect(o['7']!.single['s'], 'Studio A');
    expect(o['8']![1].containsKey('is'), isFalse);
    expect(await StashServer.owned(const []), isEmpty);
  });
}
