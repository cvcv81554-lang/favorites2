// مقاس فك الصور: يغطي المكان حسب أبعاد الصورة الحقيقية، بلا تكبير وبحد للذاكرة.
import 'package:favorites2/ui/core/fit_resize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('صورة عريضة في مكان طولي (نجمة اليوم): تُفك بارتفاع المكان — لا تُصغَّر بالعرض ثم تُمطّ', () {
    // المكان 390×490 نقطة × 3 = 1170×1470 بكسل؛ الصورة 1800×1200 ⇒ تحتاج ارتفاع 1470 > 1200 ⇒ الأصل كاملًا
    final t = FitResize.target(1800, 1200, 1170, 1470, true);
    expect(t.width, isNull); expect(t.height, isNull);
    // صورة 4000×3000: تُصغَّر لكن ارتفاعها يبقى ≥ ارتفاع المكان
    final b = FitResize.target(4000, 3000, 1170, 1470, true);
    expect(b.height! >= 1470, isTrue); expect(b.width! >= 1170, isTrue); expect(b.width! / b.height!, closeTo(4 / 3, .01));
  });

  test('صورة طولية كبيرة في خلية صغيرة: تُصغَّر لمقاس الخلية فقط (ذاكرة أقل)', () {
    final t = FitResize.target(3000, 4500, 420, 560, true);
    expect(t.width, 420); expect(t.height! >= 560, isTrue);
  });

  test('contain: تظهر كاملة داخل المكان، وحد 12 ميغابكسل', () {
    final c = FitResize.target(6000, 4000, 1170, 2532, false);
    expect(c.width! <= 1170, isTrue);
    final huge = FitResize.target(12000, 9000, 20000, 20000, true);
    expect(huge.width! * huge.height! <= 12.1e6, isTrue);
  });
}
