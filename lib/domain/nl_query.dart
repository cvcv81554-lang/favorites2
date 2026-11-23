import 'age_gate.dart';
import 'performer.dart';

/// البحث باللغة الطبيعية: «شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق» ⇒ فلاتر. على جهازك فقط.
/// محلّل قواعد عربي/إنجليزي يعمل دائمًا؛ ونموذج Apple على الجهاز (إن توفّر) يملأ نفس البنية من JSON.
class NlQuery {
  final Set<String> hair, eth, eyes, countries;
  final int? minAge, maxAge; final double? minRating, minHeight, maxHeight;
  final bool? fav, tattoos, unseen; final String? breast, sort;
  final String text;   // ما تبقّى بلا فهم (يُستخدم بحثًا بالاسم فقط إن لم يُفهم شيء)
  const NlQuery({this.hair = const {}, this.eth = const {}, this.eyes = const {}, this.countries = const {}, this.minAge, this.maxAge, this.minRating, this.minHeight, this.maxHeight,
    this.fav, this.tattoos, this.unseen, this.breast, this.sort, this.text = ''});

  bool get isEmpty => hair.isEmpty && eth.isEmpty && eyes.isEmpty && countries.isEmpty && minAge == null && maxAge == null && minRating == null && minHeight == null && maxHeight == null
    && fav == null && tattoos == null && unseen == null && breast == null && sort == null;

  /// ما فهمه البحث، بالعربية (يظهر رقائق قابلة للإزالة).
  List<String> get labels => [
    for (final h in hair) _hairAr[h] ?? h, for (final e in eth) _ethAr[e] ?? e, for (final e in eyes) 'عيون ${_eyesAr[e] ?? e}',
    for (final c in countries) _countryAr[c] ?? c,
    if (minAge != null && maxAge != null) 'العمر $minAge–$maxAge' else if (minAge != null) 'العمر $minAge+' else if (maxAge != null) 'العمر حتى $maxAge',
    if (minRating != null) 'التقييم ${_n(minRating!)}+',
    if (minHeight != null) 'الطول ${minHeight!.round()}+ سم', if (maxHeight != null) 'الطول حتى ${maxHeight!.round()} سم',
    if (fav == true) 'المفضلة', if (tattoos == true) 'بوشوم', if (tattoos == false) 'بلا وشوم', if (unseen == true) 'لم تشاهد لها',
    if (breast == 'NATURAL') 'صدر طبيعي', if (breast == 'FAKE') 'صدر مُعزَّز',
    if (sort == 'rating') 'الأعلى تقييمًا', if (sort == 'young') 'الأصغر', if (sort == 'old') 'الأكبر', if (sort == 'new') 'الأحدث إضافة',
  ];

  Map<String, dynamic> toJson() => {'hair': hair.toList(), 'eth': eth.toList(), 'eyes': eyes.toList(), 'countries': countries.toList(), 'minAge': ?minAge, 'maxAge': ?maxAge,
    'minRating': ?minRating, 'minHeight': ?minHeight, 'maxHeight': ?maxHeight, 'fav': ?fav, 'tattoos': ?tattoos, 'unseen': ?unseen, 'breast': ?breast, 'sort': ?sort};

  /// من JSON النموذج: كل قيمة تُتحقق من القوائم المسموحة (لا يُقبل شيء مخترع).
  factory NlQuery.fromJson(Map j) {
    Set<String> pick(Object? v, Iterable<String> ok) => {for (final x in (v is List ? v : const [])) if (ok.contains('$x'.toUpperCase())) '$x'.toUpperCase()};
    int? age(Object? v) { return (v as num?)?.toInt().clamp(18, 99); }
    double? num01(Object? v, double lo, double hi) { return (v as num?)?.toDouble().clamp(lo, hi); }
    bool? b(Object? v) => v is bool ? v : null;
    final br = '${j['breast'] ?? ''}'.toUpperCase(), so = '${j['sort'] ?? ''}';
    return NlQuery(hair: pick(j['hair'], _hairAr.keys), eth: pick(j['eth'], _ethAr.keys), eyes: pick(j['eyes'], _eyesAr.keys), countries: pick(j['countries'], _countryAr.keys),
      minAge: age(j['minAge']), maxAge: age(j['maxAge']), minRating: num01(j['minRating'], 0, 5), minHeight: num01(j['minHeight'], 120, 210), maxHeight: num01(j['maxHeight'], 120, 210),
      fav: b(j['fav']), tattoos: b(j['tattoos']), unseen: b(j['unseen']), breast: const {'NATURAL', 'FAKE'}.contains(br) ? br : null,
      sort: const {'rating', 'young', 'old', 'new'}.contains(so) ? so : null);
  }

