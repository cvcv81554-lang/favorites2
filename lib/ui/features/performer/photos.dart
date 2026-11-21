import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/platform/db_factory.dart';
import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// عارض صور الممثلة بملء الشاشة: سحب، تكبير بالقرص، تعيين رئيسية، حذف.
Future<void> openPhotoViewer(BuildContext context, WidgetRef ref, Performer p, int start) => Navigator.of(context).push(PageRouteBuilder(
  opaque: false, barrierColor: Colors.black, transitionDuration: S.med,
  pageBuilder: (c, a, _) => FadeTransition(opacity: a, child: _PhotoViewer(id: p.id, start: start))));

class _PhotoViewer extends ConsumerStatefulWidget {
  const _PhotoViewer({required this.id, required this.start});
  final String id; final int start;
  @override ConsumerState<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<_PhotoViewer> {
  late final _pc = PageController(initialPage: widget.start);
  late int _i = widget.start;
  @override void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = performerById(ref, widget.id);
    if (p == null || p.photos.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final ph = p.photos; final i = _i.clamp(0, ph.length - 1);
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      PageView.builder(controller: _pc, itemCount: ph.length, onPageChanged: (x) => setState(() => _i = x),
        itemBuilder: (c, k) => InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: Photo(ph[k], name: p.name, fit: BoxFit.contain, alignment: Alignment.center, full: true)))),
      SafeArea(child: Padding(padding: const EdgeInsets.all(S.s2), child: Row(children: [
        IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        Expanded(child: Text('${p.name} · ${i + 1}/${ph.length}', style: const TextStyle(color: Colors.white))),
        if (i > 0) IconButton(tooltip: 'اجعلها الرئيسية', onPressed: () async { await setMainPhoto(ref, p, i); _pc.jumpToPage(0); setState(() => _i = 0); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أصبحت الصورة الرئيسية'))); }, icon: const Icon(Icons.star_rounded, color: C.gold)),
        IconButton(tooltip: 'حذف الصورة', onPressed: () async {
          final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('حذف الصورة؟'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
          if (ok != true) return;
          await removePhoto(ref, p, i);
          if (!context.mounted) return;
          if (ph.length <= 1) { Navigator.pop(context); } else { setState(() => _i = max(0, i - 1)); }
        }, icon: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
      ]))),
    ]));
  }
}

Future<void> setMainPhoto(WidgetRef ref, Performer p, int i) async {
  final ph = [...p.photos]; final x = ph.removeAt(i); ph.insert(0, x);
  await ref.read(libraryProvider.notifier).upsert(p.copyWith({'photos': ph, 'thumb': x}));
}

Future<void> removePhoto(WidgetRef ref, Performer p, int i) async {
  final ph = [...p.photos]; final x = ph.removeAt(i);
  final th = p.thumb == x || p.thumb.isEmpty ? (ph.isNotEmpty ? ph.first : '') : p.thumb;
  await ref.read(libraryProvider.notifier).upsert(p.copyWith({'photos': ph, 'thumb': th}));
  if (x.startsWith('file:') && !ph.contains(x)) await deletePhoto(x);
}

/// إضافة صور من معرض الجهاز (حتى 30 صورة لكل ممثلة). تُصغَّر إلى 1800 بكسل وتُحفظ ملفات على الجهاز.
Future<int> addPhotosFromGallery(WidgetRef ref, Performer p) async {
  final room = 30 - p.photos.length; if (room <= 0) return -1;
  final files = await ImagePicker().pickMultiImage(maxWidth: 1800, maxHeight: 1800, imageQuality: 88, limit: room > 1 ? room : null);
  if (files.isEmpty) return 0;
  final refs = <String>[];
  for (final f in files.take(room)) {
    final b = await f.readAsBytes();
    final ext = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    refs.add(await storePhotoBytes('${p.id}_${DateTime.now().microsecondsSinceEpoch}.$ext', b));
  }
  final cur = ref.read(libraryProvider.notifier).items.where((x) => x.id == p.id).firstOrNull ?? p;
  final ph = [...cur.photos, ...refs];
  await ref.read(libraryProvider.notifier).upsert(cur.copyWith({'photos': ph, if (cur.thumb.isEmpty) 'thumb': ph.first}));
  return refs.length;
}
