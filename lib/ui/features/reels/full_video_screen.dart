import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../data/stash_server.dart';
import '../../core/theme.dart';

/// مشغّل الفيديو الكامل: تشغيل/إيقاف، ±10 ثوانٍ، تقديم بالسحب مع صور مصغرة (من Stash)، الوضع الأفقي،
/// ومزامنة مكان التوقف وعدد المشاهدات مع Stash على حاسوبك.
class FullVideoScreen extends StatefulWidget {
  const FullVideoScreen({super.key, required this.url, required this.title, this.start = 0, this.source = '', this.file, this.stashId = '', this.vtt = '', this.onClosed});
  final String url, title, source; final int start; final Object? file;   // file: ملف المقطع المحفوظ على الجهاز (إن وُجد)
  /// [stashId]: معرّف المقطع في خادمك (للمزامنة)؛ [vtt]: ملف الصور المصغرة.
  final String stashId, vtt;
  /// عند الإغلاق: مكان التوقف (ثوانٍ).
  final void Function(double resume)? onClosed;
  @override State<FullVideoScreen> createState() => _FullVideoState();
}

class _FullVideoState extends State<FullVideoScreen> {
  VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse('about:blank'));
  bool _ui = true, _err = false, _triedHls = false;
  List<VttCue> _cues = const [];
  double? _scrub;   // موضع السحب الحالي (ثوانٍ) أثناء التقديم
  final _watch = Stopwatch();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    final ex = widget.stashId.isEmpty ? null : StashServer.extra.values.where((e) => e.id == widget.stashId).firstOrNull;
    if (widget.file == null && ex != null && !ex.direct) { _useHls(); } else { _open(widget.file != null ? VideoPlayerController.file(widget.file as dynamic, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false))
      : VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false))); }
    if (widget.vtt.isNotEmpty) StashServer.thumbs(widget.vtt).then((c) { if (mounted) setState(() => _cues = c); });
  }

  /// صيغة لا يشغّلها الآيفون (mkv/wmv…) أو فشل التشغيل المباشر ⇒ بث متكيّف (HLS) يحوّله خادم Stash.
  Future<void> _useHls() async {
    _triedHls = true;
    final u = await StashServer.hls(widget.stashId);
    if (!mounted) return;
    if (u == null) { setState(() => _err = true); return; }
    _open(VideoPlayerController.networkUrl(Uri.parse(u), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false)));
  }

  void _listen() {
    if (_c.value.isPlaying) { if (!_watch.isRunning) _watch.start(); } else if (_watch.isRunning) { _watch.stop(); }
    if (mounted) setState(() {});
  }

  Future<void> _open(VideoPlayerController c) async {
    final old = _c; old.removeListener(_listen);
    setState(() { _c = c; _err = false; });
    old.dispose();
    try {
      await c.initialize();
      if (!mounted) return;
      c.addListener(_listen);
      if (widget.start > 0) await c.seekTo(Duration(seconds: widget.start));
      await c.setVolume(1); await c.play(); if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      if (widget.stashId.isNotEmpty && !_triedHls) { _useHls(); } else { setState(() => _err = true); }
    }
  }

  @override
  void dispose() {
    final pos = _c.value.isInitialized ? _c.value.position.inMilliseconds / 1000 : 0.0;
    final dur = _c.value.isInitialized ? _c.value.duration.inMilliseconds / 1000 : 0.0;
    final played = _watch.elapsedMilliseconds / 1000;
    final resume = dur > 0 && pos > dur - 20 ? 0.0 : pos;   // انتهى تقريبًا ⇒ لا «تابع المشاهدة»
    if (widget.stashId.isNotEmpty && played >= 5) {
      StashServer.saveActivity(widget.stashId, resume: resume, played: played);
      if (played >= 60 || (dur > 0 && played >= dur * .5)) StashServer.addPlay(widget.stashId);
    }
    widget.onClosed?.call(resume);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _c.removeListener(_listen); _c.dispose(); super.dispose();
  }

  String _t(Duration d) { final s = d.inSeconds; final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60; return h > 0 ? '$h:${'$m'.padLeft(2, '0')}:${'$x'.padLeft(2, '0')}' : '$m:${'$x'.padLeft(2, '0')}'; }

  Future<void> _jump(int sec) async { final p = _c.value.position + Duration(seconds: sec); await _c.seekTo(p < Duration.zero ? Duration.zero : p); }

  /// الصورة المصغرة لنقطة زمنية: قصّ الجزء المطلوب من صورة المصغرات.
  Widget _thumb(VttCue q) => ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: q.w.toDouble(), height: q.h.toDouble(), child: ClipRect(child: OverflowBox(
    alignment: Alignment.topLeft, minWidth: 0, minHeight: 0, maxWidth: double.infinity, maxHeight: double.infinity,
    child: Transform.translate(offset: Offset(-q.x.toDouble(), -q.y.toDouble()), child: Image.network(q.url, scale: 1, fit: BoxFit.none, alignment: Alignment.topLeft, gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox()))))));

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final durS = v.duration.inMilliseconds / 1000;
    final posS = _scrub ?? v.position.inMilliseconds / 1000;
    final cue = _scrub == null ? null : cueAt(_cues, _scrub!);
    return Scaffold(backgroundColor: Colors.black, body: GestureDetector(onTap: () => setState(() => _ui = !_ui), child: Stack(fit: StackFit.expand, children: [
      Center(child: _err ? const Padding(padding: EdgeInsets.all(S.s5), child: Text('تعذّر تشغيل الفيديو — تأكد أن المصدر متاح على شبكتك', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))
        : v.isInitialized ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c)) : const CircularProgressIndicator()),
      if (_ui || _scrub != null) ...[
        SafeArea(child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
          Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          if (widget.source.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(widget.source, style: const TextStyle(color: Colors.white54, fontSize: 12))),
        ])),
        if (v.isInitialized && _scrub == null) Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(iconSize: 40, onPressed: () => _jump(-10), icon: const Icon(Icons.replay_10_rounded, color: Colors.white)),
          const SizedBox(width: 24),
          IconButton(iconSize: 64, onPressed: () => v.isPlaying ? _c.pause() : _c.play(), icon: Icon(v.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded, color: Colors.white)),
          const SizedBox(width: 24),
          IconButton(iconSize: 40, onPressed: () => _jump(10), icon: const Icon(Icons.forward_10_rounded, color: Colors.white)),
        ])),
        if (v.isInitialized && durS > 0) Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s3), child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (cue != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(children: [_thumb(cue), const SizedBox(height: 4), Text(_t(Duration(seconds: _scrub!.round())), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]))
          else if (_scrub != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_t(Duration(seconds: _scrub!.round())), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
          SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: _scrub != null ? 6 : 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7), overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: C.gold, inactiveTrackColor: Colors.white24, thumbColor: Colors.white),
            child: Slider(min: 0, max: durS, value: posS.clamp(0, durS).toDouble(),
              onChangeStart: (x) => setState(() => _scrub = x),
              onChanged: (x) => setState(() => _scrub = x),
              onChangeEnd: (x) async { await _c.seekTo(Duration(milliseconds: (x * 1000).round())); if (mounted) setState(() => _scrub = null); })),
          const SizedBox(height: 6),
          Row(children: [Text(_t(v.position), style: const TextStyle(color: Colors.white70, fontSize: 12)), const Spacer(), Text(_t(v.duration), style: const TextStyle(color: Colors.white70, fontSize: 12))]),
        ])))),
      ],
    ])));
  }
}
