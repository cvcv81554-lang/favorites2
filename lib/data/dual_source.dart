import 'keys.dart';
import 'sources.dart';
import '../domain/age_gate.dart';
import '../domain/sanitize.dart';

/// المصدران معًا (StashDB + ThePornDB) لكل ممثلة: معلومات وأعمال وصور مدمجة بلا تكرار.

Set<String> _names(String name, String aliases) => {
  norm(name),
  for (final a in aliases.split(RegExp(r'[,،;/]'))) if (norm(a).length >= 3) norm(a),
}..remove('');

String _fullDate(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s) ? s.substring(0, 10) : '';
String _year(String s) => RegExp(r'^\d{4}').hasMatch(s) ? s.substring(0, 4) : '';

/// نفس الشخص في المصدرين؟ (محافظ: الخطأ هنا يخلط ممثلتين)
/// - لا بد من اسم مشترك (الاسم أو أحد الأسماء الأخرى).
/// - إن كان تاريخ الميلاد في الاثنين: يجب أن يتطابق (اليوم الكامل، أو السنة إن لم يكتمل).
/// - بلا تاريخ في أحدهما: يجب أن يتطابق الاسم الرئيسي حرفيًا، ولا يتعارض البلد.
bool samePerson(Candidate a, Candidate b) {
  final na = _names(a.name, a.aliases), nb = _names(b.name, b.aliases);
  if (na.intersection(nb).isEmpty) return false;
  final fa = _fullDate(a.birth), fb = _fullDate(b.birth);
  if (fa.isNotEmpty && fb.isNotEmpty) return fa == fb;
  final ya = _year(a.birth), yb = _year(b.birth);
  final ca = a.country.trim().toUpperCase(), cb = b.country.trim().toUpperCase();
  final countryOk = ca.isEmpty || cb.isEmpty || ca == cb || ca.length != cb.length;   // رمز بلد مقابل اسم بلد: لا نعدّه تعارضًا
  if (ya.isNotEmpty && yb.isNotEmpty && ya != yb) return false;
  if (!countryOk) return false;
  if (norm(a.name) == norm(b.name)) return true;
  // سجل باسم آخر (ThePornDB يفصل الأسماء غالبًا): اسمه من أسمائها المعروفة، وهو اسم مميّز (كلمتان فأكثر) أو يذكر اسمها الرئيسي بين أسمائه
  bool distinctive(String n) => n.split(' ').where((w) => w.isNotEmpty).length >= 2;
  return (na.contains(norm(b.name)) && (distinctive(norm(b.name)) || nb.contains(norm(a.name))))
      || (nb.contains(norm(a.name)) && (distinctive(norm(a.name)) || na.contains(norm(b.name))));
}

/// يجد الممثلة نفسها في المصدر الآخر (إن وُجد مفتاحه). مطابقة وحيدة مؤكدة فقط، وإلا null.
Future<Candidate?> findCounterpart(Candidate c) async {
  final other = c.source == 'stash' ? 'tpdb' : 'stash';
  if (!await ApiKeys.has(other == 'stash' ? ApiKeys.stash : ApiKeys.tpdb)) return null;
  try {
    final res = (other == 'stash' ? await StashDB.search(c.name) : await TPDB.search(c.name)).where((x) => x.adult && samePerson(c, x)).toList();
    if (res.length == 1) return res.first;
    final exact = res.where((x) => norm(x.name) == norm(c.name) && _fullDate(x.birth).isNotEmpty && _fullDate(x.birth) == _fullDate(c.birth)).toList();
    return exact.length == 1 ? exact.first : null;
  } catch (_) { return null; }
}

/// **كل** سجلات الممثلة في المصدرين: يبحث باسمها الرئيسي وكل أسمائها الأخرى (حتى 6 أسماء) في StashDB وThePornDB،
/// ويقبل كل سجل يطابقها بمطابقة محافظة (samePerson). [c] نفسها تُضاف لمصدرها.
Future<({List<Candidate> stash, List<Candidate> tpdb})> findAllRecords(Candidate c, {void Function(String)? progress}) async {
  final names = <String>[c.name, ...c.aliases.split(RegExp(r'[,،;/]')).map((a) => a.trim())].where((n) => n.length >= 3).toList();
  final uniq = <String>[]; for (final n in names) { if (!uniq.any((u) => norm(u) == norm(n))) uniq.add(n); }
  final stash = <String, Candidate>{if (c.source == 'stash') c.id: c}, tpdb = <String, Candidate>{if (c.source == 'tpdb') c.id: c};
  final hasS = await ApiKeys.has(ApiKeys.stash), hasT = await ApiKeys.has(ApiKeys.tpdb);
  for (final n in uniq.take(6)) {
    progress?.call('البحث عن «$n» في المصدرين…');
    await Future.wait([
      if (hasS) StashDB.search(n).then((l) { for (final x in l) { if (x.adult && (x.id == c.id && c.source == 'stash' || samePerson(c, x))) stash[x.id] ??= x; } }).catchError((_) {}),
      if (hasT) TPDB.search(n).then((l) { for (final x in l) { if (x.adult && (x.id == c.id && c.source == 'tpdb' || samePerson(c, x))) tpdb[x.id] ??= x; } }).catchError((_) {}),
    ]);
  }
  return (stash: stash.values.toList(), tpdb: tpdb.values.toList());
}

