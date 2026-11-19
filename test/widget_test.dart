// اختبارات المنطق الأساسي: بوابة +18، التنقية، النسخة الاحتياطية (قراءة/تشفير بنفس صيغة التطبيق السابق).
import 'dart:convert';
import 'dart:io';

import 'package:favorites2/data/backup.dart';
import 'package:favorites2/domain/age_gate.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/sanitize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 19);
  group('بوابة +18', () {
    test('بالغة تُقبل', () => expect(minorRec({'birth': '2000-05-05'}, now: now), isFalse));
    test('17 سنة تُرفض', () => expect(minorRec({'birth': '2009-05-05'}, now: now), isTrue));
    test('يوم الميلاد الـ18 نفسه يُقبل', () => expect(minorRec({'birth': '2008-11-19'}, now: now), isFalse));
    test('قبل الـ18 بيوم تُرفض', () => expect(minorRec({'birth': '2008-11-20'}, now: now), isTrue));
    test('سنة فقط ⇒ أسوأ حالة (آخر يوم في السنة)', () {
      expect(minorRec({'birth': '2008'}, now: now), isTrue); // قد تكون وُلدت في ديسمبر 2008
      expect(minorRec({'birth': '2007'}, now: now), isFalse);
    });
    test('شهر فقط ⇒ آخر يوم في الشهر', () {
      expect(minorRec({'birth': '2008-11'}, now: now), isTrue); // 30 نوفمبر 2008 ⇒ 17
      expect(minorRec({'birth': '2008-10'}, now: now), isFalse);
    });
    test('تاريخ مستحيل ⇒ قاصر', () => expect(minorRec({'birth': '2001-02-30'}, now: now), isTrue));
    test('نص غير مفهوم ⇒ قاصر', () => expect(minorRec({'birth': 'unknown'}, now: now), isTrue));
    test('تاريخ في المستقبل ⇒ قاصر', () => expect(minorRec({'birth': '2030-01-01'}, now: now), isTrue));
    test('بلا تاريخ ⇒ ليس قاصرًا في المكتبة', () => expect(minorRec({'birth': ''}, now: now), isFalse));
    test('مرشح خارجي: birthRaw يتقدم على birth', () {
      expect(adultOk({'birth': '1990-01-01', 'birthRaw': '2010'}, now: now), isFalse);
      expect(adultOk({'birthRaw': '1990-01-01'}, now: now), isTrue);
      expect(adultOk({'birthRaw': 'bad'}, now: now), isFalse);
    });
  });

  group('التنقية', () {
    test('safeId', () { expect(safeId('abc-1.2:x'), isTrue); expect(safeId('a b'), isFalse); expect(safeId('<x>'), isFalse); });
    test('safeImg', () {
      expect(safeImg('https://x.test/a.jpg'), isTrue);
      expect(safeImg('data:image/png;base64,AAA'), isTrue);
      expect(safeImg('javascript:alert(1)'), isFalse);
      expect(safeImg('https://x.test/a.jpg"onerror="x'), isFalse);
    });
    test('wkey يوحّد العنوان', () => expect(wkey('Hello, World! 2'), wkey('hello world2')));
    test('ydOf', () {
      expect(ydOf('2024-3-5'), {'d': '2024-03-05', 'y': '2024'});
      expect(ydOf('5-3-2024'), {'d': '2024-03-05', 'y': '2024'});
      expect(ydOf('2024'), {'y': '2024'});
    });
    test('safeWorks: روابط غير https تُحذف، والصيغة النصية القديمة تُحوّل', () {
      final w = safeWorks([{'t': 'A', 'p': 'http://x', 'u': 'https://ok', 'ip': 'bad id'}, 'Title | Site | 2020', 'Movie (2019)']);
      expect(w[0].containsKey('p'), isFalse); expect(w[0]['u'], 'https://ok'); expect(w[0].containsKey('ip'), isFalse);
      expect(w[1], {'t': 'Title', 's': 'Site', 'y': '2020'});
      expect(w[2], {'t': 'Movie', 'y': '2019'});
    });
  });

  group('السجل', () {
    test('الحقول المجهولة تبقى', () {
      final p = Performer({'id': 'a', 'name': 'X', 'customField': 42, 'criteria': {'chem': 4}});
      expect(p.raw['customField'], 42); expect(p.raw['criteria']['bold'], 4);
    });
  });

  group('النسخة الاحتياطية', () {
    String file(List<Map<String, dynamic>> items, {Map<String, String> prefs = const {}}) => jsonEncode({'app': 'vkte-favorites', 'v': 5, 'exportedAt': 1, 'lists': [{'id': 'l1', 'name': 'L'}], 'wlists': [], 'prefs': prefs, 'items': items});
    test('القاصر والسجلات غير الصالحة تُعدّ ولا تُستورد', () {
      final f = Backup.parse(file([
        {'id': 'ok1', 'name': 'Adult', 'birth': '1995-01-01', 'photos': ['https://x.test/1.jpg', 'javascript:x']},
        {'id': 'm1', 'name': 'Minor', 'birth': '2015-01-01'},
        {'id': 'bad id', 'name': 'X'},
        {'id': 'n1', 'name': ''},
      ]));
      expect(f.items.length, 1); expect(f.minorsSkipped, 1); expect(f.invalid, 2);
      expect(f.items.first['photos'], ['https://x.test/1.jpg']);
      expect(f.lists.single['id'], 'l1');
    });
    test('مفاتيح API والرمز السري لا تُقرأ من الملف', () {
      final f = Backup.parse(file([], prefs: {'vkte_key': 'SECRET', 'vkte_stash': 'S', 'vkte_pin': '1', 'vkte_theme': 'dark'}));
      expect(f.prefs, {'vkte_theme': 'dark'});
    });
    test('ملف ليس نسخة ⇒ رسالة واضحة', () => expect(() => Backup.parse('{"x":1}'), throwsA(isA<BackupError>())));
    test('تشفير ثم فك (نفس صيغة vkte-enc)', () async {
      final enc = await Backup.encrypt('{"hello":"عالم"}', 'password123');
      final j = jsonDecode(enc); expect(j['app'], 'vkte-enc'); expect(j['v'], 1);
      expect(await Backup.decrypt(enc, 'password123'), '{"hello":"عالم"}');
      expect(() => Backup.decrypt(enc, 'wrong-pass'), throwsA(isA<BackupError>()));
    }, timeout: const Timeout(Duration(minutes: 2)));
    test('كلمة مرور قصيرة مرفوضة', () => expect(() => Backup.encrypt('{}', 'short'), throwsA(isA<BackupError>())));
    test('يفك نسخة مشفّرة صنعها التطبيق السابق (WebCrypto) ويقرأها', () async {
      final txt = File('test/fixtures/old_app.vkte').readAsStringSync();
      expect(Backup.isEncrypted(txt), isTrue);
      final f = Backup.parse(await Backup.decrypt(txt, 'old-app-pass'));
      expect(f.items.single['name'], 'نموذج تجريبي');
      expect((f.items.single['works'] as List).single['t'], 'Sample');
      expect(f.prefs['vkte_theme'], 'dark');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