  NlQuery without(String label) {
    bool keep(String l) => l != label;
    return NlQuery(hair: {for (final h in hair) if (keep(_hairAr[h] ?? h)) h}, eth: {for (final e in eth) if (keep(_ethAr[e] ?? e)) e}, eyes: {for (final e in eyes) if (keep('عيون ${_eyesAr[e] ?? e}')) e},
      countries: {for (final c in countries) if (keep(_countryAr[c] ?? c)) c},
      minAge: label.startsWith('العمر') ? null : minAge, maxAge: label.startsWith('العمر') ? null : maxAge, minRating: label.startsWith('التقييم') ? null : minRating,
      minHeight: label.startsWith('الطول') ? null : minHeight, maxHeight: label.startsWith('الطول') ? null : maxHeight,
      fav: label == 'المفضلة' ? null : fav, tattoos: label.contains('وشوم') ? null : tattoos, unseen: label == 'لم تشاهد لها' ? null : unseen,
      breast: label.startsWith('صدر') ? null : breast, sort: const ['الأعلى تقييمًا', 'الأصغر', 'الأكبر', 'الأحدث إضافة'].contains(label) ? null : sort, text: text);
  }
}

String _n(double x) => x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1);

const _hairAr = {'BLONDE': 'شقراء', 'BRUNETTE': 'شعر بني', 'BLACK': 'شعر أسود', 'RED': 'صهباء', 'AUBURN': 'كستنائية', 'GREY': 'شعر رمادي'};
const _ethAr = {'CAUCASIAN': 'بيضاء', 'BLACK': 'سمراء البشرة', 'ASIAN': 'آسيوية', 'INDIAN': 'هندية', 'LATIN': 'لاتينية', 'MIDDLE_EASTERN': 'شرق أوسطية', 'MIXED': 'مختلطة'};
const _eyesAr = {'BLUE': 'زرقاء', 'BROWN': 'بنية', 'GREEN': 'خضراء', 'HAZEL': 'عسلية', 'GREY': 'رمادية'};
const _countryAr = {'BR': 'البرازيل', 'US': 'أمريكا', 'RU': 'روسيا', 'UA': 'أوكرانيا', 'CZ': 'التشيك', 'HU': 'المجر', 'FR': 'فرنسا', 'DE': 'ألمانيا', 'ES': 'إسبانيا', 'IT': 'إيطاليا',
  'GB': 'بريطانيا', 'CA': 'كندا', 'CO': 'كولومبيا', 'JP': 'اليابان', 'RO': 'رومانيا', 'LV': 'لاتفيا', 'PL': 'بولندا', 'AU': 'أستراليا', 'VE': 'فنزويلا', 'AR': 'الأرجنتين',
  'MX': 'المكسيك', 'SE': 'السويد', 'NL': 'هولندا', 'SK': 'سلوفاكيا', 'BY': 'بيلاروسيا', 'TH': 'تايلاند', 'PH': 'الفلبين', 'CU': 'كوبا', 'PT': 'البرتغال', 'GR': 'اليونان'};
/// جذور الجنسيات (عربي بعد التطبيع + إنجليزي) ⇒ رمز البلد.
const _countryStems = {'برازيل': 'BR', 'brazil': 'BR', 'امريك': 'US', 'american': 'US', 'usa': 'US', 'روس': 'RU', 'russia': 'RU', 'اوكران': 'UA', 'ukrain': 'UA', 'تشيك': 'CZ', 'czech': 'CZ',
  'مجر': 'HU', 'هنغار': 'HU', 'hungar': 'HU', 'فرنس': 'FR', 'french': 'FR', 'france': 'FR', 'الماني': 'DE', 'المانيا': 'DE', 'german': 'DE', 'اسبان': 'ES', 'spani': 'ES', 'spain': 'ES',
  'ايطال': 'IT', 'ital': 'IT', 'بريطان': 'GB', 'انجليز': 'GB', 'british': 'GB', 'english': 'GB', 'كندي': 'CA', 'كندا': 'CA', 'canad': 'CA', 'كولومب': 'CO', 'colombia': 'CO',
  'يابان': 'JP', 'japan': 'JP', 'رومان': 'RO', 'romania': 'RO', 'لاتفي': 'LV', 'latvia': 'LV', 'بولند': 'PL', 'polish': 'PL', 'poland': 'PL', 'استرال': 'AU', 'australia': 'AU',
  'فنزويل': 'VE', 'venezuela': 'VE', 'ارجنتين': 'AR', 'argentin': 'AR', 'مكسيك': 'MX', 'mexic': 'MX', 'سويد': 'SE', 'swed': 'SE', 'هولند': 'NL', 'dutch': 'NL', 'netherland': 'NL',
  'سلوفاك': 'SK', 'slovak': 'SK', 'بيلاروس': 'BY', 'belarus': 'BY', 'تايلند': 'TH', 'تايلاند': 'TH', 'thai': 'TH', 'فلبين': 'PH', 'filip': 'PH', 'philipp': 'PH', 'كوب': 'CU', 'cuba': 'CU',
  'برتغال': 'PT', 'portug': 'PT', 'يونان': 'GR', 'greek': 'GR', 'greece': 'GR'};

