import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../data/keys.dart';
import '../../../data/platform/clip_cache.dart';
import '../../../data/privacy.dart' show blurPhotos;
import '../../../data/sources.dart';
import '../../../domain/performer.dart';
import '../../../domain/reels.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../works/works_screen.dart' show worksProvider, workTasteProvider, showWorkSheet;
import 'reel_center.dart';

/// إشارات «مقاطع» (محفوظة على الجهاز فقط).
class ReelSigN extends AsyncNotifier<ReelSignals> {
  @override Future<ReelSignals> build() async => ReelSignals.fromJson(await (await ref.watch(repoProvider.future)).kvGet('reels_sig'));
  Future<void> _save(ReelSignals s) async { state = AsyncData(s); await (await ref.read(repoProvider.future)).kvSet('reels_sig', s.toJson()); }
  Future<void> view(WorkGroup g, double frac, {bool like = false}) async => _save(recordView(state.value ?? const ReelSignals({}, {}), g, frac: frac, like: like));
  Future<void> dislikeIt({String? performerId, String? studio, String? hideKey}) async => _save(dislike(state.value ?? const ReelSignals({}, {}), performerId: performerId, studio: studio, hideKey: hideKey));
}
final reelSigProvider = AsyncNotifierProvider<ReelSigN, ReelSignals>(ReelSigN.new);

/// جلب الإعلانات الرسمية من ThePornDB لأعمال مفضلاتك (تُدمج في أعمالهن بلا تكرار — يملأ «tr» فقط حيث ينقص).
Future<String> fetchTrailers(WidgetRef ref, {bool favsOnly = false, void Function(String)? progress}) async {
  if (!await ApiKeys.has(ApiKeys.tpdb)) return 'المقاطع تأتي من ThePornDB — أضف مفتاحه من «المزيد».';
  final lib = ref.read(libraryProvider.notifier);
  final ps = lib.items.where((p) => !p.isMinor && p.pdbIds.isNotEmpty && (!favsOnly || p.fav || p.rating >= 4)).toList();
  if (ps.isEmpty) return 'لا ممثلات مرتبطة بـ ThePornDB في ${favsOnly ? 'مفضلاتك' : 'مكتبتك'} — اربطها أولًا (تحديث من المصدرين).';
  var withTr = 0, i = 0; final changed = <Performer>[];
  for (final p in ps) {
    i++; progress?.call('جلب مقاطع ${p.name} ($i/${ps.length})…');
    var works = p.works;
    for (final id in p.pdbIds) {
      try { works = mergeWorks(works, await TPDB.scenes(id, maxPages: 40)).list; }
      on SourceError catch (e) { if (e.status == -2 || e.status == 401 || e.status == 403) return e.msg; }
    }
    final cur = lib.items.where((x) => x.id == p.id).firstOrNull ?? p;
    final merged = mergeWorks(cur.works, works).list;
    withTr += merged.where((w) => '${w['tr'] ?? ''}'.isNotEmpty).length;
    changed.add(cur.copyWith({'works': merged}));
  }
  if (changed.isNotEmpty) await lib.upsertMany(changed);
  await (await ref.read(repoProvider.future)).kvSet('reels_fetched_at', DateTime.now().millisecondsSinceEpoch);
  return withTr == 0 ? 'لم تُعثر على إعلانات رسمية لأعمال ${favsOnly ? 'مفضلاتك' : 'مكتبتك'} في ThePornDB.' : 'جاهز: $withTr مقطعًا';
}

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});
  @override ConsumerState<ReelsScreen> createState() => _ReelsState();
}

class _ReelsState extends ConsumerState<ReelsScreen> {
  final _pc = PageController();
  List<Reel>? _feed; int _cur = 0; bool _favsOnly = true, _muted = true, _busy = false, _preparing = false; String _msg = '';
  Map<String, dynamic> _hosts = {}; int _hidden = 0;
  int _seed = DateTime.now().millisecondsSinceEpoch;
  final _liked = <String>{};

  @override void dispose() { _pc.dispose(); super.dispose(); }

  Set<String> _cached = {};

