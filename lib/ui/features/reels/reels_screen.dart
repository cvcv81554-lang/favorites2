import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../data/keys.dart';
import '../../../data/privacy.dart' show blurPhotos;
import '../../../data/sources.dart';
import '../../../domain/performer.dart';
import '../../../domain/reels.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../works/works_screen.dart' show worksProvider, workTasteProvider, showWorkSheet;

/// إشارات «مقاطع» (محفوظة على الجهاز فقط).
class ReelSigN extends AsyncNotifier<ReelSignals> {
  @override Future<ReelSignals> build() async => ReelSignals.fromJson(await (await ref.watch(repoProvider.future)).kvGet('reels_sig'));
  Future<void> _save(ReelSignals s) async { state = AsyncData(s); await (await ref.read(repoProvider.future)).kvSet('reels_sig', s.toJson()); }
  Future<void> view(WorkGroup g, double frac, {bool like = false}) async => _save(recordView(state.value ?? const ReelSignals({}, {}), g, frac: frac, like: like));
  Future<void> dislikeIt({String? performerId, String? studio, String? hideKey}) async => _save(dislike(state.value ?? const ReelSignals({}, {}), performerId: performerId, studio: studio, hideKey: hideKey));
}
final reelSigProvider = AsyncNotifierProvider<ReelSigN, ReelSignals>(ReelSigN.new);

/// جلب الإعلانات الرسمية من ThePornDB لأعمال مفضلاتك (تُدمج في أعمالهن بلا تكرار — يملأ «tr» فقط حيث ينقص).
Future<String> fetchTrailers(WidgetRef ref, {bool favsOnly = true, void Function(String)? progress}) async {
  if (!await ApiKeys.has(ApiKeys.tpdb)) return 'المقاطع تأتي من ThePornDB — أضف مفتاحه من «المزيد».';
  final lib = ref.read(libraryProvider.notifier);
  final ps = lib.items.where((p) => !p.isMinor && p.pdbIds.isNotEmpty && (!favsOnly || p.fav || p.rating >= 4)).toList();
  if (ps.isEmpty) return 'لا ممثلات مرتبطة بـ ThePornDB في ${favsOnly ? 'مفضلاتك' : 'مكتبتك'} — اربطها أولًا (تحديث من المصدرين).';
  var withTr = 0, i = 0; final changed = <Performer>[];
  for (final p in ps) {
    i++; progress?.call('جلب مقاطع ${p.name} ($i/${ps.length})…');
    var works = p.works;
    for (final id in p.pdbIds.take(3)) {
      try { works = mergeWorks(works, await TPDB.scenes(id, maxPages: 3)).list; }
      on SourceError catch (e) { if (e.status == -2 || e.status == 401 || e.status == 403) return e.msg; }
    }
    final cur = lib.items.where((x) => x.id == p.id).firstOrNull ?? p;
    final merged = mergeWorks(cur.works, works).list;
    withTr += merged.where((w) => '${w['tr'] ?? ''}'.isNotEmpty).length;
    changed.add(cur.copyWith({'works': merged}));
  }
  if (changed.isNotEmpty) await lib.upsertMany(changed);
  return withTr == 0 ? 'لم تُعثر على إعلانات رسمية لأعمال ${favsOnly ? 'مفضلاتك' : 'مكتبتك'} في ThePornDB.' : 'جاهز: $withTr مقطعًا';
}

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});
  @override ConsumerState<ReelsScreen> createState() => _ReelsState();
}

class _ReelsState extends ConsumerState<ReelsScreen> {
  final _pc = PageController();
  List<Reel>? _feed; int _cur = 0; bool _favsOnly = true, _muted = true, _busy = false; String _msg = '';
  int _seed = DateTime.now().millisecondsSinceEpoch;
  final _liked = <String>{};

  @override void dispose() { _pc.dispose(); super.dispose(); }

  void _build() {
    final sig = ref.read(reelSigProvider).value ?? const ReelSignals({}, {});
    _feed = rankReels(ref.read(worksProvider), ref.read(workTasteProvider), sig, favsOnly: _favsOnly, seed: _seed);
    _cur = 0;
    for (final r in _feed!) { if (sig.clips[r.key]?['l'] == 1) _liked.add(r.key); }
  }

