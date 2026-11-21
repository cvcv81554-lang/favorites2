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
  if (_names(a.name, a.aliases).intersection(_names(b.name, b.aliases)).isEmpty) return false;
  final fa = _fullDate(a.birth), fb = _fullDate(b.birth);
  if (fa.isNotEmpty && fb.isNotEmpty) return fa == fb;
  final ya = _year(a.birth), yb = _year(b.birth);
  if (ya.isNotEmpty && yb.isNotEmpty) return ya == yb && norm(a.name) == norm(b.name);
  if (norm(a.name) != norm(b.name)) return false;
  final ca = a.country.trim().toUpperCase(), cb = b.country.trim().toUpperCase();
  return ca.isEmpty || cb.isEmpty || ca == cb || ca.length != cb.length;   // رمز بلد مقابل اسم بلد: لا نعدّه تعارضًا
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
  final String stashId, pdbId; final Map<String, dynamic> info; final List<String> images; final List<Map<String, dynamic>> works; final List<String> errors, sources; final bool minor;
  const DualProfile({this.stashId = '', this.pdbId = '', this.info = const {}, this.images = const [], this.works = const [], this.errors = const [], this.sources = const [], this.minor = false});
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^\d]'), ''));

/// يجلب من المصدرين: المعلومات أولًا ⇒ بوابة +18 ⇒ ثم الأعمال والصور (لا طلب صور/أعمال لقاصر أو تاريخ غير صالح).
Future<DualProfile> fetchBoth({String stashId = '', String pdbId = '', int maxPages = 5}) async {
  final errs = <String>[], srcs = <String>[];
  final hasS = stashId.isNotEmpty && await ApiKeys.has(ApiKeys.stash), hasT = pdbId.isNotEmpty && await ApiKeys.has(ApiKeys.tpdb);
  Map<String, dynamic>? sp, tp;
  await Future.wait([
    if (hasS) stashPerformer(stashId).then((v) => sp = v).catchError((e) { errs.add('StashDB: $e'); return null; }),
    if (hasT) tpdbPerformer(pdbId).then((v) => tp = v).catchError((e) { errs.add('ThePornDB: $e'); return null; }),
  ]);
  final tx = (tp?['extras'] as Map?) ?? const {};
  final births = ['${sp?['birth_date'] ?? ''}', '${tx['birthday'] ?? ''}'].where((b) => b.isNotEmpty).toList();
  // البوابة: أي مصدر يقول أقل من 18 أو تاريخ غير صالح ⇒ رفض كامل
  if (births.any((b) => !adultOk({'birth': b}))) return DualProfile(stashId: stashId, pdbId: pdbId, minor: true, errors: errs);
  // معلومات مدمجة: StashDB أولًا (أدق بنيويًا)، وThePornDB يملأ الناقص
  final info = <String, dynamic>{
    'birth': births.firstOrNull ?? '',
    'country': '${sp?['country'] ?? ''}'.isNotEmpty ? '${sp!['country']}' : '${tx['nationality'] ?? tx['birthplace_code'] ?? ''}',
    if (_int(sp?['height']) != null || _int(tx['height']) != null) 'height': _int(sp?['height']) ?? _int(tx['height']),
    if (_int(sp?['career_start_year']) != null || _int(tx['career_start_year']) != null) 'cs': _int(sp?['career_start_year']) ?? _int(tx['career_start_year']),
    'aliases': <String>{
      for (final a in (sp?['aliases'] as List? ?? const [])) '$a',
      for (final a in (tp?['aliases'] as List? ?? const [])) '$a',
    }.where((a) => a.trim().isNotEmpty).join(', '),
  };
  if (sp != null) srcs.add('StashDB');
  if (tp != null) srcs.add('ThePornDB');
  // الأعمال من الاثنين ⇒ دمج بلا تكرار (بالمعرّف ثم العنوان/الاستوديو/التاريخ)
  var works = <Map<String, dynamic>>[];
  await Future.wait([
    if (sp != null) StashDB.scenes(stashId, maxPages: maxPages).then((l) => works = mergeWorks(works, l).list).catchError((e) { errs.add('أعمال StashDB: $e'); return works; }),
  ]);
  if (tp != null) { try { works = mergeWorks(works, await TPDB.scenes(pdbId, maxPages: maxPages)).list; } catch (e) { errs.add('أعمال ThePornDB: $e'); } }
  final images = <String>{...stashImages(sp), ...tpdbImages(tp)}.toList();
  return DualProfile(stashId: stashId, pdbId: pdbId, info: info, images: images, works: works, errors: errs, sources: srcs);
}
