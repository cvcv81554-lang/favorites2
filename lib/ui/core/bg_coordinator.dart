import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/background.dart';
import '../../data/sources.dart';
import '../../domain/performer.dart';
import '../features/studio/studio_screen.dart';
import 'state.dart';

/// يدمج نتائج الجلب في **السجلات الحالية** (لا يضيع تعديل حدث أثناء الجلب) ويضيف الصور الجديدة فقط.
/// البوابة: لا يُكتب شيء لسجل قاصر.
Future<({int works, int photos})> applyFetch(WidgetRef ref, List<FetchResult> rs) async {
  final lib = ref.read(libraryProvider.notifier);
  final cur = {for (final p in lib.items) p.id: p};
  final changed = <String, Performer>{}; var works = 0;
  for (final r in rs) {
    r.works.forEach((pid, ws) {
      final p = changed[pid] ?? cur[pid]; if (p == null || p.isMinor) return;
      final m = mergeWorks(p.works, ws); if (m.added == 0) return;
      works += m.added; changed[pid] = p.copyWith({'works': m.list, 'worksAt': DateTime.now().millisecondsSinceEpoch});
    });
  }
  if (changed.isNotEmpty) await lib.upsertMany(changed.values.toList());
  var photos = 0;
  final imgs = [for (final r in rs) ...r.images.where((x) => cur.containsKey(x.pid) && !(cur[x.pid]!.isMinor))];
  if (imgs.isNotEmpty) {
    final sr = await ref.read(studioRepoProvider.future);
    final have = {for (final x in await sr.all()) x.id};
    final fresh = imgs.where((x) => !have.contains(x.id)).toList();   // لا يُستبدل سجل موجود (الإعجاب والألبومات تبقى)
    if (fresh.isNotEmpty) { await sr.put(fresh); photos = fresh.length; ref.invalidate(studioProvider); }
  }
  await (await ref.read(repoProvider.future)).kvSet('bg_last', {'at': DateTime.now().millisecondsSinceEpoch, 'works': works, 'photos': photos});
  return (works: works, photos: photos);
}

/// عند الفتح والعودة: يدمج ما جلبته مهمة الخلفية، ويحدّث ملف مدخلاتها (البالغات فقط).
class BgCoordinator extends ConsumerStatefulWidget {
  const BgCoordinator({super.key, required this.child});
  final Widget child;
  @override ConsumerState<BgCoordinator> createState() => _BgCoordinatorState();
}

class _BgCoordinatorState extends ConsumerState<BgCoordinator> with WidgetsBindingObserver {
  Timer? _t;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); if (!kIsWeb) Future<void>.delayed(const Duration(seconds: 3), _sync); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _t?.cancel(); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed && !kIsWeb) _sync(); }

  Future<void> _sync() async {
    try {
      final lib = await ref.read(libraryProvider.future);
      final pending = await takePendingResults();
      if (pending.isNotEmpty && mounted) {
        final r = await applyFetch(ref, pending);
        if (mounted && (r.works > 0 || r.photos > 0)) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('وصل في الخلفية: ${r.works} عمل · ${r.photos} صورة')));
      }
      await writeInput(ref, lib: ref.read(libraryProvider).value ?? lib);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // أي تغيير في المكتبة ⇒ تحديث مدخلات الخلفية بعد هدوء
    ref.listen(libraryProvider, (_, n) { if (kIsWeb) return; _t?.cancel(); _t = Timer(const Duration(seconds: 10), () { final v = n.value; if (v != null) writeInput(ref, lib: v); }); });
    return widget.child;
  }
}

Future<void> writeInput(WidgetRef ref, {required List<Performer> lib}) async {
  final repo = await ref.read(repoProvider.future);
  final s = BgSettings.fromJson(await repo.kvGet('bg') as Map?);
  final ids = {for (final x in await (await ref.read(studioRepoProvider.future)).all()) x.id};
  await writeBgInput(s, lib, ids);
}