  Future<void> _fetch() async {
    setState(() { _busy = true; _msg = 'جارٍ جلب المقاطع…'; });
    final m = await fetchTrailers(ref, favsOnly: _favsOnly, progress: (x) { if (mounted) setState(() => _msg = x); });
    if (!mounted) return;
    setState(() { _busy = false; _msg = m; _seed++; _build(); });
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

  void _skip() { if (_feed != null && _cur + 1 < _feed!.length) _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut); }

  @override
  Widget build(BuildContext context) {
    final sigReady = ref.watch(reelSigProvider).hasValue && ref.watch(libraryProvider).hasValue;
    if (sigReady && _feed == null) _build();
    final feed = _feed ?? const <Reel>[];
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      if (!sigReady) const Center(child: CircularProgressIndicator())
      else if (feed.isEmpty) _empty()
      else PageView.builder(controller: _pc, scrollDirection: Axis.vertical, itemCount: feed.length,
        onPageChanged: (i) => setState(() => _cur = i),
        itemBuilder: (c, i) => (i - _cur).abs() > 1 ? const ColoredBox(color: Colors.black)   // لا يُحمَّل إلا الحالي والمجاوران
          : _ReelPage(key: ValueKey(feed[i].key), reel: feed[i], active: i == _cur, muted: _muted, liked: _liked.contains(feed[i].key),
              onViewed: (f) => _onViewed(feed[i], f), onLike: () => _like(feed[i]), onMenu: () => _menu(feed[i]), onMute: () => setState(() => _muted = !_muted),
              onError: () { if (i == _cur) Future<void>.delayed(const Duration(seconds: 2), () { if (mounted && _cur == i) _skip(); }); })),
      // الشريط العلوي
      SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s2), child: Row(children: [
        IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        const Text('مقاطع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        const Spacer(),
        ChoiceChip(label: Text(_favsOnly ? 'مفضلاتي' : 'كل مكتبتي'), selected: true, showCheckmark: false, onSelected: (_) => setState(() { _favsOnly = !_favsOnly; _seed++; _build(); if (_pc.hasClients) _pc.jumpToPage(0); })),
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
  const _ReelPage({super.key, required this.reel, required this.active, required this.muted, required this.liked, required this.onViewed, required this.onLike, required this.onMenu, required this.onMute, required this.onError});
  final Reel reel; final bool active, muted, liked;
  final void Function(double) onViewed; final VoidCallback onLike, onMenu, onMute, onError;
  @override ConsumerState<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<_ReelPage> {
  VideoPlayerController? _c; bool _err = false, _paused = false, _heart = false;
  Duration _maxPos = Duration.zero; int _loops = 0; Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.reel.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c = c;
    c.initialize().then((_) { if (!mounted) return; c.setLooping(true); c.setVolume(widget.muted ? 0 : 1); if (widget.active) c.play(); setState(() {}); })
      .catchError((_) { if (mounted) { setState(() => _err = true); if (widget.active) widget.onError(); } });
    c.addListener(_tick);
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
    final c = _c; if (c == null) return;
    if (o.muted != widget.muted) c.setVolume(widget.muted ? 0 : 1);
    if (o.active && !widget.active) { c.pause(); widget.onViewed(_frac); _maxPos = Duration.zero; _loops = 0; c.seekTo(Duration.zero); }
    if (!o.active && widget.active) { if (_err) { widget.onError(); } else if (c.value.isInitialized && !_paused) { c.play(); } }
  }

  @override
  void dispose() { if (widget.active) widget.onViewed(_frac); _c?.removeListener(_tick); _c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel, g = r.g, c = _c;
    final ready = c != null && c.value.isInitialized;
    Widget video = ready ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))) : Stack(fit: StackFit.expand, children: [
      if (g.p.isNotEmpty) Opacity(opacity: .5, child: WorkImage(g.p, name: g.s)),
      Center(child: _err ? const Padding(padding: EdgeInsets.all(S.s5), child: Text('تعذّر تشغيل هذا المقطع (قد يكون محجوبًا على شبكتك أو حُذف) — ننتقل للتالي…', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))
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