/// ملف ThePornDB الكامل لممثلة (REST الرسمي).
Future<Map<String, dynamic>?> tpdbPerformer(String id) async {
  final d = await TPDB.get('/performers/${Uri.encodeComponent(id)}');
  final p = d['data'] is Map ? d['data'] : d;
  return p is Map ? Map<String, dynamic>.from(p) : null;
}

/// صور ThePornDB الكاملة (الملصقات والصورة الرئيسية — لا المصغرات ولا قص الوجه).
List<String> tpdbImages(Map<String, dynamic>? p) {
  if (p == null) return const [];
  final out = <String>[];
  for (final x in (p['posters'] as List? ?? const [])) { final u = x is Map ? '${x['url'] ?? x['large'] ?? ''}' : '$x'; if (safeHttps(u) && !out.contains(u)) out.add(u); }
  final img = '${p['image'] ?? ''}'; if (safeHttps(img) && !out.contains(img)) out.insert(0, img);
  return out;
}

/// نتيجة الجلب من المصدرين.
class DualProfile {
  final String stashId, pdbId; final Map<String, dynamic> info; final List<String> images; final List<Map<String, dynamic>> works; final List<String> errors, sources, stashIds, pdbIds; final bool minor;
  const DualProfile({this.stashId = '', this.pdbId = '', this.info = const {}, this.images = const [], this.works = const [], this.errors = const [], this.sources = const [], this.stashIds = const [], this.pdbIds = const [], this.minor = false});
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^\d]'), ''));

/// يجلب من **كل** سجلاتها في المصدرين: المعلومات أولًا ⇒ بوابة +18 (لكل السجلات) ⇒ ثم كل الأعمال (كل الصفحات) وكل الصور.
/// [stashId]/[pdbId]: السجلان الرئيسيان، و[moreStash]/[morePdb]: سجلاتها الأخرى (أسماء أخرى).
Future<DualProfile> fetchBoth({String stashId = '', String pdbId = '', List<String> moreStash = const [], List<String> morePdb = const [], int maxPages = 40}) async {
  final errs = <String>[], srcs = <String>[];
  final hasSk = await ApiKeys.has(ApiKeys.stash), hasTk = await ApiKeys.has(ApiKeys.tpdb);
  final sIds = <String>{if (stashId.isNotEmpty) stashId, ...moreStash.where((x) => x.isNotEmpty)}.toList();
  final tIds = <String>{if (pdbId.isNotEmpty) pdbId, ...morePdb.where((x) => x.isNotEmpty)}.toList();
  final sp = <String, Map<String, dynamic>>{}, tp = <String, Map<String, dynamic>>{};
  await Future.wait([
    if (hasSk) for (final id in sIds) stashPerformer(id).then((v) { if (v != null) sp[id] = v; }).catchError((e) { errs.add('StashDB: $e'); }),
    if (hasTk) for (final id in tIds) tpdbPerformer(id).then((v) { if (v != null) tp[id] = v; }).catchError((e) { errs.add('ThePornDB: $e'); }),
  ]);
  final sMain = sp[stashId] ?? sp.values.firstOrNull, tMain = tp[pdbId] ?? tp.values.firstOrNull;
  Map tx(Map<String, dynamic>? p) => (p?['extras'] as Map?) ?? const {};
  final births = [for (final p in sp.values) '${p['birth_date'] ?? ''}', for (final p in tp.values) '${tx(p)['birthday'] ?? ''}'].where((b) => b.isNotEmpty).toList();
  // البوابة: أي سجل في أي مصدر يقول أقل من 18 أو تاريخ غير صالح ⇒ رفض كامل
  if (births.any((b) => !adultOk({'birth': b}))) return DualProfile(stashId: stashId, pdbId: pdbId, minor: true, errors: errs);
  Object? first(Iterable<Object?> l) => l.firstWhere((v) => v != null && '$v'.isNotEmpty, orElse: () => null);
  final info = <String, dynamic>{
    'birth': births.firstOrNull ?? '',
    'country': '${first([sMain?['country'], ...sp.values.map((p) => p['country']), tx(tMain)['nationality'], tx(tMain)['birthplace_code']]) ?? ''}',
    'height': _int(first([sMain?['height'], ...sp.values.map((p) => p['height']), ...tp.values.map((p) => tx(p)['height'])])),
    'cs': _int(first([sMain?['career_start_year'], ...sp.values.map((p) => p['career_start_year']), ...tp.values.map((p) => tx(p)['career_start_year'])])),
    'aliases': <String>{
      for (final p in sp.values) ...[for (final a in (p['aliases'] as List? ?? const [])) '$a', '${p['name'] ?? ''}'],
      for (final p in tp.values) ...[for (final a in (p['aliases'] as List? ?? const [])) '$a', '${p['name'] ?? ''}'],
    }.where((a) => a.trim().isNotEmpty).join(', '),
  }..removeWhere((k, v) => v == null);
  if (sp.isNotEmpty) srcs.add('StashDB');
  if (tp.isNotEmpty) srcs.add('ThePornDB');
  // كل الأعمال من كل السجلات (كل الصفحات) ⇒ دمج بلا تكرار (بالمعرّف ثم العنوان/الاستوديو/التاريخ)
  var works = <Map<String, dynamic>>[];
  for (final id in sp.keys) { try { works = mergeWorks(works, await StashDB.scenes(id, maxPages: maxPages)).list; } catch (e) { errs.add('أعمال StashDB: $e'); } }
  for (final id in tp.keys) { try { works = mergeWorks(works, await TPDB.scenes(id, maxPages: maxPages)).list; } catch (e) { errs.add('أعمال ThePornDB: $e'); } }
  final images = <String>{for (final p in [?sMain, ...sp.values]) ...stashImages(p), for (final p in [?tMain, ...tp.values]) ...tpdbImages(p)}.toList();
  return DualProfile(stashId: stashId, pdbId: pdbId, info: info, images: images, works: works, errors: errs, sources: srcs, stashIds: sp.keys.toList(), pdbIds: tp.keys.toList());
}

