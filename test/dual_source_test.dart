// المصدران معًا: توحيد الأعمال بين StashDB وThePornDB، مطابقة الشخص، بوابة +18 على المصدرين، وكشف الصور المكررة.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:favorites2/data/dual_source.dart';
import 'package:favorites2/data/photo_hash.dart';
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/works.dart';
import 'package:favorites2/ui/core/user_font.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<Uint8List> png(int w, int h, {bool flip = false}) async {
  final rec = ui.PictureRecorder(); final c = ui.Canvas(rec);
  for (var i = 0; i < 8; i++) {
    final v = flip ? 7 - i : i;
    c.drawRect(ui.Rect.fromLTWH(w * i / 8, 0, w / 8, h.toDouble()), ui.Paint()..color = ui.Color.fromARGB(255, 30 * v, 255 - 30 * v, (i * 47) % 255));
  }
  c.drawCircle(ui.Offset(w * .3, h * .4), w * .15, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{'stash_key': 'S', 'tpdb_key': 'T'};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    return c.method == 'read' ? store[a['key']] : null;
  });

  group('الأعمال من المصدرين', () {
    test('نفس العمل من StashDB وThePornDB (عنوان بعلامات مختلفة، استوديو فرعي، فرق يوم) ⇒ عمل واحد بالمعرّفين', () {
      final m = mergeWorks([{'t': 'Hot Day', 's': 'Brazzers', 'd': '2024-01-02', 'is': 'A', 'w': 1, 'r': 5}], [{'t': 'Hot Day!', 's': 'Brazzers Exxtra', 'd': '2024-01-03', 'ip': 'X', 'p': 'https://img.test/x.jpg'}]);
      expect(m.list.length, 1); expect(m.added, 0);
      expect(m.list.single['ip'], 'X'); expect(m.list.single['is'], 'A');
      expect(m.list.single['w'], 1); expect(m.list.single['r'], 5);            // بياناتك باقية
      expect(m.list.single['p'], 'https://img.test/x.jpg');                       // الصورة الناقصة تُملأ
    });
    test('تاريخان متباعدان أو معرّفان مختلفان من نفس المصدر ⇒ عملان مختلفان', () {
      expect(mergeWorks([{'t': 'Intro', 's': 'St', 'd': '2020-01-01', 'is': 'A'}], [{'t': 'Intro', 's': 'St', 'd': '2023-06-01', 'ip': 'X'}]).list.length, 2);
      expect(mergeWorks([{'t': 'Intro', 's': 'St', 'ip': 'X'}], [{'t': 'Intro', 's': 'St', 'ip': 'Y'}]).list.length, 2);
    });
    test('إزالة التكرار داخل ممثلة تدمج الحقول ولا تفقد شيئًا', () {
      final d = dedupeWorks([{'t': 'Scene A', 's': 'St', 'is': 'A', 'w': 1}, {'t': 'Scene A', 's': 'St', 'ip': 'X', 'n': 'ملاحظتي'}, {'t': 'Other', 's': 'St'}]);
      expect(d.removed, 1); expect(d.list.length, 2);
      expect(d.list.first['w'], 1); expect(d.list.first['n'], 'ملاحظتي'); expect(d.list.first['ip'], 'X');
    });
    test('التوحيد عبر الممثلات: نسخة StashDB عند ممثلة ونسخة ThePornDB عند أخرى ⇒ مجموعة واحدة', () {
      final a = Performer({'id': 'a', 'name': 'A', 'works': [{'t': 'Duo Scene', 's': 'Studio', 'd': '2024-05-05', 'is': 'S1'}]});
      final b = Performer({'id': 'b', 'name': 'B', 'works': [{'t': 'Duo Scene', 's': 'Studio', 'd': '2024-05-05', 'ip': 'P1', 'w': 1}]});
      final g = groupWorks([a, b]);
      expect(g.length, 1); expect(g.single.who.length, 2); expect(g.single.key, 'is:S1'); expect(g.single.seen, isTrue);
    });
  });

  group('الشخص نفسه في المصدرين', () {
    const s = Candidate(source: 'stash', id: '1', name: 'Jane Sample', birth: '1995-04-04', country: 'CZ');
    test('نفس الاسم والتاريخ ⇒ نعم؛ تاريخ مختلف ⇒ لا؛ اسم آخر ⇒ لا', () {
      expect(samePerson(s, const Candidate(source: 'tpdb', id: '9', name: 'Jane Sample', birth: '1995-04-04')), isTrue);
      expect(samePerson(s, const Candidate(source: 'tpdb', id: '9', name: 'Jane Sample', birth: '1997-01-01')), isFalse);
      expect(samePerson(s, const Candidate(source: 'tpdb', id: '9', name: 'Jane Other', birth: '1995-04-04')), isFalse);
      expect(samePerson(s, const Candidate(source: 'tpdb', id: '9', name: 'J. S.', aliases: 'Jane Sample', birth: '1995-04-04')), isTrue);   // اسم بديل
    });
  });

  group('الجلب من المصدرين', () {
    test('يدمج المعلومات والأعمال والصور بلا تكرار', () async {
      sourceClient = MockClient((r) async {
        if (r.url.host == 'stashdb.org') {
          final q = '${jsonDecode(r.body)['query']}';
          if (q.contains('findPerformer')) return http.Response(jsonEncode({'data': {'findPerformer': {'id': 'S', 'name': 'Jane', 'birth_date': '1995-04-04', 'country': 'CZ', 'aliases': ['JJ'], 'images': [{'url': 'https://img.test/a.jpg', 'width': 600, 'height': 800}]}}}), 200);
          return http.Response(jsonEncode({'data': {'queryScenes': {'count': 1, 'scenes': [{'id': 'SC', 'title': 'Shared Scene', 'release_date': '2024-02-02', 'studio': {'name': 'Studio X'}, 'images': []}]}}}), 200);
        }
        if (r.url.path.endsWith('/scenes')) return http.Response(jsonEncode({'data': [{'id': 'TP1', 'title': 'Shared Scene', 'date': '2024-02-02', 'site': {'name': 'Studio X'}}, {'id': 'TP2', 'title': 'Only On TPDB', 'date': '2023-01-01', 'site': {'name': 'Y'}}], 'meta': {'last_page': 1}}), 200);
        return http.Response(jsonEncode({'data': {'id': 'T', 'name': 'Jane', 'aliases': ['Janey'], 'extras': {'birthday': '1995-04-04', 'height': '165cm'}, 'image': 'https://img.test/b.jpg', 'posters': [{'url': 'https://img.test/a.jpg'}]}}), 200);
      });
      final d = await fetchBoth(stashId: 'S', pdbId: 'T');
      expect(d.minor, isFalse); expect(d.sources, ['StashDB', 'ThePornDB']);
      expect(d.works.length, 2);                                          // المشترك مرة واحدة + الخاص بـ ThePornDB
      expect(d.works.firstWhere((w) => w['t'] == 'Shared Scene')['ip'], 'TP1');
      expect(d.info['height'], 165); expect('${d.info['aliases']}', contains('Janey'));
      expect(d.images.where((u) => u == 'https://img.test/a.jpg').length, 1);   // الرابط المكرر مرة واحدة
    });

    test('بوابة +18: إن قال أي مصدر أقل من 18 ⇒ لا أعمال ولا صور (ولا طلبات لها)', () async {
      final calls = <String>[];
      sourceClient = MockClient((r) async {
        calls.add(r.url.path);
        if (r.url.host == 'stashdb.org') return http.Response(jsonEncode({'data': {'findPerformer': {'id': 'S', 'name': 'X', 'birth_date': '1990-01-01', 'images': []}}}), 200);
        return http.Response(jsonEncode({'data': {'id': 'T', 'name': 'X', 'extras': {'birthday': '${DateTime.now().year - 15}-01-01'}}}), 200);
      });
      final d = await fetchBoth(stashId: 'S', pdbId: 'T');
      expect(d.minor, isTrue); expect(d.works, isEmpty); expect(d.images, isEmpty);
      expect(calls.any((p) => p.endsWith('/scenes')), isFalse);
    });
  });

  testWidgets('البصمة المرئية: نفس الصورة بمقاس آخر = مكررة، وصورة مختلفة = لا', (t) async {
    await t.runAsync(() async {
      final a = (await photoHash(await png(400, 600)))!, b = (await photoHash(await png(800, 1200)))!, c = (await photoHash(await png(400, 600, flip: true)))!;
      expect(hamming(a, b) <= dupThreshold, isTrue);
      expect(hamming(a, c) > dupThreshold, isTrue);
    });
  });

  test('انقطاع الاتصال (Connection reset by peer) ⇒ إعادة محاولة تلقائية تنجح', () async {
    var n = 0;
    sourceClient = MockClient((r) async {
      n++;
      if (n == 1) throw http.ClientException('Connection reset by peer');
      return http.Response(jsonEncode({'data': [{'id': '7', 'name': 'Elsa', 'extras': {'gender': 'Female', 'birthday': '1990-02-02'}}]}), 200);
    });
    final l = await TPDB.search('Elsa');
    expect(n, 2); expect(l.single.name, 'Elsa');
  });

  test('انقطاع دائم ⇒ رسالة عربية واضحة (لا نص الخطأ الخام)', () async {
    sourceClient = MockClient((r) async => throw http.ClientException('Connection reset by peer'));
    await expectLater(TPDB.search('Elsa'), throwsA(isA<SourceError>().having((e) => e.msg, 'msg', contains('ThePornDB غير متاح على شبكتك'))));
    // بعد اكتشاف الحجب: لا طلبات جديدة لفترة (رد فوري بلا انتظار)
    var n = 0; sourceClient = MockClient((r) async { n++; return http.Response('{}', 200); });
    await expectLater(TPDB.search('Elsa'), throwsA(isA<SourceError>().having((e) => e.status, 'status', -2)));
    expect(n, 0);
    TPDB.resetBlock();
  });

  test('سجلاتها بأسمائها الأخرى: اسم مميّز من أسمائها ⇒ نفس الشخص؛ اسم قصير شائع بلا تاريخ ⇒ لا', () {
    const me = Candidate(source: 'stash', id: '1', name: 'Jane Sample', aliases: 'Janie Smith, Jade', birth: '1995-04-04');
    expect(samePerson(me, const Candidate(source: 'tpdb', id: '2', name: 'Janie Smith')), isTrue);
    expect(samePerson(me, const Candidate(source: 'tpdb', id: '3', name: 'Jade')), isFalse);
    expect(samePerson(me, const Candidate(source: 'tpdb', id: '4', name: 'Janie Smith', birth: '1999-01-01')), isFalse);
  });

  test('بيانات ThePornDB تُترجم لحقول StashDB بلا تخمين', () {
    final m = tpdbAsStash({'id': 'T', 'name': 'X', 'extras': {'gender': 'Female', 'birthday': '1994-01-01', 'ethnicity': 'Caucasian', 'hair_colour': 'Brunette', 'eye_colour': 'Blue', 'height': '168cm', 'cupsize': '34C', 'fake_boobs': false, 'tattoos': 'None', 'birthplace_code': 'CZ'}});
    expect(m['ethnicity'], 'CAUCASIAN'); expect(m['hair_color'], 'BRUNETTE'); expect(m['eye_color'], 'BLUE');
    expect(m['height'], 168); expect(m['cup_size'], 'C'); expect(m['band_size'], 34); expect(m['breast_type'], 'NATURAL');
    expect(m['tattoos'], isEmpty); expect(m['country'], 'CZ'); expect(m.containsKey('piercings'), isFalse);
  });

  test('الجلب من عدة سجلات (اسمان في ThePornDB) ⇒ كل الأعمال مدمجة بلا تكرار', () async {
    sourceClient = MockClient((r) async {
      if (r.url.host == 'stashdb.org') {
        final q = '${jsonDecode(r.body)['query']}';
        if (q.contains('findPerformer')) return http.Response(jsonEncode({'data': {'findPerformer': {'id': 'S', 'name': 'Jane', 'birth_date': '1995-04-04', 'images': []}}}), 200);
        return http.Response(jsonEncode({'data': {'queryScenes': {'count': 1, 'scenes': [{'id': 'SC', 'title': 'Shared', 'release_date': '2024-02-02', 'studio': {'name': 'St'}, 'images': []}]}}}), 200);
      }
      final id = r.url.pathSegments[1];
      if (r.url.path.endsWith('/scenes')) {
        return http.Response(jsonEncode({'data': id == 'T1' ? [{'id': 'A', 'title': 'Shared', 'date': '2024-02-02', 'site': {'name': 'St'}}] : [{'id': 'B', 'title': 'Under Other Name', 'date': '2021-01-01', 'site': {'name': 'Z'}}], 'meta': {'last_page': 1}}), 200);
      }
      return http.Response(jsonEncode({'data': {'id': id, 'name': id == 'T1' ? 'Jane' : 'Janie Smith', 'extras': {'birthday': '1995-04-04'}}}), 200);
    });
    final d = await fetchBoth(stashId: 'S', pdbId: 'T1', morePdb: ['T2']);
    expect(d.pdbIds.toSet(), {'T1', 'T2'});
    expect(d.works.length, 2);
    expect(d.works.any((w) => w['t'] == 'Under Other Name'), isTrue);
    expect('${d.info['aliases']}', contains('Janie Smith'));
  });

  test('ملف الخط: يُقبل OTF/TTF فقط', () {
    expect(isFontFile(Uint8List.fromList([0x4F, 0x54, 0x54, 0x4F, ...List.filled(20, 0)])), isTrue);
    expect(isFontFile(Uint8List.fromList([0x00, 0x01, 0x00, 0x00, ...List.filled(20, 0)])), isTrue);
    expect(isFontFile(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(20, 0)])), isFalse);
  });
}
