// محرك الاقتراحات: البوابة، الاستبعاد، الأسباب، مسار 18–21 الموثّق، وثبات اختيار اليوم وتنوعه.
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/recs.dart';
import 'package:flutter_test/flutter_test.dart';

String ymdYearsAgo(int y, {int days = -20}) { final n = DateTime.now(); final d = DateTime(n.year - y, n.month, n.day).add(Duration(days: days)); return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'; }

void main() {
  final lib = [
    Performer({'id': 'a', 'name': 'Seed A', 'stashId': 'S1', 'rating': 5, 'fav': true, 'country': 'CZ', 'birth': '1994-01-01'}),
    Performer({'id': 'b', 'name': 'Seed B', 'stashId': 'S2', 'rating': 3, 'country': 'CZ', 'birth': '1992-01-01'}),
    Performer({'id': 'c', 'name': 'In Library', 'stashId': 'X9', 'country': 'US'}),
  ];
  RecCand c(String id, String name, {String birth = '', String country = '', Set<String>? w, Set<String>? l, int? sc}) => RecCand(id: id, name: name, birth: birth, country: country, withSeeds: w, lanes: l, scenes: sc);

  test('القاصر والتاريخ غير الصالح لا تظهر أبدًا', () {
    final r = rankRecs([c('m', 'Minor', birth: ymdYearsAgo(16)), c('bad', 'Bad', birth: 'x'), c('ok', 'Ok', birth: ymdYearsAgo(30))], lib);
    expect(r.map((x) => x.name), ['Ok']);
  });

  test('الموجودة في المكتبة (بالمعرّف أو الاسم) والمخفية تُستبعد', () {
    final r = rankRecs([c('X9', 'Other'), c('n1', 'in library'), c('h', 'Hidden'), c('k', 'Keep')], lib, hidden: {'h'});
    expect(r.map((x) => x.name), ['Keep']);
  });

  test('«عملت مع» من البذور الأعلى وزنًا ترفع الترتيب وتكتب السبب', () {
    final r = rankRecs([c('p1', 'Plain', country: 'US'), c('p2', 'CoStar', country: 'CZ', w: {'S1', 'S2'})], lib);
    expect(r.first.name, 'CoStar');
    expect(r.first.reasons.first, contains('Seed A'));
    expect(r.first.reasons.any((x) => x.contains('CZ')), isTrue);
  });

  test('18–21: تاريخ كامل فقط، والعمر بين 18 و21 اليوم', () {
    expect(c('y', 'Y', birth: ymdYearsAgo(19)).young18to21, isTrue);
    expect(c('y', 'Y', birth: ymdYearsAgo(22)).young18to21, isFalse);
    expect(c('y', 'Y', birth: '${DateTime.now().year - 19}').young18to21, isFalse); // سنة فقط
    expect(c('y', 'Y', birth: ymdYearsAgo(17)).young18to21, isFalse);
    expect(c('y', 'Y', birth: ymdYearsAgo(18, days: 1)).young18to21, isFalse); // تبلغ 18 غدًا
  });

  test('اختيار اليوم ثابت لنفس اليوم ومتنوع البلدان', () {
    final pool = [for (var i = 0; i < 30; i++) c('r$i', 'R$i', country: ['US', 'CZ', 'BR'][i % 3], sc: i * 10)];
    final r = rankRecs(pool, lib);
    final d = DateTime(2026, 11, 19);
    final a = dailyPick(r, day: d), b = dailyPick(r, day: d), other = dailyPick(r, day: DateTime(2026, 11, 20));
    expect(a.map((x) => x.id), b.map((x) => x.id));
    expect(a.map((x) => x.id).join() == other.map((x) => x.id).join(), isFalse);
    final cnt = <String, int>{}; for (final x in a) { cnt[x.country] = (cnt[x.country] ?? 0) + 1; }
    expect(cnt.values.every((v) => v <= 2), isTrue);
  });

  test('التخزين والاسترجاع بلا فقد', () {
    final x = c('j', 'J', birth: '1990-01-01', country: 'US', w: {'S1'}, l: {'debut'}, sc: 5);
    final y = RecCand.fromJson(x.toJson());
    expect([y.id, y.name, y.birth, y.country, y.scenes], ['j', 'J', '1990-01-01', 'US', 5]);
    expect(y.withSeeds, {'S1'}); expect(y.lanes, {'debut'});
  });
}