  void _build() {
    final sig = ref.read(reelSigProvider).value ?? const ReelSignals({}, {});
    bool cached(String u) => _cached.contains(clipKeyOf(u));
    _feed = rankReels(ref.read(worksProvider), ref.read(workTasteProvider), sig, favsOnly: _favsOnly, seed: _seed, n: 200,
      playable: (u) => hostUsable(_hosts, u) || cached(u), isCached: cached, photoFallback: true);
    _hidden = _feed!.where((r) => r.photo).length;
    _cur = 0;
    for (final r in _feed!) { if (sig.clips[r.key]?['l'] == 1) _liked.add(r.key); }
    final ready = _feed!.where((r) => !r.photo && cached(r.url)).length;
    if (_msg.isEmpty) _msg = '${_feed!.length - _hidden} مقطعًا يعمل${ready > 0 ? ' ($ready جاهز على جهازك)' : ''}${_hidden > 0 ? ' · $_hidden «صور» بدل مقاطع خوادمها محجوبة على شبكتك' : ''}';
  }

  Iterable<WorkGroup> _scope() => ref.read(worksProvider).where((g) => g.tr.isNotEmpty && (!_favsOnly || g.who.any((p) => p.fav || p.rating >= 4)));

  /// قبل العرض: إعدادات الصوت، المقاطع المحفوظة، وفحص الخوادم غير المفحوصة أو القديمة — فيُعرض ما يعمل والمحفوظ أولًا.
  Future<void> _prepare({bool force = false}) async {
    final cfg = await ref.read(reelsCfgProvider.future);
    _muted = !cfg.sound;
    final repo = await ref.read(repoProvider.future);
    _hosts = await loadHosts(repo);
    _cached = (await clipCacheStats()).$1;
    final todo = _scope().map((g) => g.tr);
    if (mounted) setState(() { _preparing = true; _msg = 'فحص خوادم المقاطع على شبكتك…'; });
    await probeHosts(_hosts, todo, force: force, progress: (d, t) { if (mounted) setState(() => _msg = 'فحص خوادم المقاطع على شبكتك ($d/$t)…'); });
    await saveHosts(repo, _hosts);
    if (!mounted) return;
    setState(() { _preparing = false; _msg = ''; _build(); });
    _prefetch(0); _prefetch(1);
    _autoUpdate();
  }

  /// تحديث تلقائي: إن مضى 3 أيام على آخر جلب ⇒ جلب الإعلانات الجديدة بهدوء في الخلفية.
  Future<void> _autoUpdate() async {
    final repo = await ref.read(repoProvider.future);
    final last = (await repo.kvGet('reels_fetched_at') as num?)?.toInt() ?? 0;
    if (_busy || DateTime.now().millisecondsSinceEpoch - last < 3 * 86400000 || !await ApiKeys.has(ApiKeys.tpdb)) return;
    final before = ref.read(worksProvider).where((g) => g.tr.isNotEmpty).length;
    if (mounted) setState(() => _msg = 'تحديث المقاطع في الخلفية…');
    final m = await fetchTrailers(ref);
    final added = ref.read(worksProvider).where((g) => g.tr.isNotEmpty).length - before;
    if (!mounted) return;
    setState(() => _msg = added > 0 ? 'وصل $added مقطعًا جديدًا — اضغط ↻ لعرضها' : m.startsWith('جاهز') ? '' : m);
  }

  /// خادم يحتاج تنزيلًا (المشغّل لا يصله مباشرة) ⇒ يُتذكر، ويُنزَّل التالي منه مسبقًا.
  Future<void> _markDl(String url) async {
    final h = hostOf(url); if (h.isEmpty || (_hosts[h] as Map?)?['dl'] == true) return;
    _hosts[h] = {...?(_hosts[h] as Map?), 'ok': true, 'dl': true, 't': DateTime.now().millisecondsSinceEpoch};
    await (await ref.read(repoProvider.future)).kvSet('reel_hosts', _hosts);
  }
  void _prefetch(int i) {
    final f = _feed; if (f == null || i >= f.length) return;
    if ((_hosts[hostOf(f[i].url)] as Map?)?['dl'] == true) unawaited(downloadClip(f[i].url));
  }

  Future<void> _markBlocked(String url, String why) async {
    final h = hostOf(url); if (h.isEmpty) return;
    _hosts[h] = {'ok': false, 't': DateTime.now().millisecondsSinceEpoch, 'why': why};
    await (await ref.read(repoProvider.future)).kvSet('reel_hosts', _hosts);
    if (!mounted || _feed == null) return;
    // إخفاء بقية مقاطع هذا الخادم من الخلاصة الحالية (بعد المقطع الحالي)
    setState(() { _feed = [..._feed!.take(_cur + 1), ..._feed!.skip(_cur + 1).where((r) => hostOf(r.url) != h)]; _hidden = _scope().where((g) => !hostUsable(_hosts, g.tr)).length; });
  }

