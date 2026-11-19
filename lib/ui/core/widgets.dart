import 'dart:convert';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/platform/db_factory.dart';
import '../../domain/performer.dart';
import 'theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.asset('assets/brand/logo.svg', width: size, height: size, semanticsLabel: 'شعار المفضلة');
}

/// صورة من أي مرجع: https، data URI، أو ملف على الجهاز (file:). تظهر الأحرف الأولى إن تعذّرت.
class Photo extends StatelessWidget {
  const Photo(this.src, {super.key, this.fit = BoxFit.cover, this.name = '', this.cacheWidth, this.alignment = const Alignment(0, -.4)});
  final String src; final BoxFit fit; final String name; final int? cacheWidth; final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Initials(name);
    if (src.isEmpty) return fallback();
    Widget img;
    if (src.startsWith('data:image/')) {
      img = Image.memory(base64Decode(src.substring(src.indexOf(',') + 1)), fit: fit, alignment: alignment, cacheWidth: cacheWidth, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback());
    } else if (src.startsWith('file:')) {
      final prov = fileImageProvider(src);
      if (prov == null) return fallback();
      img = Image(image: ResizeImage.resizeIfNeeded(cacheWidth, null, prov), fit: fit, alignment: alignment, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback());
    } else {
      img = Image.network(src, fit: fit, alignment: alignment, cacheWidth: cacheWidth, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback(),
          loadingBuilder: (c, child, p) => p == null ? child : const Shimmer());
    }
    return img;
  }
}

class Initials extends StatelessWidget {
  const Initials(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) {
    final ini = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w.characters.first).join().toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2A1630), C.surface], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Center(child: Text(ini.isEmpty ? '♡' : ini, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0x99F6DDA6)))),
    );
  }
}

/// هيكل تحميل لامع خفيف.
class Shimmer extends StatefulWidget { const Shimmer({super.key}); @override State<Shimmer> createState() => _ShimmerState(); }
class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, _) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
    begin: Alignment(-1 + _c.value * 3, 0), end: Alignment(_c.value * 3, 0), colors: const [C.surface, C.surface2, C.surface]))));
}

class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});
  final String text; final TextStyle? style;
  @override
  Widget build(BuildContext context) => ShaderMask(shaderCallback: (r) => C.grad.createShader(r), child: Text(text, style: (style ?? const TextStyle()).copyWith(color: Colors.white)));
}

class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.size = 14});
  final double value; final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    for (var i = 1; i <= 5; i++) Icon(value >= i ? Icons.star_rounded : value >= i - .5 ? Icons.star_half_rounded : Icons.star_outline_rounded, size: size, color: C.gold),
  ]);
}

/// بطاقة ملصق لممثلة: صورة 3:4، تدرّج، الاسم والتقييم، قلب المفضلة. تتكبر قليلًا عند التركيز (ريموت/لوحة مفاتيح).
class PosterCard extends StatefulWidget {
  const PosterCard({super.key, required this.p, required this.onTap, this.subtitle, this.heroTag});
  final Performer p; final VoidCallback onTap; final String? subtitle; final String? heroTag;
  @override State<PosterCard> createState() => _PosterCardState();
}
class _PosterCardState extends State<PosterCard> {
  bool _focus = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final sub = widget.subtitle ?? [if (p.age != null) '${p.age} سنة', if (p.country.isNotEmpty) p.country].join(' · ');
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) { widget.onTap(); return null; })},
      child: AnimatedScale(
        scale: _focus ? 1.05 : 1, duration: S.fast, curve: S.ease,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: S.fast,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: _focus ? C.gold2 : C.line, width: _focus ? 2.5 : 1),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 18, offset: const Offset(0, 10))]),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              Hero(tag: widget.heroTag ?? 'p-${p.id}', child: Photo(p.cover, name: p.name, cacheWidth: 480)),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment(0, .1), end: Alignment.bottomCenter, colors: [Color(0x000A0810), Color(0xE60A0810)]))),
              if (p.rating > 0) Positioned(top: 8, left: 8, child: _Pill('★ ${p.rating.toStringAsFixed(1)}')),
              if (p.fav) const Positioned(top: 8, right: 8, child: Icon(Icons.favorite_rounded, color: C.rose, size: 20)),
              Positioned(left: 10, right: 10, bottom: 10, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
              ])),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xB30A0810), borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 12)));
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.sub, this.action, this.onAction});
  final String title; final String? sub; final String? action; final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(S.s4, S.s5, S.s4, S.s2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (sub != null) Text(sub!, style: Theme.of(context).textTheme.bodySmall),
      ])),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!, style: const TextStyle(color: C.gold2))),
    ]),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.body, this.icon = Icons.auto_awesome_rounded, this.actions = const []});
  final String title, body; final IconData icon; final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(S.s6), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const AppLogo(size: 84), const SizedBox(height: S.s4),
    Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center), const SizedBox(height: S.s2),
    Text(body, style: const TextStyle(color: C.muted, height: 1.6), textAlign: TextAlign.center), const SizedBox(height: S.s5),
    Wrap(spacing: S.s3, runSpacing: S.s3, alignment: WrapAlignment.center, children: actions),
  ])));
}
