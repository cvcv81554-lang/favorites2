import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/background.dart';
import '../../data/sources.dart';
import '../../domain/performer.dart';
import '../features/discover/taste_state.dart';
import '../features/reels/reel_center.dart';
import '../features/studio/studio_screen.dart';
import '../../data/privacy.dart';
import 'home_widget_sync.dart';
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
  // مرشحات جديدة قريبة من ذوقك (وجدتها الخلفية) ⇒ مسار «جديد قريب من ذوقك» في «اكتشف»
  final recs = [for (final r in rs) ...r.recs];
  if (recs.isNotEmpty) { try { await ref.read(tasteProvider.notifier).addNew([for (final j in recs) TasteRec.fromJson(j)]); } catch (_) {} }
  await (await ref.read(repoProvider.future)).kvSet('bg_last', {'at': DateTime.now().millisecondsSinceEpoch, 'works': works, 'photos': photos, 'recs': recs.length});
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
      await rescheduleReminders(ref);
      await refreshHomeWidget(ref);
      // المقاطع: وضع اللحاق (إن صارت الشبكة تصل لخوادم محجوبة) ثم التحميل المسبق على Wi-Fi — بعد هدوء بدء التشغيل
      Future<void>.delayed(const Duration(seconds: 15), () async {
        if (!mounted) return;
        final p = ref.read(prefetchProvider.notifier);
        final opened = await p.catchUp();
        if (opened == 0) await p.run();
        if (opened > 0 && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('شبكتك الآن تصل إلى $opened خادمًا كان محجوبًا — نحمّل مقاطعه لتعمل لاحقًا بدونه')));
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // أي تغيير في المكتبة ⇒ تحديث مدخلات الخلفية بعد هدوء
    ref.listen(libraryProvider, (_, n) { if (kIsWeb) return; _t?.cancel(); _t = Timer(const Duration(seconds: 10), () { final v = n.value; if (v != null) { writeInput(ref, lib: v); rescheduleReminders(ref); refreshHomeWidget(ref); } }); });
    return widget.child;
  }
}

Future<void> writeInput(WidgetRef ref, {required List<Performer> lib}) async {
  final repo = await ref.read(repoProvider.future);
  final s = BgSettings.fromJson(await repo.kvGet('bg') as Map?);
  final ids = {for (final x in await (await ref.read(studioRepoProvider.future)).all()) x.id};
  await writeBgInput(s, lib, ids, taste: await tasteInput(ref));
}

/// ما تحتاجه الخلفية لكشف «ممثلة جديدة قريبة من ذوقك»: ملف الذوق المحفوظ + التعلّم + المخفيات.
Future<Map<String, dynamic>?> tasteInput(WidgetRef ref) async {
  final repo = await ref.read(repoProvider.future);
  final prof = await repo.kvGet('taste_prof');
  if (prof == null) return null;
  return {'prof': prof, 'fb': await repo.kvGet('taste_fb') ?? {}, 'hidden': await repo.kvGet('recs_hidden') ?? []};
}

/// إعادة جدولة تذكيرات إصدارات المفضلات حسب الإعدادات (عند الفتح وكل تغيّر في المكتبة).
Future<int> rescheduleReminders(WidgetRef ref) async {
  if (kIsWeb) return 0;
  final repo = await ref.read(repoProvider.future);
  final s = BgSettings.fromJson(await repo.kvGet('bg') as Map?);
  try { return await scheduleReleaseReminders(ref.read(libraryProvider).value ?? const [], s); } catch (_) { return 0; }
}

/// تحديث ويدجت الشاشة الرئيسية. خاص (بلا صورة ولا اسم) إن اخترت ذلك أو كان قفل التطبيق مفعّلًا.
Future<void> refreshHomeWidget(WidgetRef ref) async {
  if (kIsWeb) return;
  final repo = await ref.read(repoProvider.future);
  final priv = (await repo.kvGet('widget_private')) == true || await Privacy.hasPin();
  await syncHomeWidget(ref.read(libraryProvider).value ?? const [], private: priv);
}