  Future<void> _fetch() async {
    setState(() { _busy = true; _msg = 'جارٍ جلب المقاطع…'; });
    final m = await fetchTrailers(ref, progress: (x) { if (mounted) setState(() => _msg = x); });
    if (!mounted) return;
    setState(() { _busy = false; _msg = m; _seed++; });
    await _prepare();
  }

  void _onViewed(Reel r, double frac) => ref.read(reelSigProvider.notifier).view(r.g, frac, like: false);

  void _like(Reel r) {
    HapticFeedback.lightImpact();
    if (_liked.add(r.key)) { ref.read(reelSigProvider.notifier).view(r.g, 1, like: true); }
    setState(() {});
  }

  void _menu(Reel r) => showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    for (final p in r.g.who) ListTile(leading: const Icon(Icons.person_remove_rounded), title: Text('أقل من ${p.name}'),
      onTap: () { Navigator.pop(c); ref.read(reelSigProvider.notifier).dislikeIt(performerId: p.id); _skip(); }),
    if (r.g.s.isNotEmpty) ListTile(leading: const Icon(Icons.business_rounded), title: Text('أقل من ${r.g.s}'),
      onTap: () { Navigator.pop(c); ref.read(reelSigProvider.notifier).dislikeIt(studio: r.g.s); _skip(); }),
    ListTile(leading: const Icon(Icons.visibility_off_rounded), title: const Text('إخفاء هذا المقطع'),
      onTap: () { Navigator.pop(c); ref.read(reelSigProvider.notifier).dislikeIt(hideKey: r.key); _skip(); }),
  ])));

  Future<void> _toggleSound() async {
    setState(() => _muted = !_muted);
    final c = await ref.read(reelsCfgProvider.future);
    await ref.read(reelsCfgProvider.notifier).set(c.copy(sound: !_muted));
  }

  void _skip() { if (_feed != null && _cur + 1 < _feed!.length) _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut); }

  @override
  Widget build(BuildContext context) {
    final sigReady = ref.watch(reelSigProvider).hasValue && ref.watch(libraryProvider).hasValue;
    if (sigReady && _feed == null && !_preparing) { _feed = const []; _preparing = true; Future.microtask(_prepare); }
    final feed = _feed ?? const <Reel>[];
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      if (!sigReady || (_preparing && feed.isEmpty)) Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: S.s3), Text(_msg, style: const TextStyle(color: Colors.white70))]))
      else if (feed.isEmpty) _empty()
      else PageView.builder(controller: _pc, scrollDirection: Axis.vertical, itemCount: feed.length,
        onPageChanged: (i) { setState(() => _cur = i); _prefetch(i + 1); },
        itemBuilder: (c, i) => (i - _cur).abs() > 1 ? const ColoredBox(color: Colors.black)   // لا يُحمَّل إلا الحالي والمجاوران
          : feed[i].photo ? _PhotoReel(key: ValueKey('ph${feed[i].key}'), reel: feed[i], active: i == _cur, onMenu: () => _menu(feed[i]))
          : _ReelPage(key: ValueKey(feed[i].key), reel: feed[i], active: i == _cur, muted: _muted, liked: _liked.contains(feed[i].key),
              onViewed: (f) => _onViewed(feed[i], f), onLike: () => _like(feed[i]), onMenu: () => _menu(feed[i]), onMute: _toggleSound,
              preferDownload: (_hosts[hostOf(feed[i].url)] as Map?)?['dl'] == true, onDownloaded: () => _markDl(feed[i].url),
              onError: (why) { _markBlocked(feed[i].url, why.isEmpty ? 'تعذّر التشغيل والتنزيل' : why); if (i == _cur) Future<void>.delayed(const Duration(seconds: 2), () { if (mounted && _cur == i) _skip(); }); })),
      // الشريط العلوي
      SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s2), child: Row(children: [
        IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        const Text('مقاطع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        const Spacer(),
        ChoiceChip(label: Text(_favsOnly ? 'مفضلاتي' : 'كل مكتبتي'), selected: true, showCheckmark: false, onSelected: (_) => setState(() { _favsOnly = !_favsOnly; _seed++; _build(); if (_pc.hasClients) _pc.jumpToPage(0); })),
        IconButton(tooltip: 'الشبكة والمقاطع', onPressed: () async { await context.push('/network'); if (mounted) { setState(() => _msg = ''); _prepare(); } }, icon: const Icon(Icons.network_check_rounded, color: Colors.white)),
        IconButton(tooltip: 'جلب مقاطع جديدة', onPressed: _busy ? null : _fetch, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, color: Colors.white)),
      ]))),
      if (_msg.isNotEmpty && (_busy || feed.isNotEmpty)) Positioned(top: 100, left: S.s4, right: S.s4, child: SafeArea(child: Container(padding: const EdgeInsets.all(S.s2),
        decoration: BoxDecoration(color: const Color(0xCC0A0810), borderRadius: BorderRadius.circular(S.rMd)),
        child: Row(children: [Expanded(child: Text(_msg, style: const TextStyle(color: Colors.white70, fontSize: 12.5))), if (!_busy) IconButton(onPressed: () => setState(() => _msg = ''), icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54))])))),
    ]));
  }

  Widget _empty() => Center(child: Padding(padding: const EdgeInsets.all(S.s5), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.slow_motion_video_rounded, color: C.gold, size: 56),
    const SizedBox(height: S.s3),
    const Text('مقاطع ممثلاتك', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
    const SizedBox(height: S.s2),
    Text(_msg.isNotEmpty && !_busy ? _msg : 'الإعلانات الرسمية لأعمال ${_favsOnly ? 'مفضلاتك' : 'مكتبتك'} من ThePornDB، مرتبة بخوارزمية تتعلم من مشاهدتك: ما تكمله وتعيده وتعجبك، وما تتخطاه بسرعة. كل ذلك على جهازك فقط.',
      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.6)),
    const SizedBox(height: S.s4),
    FilledButton.icon(onPressed: _busy ? null : _fetch, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded), label: Text(_busy ? _msg : 'جلب المقاطع')),
  ])));
}

