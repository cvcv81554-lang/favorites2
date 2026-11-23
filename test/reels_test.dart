// «مقاطع»: الإعلانات الرسمية فقط، خوارزمية تتعلم من السلوك، استكشاف وتنويع، و«أقل منها» يُحترم.
import 'package:favorites2/data/sources.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/reels.dart';
import 'package:favorites2/domain/work_taste.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> w(String t, String s, {String tr = ''}) => {'t': t, 's': s, 'd': '2024-01-01', 'ip': t, if (tr.isNotEmpty) 'tr': tr};

void main() {
  final perf = [
    for (var k = 0; k < 6; k++) Performer({'id': 'p$k', 'name': 'P$k', 'fav': true, 'works': [for (var j = 0; j < 4; j++) w('W$k-$j', 'S$k', tr: 'https://cdn.test/$k-$j.mp4'), w('NoTrailer$k', 'S$k')]}),
    Performer({'id': 'x', 'name': 'NotFav', 'works': [w('X1', 'SX', tr: 'https://cdn.test/x.mp4')]}),
  ];
  final groups = groupWorks(perf);
  final t = buildWorkTaste(groups);

  test('المقاطع: ما له إعلان فقط، ومن المفضلات افتراضيًا، والكل عند التوسيع', () {
    final f = rankReels(groups, t, const ReelSignals({}, {}));
    expect(f.every((r) => r.url.startsWith('https://')), isTrue);
    expect(f.any((r) => r.g.t.startsWith('NoTrailer')), isFalse);
    expect(f.any((r) => r.g.t == 'X1'), isFalse);
    expect(rankReels(groups, t, const ReelSignals({}, {}), favsOnly: false).any((r) => r.g.t == 'X1'), isTrue);
  });

  test('التنويع: لا تتكرر ممثلة خلال 3 مقاطع متتالية (ما دام ذلك ممكنًا)', () {
    final f = rankReels(groups, t, const ReelSignals({}, {}), seed: 3);
    for (var i = 1; i < 4; i++) { expect(f[i].g.who.first.id == f[i - 1].g.who.first.id, isFalse); }
  });

  test('التعلّم: الإكمال والإعجاب يرفعان ممثلة، والتخطي السريع يخفضها', () {
    var s = const ReelSignals({}, {});
    final loved = groups.firstWhere((g) => g.t == 'W2-0'), skipped = groups.firstWhere((g) => g.t == 'W4-0');
    for (var i = 0; i < 3; i++) { s = recordView(s, loved, frac: 2.1, like: i == 0); s = recordView(s, skipped, frac: .05); }
    expect(s.aff['pf:p2']! > 1, isTrue); expect(s.aff['pf:p4']! < 0, isTrue);
    final f = rankReels(groups, t, s, seed: 1);
    final firstLoved = f.indexWhere((r) => r.g.who.first.id == 'p2' && r.g.t != 'W2-0');
    final firstSkipped = f.indexWhere((r) => r.g.who.first.id == 'p4' && !r.explore);
    expect(firstLoved < firstSkipped || firstSkipped == -1, isTrue);
    expect(f.firstWhere((r) => r.g.who.first.id == 'p2').why, anyOf(contains('P2'), contains('استكشاف')));
  });

  test('«أقل منها» و«إخفاء المقطع» يُحترمان', () {
    var s = dislike(const ReelSignals({}, {}), performerId: 'p1');
    s = dislike(s, hideKey: groups.firstWhere((g) => g.t == 'W0-0').key);
    final f = rankReels(groups, t, s, seed: 2);
    expect(f.any((r) => r.g.t == 'W0-0'), isFalse);
    final idx = f.indexWhere((r) => r.g.who.first.id == 'p1');
    expect(idx == -1 || idx > f.length ~/ 2, isTrue);   // تنزل للأسفل (قد تظهر استكشافًا فقط)
  });

  test('الاستكشاف ~20٪ تقريبًا ومعلَّم بوضوح', () {
    final big = groupWorks([for (var k = 0; k < 20; k++) Performer({'id': 'q$k', 'name': 'Q$k', 'fav': true, 'works': [for (var j = 0; j < 5; j++) w('Q$k-$j', 'T$k', tr: 'https://cdn.test/q$k-$j.mp4')]})]);
    final f = rankReels(big, buildWorkTaste(big), const ReelSignals({}, {}), seed: 9, n: 80);
    final ex = f.where((r) => r.explore).length;
    expect(ex > 4 && ex < 30, isTrue, reason: 'استكشاف: $ex من ${f.length}');
    expect(f.where((r) => r.explore).every((r) => r.why.contains('استكشاف')), isTrue);
  });

  test('رابط الإعلان من ThePornDB يُقرأ بتسامح (نص، {url}، قائمة) — https فقط', () {
    expect(trailerOf({'trailer': 'https://cdn.test/a.mp4'}), 'https://cdn.test/a.mp4');
    expect(trailerOf({'trailer': {'url': 'https://cdn.test/b.mp4'}}), 'https://cdn.test/b.mp4');
    expect(trailerOf({'trailers': [{'url': 'https://cdn.test/c.mp4'}]}), 'https://cdn.test/c.mp4');
    expect(trailerOf({'trailer': 'http://insecure.test/d.mp4'}), '');
    expect(trailerOf({}), '');
  });

  test('الخوادم: المحجوب لا يُعرض، غير المفحوص يُجرَّب، وإعادة الفحص بمواعيدها', () {
    final now = DateTime(2026, 11, 22).millisecondsSinceEpoch;
    final hosts = <String, dynamic>{'cdn.test': {'ok': false, 't': now}};
    final f = rankReels(groups, t, const ReelSignals({}, {}), playable: (u) => hostUsable(hosts, u));
    expect(f, isEmpty);                                                   // كل المقاطع على خادم محجوب
    expect(rankReels(groups, t, const ReelSignals({}, {}), playable: (u) => hostUsable({}, u)), isNotEmpty);   // غير مفحوص ⇒ يُجرَّب
    expect(hostStale({'ok': false, 't': now - 2 * 3600000}, now), isFalse);
    expect(hostStale({'ok': false, 't': now - 7 * 3600000}, now), isTrue);
    expect(hostStale({'ok': true, 't': now - 10 * 86400000}, now), isFalse);
    expect(hostStale(null, now), isTrue);
    expect(hostOf('https://CDN.Test/a.mp4'), 'cdn.test');
  });

  test('خطأ المشغّل الدال على الحجب يُعرف (TLS / -1200 / reset)', () {
    expect(looksBlocked('NSErrorClientException: A TLS error caused the secure connection to fail'), isTrue);
    expect(looksBlocked('PlatformException(VideoError, Failed to load video: NSURLErrorDomain -1200)'), isTrue);
    expect(looksBlocked('Connection reset by peer'), isTrue);
    expect(looksBlocked('Failed to load video: 404'), isFalse);
  });

  test('الجودة: المعاينة (بلا صوت أو < 480p) تُستبعد، والخادم الذي معظمه معاينات يُستبعد، وغير المقاس يُجرَّب', () {
    final q = <String, dynamic>{
      'https://prev.test/1.mp4': {'h': 360, 'a': 1}, 'https://prev.test/2.mp4': {'h': 720, 'a': 0}, 'https://prev.test/3.mp4': {'h': 240},
      'https://good.test/1.mp4': {'h': 1080, 'a': 1},
    };
    expect(isPreviewClip({'h': 720, 'a': 0}), isTrue); expect(isPreviewClip({'h': 1080, 'a': 1}), isFalse); expect(isPreviewClip({'h': 1080}), isFalse);
    expect(isPreviewHost(q, 'prev.test'), isTrue); expect(isPreviewHost(q, 'good.test'), isFalse);
    expect(qualityOk(q, 'https://prev.test/9.mp4', hqOnly: true), isFalse);
    expect(qualityOk(q, 'https://good.test/1.mp4', hqOnly: true), isTrue);
    expect(qualityOk(q, 'https://new.test/1.mp4', hqOnly: true), isTrue);
    expect(qualityOk(q, 'https://prev.test/9.mp4', hqOnly: false), isTrue);
  });
}
