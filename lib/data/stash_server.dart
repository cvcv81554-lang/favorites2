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

  /// بيانات إضافية لمقاطع الخادم (بمفتاح العمل «stash:ID»): العلامات، الصور المصغرة للتقديم، مكان التوقف وعدد المشاهدات.
  static final extra = <String, StashExtra>{};

  /// مزامنة مع Stash على حاسوبك: مكان التوقف ومدة المشاهدة (تظهر في Stash نفسه).
  static Future<void> saveActivity(String id, {required double resume, required double played}) async {
    try { await q(r'mutation($id:ID!,$r:Float,$d:Float){sceneSaveActivity(id:$id,resume_time:$r,playDuration:$d)}', {'id': id, 'r': resume, 'd': played}); } catch (_) {}
  }
  /// يُسجَّل «مشاهدة» في Stash (بعد مشاهدة فعلية).
  static Future<void> addPlay(String id) async {
    try { await q(r'mutation($id:ID!){sceneAddPlay(id:$id){count}}', {'id': id}); } catch (_) {}
  }

  /// ملف VTT للصور المصغرة (يُجلب بنفس شبكات النظام).
  static Future<List<VttCue>> thumbs(String vttUrl) async {
    if (vttUrl.isEmpty) return const [];
    try {
      final r = await sourceClient.get(Uri.parse(vttUrl)).timeout(const Duration(seconds: 12));
      return r.statusCode == 200 ? parseVtt(utf8.decode(r.bodyBytes), vttUrl) : const [];
    } catch (_) { return const []; }
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
    final d = await q(r'query($ids:[ID!],$p:Int!){findScenes(scene_filter:{performers:{value:$ids,modifier:INCLUDES}},filter:{per_page:100,page:$p,sort:"random"}){count scenes{id title date play_count resume_time files{duration width height} paths{stream preview screenshot vtt sprite} scene_markers{id title seconds end_seconds primary_tag{name}} performers{id name} studio{name}}}}',
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
      extra[g.key] = StashExtra('${s['id']}', vtt: withKey('${paths['vtt'] ?? ''}', c.$2), resume: ((s['resume_time'] as num?) ?? 0).toDouble(), plays: ((s['play_count'] as num?) ?? 0).toInt(),
        markers: [for (final m in (s['scene_markers'] as List? ?? const [])) if (m is Map && m['seconds'] is num)
          StashMarker((m['seconds'] as num).toDouble(), (m['end_seconds'] as num?)?.toDouble(), '${m['title'] ?? ''}'.trim().isNotEmpty ? '${m['title']}' : '${(m['primary_tag'] as Map?)?['name'] ?? ''}')]);
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


/// علامة داخل فيديو في Stash (أفضل اللقطات التي حددتها أنت أو إضافات التحليل): البداية والنهاية (اختيارية) والوسم.
class StashMarker {
  final double at; final double? end; final String label;
  const StashMarker(this.at, this.end, this.label);
}

class StashExtra {
  final String id, vtt; final double resume; final int plays; final List<StashMarker> markers;
  const StashExtra(this.id, {this.vtt = '', this.resume = 0, this.plays = 0, this.markers = const []});
}

/// مقاطع قصيرة من العلامات بدل البداية العشوائية: (البداية، الطول، الوسم) — الطول من نهاية العلامة أو 30 ثانية، بين 8 و90، بلا تداخل، 3 كحد.
List<(int, int, String)> markerSegments(List<StashMarker> ms, int durationSec, {int max = 3}) {
  final out = <(int, int, String)>[];
  for (final m in [...ms]..sort((a, b) => a.at.compareTo(b.at))) {
    final s = m.at.floor(); if (s < 0 || (durationSec > 0 && s >= durationSec - 5)) continue;
    var len = m.end != null && m.end! > m.at ? (m.end! - m.at).round() : 30;
    len = len.clamp(8, 90);
    if (durationSec > 0 && s + len > durationSec) len = durationSec - s;
    if (out.isNotEmpty && s < out.last.$1 + out.last.$2) continue;   // لا تداخل
    out.add((s, len, m.label));
    if (out.length >= max) break;
  }
  return out;
}

/// صورة مصغرة لنقطة زمنية: جزء [x,y,w,h] من صورة المصغرات [url].
class VttCue {
  final double start, end; final String url; final int x, y, w, h;
  const VttCue(this.start, this.end, this.url, this.x, this.y, this.w, this.h);
}

double _vttTime(String t) {
  final p = t.trim().split(':'); var s = 0.0;
  for (final x in p) { s = s * 60 + (double.tryParse(x.replaceAll(',', '.')) ?? 0); }
  return s;
}

/// يقرأ ملف WebVTT للمصغرات («00:00:05.000 --> 00:00:10.000» ثم «sprite.jpg#xywh=160,0,160,90»)، والرابط النسبي يُحل نسبةً لملف VTT (مع المفتاح).
List<VttCue> parseVtt(String text, String base) {
  final out = <VttCue>[]; final lines = const LineSplitter().convert(text);
  final b = Uri.tryParse(base); final key = b?.queryParameters['apikey'] ?? '';
  for (var i = 0; i < lines.length - 1; i++) {
    final l = lines[i]; if (!l.contains('-->')) continue;
    final t = l.split('-->'); final ref = lines[i + 1].trim();
    final m = RegExp(r'^(.*)#xywh=(\d+),(\d+),(\d+),(\d+)$').firstMatch(ref); if (m == null) continue;
    var u = m.group(1)!; final abs = b == null ? Uri.tryParse(u) : b.resolve(u);
    if (abs != null) u = StashServer.withKey(abs.replace(queryParameters: {...abs.queryParameters}..remove('apikey')).toString(), key);
    out.add(VttCue(_vttTime(t[0]), _vttTime(t[1].trim().split(' ').first), u, int.parse(m.group(2)!), int.parse(m.group(3)!), int.parse(m.group(4)!), int.parse(m.group(5)!)));
  }
  return out;
}

VttCue? cueAt(List<VttCue> cues, double sec) {
  for (final c in cues) { if (sec >= c.start && sec < c.end) return c; }
  return cues.isEmpty ? null : (sec >= cues.last.end ? cues.last : null);
}