/// مقطع واحد: يعمل حين يكون الحالي، يتكرر، ويحسب نسبة المشاهدة عند المغادرة.
class _ReelPage extends ConsumerStatefulWidget {
  const _ReelPage({super.key, required this.reel, required this.active, required this.muted, required this.liked, required this.onViewed, required this.onLike, required this.onMenu, required this.onMute, required this.onError, this.preferDownload = false, required this.onDownloaded});
  final Reel reel; final bool active, muted, liked, preferDownload; final VoidCallback onDownloaded;
  final void Function(double) onViewed; final VoidCallback onLike, onMenu, onMute; final void Function(String why) onError;
  @override ConsumerState<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<_ReelPage> {
  VideoPlayerController? _c; bool _err = false, _paused = false, _heart = false; String _why = '';
  Duration _maxPos = Duration.zero; int _loops = 0; Duration _last = Duration.zero;

  double? _dl;   // تقدم التنزيل (عند الحاجة)

  @override
  void initState() { super.initState(); _start(); }

  /// التشغيل الذكي: محفوظ على الجهاز ⇒ مباشرة من الشبكة ⇒ (إن فشل) تنزيل عبر شبكات النظام ثم تشغيل من الجهاز.
  Future<void> _start() async {
    final url = widget.reel.url;
    final saved = await cachedClipPath(url);
    if (saved != null) { if (await _open(_fileController(saved))) return; }
    if (!widget.preferDownload) {
      final ok = await _open(VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false)));
      if (ok) return;
    }
    if (clipCacheSupported) {
      if (mounted) setState(() { _err = false; _dl = 0; });
      final path = await downloadClip(url, onProgress: (p) { if (mounted) setState(() => _dl = p); });
      if (!mounted) return;
      if (path != null && await _open(_fileController(path))) { _dl = null; widget.onDownloaded(); return; }
    }
    if (mounted) { setState(() { _dl = null; _err = true; }); widget.onError(_why); }
  }

  VideoPlayerController _fileController(String path) {
    final f = fileVideoSource(path);
    return f == null ? VideoPlayerController.networkUrl(Uri.file(path)) : VideoPlayerController.file(f as dynamic, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
  }

  Future<bool> _open(VideoPlayerController c) async {
    try {
      await c.initialize();
      if (!mounted) { await c.dispose(); return false; }
      _c?.removeListener(_tick); final old = _c; _c = c; await old?.dispose();
      c.setLooping(true); c.setVolume(widget.muted ? 0 : 1); c.addListener(_tick);
      if (widget.active && !_paused) c.play();
      setState(() { _err = false; });
      return true;
    } catch (e) { _why = '$e'; try { await c.dispose(); } catch (_) {} return false; }
  }

  void _tick() {
    final v = _c!.value; if (!v.isInitialized) return;
    if (v.position < _last - const Duration(seconds: 1)) _loops++;   // رجع للبداية ⇒ إعادة
    _last = v.position; if (v.position > _maxPos) _maxPos = v.position;
  }

  double get _frac { final d = _c?.value.duration ?? Duration.zero; if (d.inMilliseconds <= 0) return 0; return _loops + _maxPos.inMilliseconds / d.inMilliseconds; }

  @override
  void didUpdateWidget(covariant _ReelPage o) {
    super.didUpdateWidget(o);
    final c = _c; if (c == null || !c.value.isInitialized) { return; }
    if (o.muted != widget.muted) c.setVolume(widget.muted ? 0 : 1);
    if (o.active && !widget.active) { c.pause(); widget.onViewed(_frac); _maxPos = Duration.zero; _loops = 0; c.seekTo(Duration.zero); }
    if (!o.active && widget.active) { if (_err) { widget.onError(_why); } else if (c.value.isInitialized && !_paused) { c.play(); } }
  }

  @override
  void dispose() { if (widget.active) widget.onViewed(_frac); _c?.removeListener(_tick); _c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel, g = r.g, c = _c;
    final ready = c != null && c.value.isInitialized;
    Widget video = ready ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))) : Stack(fit: StackFit.expand, children: [
      if (g.p.isNotEmpty) Opacity(opacity: .5, child: WorkImage(g.p, name: g.s)),
      Center(child: _err ? Padding(padding: const EdgeInsets.all(S.s5), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تعذّر تشغيل هذا المقطع — ننتقل للتالي…', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Text('الخادم: ${Uri.tryParse(widget.reel.url)?.host ?? '?'}\n${_why.length > 160 ? _why.substring(0, 160) : _why}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]))
        : _dl != null ? Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(value: _dl! > 0 ? _dl : null), const SizedBox(height: 8), Text(_dl! > 0 ? 'تحميل المقطع ${(_dl! * 100).round()}٪' : 'تحميل المقطع…', style: const TextStyle(color: Colors.white70))])
        : const CircularProgressIndicator()),
    ]);
    return ValueListenableBuilder<bool>(valueListenable: blurPhotos, builder: (_, blur, _) => GestureDetector(
      onTap: () { if (!ready) return; setState(() { _paused = !_paused; _paused ? c.pause() : c.play(); }); },
      onDoubleTap: () { widget.onLike(); setState(() => _heart = true); Future<void>.delayed(const Duration(milliseconds: 700), () { if (mounted) setState(() => _heart = false); }); },
      onLongPress: widget.onMenu,
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        blur ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: video) : video,
        if (_paused) const Center(child: Icon(Icons.play_arrow_rounded, size: 84, color: Colors.white70)),
        if (_heart) const Center(child: Icon(Icons.favorite_rounded, size: 110, color: C.rose)),
        // المعلومات (أسفل) والأزرار (جانبًا)
        Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(S.s4, 60, S.s4, S.s5),
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xD9000000)])),
          child: SafeArea(top: false, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(g.who.map((p) => p.name).take(2).join('، '), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              Text([if (g.s.isNotEmpty) g.s, if (g.y.isNotEmpty) g.y].join(' · '), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 4),
              Text(r.why, style: TextStyle(color: r.explore ? C.rose : C.gold2, fontSize: 12)),
            ])),
            const SizedBox(width: S.s3),
            Column(mainAxisSize: MainAxisSize.min, children: [
              _side(widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, 'إعجاب', widget.liked ? C.rose : Colors.white, widget.onLike),
              _side(Icons.person_rounded, 'ملفها', Colors.white, () => context.push('/p/${g.who.first.id}')),
              _side(Icons.movie_rounded, 'العمل', Colors.white, () => showWorkSheet(context, ref, g.key)),
              _side(widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, widget.muted ? 'صامت' : 'صوت', Colors.white, widget.onMute),
            ]),
          ])))),
        if (ready) Positioned(left: 0, right: 0, bottom: 0, child: VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: C.gold, bufferedColor: Colors.white24, backgroundColor: Colors.white10))),
      ])));
  }

  Widget _side(IconData i, String t, Color col, VoidCallback f) => Padding(padding: const EdgeInsets.only(bottom: S.s3), child: GestureDetector(onTap: f, child: Column(children: [
    Icon(i, color: col, size: 30, shadows: const [Shadow(blurRadius: 6)]), Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(blurRadius: 6)])),
  ])));
}


