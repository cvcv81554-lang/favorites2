// بوابة +18 — منقولة حرفيًا من التطبيق السابق (01b-storage.js: sdAge / adultOk / minorRec) مع تشديد واحد:
// التاريخ المستحيل (مثل 2005-02-30) يُعامل كغير صالح ⇒ قاصر (أسوأ حالة)، بدل أن يُدوَّر لتاريخ آخر.
// قاعدة لا تُكسر: لا تُضعَف أبدًا، وتُطبَّق قبل أي طلب شبكة لأي سجل أو مرشح.

/// نتيجة حساب العمر: [age] صالح، أو [invalid] لتاريخ غير مفهوم، أو [none] بلا تاريخ.
class AgeResult {
  final int? age;
  final bool invalid;
  const AgeResult._(this.age, this.invalid);
  static const none = AgeResult._(null, false);
  static const bad = AgeResult._(null, true);
  factory AgeResult.of(int a) => AgeResult._(a, false);
  bool get isNone => age == null && !invalid;
}

/// العمر بالتقويم المحلي (يوم الميلاد نفسه يُحتسب).
int ageOn(DateTime birth, DateTime today) {
  var a = today.year - birth.year;
  if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) a--;
  return a;
}

final _re = RegExp(r'^(\d{4})(?:-(\d{1,2}))?(?:-(\d{1,2}))?(?:$|[T\s])');

/// مثل sdAge: تاريخ ناقص ⇒ أسوأ حالة (آخر شهر/آخر يوم = الأصغر سنًا).
AgeResult sdAge(Object? raw, {DateTime? now}) {
  final s = (raw ?? '').toString().trim();
  if (s.isEmpty) return AgeResult.none;
  final m = _re.firstMatch(s);
  if (m == null) return AgeResult.bad;
  final y = int.parse(m.group(1)!);
  final mo = m.group(2) != null ? int.parse(m.group(2)!) : 12;
  if (mo < 1 || mo > 12) return AgeResult.bad;
  final lastDay = DateTime(y, mo + 1, 0).day;
  final da = m.group(3) != null ? int.parse(m.group(3)!) : lastDay;
  if (da < 1 || da > lastDay) return AgeResult.bad;
  final t = now ?? DateTime.now();
  final b = DateTime(y, mo, da);
  if (b.isAfter(DateTime(t.year, t.month, t.day))) return AgeResult.bad; // تاريخ في المستقبل
  return AgeResult.of(ageOn(b, t));
}

/// سجل في المكتبة: قاصر إن كان له تاريخ ميلاد يقول أقل من 18، أو تاريخه غير مفهوم.
/// (بلا تاريخ ⇒ ليس قاصرًا هنا، كما في التطبيق السابق؛ يُستبعد من مسارات العمر الموثّق فقط.)
bool minorRec(Map<String, dynamic>? x, {DateTime? now}) {
  if (x == null) return false;
  final b = x['birth'];
  if (b == null || b.toString().trim().isEmpty) return false;
  final a = sdAge(b, now: now);
  return a.invalid || (a.age ?? 0) < 18;
}

/// مرشح خارجي (له birthRaw أو birth): مقبول فقط إن كان بلا تاريخ أو تاريخه يؤكد 18+.
bool adultOk(Map<String, dynamic>? m, {DateTime? now}) {
  if (m == null) return false;
  final raw = (m['birthRaw'] ?? '').toString().isNotEmpty ? m['birthRaw'] : m['birth'];
  final a = sdAge(raw, now: now);
  return a.isNone || (!a.invalid && (a.age ?? 0) >= 18);
}
