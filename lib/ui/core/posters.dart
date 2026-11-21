import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/keys.dart';
import '../../data/sources.dart';
import '../../domain/sanitize.dart';
import '../../domain/works.dart';
import 'state.dart';

/// جلب صور الأعمال الناقصة **بمعرّف المشهد فقط** (StashDB is / ThePornDB ip) — لا بحث بالعنوان، فلا تظهر صورة عمل آخر.
/// - طابور بلا تكرار، طلبان متوازيان كحد أقصى.
/// - ذاكرة دائمة (kv «posters»): المعرّف ⇒ الرابط، أو «لا صورة» مع وقت (يُعاد بعد 7 أيام).
/// - النتيجة تُكتب في كل نسخ العمل لدى الممثلات (دفعة كل ثانيتين).
class PosterResolver extends Notifier<int> {
  final _queue = Queue<String>(); final _inFlight = <String>{}; final _asked = <String>{};
  Map<String, dynamic>? _cache; final Map<String, String> _pending = {}; Timer? _flushT; int _running = 0;

  @override int build() => 0;

  Future<Map<String, dynamic>> _c() async => _cache ??= Map<String, dynamic>.from(await (await ref.read(repoProvider.future)).kvGet('posters') as Map? ?? {});

  /// [sid]: «is:…» أو «ip:…».
  void want(String sid) {
    if (!(sid.startsWith('is:') || sid.startsWith('ip:')) || !_asked.add(sid)) return;   // مرة واحدة لكل معرّف في الجلسة
    _queue.add(sid); _pump();
  }

  Future<void> _pump() async {
    while (_running < 2 && _queue.isNotEmpty) {
      final sid = _queue.removeFirst(); _inFlight.add(sid); _running++;
      unawaited(_resolve(sid).whenComplete(() { _inFlight.remove(sid); _running--; _pump(); }));
    }
  }

  Future<void> _resolve(String sid) async {
    final c = await _c(); final hit = c[sid];
    if (hit is String && hit.isNotEmpty) { _pending[sid] = hit; _scheduleFlush(); return; }
    if (hit is int && DateTime.now().millisecondsSinceEpoch - hit < 7 * 86400000) return;   // جُرّب مؤخرًا بلا نتيجة
    String url = '';
    try {
      if (sid.startsWith('is:') && await ApiKeys.has(ApiKeys.stash)) {
        final d = await StashDB.q(r'query($id:ID!){findScene(id:$id){images{url width height}}}', {'id': sid.substring(3)});
        url = bestImageUrl((d['findScene'] as Map?)?['images'], wide: true);
      } else if (sid.startsWith('ip:') && await ApiKeys.has(ApiKeys.tpdb)) {
        final d = await TPDB.get('/scenes/${Uri.encodeComponent(sid.substring(3))}');
        final s = (d['data'] is Map ? d['data'] : d) as Map;
        for (final x in [(s['background'] as Map?)?['large'], (s['posters'] as Map?)?['large'], (s['background'] as Map?)?['full'], s['image']]) { if (safeHttps(x)) { url = '$x'; break; } }
      } else { return; }   // لا مفتاح: لا طلب
    } on SourceError catch (e) { if (e.status == 404) { c[sid] = DateTime.now().millisecondsSinceEpoch; _saveCache(); } return; }
    catch (_) { return; }
    c[sid] = url.isEmpty ? DateTime.now().millisecondsSinceEpoch : url; _saveCache();
    if (url.isNotEmpty) { _pending[sid] = url; _scheduleFlush(); }
  }

  Timer? _saveT;
  void _saveCache() { _saveT?.cancel(); _saveT = Timer(const Duration(seconds: 3), () async { if (_cache != null) await (await ref.read(repoProvider.future)).kvSet('posters', _cache); }); }

  void _scheduleFlush() { _flushT?.cancel(); _flushT = Timer(const Duration(seconds: 2), _flush); }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final got = Map<String, String>.from(_pending); _pending.clear();
    final lib = ref.read(libraryProvider.notifier);
    final changed = [
      for (final p in lib.items) if (p.works.any((w) => '${w['p'] ?? ''}'.isEmpty && got.containsKey(sceneIdOf(w))))
        p.copyWith({'works': [for (final w in p.works) ('${w['p'] ?? ''}'.isEmpty && got.containsKey(sceneIdOf(w))) ? {...w, 'p': got[sceneIdOf(w)]} : w]}),
    ];
    if (changed.isNotEmpty) { await lib.upsertMany(changed); state++; }
  }
}

final posterResolverProvider = NotifierProvider<PosterResolver, int>(PosterResolver.new);
