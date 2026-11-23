import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../../data/clip_prefetch.dart';
import '../../../data/library_repo.dart';
import '../../../data/platform/clip_cache.dart';
import '../../../domain/reels.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../works/works_screen.dart' show worksProvider, workTasteProvider;
import 'reels_screen.dart' show reelSigProvider, probeVideoUrl;

/// مركز «المقاطع»: الإعدادات، حالة الخوادم على شبكتك، التحميل المسبق (Wi-Fi + ليلًا)، ووضع اللحاق.

class ReelsCfgN extends AsyncNotifier<ReelsCfg> {
  @override Future<ReelsCfg> build() async {
    final c = ReelsCfg.fromJson(await (await ref.watch(repoProvider.future)).kvGet('reels_cfg'));
    setClipCacheLimit(c.gb << 30);
    return c;
  }
  Future<void> set(ReelsCfg c) async {
    state = AsyncData(c); setClipCacheLimit(c.gb << 30);
    await (await ref.read(repoProvider.future)).kvSet('reels_cfg', c.toJson());
    await scheduleNight(c);
  }
}
final reelsCfgProvider = AsyncNotifierProvider<ReelsCfgN, ReelsCfg>(ReelsCfgN.new);

// ===== الخوادم =====
Future<Map<String, dynamic>> loadHosts(LibraryRepo repo) async => Map<String, dynamic>.from(await repo.kvGet('reel_hosts') as Map? ?? {});
Future<void> saveHosts(LibraryRepo repo, Map<String, dynamic> h) => repo.kvSet('reel_hosts', h);

/// يفحص الخوادم غير المفحوصة/القديمة (أو كلها مع [force]) — طلب صغير لكل خادم، 4 معًا.
Future<List<String>> probeHosts(Map<String, dynamic> hosts, Iterable<String> urls, {bool force = false, bool onlyBlocked = false, void Function(int done, int total)? progress}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final byHost = <String, String>{};
  for (final u in urls) { final h = hostOf(u); if (h.isNotEmpty) byHost.putIfAbsent(h, () => u); }
  final todo = byHost.entries.where((e) {
    final st = hosts[e.key] as Map?;
    if (onlyBlocked) return st?['ok'] == false;
    return force || hostStale(st, now);
  }).toList();
  final nowOk = <String>[]; var done = 0;
  for (var i = 0; i < todo.length; i += 4) {
    await Future.wait([for (final e in todo.skip(i).take(4)) probeVideoUrl(e.value).then((r) {
      final was = (hosts[e.key] as Map?)?['ok'];
      hosts[e.key] = {...?(hosts[e.key] as Map?), 'ok': r.$1, 't': now, 'why': r.$2};
      if (r.$1 && was == false) nowOk.add(e.key);
      progress?.call(++done, todo.length);
    })]);
  }
  return nowOk;
}

/// الخلاصة كما ستُعرض (مفضلاتك أولًا ثم بقية مكتبتك)، بالخوادم العاملة أو المحفوظ.
List<Reel> buildFeed(Ref ref, Map<String, dynamic> hosts, Set<String> cachedKeys, {bool favsOnly = true, int seed = 0, bool photo = true, int n = 400}) {
  final sig = ref.read(reelSigProvider).value ?? const ReelSignals({}, {});
  bool cached(String u) => cachedKeys.contains(clipKeyOf(u));
  return rankReels(ref.read(worksProvider), ref.read(workTasteProvider), sig, favsOnly: favsOnly, seed: seed, n: n,
    playable: (u) => hostUsable(hosts, u) || cached(u), isCached: cached, photoFallback: photo);
}

/// كل روابط المقاطع في المكتبة.
Iterable<String> allTrailerUrls(List<WorkGroup> ws) => ws.where((g) => g.tr.isNotEmpty).map((g) => g.tr);

// ===== التحميل المسبق =====
class PrefetchState {
  final bool running; final int have, want, cachedCount, bytes; final String msg;
  const PrefetchState({this.running = false, this.have = 0, this.want = 0, this.cachedCount = 0, this.bytes = 0, this.msg = ''});
  PrefetchState copy({bool? running, int? have, int? want, int? cachedCount, int? bytes, String? msg}) =>
    PrefetchState(running: running ?? this.running, have: have ?? this.have, want: want ?? this.want, cachedCount: cachedCount ?? this.cachedCount, bytes: bytes ?? this.bytes, msg: msg ?? this.msg);
}

class PrefetchN extends Notifier<PrefetchState> {
  bool _stop = false; int _lastCatchUp = 0;
  @override PrefetchState build() => const PrefetchState();

  Future<void> refreshStats() async { final s = await clipCacheStats(); state = state.copy(cachedCount: s.$1.length, bytes: s.$2); }

