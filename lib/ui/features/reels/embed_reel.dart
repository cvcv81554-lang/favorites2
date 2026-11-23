import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../domain/reels.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// مقطع من موقع تضمين رسمي: مشغّل التضمين الذي يسمح به الموقع (داخل صفحة ويب)، يُحمَّل للمقطع الحالي فقط.
/// مدة المشاهدة تُحسب بوقت البقاء على المقطع (لا يمكن قراءة مشغّل الموقع).
class EmbedReel extends StatefulWidget {
  const EmbedReel({super.key, required this.reel, required this.active, required this.liked, required this.onViewed, required this.onLike, required this.onMenu, required this.onProfile});
  final Reel reel; final bool active, liked; final void Function(double) onViewed; final VoidCallback onLike, onMenu, onProfile;
  @override State<EmbedReel> createState() => _EmbedReelState();
}

class _EmbedReelState extends State<EmbedReel> {
  WebViewController? _w; final _sw = Stopwatch();

  WebViewController _make() {
    final params = defaultTargetPlatform == TargetPlatform.iOS
      ? WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true, mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{})
      : const PlatformWebViewControllerCreationParams();
    return WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (r) {
        // يبقى داخل مشغّل التضمين؛ أي رابط خارجه (إعلانات/صفحات) لا يُفتح داخل التطبيق
        final allowed = Uri.tryParse(widget.reel.url)?.host ?? '';
        return Uri.tryParse(r.url)?.host == allowed || r.url == 'about:blank' ? NavigationDecision.navigate : NavigationDecision.prevent;
      }))
      ..loadRequest(Uri.parse(widget.reel.url));
  }

  void _activate() { if (kIsWeb) return; _w ??= _make(); _sw..reset()..start(); }
  void _deactivate() {
    if (_sw.isRunning) { _sw.stop(); final d = widget.reel.g.du * 60; widget.onViewed(d <= 0 ? 0 : (_sw.elapsed.inSeconds / d).clamp(0.0, 1.0)); }
    _w?.loadRequest(Uri.parse('about:blank')); _w = null;   // يوقف الصوت ويحرر الذاكرة
  }

  @override void initState() { super.initState(); if (widget.active) _activate(); }
  @override void didUpdateWidget(covariant EmbedReel o) { super.didUpdateWidget(o); if (!o.active && widget.active) { setState(_activate); } else if (o.active && !widget.active) { setState(_deactivate); } }
  @override void dispose() { if (widget.active) _deactivate(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel, g = r.g;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (_w != null) Padding(padding: const EdgeInsets.only(top: 90, bottom: 150), child: WebViewWidget(controller: _w!))
      else Stack(fit: StackFit.expand, children: [
        if (g.p.isNotEmpty) Opacity(opacity: .6, child: WorkImage(g.p, name: g.t)),
        Center(child: kIsWeb ? FilledButton.icon(onPressed: () => launchUrl(Uri.parse(r.url)), icon: const Icon(Icons.open_in_new_rounded), label: const Text('افتح في المتصفح'))
          : const Icon(Icons.play_circle_rounded, size: 72, color: Colors.white70)),
      ]),
      Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(S.s4, 24, S.s4, S.s4),
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xE6000000)])),
        child: SafeArea(top: false, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(g.who.map((p) => p.name).take(2).join('، '), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
            Text(r.why, style: TextStyle(color: r.explore ? C.rose : C.gold2, fontSize: 12)),
            Text('${r.src}${g.du > 0 ? ' · ${g.du} د' : ''}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(onPressed: widget.onLike, icon: Icon(widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: widget.liked ? C.rose : Colors.white, size: 30)),
            IconButton(onPressed: widget.onProfile, icon: const Icon(Icons.person_rounded, color: Colors.white, size: 28)),
            IconButton(onPressed: widget.onMenu, icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 28)),
          ]),
        ])))),
    ]);
  }
}
