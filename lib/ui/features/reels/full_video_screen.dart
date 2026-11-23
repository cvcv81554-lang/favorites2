import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';

/// مشغّل الفيديو الكامل (من خادمك أو أي مصدر بث مباشر): تشغيل/إيقاف، تقديم وتأخير 10 ثوانٍ، شريط تمرير، وملء الشاشة بالعرض.
class FullVideoScreen extends StatefulWidget {
  const FullVideoScreen({super.key, required this.url, required this.title, this.start = 0, this.source = ''});
  final String url, title, source; final int start;
  @override State<FullVideoScreen> createState() => _FullVideoState();
}

class _FullVideoState extends State<FullVideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
  bool _ui = true, _err = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _c.initialize().then((_) async { if (widget.start > 0) await _c.seekTo(Duration(seconds: widget.start)); await _c.setVolume(1); await _c.play(); if (mounted) setState(() {}); })
      .catchError((Object _) { if (mounted) setState(() => _err = true); });
    _c.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); _c.dispose(); super.dispose(); }

  String _t(Duration d) { final s = d.inSeconds; final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60; return h > 0 ? '$h:${'$m'.padLeft(2, '0')}:${'$x'.padLeft(2, '0')}' : '$m:${'$x'.padLeft(2, '0')}'; }

  Future<void> _jump(int sec) async { final p = _c.value.position + Duration(seconds: sec); await _c.seekTo(p < Duration.zero ? Duration.zero : p); }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(backgroundColor: Colors.black, body: GestureDetector(onTap: () => setState(() => _ui = !_ui), child: Stack(fit: StackFit.expand, children: [
      Center(child: _err ? const Padding(padding: EdgeInsets.all(S.s5), child: Text('تعذّر تشغيل الفيديو — تأكد أن المصدر متاح على شبكتك', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))
        : v.isInitialized ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c)) : const CircularProgressIndicator()),
      if (_ui) ...[
        SafeArea(child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
          Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          if (widget.source.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(widget.source, style: const TextStyle(color: Colors.white54, fontSize: 12))),
        ])),
        if (v.isInitialized) Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(iconSize: 40, onPressed: () => _jump(-10), icon: const Icon(Icons.replay_10_rounded, color: Colors.white)),
          const SizedBox(width: 24),
          IconButton(iconSize: 64, onPressed: () => v.isPlaying ? _c.pause() : _c.play(), icon: Icon(v.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded, color: Colors.white)),
          const SizedBox(width: 24),
          IconButton(iconSize: 40, onPressed: () => _jump(10), icon: const Icon(Icons.forward_10_rounded, color: Colors.white)),
        ])),
        if (v.isInitialized) Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s3), child: Column(mainAxisSize: MainAxisSize.min, children: [
          VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 10), colors: const VideoProgressColors(playedColor: C.gold, bufferedColor: Colors.white30, backgroundColor: Colors.white12)),
          Row(children: [Text(_t(v.position), style: const TextStyle(color: Colors.white70, fontSize: 12)), const Spacer(), Text(_t(v.duration), style: const TextStyle(color: Colors.white70, fontSize: 12))]),
        ])))),
      ],
    ])));
  }
}
