import 'dart:convert';


import 'package:http/http.dart' as http;

import '../domain/age_gate.dart';
import '../domain/sanitize.dart';
import '../domain/works.dart' show sceneIdsOf, normTitle, idConflict, sameWork;
import 'keys.dart';

/// خطأ مصدر بنص عربي واضح.
class SourceError implements Exception {
  final String msg; final int? status;
  SourceError(this.msg, [this.status]);
  @override String toString() => msg;
}

/// مرشح من مصدر رسمي (قبل الإضافة للمكتبة).
class Candidate {
  final String source; // 'stash' | 'tpdb'
  final String id, name, aliases, birth, country, image;
  final int? height, careerStart;
  const Candidate({required this.source, required this.id, required this.name, this.aliases = '', this.birth = '', this.country = '', this.image = '', this.height, this.careerStart});
  /// بوابة +18 للمرشح الخارجي: بلا تاريخ أو تاريخ يؤكد 18+.
  bool get adult => adultOk({'birth': birth});
}

const _timeout = Duration(seconds: 20);
http.Client _pool = http.Client();
/// عميل HTTP قابل للاستبدال في الاختبارات.
http.Client sourceClient = _pool;

/// إرسال طلب لمصدر رسمي مع إعادة المحاولة:
/// - انقطاع الاتصال (Connection reset / مهلة / فشل اتصال): يحدث غالبًا حين يُعاد استخدام اتصال قديم أغلقه الخادم أو iOS
///   بعد بقاء التطبيق في الخلفية ⇒ اتصال جديد ومحاولة أخرى (3 محاولات).
/// - 429 (طلبات كثيرة) و5xx: انتظار متزايد ثم محاولة أخرى.
Future<http.Response> sendWithRetry(String source, Future<http.Response> Function(http.Client c) send) async {
  Object? last;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 700 * attempt * attempt));
    try {
      final r = await send(sourceClient).timeout(_timeout);
      if ((r.statusCode == 429 || r.statusCode >= 500) && attempt < 2) { last = r; continue; }
      return r;
    } on SourceError { rethrow; }
    catch (e) {
      last = e;
      if (identical(sourceClient, _pool)) { try { _pool.close(); } catch (_) {} _pool = http.Client(); sourceClient = _pool; }   // اتصال جديد بدل القديم المقطوع
    }
  }
  if (last is http.Response) return last;
  throw SourceError('تعذّر الاتصال بـ $source (انقطع الاتصال أو الشبكة ضعيفة) — تحقّق من الإنترنت وحاول مجددًا');
}

// ===================== StashDB (GraphQL الرسمي) =====================
class StashDB {
  static const url = 'https://stashdb.org/graphql';
  static Future<Map<String, dynamic>> q(String query, [Map<String, dynamic>? vars, String? keyOverride]) async {
    final key = keyOverride ?? await ApiKeys.get(ApiKeys.stash);
    if (key.isEmpty) throw SourceError('أضف مفتاح StashDB من «المزيد»');
    final r = await sendWithRetry('StashDB', (c) => c.post(Uri.parse(url), headers: {'Content-Type': 'application/json', 'ApiKey': key}, body: jsonEncode({'query': query, 'variables': vars ?? {}})));
    if (r.statusCode == 401 || r.statusCode == 403) throw SourceError('مفتاح StashDB غير صالح', r.statusCode);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200 && (j is! Map || j['data'] == null)) throw SourceError('StashDB: خطأ ${r.statusCode}', (r.statusCode == 400 || r.statusCode == 422) ? -1 : r.statusCode);
    if (j is Map && j['errors'] is List && j['data'] == null) throw SourceError('StashDB: ${(j['errors'] as List).first['message']}', -1);   // -1 = خطأ استعلام (يُجرَّب البديل)
    return Map<String, dynamic>.from((j as Map)['data'] ?? {});
  }

  static Future<bool> test(String key) async { await q('query{me{name}}', null, key); return true; }

  static Future<List<Candidate>> search(String term) async {
    Map<String, dynamic> d;
    try { d = await q(r'query($t:String!){searchPerformer(term:$t,limit:12){id name aliases birth_date country height career_start_year gender images{url width height}}}', {'t': term}); }
    on SourceError catch (e) { if (e.status != -1) rethrow; d = await q(r'query($t:String!){searchPerformer(term:$t,limit:12){id name aliases birth_date country gender images{url}}}', {'t': term}); }
    return [for (final p in (d['searchPerformer'] as List? ?? const []))
      if (p is Map && (p['gender'] == null || p['gender'] == 'FEMALE'))
        Candidate(source: 'stash', id: '${p['id']}', name: '${p['name'] ?? ''}', aliases: ((p['aliases'] as List?) ?? const []).join(', '), birth: '${p['birth_date'] ?? ''}',
          country: '${p['country'] ?? ''}', image: _bestImg(p['images']), height: (p['height'] as num?)?.toInt(), careerStart: (p['career_start_year'] as num?)?.toInt())];
  }

  static Future<List<Map<String, dynamic>>> scenes(String performerId, {int maxPages = 5}) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= maxPages; page++) {
      Map<String, dynamic>? d;
      for (final f in _sceneFieldSets) {
        try { d = await q('query(\$id:ID!,\$p:Int!){queryScenes(input:{performers:{value:[\$id],modifier:INCLUDES},page:\$p,per_page:100${f.$2}}){count scenes{${f.$1}}}}', {'id': performerId, 'p': page}); break; }
        on SourceError catch (e) { if (e.status != -1 || f == _sceneFieldSets.last) rethrow; }
      }
      d ??= {};
      final qs = d['queryScenes'] as Map? ?? {};
      final sc = qs['scenes'] as List? ?? const [];
      for (final s in sc) {
        if (s is! Map) continue;
        final yd = ydOf(s['release_date'] ?? s['date']);
        out.add({'t': '${s['title'] ?? ''}'.trim(), 's': '${(s['studio'] as Map?)?['name'] ?? ''}', ...yd,
          if ((s['duration'] as num?) != null) 'du': ((s['duration'] as num) > 180 ? (s['duration'] as num) / 60 : s['duration']).round(),
          if ('${s['details'] ?? ''}'.isNotEmpty) 'ds': _cut('${s['details']}', 280),
          if (_bestImg(s['images'], wide: true).isNotEmpty) 'p': _bestImg(s['images'], wide: true),
          'u': 'https://stashdb.org/scenes/${s['id']}', 'is': '${s['id']}',
          'tg': [for (final t in (s['tags'] as List? ?? const []).take(8)) if (t is Map) '${t['name']}']});
      }
      if (sc.length < 100) break;
    }
    return out.where((w) => (w['t'] as String).isNotEmpty).toList();
  }
}