String? _pick(Object? v, Map<String, String> m) {
  final s = '${v ?? ''}'.toLowerCase().trim(); if (s.isEmpty) return null;
  for (final e in m.entries) { if (s.contains(e.key)) return e.value; }
  return null;
}
bool _yes(Object? v) { final s = '${v ?? ''}'.toLowerCase().trim(); return s.isNotEmpty && !const ['none', 'no', 'n/a', 'na', 'unknown', '-', 'false'].contains(s); }

/// بيانات ThePornDB الوصفية بصيغة حقول StashDB (لتحليل الذوق) — ما لا يُعرف يبقى غائبًا (لا تخمين).
Map<String, dynamic> tpdbAsStash(Map<String, dynamic> p) {
  final x = (p['extras'] as Map?) ?? const {};
  final cup = '${x['cupsize'] ?? ''}'.toUpperCase().trim();
  final band = RegExp(r'^\d{2}').firstMatch(cup)?.group(0);
  final letters = cup.replaceAll(RegExp(r'[^A-K]'), '');
  return {
    'id': p['id'], 'name': p['name'], 'gender': x['gender'] == null ? null : ('${x['gender']}'.toLowerCase() == 'female' ? 'FEMALE' : 'OTHER'),
    'birth_date': x['birthday'], 'country': '${x['birthplace_code'] ?? ''}'.length == 2 ? x['birthplace_code'] : null,
    'ethnicity': _pick(x['ethnicity'], const {'caucas': 'CAUCASIAN', 'white': 'CAUCASIAN', 'black': 'BLACK', 'ebony': 'BLACK', 'asian': 'ASIAN', 'indian': 'INDIAN', 'latin': 'LATIN', 'hispanic': 'LATIN', 'middle': 'MIDDLE_EASTERN', 'arab': 'MIDDLE_EASTERN', 'mix': 'MIXED'}),
    'hair_color': _pick(x['hair_colour'], const {'blond': 'BLONDE', 'brunet': 'BRUNETTE', 'brown': 'BRUNETTE', 'black': 'BLACK', 'red': 'RED', 'auburn': 'AUBURN', 'grey': 'GREY', 'gray': 'GREY'}),
    'eye_color': _pick(x['eye_colour'], const {'blue': 'BLUE', 'brown': 'BROWN', 'green': 'GREEN', 'hazel': 'HAZEL', 'grey': 'GREY', 'gray': 'GREY'}),
    'height': _int(x['height']), 'waist_size': _int(x['waist']), 'hip_size': _int(x['hips']),
    if (letters.isNotEmpty) 'cup_size': letters, if (band != null) 'band_size': int.parse(band),
    if (x['fake_boobs'] is bool) 'breast_type': x['fake_boobs'] == true ? 'FAKE' : 'NATURAL',
    if (x.containsKey('tattoos')) 'tattoos': _yes(x['tattoos']) ? [{'location': '${x['tattoos']}'}] : [],
    if (x.containsKey('piercings')) 'piercings': _yes(x['piercings']) ? [{'location': '${x['piercings']}'}] : [],
    'career_start_year': _int(x['career_start_year']), 'career_end_year': _int(x['career_end_year']),
  }..removeWhere((k, v) => v == null || (v is String && v.isEmpty));
}

/// يملأ الحقول الناقصة في بيانات StashDB من ThePornDB (لا يستبدل الموجود).
Map<String, dynamic> fillFrom(Map<String, dynamic> a, Map<String, dynamic> b) {
  final o = Map<String, dynamic>.from(a);
  b.forEach((k, v) { final e = o[k]; if (e == null || e == '' || (e is List && e.isEmpty && !(v is List && v.isEmpty))) o[k] = v; });
  return o;
}