/// تطبيع عربي للمطابقة: بلا تشكيل، أ/إ/آ ⇒ ا، ة ⇒ ه، ى ⇒ ي، أرقام عربية ⇒ لاتينية.
String arNorm(String s) {
  var x = s.toLowerCase().replaceAll(RegExp('[ً-ْـ]'), '').replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي');
  const d = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) { x = x.replaceAll(d[i], '$i'); }
  return x.replaceAll('٫', '.');
}

NlQuery parseQuery(String input) {
  var s = ' ${arNorm(input)} ';
  final hair = <String>{}, eth = <String>{}, eyes = <String>{}, countries = <String>{};
  int? minAge, maxAge; double? minRating, minHeight, maxHeight; bool? fav, tattoos, unseen; String? breast, sort;
  bool take(RegExp r) { if (!r.hasMatch(s)) return false; s = s.replaceAll(r, ' '); return true; }
  RegExp w(String p) => RegExp(p, caseSensitive: false);

  // التقييم أولًا (حتى لا تُقرأ أرقامه أعمارًا)
  final rm = w(r'(?:تقييم\S*|نجوم|نجمات|نجمه|rating|rated|stars?)\D{0,14}?(\d(?:\.\d)?)|(\d(?:\.\d)?)\s*(?:نجوم|نجمات|نجمه|stars?|\+\s*نجوم)').firstMatch(s);
  if (rm != null) { minRating = double.parse(rm.group(1) ?? rm.group(2)!).clamp(0, 5).toDouble(); s = s.replaceFirst(rm.group(0)!, ' '); s = s.replaceAll(w(r'فما فوق|فاكثر|او اكثر|and up|or more'), ' '); }
  // الطول
  final hm = w(r'طول\S*\s*(?:فوق|اكثر من|over|>)\s*(\d{3})|(?:taller than|over)\s*(\d{3})\s*cm').firstMatch(s);
  if (hm != null) { minHeight = double.parse(hm.group(1) ?? hm.group(2)!); s = s.replaceFirst(hm.group(0)!, ' '); }
  final hm2 = w(r'طول\S*\s*(?:تحت|اقل من|under|<)\s*(\d{3})').firstMatch(s);
  if (hm2 != null) { maxHeight = double.parse(hm2.group(1)!); s = s.replaceFirst(hm2.group(0)!, ' '); }
  if (minHeight == null && take(w(r'\s(?:طويل\S*|tall)\s'))) minHeight = 170;
  if (maxHeight == null && take(w(r'\s(?:قصير\S*|petite|short)\s'))) maxHeight = 160;
  // العمر
  final between = w(r'(?:بين|من|between|aged?)\s*(\d{2})\s*(?:و|الي|الى|to|and|-)\s*(\d{2})|(\d{2})\s*[-–]\s*(\d{2})').firstMatch(s);
  if (between != null) {
    final a = int.parse(between.group(1) ?? between.group(3)!), b = int.parse(between.group(2) ?? between.group(4)!);
    if (a >= 18 && b >= 18 && a <= 99 && b <= 99) { minAge = a < b ? a : b; maxAge = a < b ? b : a; s = s.replaceFirst(between.group(0)!, ' '); }
  }
  final under = w(r'(?:اقل من|تحت|اصغر من|دون|under|below|younger than)\s*(\d{2})').firstMatch(s);
  if (under != null) { maxAge = int.parse(under.group(1)!); s = s.replaceFirst(under.group(0)!, ' '); }
  final over = w(r'(?:اكبر من|فوق|اكثر من|over|above|older than)\s*(\d{2})').firstMatch(s);
  if (over != null) { minAge = int.parse(over.group(1)!); s = s.replaceFirst(over.group(0)!, ' '); }
  final exact = w(r'(?:عمرها|سنها|عمر|age)\s*(\d{2})').firstMatch(s);
  if (exact != null) { final a = int.parse(exact.group(1)!); minAge ??= a; maxAge ??= a; s = s.replaceFirst(exact.group(0)!, ' '); }
  if (minAge == null && maxAge == null && take(w(r'\s(?:صغير\S*|شاب\S*|young|teen)\s'))) maxAge = 25;
  if (minAge == null && take(w(r'\s(?:ناضج\S*|milf|mature)\s'))) minAge = 35;
  if (minAge != null) minAge = minAge.clamp(18, 99);
  if (maxAge != null) maxAge = maxAge.clamp(18, 99);
  // الشعر والعرق والعيون (العيون والشعر الصريح قبل الألوان العامة)
  if (take(w(r'عيون\S*\s*زرق\S*|زرقاء العيون|blue eyes|blue-eyed'))) eyes.add('BLUE');
  if (take(w(r'عيون\S*\s*خضر\S*|خضراء العيون|green eyes'))) eyes.add('GREEN');
  if (take(w(r'عيون\S*\s*عسلي\S*|hazel'))) eyes.add('HAZEL');
  if (take(w(r'عيون\S*\s*بني\S*|brown eyes'))) eyes.add('BROWN');
  if (take(w(r'شعر\S*\s*بني\S*|بنيه الشعر|brunette|brown hair'))) hair.add('BRUNETTE');
  if (take(w(r'شعر\S*\s*اسود|سوداء الشعر|black hair'))) hair.add('BLACK');
  if (take(w(r'صهباء|صهب\S*|شعر\S*\s*احمر|حمراء الشعر|redhead|ginger|red hair'))) hair.add('RED');
  if (take(w(r'\s(?:ال)?شقر\S*|blonde?s?\s'))) hair.add('BLONDE');
  if (take(w(r'\s(?:ال)?سمر\S*|سوداء البشره|ebony|black women|\sblack\s'))) eth.add('BLACK');
  if (take(w(r'لاتين\S*|latina?s?'))) eth.add('LATIN');
  if (take(w(r'اسيوي\S*|asians?'))) eth.add('ASIAN');
  if (take(w(r'هندي\S*|indian'))) eth.add('INDIAN');
  if (take(w(r'شرق اوسطي\S*|عربي\S*|arab\S*|middle eastern'))) eth.add('MIDDLE_EASTERN');
  if (take(w(r'\s(?:بيضاء|بيض|caucasian|white)\s'))) eth.add('CAUCASIAN');
  // البلد
  for (final e in _countryStems.entries) {
    final r = w('\\s(?:ال)?${RegExp.escape(e.key)}\\S*');
    if (r.hasMatch(s)) { countries.add(e.value); s = s.replaceAll(r, ' '); }
  }
  // الوشوم والصدر
  if (take(w(r'(?:بدون|بلا|من غير|ما عندها|no|without)\s*(?:اي\s*)?(?:وشو?م\S*|تاتو\S*|tattoos?)'))) { tattoos = false; }
  else if (take(w(r'وشو?م\S*|موشوم\S*|تاتو\S*|tattoo\S*|inked'))) { tattoos = true; }
  if (take(w(r'صدر\S*\s*طبيعي\S*|طبيعي\S*|natural'))) breast = 'NATURAL';
  if (take(w(r'صدر\S*\s*(?:صناعي|مكبر|معزز|سيليكون)\S*|سيليكون|fake|enhanced|implants?'))) breast = 'FAKE';
  // المكتبة
  if (take(w(r'(?:من\s*)?(?:ال)?مفضل\S*|favou?rites?|favs?'))) fav = true;
  if (take(w(r'(?:ما|لم)\s*(?:شاهدت|اشاهد|شفت)\s*(?:لها)?\S*|unwatched|not watched|haven.?t seen'))) unseen = true;
  // الترتيب
  if (take(w(r'الاعلي تقييما|الاعلى تقييما|اعلى تقييم|top rated|best rated'))) { sort = 'rating'; }
  else if (take(w(r'الاصغر\S*|youngest'))) { sort = 'young'; }
  else if (take(w(r'الاكبر سنا|الاكبر\S*|oldest'))) { sort = 'old'; }
  else if (take(w(r'الاحدث اضافه|المضافه حديثا|احدث\S*|newest|recent'))) { sort = 'new'; }
  // ما تبقّى: كلمات وصل وحشو تُحذف
  final rest = s.replaceAll(w(r'\s(?:ابي|ابغى|ابغي|ابحث|عن|اعرض|ورني|وريني|ممثل\S*|التي|اللي|الي|و|من|في|مع|ذات|لها|عندها|عمرها|سن\S*|عمر\S*|سنه|سنوات|سنة|و?بين|او|show|me|find|with|and|the|a|years?|old|girls?|women|performers?)(?=\s)'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ').trim();
  return NlQuery(hair: hair, eth: eth, eyes: eyes, countries: countries, minAge: minAge, maxAge: maxAge, minRating: minRating, minHeight: minHeight, maxHeight: maxHeight,
    fav: fav, tattoos: tattoos, unseen: unseen, breast: breast, sort: sort, text: rest);
}

/// هل الممثلة تطابق؟ [f]: خصائصها الموثّقة (من ذاكرة التحليل: hair_color, ethnicity, eye_color, breast_type, height, tattoos).
/// الخاصية المطلوبة وغير المعروفة للممثلة ⇒ لا تطابق (لا تخمين).
bool nlMatch(NlQuery q, Performer p, Map<String, Object> f) {
  if (p.isMinor) return false;
  bool inSet(Set<String> want, String key) => want.isEmpty || want.contains('${f[key] ?? ''}');
  if (!inSet(q.hair, 'hair_color') || !inSet(q.eth, 'ethnicity') || !inSet(q.eyes, 'eye_color')) return false;
  if (q.countries.isNotEmpty && !q.countries.contains((p.country.isNotEmpty ? p.country : '${f['country'] ?? ''}').toUpperCase())) return false;
  if (q.minAge != null || q.maxAge != null) {
    final a = sdAge(p.birth).age ?? (f['age'] as num?)?.toInt(); if (a == null) return false;
    if (q.minAge != null && a < q.minAge!) return false;
    if (q.maxAge != null && a > q.maxAge!) return false;
  }
  if (q.minRating != null && p.rating < q.minRating!) return false;
  final h = (f['height'] as num?)?.toDouble();
  if ((q.minHeight != null || q.maxHeight != null) && h == null) return false;
  if (q.minHeight != null && h! < q.minHeight!) return false;
  if (q.maxHeight != null && h! > q.maxHeight!) return false;
  if (q.fav == true && !p.fav) return false;
  if (q.tattoos != null && f['tattoos'] != (q.tattoos! ? 'yes' : 'no')) return false;
  if (q.breast != null && f['breast_type'] != q.breast) return false;
  if (q.unseen == true && p.watchedCount > 0) return false;
  return true;
}

/// ترتيب النتائج حسب طلبك.
List<Performer> nlSort(NlQuery q, List<Performer> l) {
  int age(Performer p) => sdAge(p.birth).age ?? 999;
  return switch (q.sort) {
    'rating' => [...l]..sort((a, b) => b.rating.compareTo(a.rating)),
    'young' => [...l]..sort((a, b) => age(a).compareTo(age(b))),
    'old' => [...l]..sort((a, b) => (age(b) == 999 ? -1 : age(b)).compareTo(age(a) == 999 ? -1 : age(a))),
    'new' => [...l]..sort((a, b) => b.added.compareTo(a.added)),
    _ => [...l]..sort((a, b) => (b.fav ? 1 : 0) - (a.fav ? 1 : 0) != 0 ? (b.fav ? 1 : 0) - (a.fav ? 1 : 0) : b.rating.compareTo(a.rating)),
  };
}

/// تعليمات نموذج Apple على الجهاز: يعيد JSON بنفس البنية، بالقيم المسموحة فقط.
const nlModelInstructions = '''Convert the user's search (Arabic or English) for performers in their private library into JSON only, no prose.
Keys (omit unknown): hair [BLONDE,BRUNETTE,BLACK,RED,AUBURN,GREY], eth [CAUCASIAN,BLACK,ASIAN,INDIAN,LATIN,MIDDLE_EASTERN,MIXED], eyes [BLUE,BROWN,GREEN,HAZEL,GREY],
countries [ISO-3166 alpha-2 codes], minAge, maxAge (integers, 18 or more), minRating (0-5), minHeight, maxHeight (cm), fav (bool), tattoos (bool), unseen (bool),
breast (NATURAL|FAKE), sort (rating|young|old|new).
Example: "شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق" => {"hair":["BLONDE"],"countries":["BR"],"minAge":20,"maxAge":25,"minRating":4}''';