/// يفحص رابط مقطع بطلب أول 1 كيلوبايت (نفس شبكات النظام): (يعمل؟، الوصف).
Future<(bool, String)> probeVideoUrl(String url) async {
  try {
    final r = await sourceClient.get(Uri.parse(url), headers: {'Range': 'bytes=0-1023'}).timeout(const Duration(seconds: 15));
    final ct = r.headers['content-type'] ?? '?';
    if (r.statusCode == 403 || r.statusCode == 401) return (false, 'الخادم يرفض (${r.statusCode}) — رابط منتهٍ أو يمنع التشغيل خارج موقعه');
    if (r.statusCode == 404 || r.statusCode == 410) return (false, 'غير موجود (${r.statusCode}) — حُذف المقطع');
    if (r.statusCode >= 400) return (false, 'خطأ من الخادم (${r.statusCode})');
    final b = r.bodyBytes;
    final mp4 = b.length > 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70;   // ftyp
    final webm = b.length > 4 && b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3;
    final hls = String.fromCharCodes(b.take(7)) == '#EXTM3U';
    if (webm) return (false, 'صيغة WebM — لا يشغّلها الآيفون');
    if (ct.contains('text/html')) return (false, 'الرابط صفحة ويب وليس ملف فيديو');
    if (mp4 || hls || ct.startsWith('video/') || ct.contains('mpegurl')) return (true, 'يعمل (${hls ? 'HLS' : mp4 ? 'MP4' : ct})');
    return (true, 'قد يعمل — نوع غير معتاد ($ct) يُجرَّب في المشغّل');
  } on SourceError catch (e) { return (false, e.msg); }
  catch (e) {
    final s = '$e';
    if (looksBlocked(s)) return (false, 'محجوب على شبكتك (الاتصال يُقطع أثناء التشفير)');
    if (s.contains('Timeout')) return (false, 'لا رد (مهلة)');
    return (false, s.length > 90 ? s.substring(0, 90) : s);
  }
}


