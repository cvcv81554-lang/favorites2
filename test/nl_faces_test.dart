// البحث باللغة الطبيعية (محلّل عربي/إنجليزي، والتحقق من JSON النموذج) ورياضيات تمييز الوجوه (التشابه، الإجماع، الترتيب).
import 'dart:math';
import 'dart:typed_data';

import 'package:favorites2/data/faces.dart';
import 'package:favorites2/domain/nl_query.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List vec(List<double> v) { final n = sqrt(v.fold<double>(0, (a, x) => a + x * x)); return Float32List.fromList([for (final x in v) x / n]); }

void main() {
  test('المثال الأساسي: «شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق»', () {
    final q = parseQuery('شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق');
    expect(q.hair, {'BLONDE'}); expect(q.countries, {'BR'}); expect(q.minAge, 20); expect(q.maxAge, 25); expect(q.minRating, 4); expect(q.text, '');
    expect(q.labels, containsAll(['شقراء', 'البرازيل', 'العمر 20–25', 'التقييم 4+']));
  });

  test('صيغ أخرى: عيون، شعر، عرق، وشوم، طول، مفضلة، ترتيب، أرقام عربية، إنجليزي', () {
    final a = parseQuery('سمراء طويلة بدون وشوم من المفضلة الأعلى تقييما');
    expect(a.eth, {'BLACK'}); expect(a.minHeight, 170); expect(a.tattoos, false); expect(a.fav, true); expect(a.sort, 'rating');
    final b = parseQuery('صهباء عيونها زرق تحت ٣٠');
    expect(b.hair, {'RED'}); expect(b.eyes, {'BLUE'}); expect(b.maxAge, 30);
    final c = parseQuery('latina blonde over 30 with tattoos 4 stars');
    expect(c.eth, {'LATIN'}); expect(c.hair, {'BLONDE'}); expect(c.minAge, 30); expect(c.tattoos, true); expect(c.minRating, 4);
    final d = parseQuery('روسية أو أوكرانية صدر طبيعي ما شاهدت لها');
    expect(d.countries, {'RU', 'UA'}); expect(d.breast, 'NATURAL'); expect(d.unseen, true);
    expect(parseQuery('عمرها 17').minAge, 18);                   // لا عمر تحت 18 أبدًا
    expect(parseQuery('Jane Doe').isEmpty, isTrue); expect(parseQuery('Jane Doe').text, 'jane doe');
  });

  test('المطابقة: الخاصية المطلوبة وغير المعروفة لا تطابق، والقاصر لا تظهر أبدًا', () {
    final y = DateTime.now().year;
    final p = Performer({'id': 'a', 'name': 'A', 'birth': '${y - 23}-01-01', 'country': 'br', 'rating': 4.5, 'fav': true});
    final q = parseQuery('شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق');
    expect(nlMatch(q, p, const {'hair_color': 'BLONDE'}), isTrue);
    expect(nlMatch(q, p, const {'hair_color': 'BRUNETTE'}), isFalse);
    expect(nlMatch(q, p, const {}), isFalse);                         // الشعر غير معروف
    expect(nlMatch(parseQuery('برازيلية'), p, const {}), isTrue);
    final minor = Performer({'id': 'm', 'name': 'M', 'birth': '${y - 16}-01-01', 'country': 'BR'});
    expect(nlMatch(parseQuery('برازيلية'), minor, const {}), isFalse);
    expect(nlSort(parseQuery('الأصغر'), [Performer({'id': '1', 'name': 'x', 'birth': '1990-01-01'}), Performer({'id': '2', 'name': 'y', 'birth': '2000-01-01'})]).first.id, '2');
  });

  test('JSON النموذج: القيم خارج القوائم المسموحة تُرفض، والأعمار تُقص عند 18', () {
    final q = NlQuery.fromJson({'hair': ['BLONDE', 'PURPLE'], 'countries': ['br', 'XX'], 'minAge': 12, 'maxAge': 25, 'minRating': 9, 'breast': 'HUGE', 'sort': 'random', 'fav': 'yes'});
    expect(q.hair, {'BLONDE'}); expect(q.countries, {'BR'}); expect(q.minAge, 18); expect(q.maxAge, 25); expect(q.minRating, 5);
    expect(q.breast, isNull); expect(q.sort, isNull); expect(q.fav, isNull);
    expect(NlQuery.fromJson(q.toJson()).labels, q.labels);
    expect(q.without('شقراء').hair, isEmpty);
  });

  test('الوجوه: التشابه، الإجماع يتجاهل صورة شخص آخر، والترتيب، وبوابة +18', () {
    final her1 = vec([1, .1, 0, 0]), her2 = vec([.95, .2, .05, 0]), her3 = vec([.9, 0, .1, .05]), other = vec([0, 0, 1, .2]);
    expect(cosine(her1, her1), closeTo(1, 1e-6));
    expect(cosine(her1, other) < Faces.maybe, isTrue);
    final c = consensus([her1, other, her2, her3])!;
    expect(cosine(c, her1) > Faces.same, isTrue); expect(cosine(c, other) < Faces.maybe, isTrue);
    expect(consensus([her1, other]), isNull);                       // لا إجماع
    expect(verdict(.6), FaceVerdict.same); expect(verdict(.35), FaceVerdict.maybe); expect(verdict(.1), FaceVerdict.other); expect(verdict(null), FaceVerdict.none);
    final y = DateTime.now().year;
    final a = Performer({'id': 'a', 'name': 'A'}), b = Performer({'id': 'b', 'name': 'B'}), m = Performer({'id': 'm', 'name': 'M', 'birth': '${y - 16}-01-01'});
    final r = rankByFace(her2, {'a': c, 'b': other, 'm': c}, [a, b, m]);
    expect(r.map((x) => x.$1.id), ['a', 'b']);
  });

  test('نموذج الوجوه مثبّت على نسخة محددة وبصمة SHA-256 وحجم', () {
    expect(Faces.modelUrl, contains('/resolve/fac7fea8becbb1963b80670cad1ee1eca4b38fb7/'));
    expect(Faces.modelUrl.contains('/resolve/main/'), isFalse);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(Faces.modelSha256), isTrue);
    expect(Faces.modelBytes, 130356005);
  });
}
