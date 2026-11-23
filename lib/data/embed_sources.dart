import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/performer.dart';
import '../domain/sanitize.dart';
import '../domain/works.dart';
import 'sources.dart' show sourceClient;

/// مصادر التضمين الرسمية (اختيارية): فيديوهات كاملة عبر واجهات المواقع الرسمية للمطورين، وتُشغَّل في مشغّل التضمين
/// الذي يسمح به كل موقع رسميًا — لا تنزيل ولا كشط. كل مقطع موسوم بمصدره.
/// على شبكة تحجب هذه المواقع لا تعمل (تُتخطى تلقائيًا وتظهر «تحتاج VPN»).

class EmbedSource {
  final String id, name, host;
  const EmbedSource(this.id, this.name, this.host);
}
const embedSources = [
  EmbedSource('ph', 'Pornhub', 'www.pornhub.com'),
  EmbedSource('rt', 'RedTube', 'api.redtube.com'),
  EmbedSource('ep', 'Eporner', 'www.eporner.com'),
];

int _secs(Object? v) {
  if (v is num) return v.toInt();
  final p = '${v ?? ''}'.split(':').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  return p.isEmpty ? 0 : p.fold<int>(0, (a, b) => a * 60 + b);
}

/// هل الفيديو لها فعلًا؟ (اسمها الكامل كلمةً كاملةً في العنوان أو قائمة الممثلات أو الوسوم) — المطابقة بالاسم وحده محافظة.
bool embedMatches(Performer p, String title, List<String> names) {
  final want = {norm(p.name), for (final a in p.aliases.split(',')) if (norm(a).split(' ').length >= 2) norm(a)}..remove('');
  if (names.any((n) => want.contains(norm(n)))) return true;
  final t = ' ${norm(title).replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')} ';
  return want.any((w) => w.split(' ').length >= 2 && t.contains(' $w '));
}

WorkGroup _group(String src, String id, String title, String thumb, String embed, int secs, Performer p) {
  final g = WorkGroup('emb:$src:$id')..t = title..p = thumb..tr = embed..du = (secs / 60).round();
  g.who.add(p);
  return g;
}

/// يبحث في مصدر واحد عن فيديوهات ممثلة (أعلى مشاهدة). يعيد [] إن لم يصل الموقع.
Future<List<WorkGroup>> searchEmbeds(EmbedSource s, Performer p, {http.Client? client}) async {
  if (p.isMinor) return const [];   // بوابة +18 قبل أي طلب
  final c = client ?? sourceClient;
  final q = Uri.encodeQueryComponent(p.name);
  try {
    switch (s.id) {
      case 'ph':
        final r = await c.get(Uri.parse('https://www.pornhub.com/webmasters/search?search=$q&ordering=mostviewed&thumbsize=large')).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) return const [];
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        return [for (final v in ((j is Map ? j['videos'] : null) as List? ?? const [])) if (v is Map && '${v['video_id'] ?? ''}'.isNotEmpty &&
            embedMatches(p, '${v['title'] ?? ''}', [for (final x in (v['pornstars'] as List? ?? const [])) x is Map ? '${x['pornstar_name'] ?? ''}' : '$x']))
          _group('ph', '${v['video_id']}', '${v['title'] ?? ''}', '${v['default_thumb'] ?? v['thumb'] ?? ''}', 'https://www.pornhub.com/embed/${v['video_id']}', _secs(v['duration']), p)];
      case 'rt':
        final r = await c.get(Uri.parse('https://api.redtube.com/?data=redtube.Videos.searchVideos&output=json&search=$q&ordering=mostviewed&thumbsize=big')).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) return const [];
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        return [for (final w in ((j is Map ? j['videos'] : null) as List? ?? const [])) if (w is Map) () {
          final v = (w['video'] is Map ? w['video'] : w) as Map;
          final id = '${v['video_id'] ?? ''}';
          final names = [for (final x in (v['pornstars'] as List? ?? const [])) x is Map ? '${x['pornstar_name'] ?? ''}' : '$x'];
          return id.isEmpty || !embedMatches(p, '${v['title'] ?? ''}', names) ? null
            : _group('rt', id, '${v['title'] ?? ''}', '${v['default_thumb'] ?? v['thumb'] ?? ''}', 'https://embed.redtube.com/?id=$id', _secs(v['duration']), p);
        }()].whereType<WorkGroup>().toList();
      case 'ep':
        final r = await c.get(Uri.parse('https://www.eporner.com/api/v2/video/search/?query=$q&per_page=30&page=1&thumbsize=big&order=most-popular&gay=0&lq=0&format=json')).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) return const [];
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        return [for (final v in ((j is Map ? j['videos'] : null) as List? ?? const [])) if (v is Map && '${v['id'] ?? ''}'.isNotEmpty &&
            embedMatches(p, '${v['title'] ?? ''}', '${v['keywords'] ?? ''}'.split(',').map((x) => x.trim()).toList()))
          _group('ep', '${v['id']}', '${v['title'] ?? ''}', '${(v['default_thumb'] as Map?)?['src'] ?? ''}', '${v['embed'] ?? 'https://www.eporner.com/embed/${v['id']}/'}', _secs(v['length_sec']), p)];
    }
  } catch (_) {}
  return const [];
}

/// هل المصدر متاح على شبكتك؟ (طلب خفيف للواجهة)
Future<bool> embedReachable(EmbedSource s) async {
  try { final r = await sourceClient.get(Uri.parse('https://${s.host}/')).timeout(const Duration(seconds: 8)); return r.statusCode < 500; } catch (_) { return false; }
}

String embedSourceName(String key) {
  final id = key.split(':').length > 1 ? key.split(':')[1] : '';
  return embedSources.where((s) => s.id == id).firstOrNull?.name ?? '';
}
