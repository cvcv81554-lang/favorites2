// «يومياتي»: ملخص الشهر مع المقارنة، اكتشافات أول مرة، تقويم المشاهدة، السلاسل، المراحل، وإكمال أعمال المفضلات.
import 'package:favorites2/domain/journal.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> w(String t, String s, {String? wd, String d = '2023-01-01', List<String> tg = const [], int r = 0}) =>
  {'t': t, 's': s, 'd': d, 'ip': t, if (wd != null) 'w': 1, 'wd': ?wd, 'tg': tg, if (r > 0) 'r': r};

void main() {
  final a = Performer({'id': 'a', 'name': 'A', 'fav': true, 'works': [
    w('A1', 'S1', wd: '2026-03-02', tg: ['Outdoor'], r: 4), w('A2', 'S1', wd: '2026-03-02'), w('A3', 'S2', wd: '2026-02-10'),
    w('A4', 'S1'), w('A5', 'S1'), w('A6', 'S1', d: '2099-01-01')]});
  final b = Performer({'id': 'b', 'name': 'B', 'fav': true, 'works': [w('B1', 'S2', wd: '2026-03-20', r: 2), w('B2', 'S2'), w('B3', 'S2'), w('B4', 'S2'), w('B5', 'S2', wd: '2026-03-21')]});
  final gs = groupWorks([a, b]);

  test('ملخص الشهر: العدد والمقارنة بالسابق، الأكثر مشاهدة، أول مرة، الاستوديوهات، الطابع، أنشط يوم، المتوسط', () {
    final r = monthReview(gs, [a, b], 2026, 3);
    expect(r.watched, 4); expect(r.prevWatched, 1); expect(r.delta, 3); expect(r.activeDays, 3);
    expect(r.topPerformers.first.$1.id, 'a'); expect(r.topPerformers.first.$2, 2);
    expect(r.firstTime.map((p) => p.id), ['b']);                // A شاهدت لها في فبراير
    expect(r.topStudios.first, ('S1', 2)); expect(r.topTags.single, ('Outdoor', 1));
    expect(r.bestDay, '2026-03-02'); expect(r.bestDayCount, 2); expect(r.avgRating, 3.0);
    expect(monthReview(gs, [a, b], 2026, 1).watched, 0);
    expect(monthReview(gs, [a, b], 2026, 1).prevWatched, 0);   // ديسمبر السابق
  });

  test('تقويم المشاهدة وسلاسل الأيام', () {
    final hm = watchHeatmap(gs, days: 60, now: DateTime(2026, 3, 25));
    expect(hm, {'2026-03-02': 2, '2026-02-10': 1, '2026-03-20': 1, '2026-03-21': 1});
    expect(watchHeatmap(gs, days: 10, now: DateTime(2026, 3, 25)).keys.toSet(), {'2026-03-20', '2026-03-21'});
    expect(streaks(['2026-03-20', '2026-03-21', '2026-03-22', '2026-03-01'], now: DateTime(2026, 3, 22)), (3, 3));
    expect(streaks(['2026-03-20', '2026-03-21'], now: DateTime(2026, 3, 22)), (2, 2));   // اليوم لم ينتهِ
    expect(streaks(['2026-03-10'], now: DateTime(2026, 3, 22)), (1, 0));
    expect(streaks(const []), (0, 0));
  });

  test('المراحل: إكمال أعمال المفضلات (المنشورة فقط) والمرحلة التالية', () {
    final m = performerMilestones(gs, [a, b]);
    expect(m.map((x) => x.p.id), ['a', 'b']);                       // 3/5 قبل 2/5
    expect(m.first.seen, 3); expect(m.first.total, 5);              // القادم لا يُحسب
    expect(performerMilestones(gs, [a, b], minTotal: 6), isEmpty);
    expect(nextMilestone(0), (10, 0)); expect(nextMilestone(10), (25, 10)); expect(nextMilestone(240), (250, 100)); expect(nextMilestone(5200), (10000, 5000));
  });
}
