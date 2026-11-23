import 'dart:convert';

import '../domain/reels.dart';
import 'platform/clip_cache.dart';
import 'platform/db_factory.dart' show bgRead, bgWrite;

/// التحميل المسبق للمقاطع (داخل التطبيق على Wi-Fi + ليلًا أثناء الشحن): يُبقي أول N مقطعًا من ترتيبك محفوظًا على الجهاز.
/// لا يعتمد على واجهة ولا قاعدة بيانات — يعمل في مهمة الخلفية أيضًا (من ملف `clips_input.json`).

const clipsTaskId = 'com.favlib.favorites2.clips';

/// إعدادات «الشبكة والمقاطع».
class ReelsCfg {
  final bool prefetch, night, catchUp, sound; final int count, gb;
  const ReelsCfg({this.prefetch = true, this.night = true, this.catchUp = true, this.sound = true, this.count = 100, this.gb = 3});
  Map<String, dynamic> toJson() => {'pf': prefetch, 'night': night, 'cu': catchUp, 'snd': sound, 'n': count, 'gb': gb};
  factory ReelsCfg.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return ReelsCfg(prefetch: m['pf'] != false, night: m['night'] != false, catchUp: m['cu'] != false, sound: m['snd'] != false,
      count: (m['n'] as num?)?.toInt() ?? 100, gb: (m['gb'] as num?)?.toInt() ?? 3);
  }
  ReelsCfg copy({bool? prefetch, bool? night, bool? catchUp, bool? sound, int? count, int? gb}) =>
    ReelsCfg(prefetch: prefetch ?? this.prefetch, night: night ?? this.night, catchUp: catchUp ?? this.catchUp, sound: sound ?? this.sound, count: count ?? this.count, gb: gb ?? this.gb);
}

/// قائمة التحميل: ترتيب الخلاصة نفسه (ما ستراه أولًا)، مقاطع حقيقية فقط، والخوادم العاملة.
List<String> prefetchOrder(List<Reel> feed) => [for (final r in feed) if (!r.photo && r.url.startsWith('https://')) r.url];

/// يحمّل حتى يصبح أول [max] رابطًا محفوظًا (أو ينتهي المسموح). مقطعان معًا. يعيد (المحفوظ الآن، المطلوب).
Future<(int, int)> prefetchClips(List<String> urls, {int max = 100, void Function(int have, int want)? progress, bool Function()? cancelled}) async {
  if (!clipCacheSupported) return (0, 0);
  final want = urls.take(max).toList();
  final keys = (await clipCacheStats()).$1;
  var have = want.where((u) => keys.contains(clipKeyOf(u))).length;
  progress?.call(have, want.length);
  final todo = want.where((u) => !keys.contains(clipKeyOf(u))).toList();
  for (var i = 0; i < todo.length; i += 2) {
    if (cancelled?.call() == true) break;
    final r = await Future.wait([for (final u in todo.skip(i).take(2)) downloadClip(u)]);
    have += r.whereType<String>().length;
    progress?.call(have, want.length);
  }
  return (have, want.length);
}

/// مدخلات مهمة الليل (يكتبها التطبيق).
Future<void> writeClipsInput(List<String> urls, ReelsCfg cfg) => bgWrite('clips_input.json', jsonEncode({'urls': urls, 'max': cfg.count, 'gb': cfg.gb, 'on': cfg.prefetch && cfg.night}));

/// مهمة الليل: تُكمل التحميل المسبق من آخر قائمة كتبها التطبيق.
Future<void> runNightPrefetch() async {
  final raw = await bgRead('clips_input.json'); if (raw == null) return;
  final j = jsonDecode(raw) as Map;
  if (j['on'] != true) return;
  setClipCacheLimit(((j['gb'] as num?)?.toInt() ?? 3) << 30);
  final started = DateTime.now();
  final r = await prefetchClips([for (final u in (j['urls'] as List? ?? const [])) '$u'], max: (j['max'] as num?)?.toInt() ?? 100,
    cancelled: () => DateTime.now().difference(started) > const Duration(minutes: 25));   // iOS يمنح مهمة المعالجة دقائق
  await bgWrite('clips_state.json', jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'have': r.$1, 'want': r.$2}));
}
