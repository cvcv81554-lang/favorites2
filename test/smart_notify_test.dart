// تنبيهات أذكى: تذكير إصدارات المفضلات (توقيت صحيح، بلا أسماء) + «ممثلة جديدة قريبة من ذوقك» (بوابة +18، بلا تكرار).
import 'dart:convert';

import 'package:favorites2/data/background.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/taste.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stash_key': 'S'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  group('تذكير الإصدارات', () {
    final now = DateTime(2026, 11, 22, 12);
    final lib = [
      Performer({'id': 'f', 'name': 'Fav Name', 'fav': true, 'works': [
        {'t': 'In 3 days', 's': 'S', 'd': '2026-11-25'}, {'t': 'Also in 3 days', 's': 'S2', 'd': '2026-11-25'},
        {'t': 'Tomorrow', 's': 'S', 'd': '2026-11-23'}, {'t': 'Far', 's': 'S', 'd': '2027-03-01'}, {'t': 'Past', 's': 'S', 'd': '2026-11-01'},
        {'t': 'Year only', 's': 'S', 'y': '2026'}, {'t': 'Watched', 's': 'S', 'd': '2026-11-24', 'w': 1}]}),
      Performer({'id': 'x', 'name': 'Not Fav', 'works': [{'t': 'Other', 's': 'S', 'd': '2026-11-24'}]}),
    ];
    test('المفضلات فقط، يوم كامل خلال 60 يومًا، مساء قبله وصباح يومه — والمُشاهد والبعيد والماضي لا', () {
      final r = computeReminders(lib, now);
      final times = r.map((x) => x.$2).toList();
      expect(times, containsAll([DateTime(2026, 11, 22, 20), DateTime(2026, 11, 23, 9), DateTime(2026, 11, 24, 20), DateTime(2026, 11, 25, 9)]));
      expect(r.length, 4);
      expect(r.firstWhere((x) => x.$2 == DateTime(2026, 11, 25, 9)).$4, contains('2 أعمال'));   // يومان بعملين يُجمعان
      for (final x in r) { expect(x.$4.contains('Fav Name'), isFalse); expect(x.$3.contains('Fav Name'), isFalse); }   // بلا أسماء
      expect(r.map((x) => x.$1).toSet().length, r.length);
    });
  });

  group('ممثلة جديدة قريبة من ذوقك', () {
    Map<String, dynamic> perf(String id, {String hair = 'BRUNETTE', String birth = '1999-01-01', String eth = 'CAUCASIAN'}) =>
      {'id': id, 'name': 'N$id', 'gender': 'FEMALE', 'birth_date': birth, 'ethnicity': eth, 'hair_color': hair, 'eye_color': 'BROWN', 'height': 165, 'images': [{'url': 'https://img.test/$id.jpg', 'width': 600, 'height': 800}]};
    final prof = buildProfile([for (var i = 0; i < 4; i++) featuresOf(perf('f$i', birth: '1997-01-01'))]);
    Map<String, dynamic> input({List<String> libS = const []}) => {'settings': {'on': true}, 'taste': {'prof': profileToJson(prof), 'fb': {}, 'hidden': ['hid']}, 'libS': libS, 'libN': []};

    test('القريبة جدًا فقط، بعد البوابة، وليست في مكتبتك أو مخفية أو سبق التنبيه عنها', () async {
      final y = DateTime.now().year;
      sourceClient = MockClient((r) async => http.Response(jsonEncode({'data': {'queryPerformers': {'performers': [
        perf('close'), perf('far', hair: 'BLONDE', eth: 'ASIAN'), perf('minor', birth: '${y - 16}-01-01'), perf('mine'), perf('hid'), perf('told'),
      ]}}}), 200));
      final out = await findTasteNew(input(libS: ['mine']), {'told'});
      expect(out.map((x) => x['id']), ['close']);
      expect(out.single['tags'], contains('new'));
      expect((out.single['why'] as List).first, contains('ظهرت حديثًا'));
    });

    test('مُعطّل أو بلا ملف ذوق ⇒ لا طلب شبكة', () async {
      var n = 0; sourceClient = MockClient((r) async { n++; return http.Response('{}', 200); });
      expect(await findTasteNew({...input(), 'settings': {'on': true, 'tn': false}}, {}), isEmpty);
      expect(await findTasteNew({'settings': {'on': true}}, {}), isEmpty);
      expect(n, 0);
    });

    test('ملف الذوق يُحفظ ويُستعاد بنفس النتيجة', () {
      final back = profileFromJson(jsonDecode(jsonEncode(profileToJson(prof))))!;
      final f = featuresOf(perf('z'));
      expect(similarity(back, f).score, closeTo(similarity(prof, f).score, 1e-9));
    });
  });
}
