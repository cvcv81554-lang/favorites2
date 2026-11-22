import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/studio_repo.dart';
import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'studio_screen.dart';

/// الفرز السريع للصور الجديدة: اسحب يسارًا = إعجاب ♥، يمينًا = تخطٍّ، لأعلى = إخفاء — أو بالأزرار، مع تراجع.
class SwipeSortScreen extends ConsumerStatefulWidget {
  const SwipeSortScreen({super.key});
  @override ConsumerState<SwipeSortScreen> createState() => _SwipeSortState();
}

class _SwipeSortState extends ConsumerState<SwipeSortScreen> {
  List<StudioImg>? _queue; int _i = 0; Offset _drag = Offset.zero;
  final _history = <(StudioImg, int, bool, bool)>[];   // للتراجع: (الصورة، seen، like، hid) قبل القرار
  int _liked = 0, _hidden = 0;

  void _init(List<StudioImg> all, Map<String, Performer> lib) {
    _queue ??= (all.where((x) => x.seen == 0 && !x.hid && lib.containsKey(x.pid)).toList()..sort((a, b) => b.found.compareTo(a.found)));
  }

  Future<void> _decide(String act) async {
    final q = _queue!; if (_i >= q.length) return;
    final x = q[_i]; _history.add((x, x.seen, x.like, x.hid));
    HapticFeedback.selectionClick();
    final n = ref.read(studioProvider.notifier);
    if (act == 'like') { await n.sortAs(x, like: true); _liked++; }
    else if (act == 'hide') { await n.sortAs(x, hid: true); _hidden++; }
    else { await n.sortAs(x); }
    if (mounted) setState(() { _i++; _drag = Offset.zero; });
  }

  Future<void> _undo() async {
    if (_history.isEmpty) return;
    final h = _history.removeLast();
    if (h.$1.like && !h.$3) _liked--;
    if (h.$1.hid && !h.$4) _hidden--;
    await ref.read(studioProvider.notifier).restore(h.$1, seen: h.$2, like: h.$3, hid: h.$4);
    if (mounted) setState(() { _i = (_i - 1).clamp(0, _queue!.length); _drag = Offset.zero; });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(studioProvider).value;
    final lib = {for (final p in ref.watch(libraryProvider).value ?? const <Performer>[]) if (!p.isMinor) p.id: p};
    if (st != null) _init(st.imgs, lib);
    final q = _queue ?? const <StudioImg>[];
    final done = _i >= q.length;
    final w = MediaQuery.sizeOf(context).width;
    String? hint() => _drag.dy < -60 && _drag.dy.abs() > _drag.dx.abs() ? 'إخفاء' : _drag.dx < -50 ? 'إعجاب ♥' : _drag.dx > 50 ? 'تخطٍّ' : null;
    return Scaffold(
      appBar: AppBar(title: Text(q.isEmpty ? 'فرز سريع' : 'فرز سريع · ${(_i + 1).clamp(0, q.length)} / ${q.length}'),
        actions: [IconButton(tooltip: 'تراجع', onPressed: _history.isEmpty ? null : _undo, icon: const Icon(Icons.undo_rounded))]),
      body: q.isEmpty ? const EmptyState(title: 'لا صور جديدة للفرز', body: 'كل الصور الجديدة فُرزت. ابحث عن صور جديدة في الاستديو ثم عد.')
        : done ? EmptyState(title: 'انتهيت ✓', body: 'أعجبتك $_liked · أخفيت $_hidden · والباقي عُلّم «شوهد».', actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع للاستديو'))])
        : Column(children: [
          const Padding(padding: EdgeInsets.fromLTRB(S.s4, S.s2, S.s4, 0), child: Text('اسحب يسارًا للإعجاب ♥ · يمينًا للتخطي · لأعلى للإخفاء', style: TextStyle(color: C.muted, fontSize: 12.5))),
          Expanded(child: Padding(padding: const EdgeInsets.all(S.s4), child: Stack(children: [
            if (_i + 1 < q.length) Positioned.fill(child: Transform.scale(scale: .94, child: Opacity(opacity: .5, child: ClipRRect(borderRadius: BorderRadius.circular(S.rXl), child: Photo(q[_i + 1].thumb, alignment: Alignment.center))))),
            Positioned.fill(child: GestureDetector(
              onPanUpdate: (d) => setState(() => _drag += d.delta),
              onPanEnd: (_) { final h = hint(); if (h == null) { setState(() => _drag = Offset.zero); return; } _decide(h.startsWith('إعجاب') ? 'like' : h == 'إخفاء' ? 'hide' : 'skip'); },
              child: Transform.translate(offset: _drag, child: Transform.rotate(angle: _drag.dx / w * .25, child: ClipRRect(borderRadius: BorderRadius.circular(S.rXl), child: Stack(fit: StackFit.expand, children: [
                Container(color: Colors.black),
                Photo(q[_i].url, fit: BoxFit.contain, alignment: Alignment.center, fallbacks: [q[_i].wide]),
                Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(S.s3, 24, S.s3, S.s3),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)])),
                  child: Text(lib[q[_i].pid]?.name ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)))),
                if (hint() != null) Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: const Color(0xCC0A0810), borderRadius: BorderRadius.circular(99)),
                  child: Text(hint()!, style: TextStyle(color: hint()!.startsWith('إعجاب') ? C.rose : hint() == 'إخفاء' ? C.danger : Colors.white, fontSize: 22, fontWeight: FontWeight.w800)))),
              ])))))),
          ]))),
          SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s3), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _btn(Icons.visibility_off_rounded, 'إخفاء', C.danger, () => _decide('hide')),
            _btn(Icons.favorite_rounded, 'إعجاب', C.rose, () => _decide('like'), big: true),
            _btn(Icons.skip_next_rounded, 'تخطٍّ', C.muted, () => _decide('skip')),
          ]))),
        ]),
    );
  }

  Widget _btn(IconData i, String t, Color c, VoidCallback f, {bool big = false}) => Column(mainAxisSize: MainAxisSize.min, children: [
    IconButton.filledTonal(iconSize: big ? 34 : 26, onPressed: f, icon: Icon(i, color: c)), Text(t, style: const TextStyle(fontSize: 12)),
  ]);
}
