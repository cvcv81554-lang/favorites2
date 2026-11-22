// بيانات الويدجت: نفس «نجمة اليوم» في الرئيسية والويدجت، وأقرب إصدار للمفضلات فقط.
import 'dart:math';

import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/ui/core/home_widget_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 22);
  final lib = [
    for (var i = 0; i < 6; i++) Performer({'id': 'p$i', 'name': 'P$i', 'fav': i < 4, 'photos': i == 3 ? <String>[] : ['file:x$i.jpg'],
      'works': [if (i == 1) {'t': 'Soon', 's': 'S', 'd': '2026-11-25'}, if (i == 2) {'t': 'Sooner', 's': 'S', 'd': '2026-11-23'}, if (i == 5) {'t': 'Not fav', 's': 'S', 'd': '2026-11-22'}]}),
  ];

  test('نجمة اليوم: ثابتة طوال اليوم، من المفضلات بصور كاملة، وتطابق اختيار الرئيسية السابق', () {
    final a = pickSpotlight(lib, day)!, b = pickSpotlight(lib, DateTime(2026, 11, 22, 23, 59))!;
    expect(a.id, b.id); expect(a.fav, isTrue); expect(a.photos, isNotEmpty);
    // نفس معادلة الرئيسية قبل التوحيد
    final pool = lib.where((p) => p.fav && p.photos.isNotEmpty).toList();
    expect(a.id, pool[Random(day.year * 1000 + day.month * 40 + day.day).nextInt(pool.length)].id);
  });

  test('أقرب إصدار: للمفضلات فقط، الأقرب أولًا، وعدد إصدارات الأسبوع', () {
    final n = nextRelease(lib, day)!;
    expect(n.$1, 'Sooner'); expect(n.$2, 1); expect(n.$3, 2);
    expect(whenText(0), 'اليوم'); expect(whenText(1), 'غدًا'); expect(whenText(3), 'بعد 3 أيام');
  });

  test('لا قاصر في الويدجت', () {
    final y = DateTime.now().year;
    final only = [Performer({'id': 'm', 'name': 'M', 'fav': true, 'birth': '${y - 15}-01-01', 'photos': ['file:m.jpg']})];
    expect(pickSpotlight(only, day), isNull);
  });
}
