import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/insights.dart';
import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../performer/insights_widgets.dart' show attrFeatsProvider, attrKey;
import '../works/works_screen.dart' show worksProvider;
import 'discover_screen.dart' show openCandidate;
import 'taste_state.dart';

/// نقطة على خريطة الذوق: مفضلة (ذهبي) أو مرشحة (وردي).
class _Pt { final String id, name; final bool fav; final double x, y; final TasteRec? rec; const _Pt(this.id, this.name, this.fav, this.x, this.y, this.rec); }

/// «خريطة ذوقك» و«ذوقك عبر الزمن» — من البيانات الموثّقة فقط (بلا صور).
class TasteMapScreen extends ConsumerStatefulWidget {
  const TasteMapScreen({super.key, this.tab = 0});
  final int tab;
  @override ConsumerState<TasteMapScreen> createState() => _TasteMapState();
}

class _TasteMapState extends ConsumerState<TasteMapScreen> {
  _Pt? _sel;

  @override
  Widget build(BuildContext context) {
    final feats = ref.watch(attrFeatsProvider).value ?? const {};
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    final recs = ref.watch(tasteProvider).value?.recs ?? const <TasteRec>[];
    final favs = [for (final p in lib) if ((p.fav || p.rating >= 4) && !p.isMinor && feats[attrKey(p)] != null && feats[attrKey(p)]!.isNotEmpty) p];
    final rs = recs.where((r) => r.feats.isNotEmpty).take(60).toList();
    final coords = tasteMap([for (final p in favs) feats[attrKey(p)]!, for (final r in rs) r.feats]);
    final pts = [
      for (var i = 0; i < favs.length; i++) _Pt(favs[i].id, favs[i].name, true, coords[i].$1, coords[i].$2, null),
      for (var i = 0; i < rs.length; i++) _Pt(rs[i].id, rs[i].name, false, coords[favs.length + i].$1, coords[favs.length + i].$2, rs[i]),
    ];
    final years = tasteOverTime(lib, ref.watch(worksProvider), {for (final p in lib) if (feats[attrKey(p)] != null) p.id: feats[attrKey(p)]!});

    return DefaultTabController(length: 2, initialIndex: widget.tab, child: Scaffold(
      appBar: AppBar(title: const Text('ذوقك'), bottom: const TabBar(tabs: [Tab(text: '🗺 الخريطة'), Tab(text: '📈 عبر الزمن')])),
      body: TabBarView(children: [
        // ===== الخريطة =====
        favs.length < 3 ? const EmptyState(title: 'الخريطة تحتاج بيانات', body: 'حلّل ذوقك في «اكتشف» أولًا (3 مفضلات مرتبطة على الأقل).')
        : Column(children: [
          const Padding(padding: EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: Text('كل نقطة ممثلة، والنقاط المتقاربة خصائصها الموثّقة متقاربة (الشعر، العرق، العيون، الطول، العمر…). اضغط أي نقطة.', style: TextStyle(color: C.muted, fontSize: 12.5))),
          Padding(padding: const EdgeInsets.all(S.s2), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _legend(C.gold, 'مفضلاتك (${favs.length})'), const SizedBox(width: S.s4), _legend(C.rose, 'مقترحات (${rs.length})'),
          ])),
          Expanded(child: LayoutBuilder(builder: (c, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            Offset at(_Pt p) => Offset(size.width / 2 + p.x * (size.width / 2 - 28), size.height / 2 - p.y * (size.height / 2 - 28));
            return GestureDetector(
              onTapUp: (d) { _Pt? best; var bd = 26.0; for (final p in pts) { final dd = (at(p) - d.localPosition).distance; if (dd < bd) { bd = dd; best = p; } } setState(() => _sel = best); },
              child: CustomPaint(size: size, painter: _MapPainter(pts, at, _sel)));
          })),
          if (_sel != null) SafeArea(top: false, child: Container(margin: const EdgeInsets.all(S.s3), padding: const EdgeInsets.all(S.s3),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(S.rLg)),
            child: Row(children: [
              Icon(Icons.circle, size: 12, color: _sel!.fav ? C.gold : C.rose), const SizedBox(width: S.s2),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_sel!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_sel!.fav ? 'من مفضلاتك' : 'مقترحة · ${_sel!.rec!.pct}٪ · ${_sel!.rec!.why.isEmpty ? '' : _sel!.rec!.why.first}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
              ])),
              TextButton(onPressed: () => _sel!.fav ? context.push('/p/${_sel!.id}') : openCandidate(context, ref, _sel!.id, _sel!.rec!.why), child: const Text('افتح')),
            ]))),
        ]),
        // ===== عبر الزمن =====
        years.isEmpty ? const EmptyState(title: 'لا تاريخ بعد', body: 'يظهر هنا تطور ذوقك سنة بسنة: من أضفت من المفضلات وما شاهدت.')
        : ListView(padding: const EdgeInsets.all(S.s4), children: [
          const Text('كل سنة: المفضلات التي أضفتها (وأبرز ما يجمعهن) وما شاهدته (وأكثر الاستوديوهات).', style: TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(height: S.s3),
          for (final y in years.reversed) Container(margin: const EdgeInsets.only(bottom: S.s3), padding: const EdgeInsets.all(S.s3),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text('${y.year}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.gold2)), const Spacer(),
                Text('أضفت ${y.added} مفضلة · شاهدت ${y.watched} عملًا', style: const TextStyle(color: C.muted, fontSize: 12.5))]),
              if (y.traits.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, runSpacing: 6, children: [for (final t in y.traits) _chip(t, C.gold)])),
              if (y.studios.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, runSpacing: 6, children: [for (final s in y.studios) _chip(s, C.muted)])),
            ])),
        ]),
      ]),
    ));
  }

  static Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 10, color: c), const SizedBox(width: 4), Text(t, style: const TextStyle(fontSize: 12))]);
  static Widget _chip(String t, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: c.withValues(alpha: .5))), child: Text(t, style: const TextStyle(fontSize: 12)));
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.pts, this.at, this.sel);
  final List<_Pt> pts; final Offset Function(_Pt) at; final _Pt? sel;
  @override
  void paint(Canvas c, Size s) {
    final grid = Paint()..color = const Color(0x22FFFFFF)..strokeWidth = 1;
    c.drawLine(Offset(s.width / 2, 8), Offset(s.width / 2, s.height - 8), grid);
    c.drawLine(Offset(8, s.height / 2), Offset(s.width - 8, s.height / 2), grid);
    for (final p in pts.where((p) => !p.fav)) { c.drawCircle(at(p), 5, Paint()..color = C.rose.withValues(alpha: .75)); }
    for (final p in pts.where((p) => p.fav)) { c.drawCircle(at(p), 7, Paint()..color = C.gold); c.drawCircle(at(p), 7, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF1A1208)..strokeWidth = 1.5); }
    if (sel != null) { c.drawCircle(at(sel!), 13, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white); }
  }
  @override bool shouldRepaint(_MapPainter o) => o.pts != pts || o.sel != sel;
}