/// جمع مرشحات الاقتراحات من StashDB الرسمي:
///  - «عملت مع»: performed_with لكل بذرة من مكتبتك (الأعلى وزنًا) مرتبة بعدد المشاهد المشتركة.
///  - «وجوه جديدة»: الأحدث ظهورًا (DEBUT).
///  - «من بلدانك»: الأكثر شهرة في أكثر بلدين في مكتبتك.
/// بوابة +18 تُطبَّق عند الترتيب والعرض (rankRecs) قبل أي صورة؛ هنا تُستبعد القاصر مبكرًا أيضًا.
Future<List<Map<String, dynamic>>> stashRecPool({required List<(String id, double w)> seeds, required List<String> countries, void Function(String)? progress}) async {
  const fields = 'id name birth_date country gender career_start_year scene_count images{url width height}';
  final byId = <String, Map<String, dynamic>>{};
  void absorb(Object? list, {String? seed, String? lane}) {
    for (final p in (list as List? ?? const [])) {
      if (p is! Map || (p['gender'] != null && p['gender'] != 'FEMALE')) continue;
      if (!adultOk({'birth': p['birth_date']})) continue;
      final e = byId.putIfAbsent('${p['id']}', () => {'id': '${p['id']}', 'name': '${p['name'] ?? ''}', 'birth': '${p['birth_date'] ?? ''}', 'country': '${p['country'] ?? ''}',
        'image': _bestImg(p['images']), 'cs': p['career_start_year'], 'sc': p['scene_count'], 'w': <String>[], 'l': <String>[]});
      if (seed != null && !(e['w'] as List).contains(seed)) (e['w'] as List).add(seed);
      if (lane != null && !(e['l'] as List).contains(lane)) (e['l'] as List).add(lane);
    }
  }
  var i = 0;
  for (final s in seeds) {
    progress?.call('تحليل مكتبتك… ${++i}/${seeds.length}');
    try {
      final d = await StashDB.q('query(\$id:ID!){queryPerformers(input:{performed_with:\$id,gender:FEMALE,sort:SHARED_SCENE_COUNT,direction:DESC,per_page:20}){performers{$fields}}}', {'id': s.$1});
      absorb((d['queryPerformers'] as Map?)?['performers'], seed: s.$1);
    } on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  progress?.call('وجوه جديدة…');
  try { final d = await StashDB.q('query{queryPerformers(input:{gender:FEMALE,sort:DEBUT,direction:DESC,per_page:30}){performers{$fields}}}'); absorb((d['queryPerformers'] as Map?)?['performers'], lane: 'debut'); } on SourceError catch (_) {}
  for (final c in countries.take(2)) {
    progress?.call('من $c…');
    try { final d = await StashDB.q('query(\$c:String!){queryPerformers(input:{gender:FEMALE,country:{value:\$c,modifier:EQUALS},sort:POPULARITY,direction:DESC,per_page:25}){performers{$fields}}}', {'c': c}); absorb((d['queryPerformers'] as Map?)?['performers'], lane: 'country'); } on SourceError catch (_) {}
  }
  return byId.values.toList();
}

/// مجموعات حقول المشاهد من الأغنى للأبسط، مع الترتيب أو بدونه — إن اختلف إصدار خادم StashDB لا يفشل الجلب كله.
const _sceneFieldSets = <(String, String)>[
  ('id title release_date duration details studio{name} images{url width height} tags{name}', ',sort:DATE,direction:DESC'),
  ('id title date duration details studio{name} images{url width height}', ',sort:DATE,direction:DESC'),
  ('id title date studio{name}', ''),
];

/// الملف المهني الكامل لممثلة من StashDB (بيانات وصفية موثّقة فقط — لا تحليل صور).
/// مجموعتا حقول: الكاملة ثم البسيطة إن رفض الخادم حقلًا.
const _perfFull = 'id name disambiguation aliases gender birth_date country ethnicity hair_color eye_color height cup_size band_size waist_size hip_size breast_type career_start_year career_end_year tattoos{location} piercings{location} scene_count images{url width height}';
const _perfBasic = 'id name aliases gender birth_date country height career_start_year scene_count images{url width height}';

Future<Map<String, dynamic>?> stashPerformer(String id) async {
  for (final f in [_perfFull, _perfBasic]) {
    try { final d = await StashDB.q('query(\$id:ID!){findPerformer(id:\$id){$f}}', {'id': id}); final p = d['findPerformer']; return p is Map ? Map<String, dynamic>.from(p) : null; }
    on SourceError catch (e) { if (e.status != -1 || f == _perfBasic) rethrow; }
  }
  return null;
}

/// صور ممثلة من رد StashDB مرتبة من الأعلى دقة (https فقط، بلا تكرار).
List<String> stashImages(Map<String, dynamic>? p) {
  final l = [for (final m in (p?['images'] as List? ?? const [])) if (m is Map && safeHttps(m['url'])) m];
  l.sort((a, b) => (((b['width'] ?? 0) as num) * ((b['height'] ?? 0) as num)).compareTo(((a['width'] ?? 0) as num) * ((a['height'] ?? 0) as num)));
  return <String>{for (final m in l) "${m["url"]}"}.toList();
}

// ===================== ThePornDB (REST الرسمي) =====================
class TPDB {
  static const base = 'https://api.theporndb.net';
  static Future<Map<String, dynamic>> get(String path, [String? keyOverride]) async {
    final key = keyOverride ?? await ApiKeys.get(ApiKeys.tpdb);
    if (key.isEmpty) throw SourceError('أضف مفتاح ThePornDB من «المزيد»');
    final r = await sendWithRetry('ThePornDB', (c) => c.get(Uri.parse('$base$path'), headers: {'Authorization': 'Bearer $key', 'Accept': 'application/json'}));
    if (r.statusCode == 401 || r.statusCode == 403) throw SourceError('مفتاح ThePornDB غير صالح', r.statusCode);
    if (r.statusCode == 429) throw SourceError('ThePornDB: طلبات كثيرة، حاول بعد قليل', 429);
    if (r.statusCode != 200) throw SourceError('ThePornDB: خطأ ${r.statusCode}', r.statusCode);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
  }

  static Future<bool> test(String key) async { await get('/performers?q=a&per_page=1', key); return true; }

  static Future<List<Candidate>> search(String term) async {
    final d = await get('/performers?q=${Uri.encodeQueryComponent(term)}&per_page=12');
    return [for (final p in (d['data'] as List? ?? const []))
      if (p is Map && ((p['extras'] as Map?)?['gender'] == null || '${(p['extras'] as Map)['gender']}'.toLowerCase() == 'female'))
        Candidate(source: 'tpdb', id: '${p['id']}', name: '${p['name'] ?? ''}', aliases: ((p['aliases'] as List?) ?? const []).join(', '),
          birth: '${(p['extras'] as Map?)?['birthday'] ?? ''}', country: '${(p['extras'] as Map?)?['nationality'] ?? ''}',
          image: '${p['image'] ?? p['thumbnail'] ?? ''}', height: int.tryParse('${(p['extras'] as Map?)?['height'] ?? ''}'.replaceAll(RegExp(r'\D'), '')),
          careerStart: int.tryParse('${(p['extras'] as Map?)?['career_start_year'] ?? ''}'))];
  }

  static Future<List<Map<String, dynamic>>> scenes(String performerId, {int maxPages = 5}) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= maxPages; page++) {
      final d = await get('/performers/$performerId/scenes?page=$page&per_page=100');
      for (final s in (d['data'] as List? ?? const [])) {
        if (s is! Map) continue;
        final img = '${(s['background'] as Map?)?['large'] ?? (s['posters'] as Map?)?['large'] ?? s['image'] ?? ''}';
        out.add({'t': '${s['title'] ?? ''}'.trim(), 's': '${(s['site'] as Map?)?['name'] ?? ''}', ...ydOf(s['date']),
          if ((s['duration'] as num?) != null && (s['duration'] as num) > 0) 'du': ((s['duration'] as num) > 180 ? (s['duration'] as num) / 60 : s['duration']).round(),
          if ('${s['description'] ?? ''}'.isNotEmpty) 'ds': _cut('${s['description']}', 280),
          if (safeHttps(img)) 'p': img, if (safeHttps(s['url'])) 'u': s['url'], 'ip': '${s['id']}',
          'tg': [for (final t in (s['tags'] as List? ?? const []).take(8)) if (t is Map) '${t['name']}']});
      }
      final last = ((d['meta'] as Map?)?['last_page'] as num?)?.toInt() ?? 1;
      if (page >= last) break;
    }
    return out.where((w) => (w['t'] as String).isNotEmpty).toList();
  }
}

