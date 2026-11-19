import 'dart:convert';


import 'package:http/http.dart' as http;

import '../domain/age_gate.dart';
import '../domain/sanitize.dart';
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
/// عميل HTTP قابل للاستبدال في الاختبارات.
http.Client sourceClient = http.Client();

// ===================== StashDB (GraphQL الرسمي) =====================
class StashDB {
  static const url = 'https://stashdb.org/graphql';
  static Future<Map<String, dynamic>> q(String query, [Map<String, dynamic>? vars, String? keyOverride]) async {
    final key = keyOverride ?? await ApiKeys.get(ApiKeys.stash);
    if (key.isEmpty) throw SourceError('أضف مفتاح StashDB من «المزيد»');
    final r = await sourceClient.post(Uri.parse(url), headers: {'Content-Type': 'application/json', 'ApiKey': key}, body: jsonEncode({'query': query, 'variables': vars ?? {}})).timeout(_timeout);
    if (r.statusCode == 401 || r.statusCode == 403) throw SourceError('مفتاح StashDB غير صالح', r.statusCode);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200 && (j is! Map || j['data'] == null)) throw SourceError('StashDB: خطأ ${r.statusCode}', r.statusCode);
    if (j is Map && j['errors'] is List && j['data'] == null) throw SourceError('StashDB: ${(j['errors'] as List).first['message']}');
    return Map<String, dynamic>.from((j as Map)['data'] ?? {});
  }

  static Future<bool> test(String key) async { await q('query{me{name}}', null, key); return true; }

  static Future<List<Candidate>> search(String term) async {
    final d = await q(r'query($t:String!){searchPerformer(term:$t,limit:12){id name aliases birth_date country height career_start_year gender images{url width height}}}', {'t': term});
    return [for (final p in (d['searchPerformer'] as List? ?? const []))
      if (p is Map && (p['gender'] == null || p['gender'] == 'FEMALE'))
        Candidate(source: 'stash', id: '${p['id']}', name: '${p['name'] ?? ''}', aliases: ((p['aliases'] as List?) ?? const []).join(', '), birth: '${p['birth_date'] ?? ''}',
          country: '${p['country'] ?? ''}', image: _bestImg(p['images']), height: (p['height'] as num?)?.toInt(), careerStart: (p['career_start_year'] as num?)?.toInt())];
  }

  static Future<List<Map<String, dynamic>>> scenes(String performerId, {int maxPages = 5}) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= maxPages; page++) {
      final d = await q(r'query($id:ID!,$p:Int!){queryScenes(input:{performers:{value:[$id],modifier:INCLUDES},page:$p,per_page:100,sort:DATE,direction:DESC}){count scenes{id title release_date duration details studio{name} images{url width height} tags{name}}}}', {'id': performerId, 'p': page});
      final qs = d['queryScenes'] as Map? ?? {};
      final sc = qs['scenes'] as List? ?? const [];
      for (final s in sc) {
        if (s is! Map) continue;
        final yd = ydOf(s['release_date']);
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

// ===================== ThePornDB (REST الرسمي) =====================
class TPDB {
  static const base = 'https://api.theporndb.net';
  static Future<Map<String, dynamic>> get(String path, [String? keyOverride]) async {
    final key = keyOverride ?? await ApiKeys.get(ApiKeys.tpdb);
    if (key.isEmpty) throw SourceError('أضف مفتاح ThePornDB من «المزيد»');
    final r = await sourceClient.get(Uri.parse('$base$path'), headers: {'Authorization': 'Bearer $key', 'Accept': 'application/json'}).timeout(_timeout);
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
  final idx = <String, int>{for (var i = 0; i < out.length; i++) wKeyOf(out[i]): i};
  var added = 0, filled = 0; final now = DateTime.now().millisecondsSinceEpoch;
  for (final w in safeWorks(incoming)) {
    final k = wKeyOf(w); final i = idx[k];
    if (i == null) { out.add({...w, 'a': now}); idx[k] = out.length - 1; added++; continue; }
    var ch = false;
    w.forEach((f, v) { final e = out[i][f]; if ((e == null || e == '' || (e is List && e.isEmpty)) && v != null && v != '' && !(v is List && v.isEmpty)) { out[i][f] = v; ch = true; } });
    if (ch) filled++;
  }
  return (list: out, added: added, filled: filled);
}
