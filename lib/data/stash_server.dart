import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/performer.dart';
import '../domain/sanitize.dart';
import '../domain/works.dart';
import 'keys.dart';
import 'sources.dart' show sourceClient, SourceError;

/// خادم Stash الخاص بك (برنامج Stash المجاني على حاسوبك — نفس عائلة StashDB): مقاطعك الكاملة عبر واجهته الرسمية (GraphQL).
/// العنوان والمفتاح في المخزن الآمن (لا يدخلان النسخة الاحتياطية ولا المستودع). الاتصال على شبكتك المنزلية.
class StashServer {
  static const urlKey = 'stashapp_url', apiKey = 'stashapp_key';
  static const _stashdb = 'https://stashdb.org/graphql';

  /// تطبيع العنوان: يقبل «192.168.1.10:9999» أو مع http(s)، بلا شرطة أخيرة.
  static String normalize(String u) {
    var s = u.trim(); if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.endsWith('/')) { s = s.substring(0, s.length - 1); }
    return s;
  }

  static Future<(String, String)> cfg() async => (normalize(await ApiKeys.get(urlKey)), (await ApiKeys.get(apiKey)).trim());
  static Future<bool> configured() async => (await cfg()).$1.isNotEmpty;

  static Future<Map<String, dynamic>> q(String query, [Map<String, dynamic>? vars, (String, String)? override]) async {
    final c = override ?? await cfg();
    if (c.$1.isEmpty) throw SourceError('أضف عنوان خادم Stash من «الشبكة والمقاطع»');
    final http.Response r;
    try {
      r = await sourceClient.post(Uri.parse('${c.$1}/graphql'), headers: {'Content-Type': 'application/json', if (c.$2.isNotEmpty) 'ApiKey': c.$2},
        body: jsonEncode({'query': query, 'variables': vars ?? {}})).timeout(const Duration(seconds: 12));
    } catch (e) { throw SourceError('لا يصل خادم Stash على ${c.$1} — تأكد أنه يعمل وأن الجوال على نفس شبكة المنزل'); }
    if (r.statusCode == 401 || r.statusCode == 403) throw SourceError('خادم Stash رفض المفتاح — انسخ «API Key» من إعداداته (Security)', r.statusCode);
    if (r.statusCode != 200) throw SourceError('خادم Stash: خطأ ${r.statusCode}', r.statusCode);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is Map && j['errors'] is List && j['data'] == null) throw SourceError('خادم Stash: ${(j['errors'] as List).first['message']}', -1);
    return Map<String, dynamic>.from((j as Map)['data'] ?? {});
  }

  /// اختبار: يعيد إصدار Stash.
  static Future<String> test(String url, String key) async {
    final d = await q('query{version{version}}', null, (normalize(url), key.trim()));
    return '${(d['version'] as Map?)?['version'] ?? '?'}';
  }

  /// رابط تشغيل يحمل المفتاح (Stash يقبل ?apikey= في روابط البث).
  static String withKey(String u, String key) {
    if (key.isEmpty || u.isEmpty) return u;
    final x = Uri.tryParse(u); if (x == null) return u;
    return x.replace(queryParameters: {...x.queryParameters, 'apikey': key}).toString();
  }

  /// معرّف الممثلة في خادمك: بمعرّف StashDB المرتبط أولًا (الأدق)، وإلا بالاسم المطابق حرفيًا.
  static Future<String?> localPerformer(Performer p) async {
    if (p.stashId.isNotEmpty) {
      final d = await q(r'query($e:String!,$id:String!){findPerformers(performer_filter:{stash_id_endpoint:{endpoint:$e,stash_id:$id,modifier:EQUALS}},filter:{per_page:5}){performers{id name}}}', {'e': _stashdb, 'id': p.stashId});
      final l = ((d['findPerformers'] as Map?)?['performers'] as List?) ?? const [];
      if (l.isNotEmpty) return '${(l.first as Map)['id']}';
    }
    final d = await q(r'query($q:String!){findPerformers(filter:{q:$q,per_page:5}){performers{id name alias_list stash_ids{endpoint stash_id}}}}', {'q': p.name});
    for (final x in ((d['findPerformers'] as Map?)?['performers'] as List?) ?? const []) {
      if (x is! Map) continue;
      final names = {norm(x['name']), for (final a in (x['alias_list'] as List? ?? const [])) norm(a)};
      if (names.contains(norm(p.name))) return '${x['id']}';
    }
    return null;
  }

  /// مقاطع ممثلاتك في خادمك (عشوائية) ⇒ «أعمال» مؤقتة للخلاصة: tr = رابط البث الكامل، p = لقطة الشاشة.
  /// [byLocal]: معرّف الخادم ⇒ ممثلة المكتبة.
  static Future<List<WorkGroup>> scenes(Map<String, Performer> byLocal, {int page = 1}) async {
    if (byLocal.isEmpty) return const [];
    final c = await cfg();
    final d = await q(r'query($ids:[ID!],$p:Int!){findScenes(scene_filter:{performers:{value:$ids,modifier:INCLUDES}},filter:{per_page:100,page:$p,sort:"random"}){count scenes{id title date files{duration width height} paths{stream preview screenshot} performers{id name} studio{name}}}}',
      {'ids': byLocal.keys.toList(), 'p': page});
    final out = <WorkGroup>[];
    for (final s in ((d['findScenes'] as Map?)?['scenes'] as List?) ?? const []) {
      if (s is! Map) continue;
      final paths = (s['paths'] as Map?) ?? const {};
      final stream = '${paths['stream'] ?? ''}'; if (stream.isEmpty) continue;
      final who = [for (final pp in (s['performers'] as List? ?? const [])) if (pp is Map && byLocal['${pp['id']}'] != null) byLocal['${pp['id']}']!];
      if (who.isEmpty || who.any((p) => p.isMinor)) continue;                     // بوابة +18 على ممثلات المكتبة
      final f = ((s['files'] as List?) ?? const []).whereType<Map>().firstOrNull;
      final g = WorkGroup('stash:${s['id']}')
        ..t = '${s['title'] ?? ''}'.trim().isEmpty ? 'مقطع من خادمك' : '${s['title']}'
        ..s = '${(s['studio'] as Map?)?['name'] ?? ''}'
        ..d = '${s['date'] ?? ''}'
        ..y = '${s['date'] ?? ''}'.length >= 4 ? '${s['date']}'.substring(0, 4) : ''
        ..p = withKey('${paths['screenshot'] ?? ''}', c.$2)
        ..tr = withKey(stream, c.$2)
        ..du = (((f?['duration'] as num?) ?? 0) / 60).round();
      g.who.addAll(who);
      out.add(g);
    }
    return out;
  }
}

/// مقطع قصير من فيديو كامل: نقطة بداية ثابتة لكل فيديو (من معرّفه) بين 10٪ و80٪ من مدته، وطول 45 ثانية.
(int, int) shortSegment(String key, int durationSec, {int len = 45}) {
  if (durationSec <= len + 20) return (0, 0);
  final r = Random(key.hashCode);
  final start = (durationSec * (.1 + r.nextDouble() * .7)).round();
  return (start.clamp(0, durationSec - len), len);
}