/// أفضل صورة من قائمة صور (الأكبر دقة؛ العريضة للمشاهد) — https فقط.
String bestImageUrl(Object? imgs, {bool wide = false}) => _bestImg(imgs, wide: wide);

String _cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
String _bestImg(Object? imgs, {bool wide = false}) {
  if (imgs is! List || imgs.isEmpty) return '';
  final l = imgs.whereType<Map>().where((m) => safeHttps(m['url'])).toList();
  if (l.isEmpty) return '';
  l.sort((a, b) => (((b['width'] ?? 0) as num) * ((b['height'] ?? 0) as num)).compareTo(((a['width'] ?? 0) as num) * ((a['height'] ?? 0) as num)));
  if (wide) { final w = l.where((m) => ((m['width'] ?? 0) as num) >= ((m['height'] ?? 1) as num)); if (w.isNotEmpty) return '${w.first['url']}'; }
  return '${l.first['url']}';
}

/// دمج أعمال جديدة مع القائمة (قاعدة التطبيق السابق): نفس المفتاح ⇒ تُملأ الحقول الفارغة فقط ولا يُحذف شيء؛ الجديد يأخذ a=الآن.
({List<Map<String, dynamic>> list, int added, int filled}) mergeWorks(List<Map<String, dynamic>> cur, List<Map<String, dynamic>> incoming) {
  final out = [for (final w in cur) Map<String, dynamic>.from(w)];
  // المطابقة بأي معرّف مشترك (StashDB/ThePornDB) أولًا، ثم sameWork (العنوان + الاستوديو/التاريخ) بلا تعارض معرّف من نفس المصدر.
  // الحقول الفارغة فقط تُملأ (ومنها معرّف المصدر الآخر) — لا يُحذف شيء ولا تُستبدل بيانات المستخدم.
  final byId = <String, int>{}, byT = <String, List<int>>{};
  void index(int i) { for (final x in sceneIdsOf(out[i])) { byId[x] = i; } final l = byT[normTitle(out[i]['t'])] ??= []; if (!l.contains(i)) l.add(i); }
  for (var i = 0; i < out.length; i++) { index(i); }
  var added = 0, filled = 0; final now = DateTime.now().millisecondsSinceEpoch;
  for (final w in safeWorks(incoming)) {
    int? i;
    for (final x in sceneIdsOf(w)) { i ??= byId[x]; }
    if (i != null && idConflict(out[i], w)) i = null;
    i ??= (byT[normTitle(w['t'])] ?? const <int>[]).where((j) => sameWork(out[j], w)).firstOrNull;
    if (i == null) { out.add({...w, 'a': w['a'] ?? now}); index(out.length - 1); added++; continue; }
    final t = i; var ch = false;   // ثابت غير فارغ للإغلاق
    w.forEach((f, v) { final e = out[t][f]; if ((e == null || e == '' || (e is List && e.isEmpty)) && v != null && v != '' && !(v is List && v.isEmpty)) { out[t][f] = v; ch = true; } });
    if (ch) { filled++; index(t); }
  }
  return (list: out, added: added, filled: filled);
}

/// إزالة الأعمال المكررة داخل قائمة ممثلة واحدة (نفس العمل من مصدرين أو مدخل مرتين): تُدمج الحقول ولا يضيع شيء من بياناتك.
({List<Map<String, dynamic>> list, int removed}) dedupeWorks(List<Map<String, dynamic>> ws) {
  final m = mergeWorks(const [], ws);
  return (list: m.list, removed: ws.length - m.list.length);
}
