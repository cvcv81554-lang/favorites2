// تحسينات «مقاطع» المستوحاة من TikTok: إشارات جديدة، الحفظ، السجل، تلاشي الاهتمام، تنويع الاستوديو، والتركيز.
import 'package:favorites2/data/clip_prefetch.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/reels.dart';
import 'package:favorites2/domain/work_taste.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> w(String t, String s, {List<String> tags = const []}) => {'t': t, 's': s, 'd': '2024-01-01', 'ip': t, 'tr': 'https://cdn.test/$t.mp4', 'tg': tags};

void main() {
  final perf = [
    for (var k = 0; k < 6; k++) Performer({'id': 'p$k', 'name': 'P$k', 'fav': true, 'works': [for (var j = 0; j < 4; j++) w('W$k-$j', j.isEven ? 'SA' : 'SB', tags: j == 0 ? ['Outdoor'] : const [])]}),
  ];
  final groups = groupWorks(perf);
  final t = buildWorkTaste(groups);
  WorkGroup g(String title) => groups.firstWhere((x) => x.t == title);

  test('زيارة الملف وفتح الكامل والمتابعة ترفع الممثلة، و«غير مهتم» يخفي ويخفض', () {
    var s = const ReelSignals({}, {});
    s = recordAction(s, g('W1-0'), 'profile'); s = recordAction(s, g('W1-0'), 'full'); s = recordAction(s, g('W1-0'), 'follow');
    expect(s.aff['pf:p1']!, closeTo(2.0, .001));
    s = recordAction(s, g('W3-0'), 'nope');
    expect(s.aff['pf:p3']! < 0, isTrue); expect(s.clips[g('W3-0').key]?['h'], 1);
    expect(rankReels(groups, t, s).any((r) => r.g.t == 'W3-0'), isFalse);
  });

  test('الحفظ يبدّل ويظهر في «المحفوظة»، والمشاهدة تظهر في «سجلّي» والإعجاب في «أعجبتني»', () {
    var s = toggleSave(const ReelSignals({}, {}), g('W0-1'));
    expect(reelSaved(s), [g('W0-1').key]); expect(s.aff['pf:p0']! > 0, isTrue);
    s = toggleSave(s, g('W0-1'));
    expect(reelSaved(s), isEmpty);
    s = recordView(s, g('W2-2'), frac: .5); s = recordView(s, g('W4-1'), frac: 1, like: true);
    expect(reelHistory(s).toSet(), {g('W2-2').key, g('W4-1').key});
    expect(reelLiked(s), [g('W4-1').key]);
    expect(reelHistory(recordView(const ReelSignals({}, {}), g('W5-0'), frac: 0)), isEmpty);   // لم يُشاهَد فعلًا
  });

  test('تلاشي الاهتمام يوميًا، و«أقل منها» الصريح يبقى، والحفظ/الاسترجاع متوافق', () {
    final s0 = ReelSignals(const {}, {'pf:a': 2.0, 'pf:b': -2.0}, 100);
    final s = decayReels(s0, 130);
    expect(s.aff['pf:a']!, closeTo(2 * 0.6355, .01)); expect(s.aff['pf:b'], -2.0); expect(s.day, 130);
    expect(decayReels(const ReelSignals({}, {'x': 1}), 50).day, 50);   // أول مرة: يبدأ العد فقط
    final back = ReelSignals.fromJson(s.toJson()); expect(back.day, 130); expect(back.aff['pf:a'], s.aff['pf:a']);
    expect(ReelSignals.fromJson({'c': {}, 'a': {'x': .5}}).day, 0);   // صيغة قديمة بلا «d»
  });

  test('تنويع الاستوديو: لا يتكرر استوديو في مقطعين متتاليين ما دام ممكنًا', () {
    final f = rankReels(groups, t, const ReelSignals({}, {}), seed: 4, n: 12);
    for (var i = 1; i < 8; i++) { expect(f[i].g.s == f[i - 1].g.s, isFalse, reason: 'المقطع $i'); }
  });

  test('التركيز: ممثلة / استوديو / وسم (بلا حساسية للحالة)', () {
    expect(reelFocusMatch(g('W2-1'), 'pf', 'p2'), isTrue);
    expect(reelFocusMatch(g('W2-1'), 'pf', 'p3'), isFalse);
    expect(reelFocusMatch(g('W2-1'), 'st', 'sb'), isTrue);
    expect(reelFocusMatch(g('W2-0'), 'tg', 'outdoor'), isTrue);
    expect(reelFocusMatch(g('W2-1'), 'tg', 'outdoor'), isFalse);
  });

  test('الإعدادات: التمرير التلقائي والتبويب الأخير اختياريان ومتوافقان', () {
    final c = ReelsCfg.fromJson({'pf': true});
    expect(c.auto, isFalse); expect(c.favTab, isFalse);
    final d = ReelsCfg.fromJson(c.copy(auto: true, favTab: true).toJson());
    expect(d.auto, isTrue); expect(d.favTab, isTrue); expect(d.count, 100);
  });
}