  static Future<bool> onWifi() async {
    if (kIsWeb) return false;
    try { final c = await Connectivity().checkConnectivity(); return c.contains(ConnectivityResult.wifi) || c.contains(ConnectivityResult.ethernet); } catch (_) { return false; }
  }

  void stop() => _stop = true;

  /// يحمّل أول N مقطعًا من ترتيبك. [force]: حتى لو لم يكن Wi-Fi (بطلبك من الزر).
  Future<void> run({bool force = false, List<String> priority = const []}) async {
    if (state.running || !clipCacheSupported) return;
    final cfg = await ref.read(reelsCfgProvider.future);
    if (!force && (!cfg.prefetch || !await onWifi())) { await refreshStats(); return; }
    _stop = false;
    state = state.copy(running: true, msg: 'تجهيز قائمة المقاطع…');
    try {
      await ref.read(reelSigProvider.future); await ref.read(libraryProvider.future);
      final repo = await ref.read(repoProvider.future);
      final hosts = await loadHosts(repo);
      final urls = allTrailerUrls(ref.read(worksProvider)).toList();
      await probeHosts(hosts, urls, progress: (d, t) => state = state.copy(msg: 'فحص الخوادم ($d/$t)…'));
      await saveHosts(repo, hosts);
      final keys = (await clipCacheStats()).$1;
      final day = DateTime.now(); final seed = day.year * 400 + day.month * 32 + day.day;   // ترتيب ثابت طوال اليوم
      final order = <String>{...priority, ...prefetchOrder(buildFeed(ref, hosts, keys, seed: seed, photo: false)), ...prefetchOrder(buildFeed(ref, hosts, keys, favsOnly: false, seed: seed, photo: false))}.toList();
      await writeClipsInput(order, cfg);
      await scheduleNight(cfg);
      final r = await prefetchClips(order, max: cfg.count, cancelled: () => _stop, progress: (h, w) => state = state.copy(have: h, want: w, msg: 'تحميل مسبق: $h / $w'));
      final s = await clipCacheStats();
      state = state.copy(running: false, have: r.$1, want: r.$2, cachedCount: s.$1.length, bytes: s.$2,
        msg: _stop ? 'أُوقف التحميل — جاهز ${r.$1} مقطعًا' : r.$1 >= r.$2 ? 'جاهز: ${r.$1} مقطعًا محفوظًا على جهازك ✓' : 'جاهز ${r.$1} من ${r.$2} (بعضها تعذّر تنزيله)');
    } catch (e) { state = state.copy(running: false, msg: 'تعذّر التحميل المسبق: $e'); }
  }

  /// وضع اللحاق: إن صارت الشبكة تصل لخوادم كانت محجوبة (مثل تشغيلك VPN) ⇒ تُحمَّل مقاطعها فورًا لتعمل لاحقًا بدونها.
  Future<int> catchUp() async {
    if (state.running || !clipCacheSupported) return 0;
    final cfg = await ref.read(reelsCfgProvider.future);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!cfg.catchUp || now - _lastCatchUp < 10 * 60000) return 0;
    _lastCatchUp = now;
    final repo = await ref.read(repoProvider.future);
    final hosts = await loadHosts(repo);
    if (!hosts.values.any((h) => h is Map && h['ok'] == false)) return 0;
    await ref.read(libraryProvider.future);
    final urls = allTrailerUrls(ref.read(worksProvider)).toList();
    final opened = await probeHosts(hosts, urls, onlyBlocked: true);
    if (opened.isEmpty) return 0;
    for (final h in opened) { hosts[h] = {...(hosts[h] as Map), 'was': 'blocked'}; }
    await saveHosts(repo, hosts);
    final pri = [for (final u in urls) if (opened.contains(hostOf(u))) u];
    state = state.copy(msg: 'الشبكة الآن تصل إلى ${opened.length} خادمًا كان محجوبًا — نحمّل مقاطعها لتعمل لاحقًا بدونها');
    await run(force: true, priority: pri);
    return opened.length;
  }
}
final prefetchProvider = NotifierProvider<PrefetchN, PrefetchState>(PrefetchN.new);

/// جدولة التحميل الليلي (iOS: مهمة معالجة أثناء الشحن والاتصال — النظام يقرر التوقيت).
Future<void> scheduleNight(ReelsCfg c) async {
  if (kIsWeb) return;
  try {
    if (!c.prefetch || !c.night) { await Workmanager().cancelByUniqueName(clipsTaskId); return; }
    await Workmanager().registerProcessingTask(clipsTaskId, clipsTaskId, initialDelay: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.unmetered, requiresCharging: true));
  } catch (_) {}
}