/// «مقطع صور»: لعمل مقطعه محجوب على شبكتك — صورة العمل وصور ممثلاته بحركة تكبير وانزلاق بطيئة (Ken Burns)، مُعلَّم بوضوح.
class _PhotoReel extends StatefulWidget {
  const _PhotoReel({super.key, required this.reel, required this.active, required this.onMenu});
  final Reel reel; final bool active; final VoidCallback onMenu;
  @override State<_PhotoReel> createState() => _PhotoReelState();
}
class _PhotoReelState extends State<_PhotoReel> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(seconds: 5));
  int _i = 0;
  @override
  void initState() {
    super.initState();
    _a.addStatusListener((s) { if (s == AnimationStatus.completed && mounted && widget.reel.images.length > 1) { setState(() => _i = (_i + 1) % widget.reel.images.length); _a.forward(from: 0); } });
    if (widget.active) _a.forward();
  }
  @override void didUpdateWidget(covariant _PhotoReel o) { super.didUpdateWidget(o); if (widget.active && !_a.isAnimating) { _a.forward(); } else if (!widget.active) { _a.stop(); } }
  @override void dispose() { _a.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final r = widget.reel, g = r.g, imgs = r.images.isEmpty ? [g.p] : r.images;
    return GestureDetector(onLongPress: widget.onMenu, child: Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      AnimatedSwitcher(duration: const Duration(milliseconds: 600), child: AnimatedBuilder(key: ValueKey(_i), animation: _a, builder: (_, _) {
        final t = Curves.easeInOut.transform(_a.value);
        return Transform.scale(scale: 1.05 + .12 * t, child: Transform.translate(offset: Offset((_i.isEven ? -1 : 1) * 14 * t, -10 * t), child: WorkImage(imgs[_i % imgs.length], name: g.s)));
      })),
      Positioned(top: 110, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: const Color(0xCC0A0810), borderRadius: BorderRadius.circular(99)),
        child: const Text('📷 صور — مقطعه محجوب على شبكتك', style: TextStyle(color: Colors.white70, fontSize: 12.5))))),
      Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(S.s4, 60, S.s4, S.s5),
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xD9000000)])),
        child: SafeArea(top: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(g.who.map((p) => p.name).take(2).join('، '), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          Text([if (g.s.isNotEmpty) g.s, if (g.y.isNotEmpty) g.y].join(' · '), style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ])))),
    ]));
  }
}
