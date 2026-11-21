import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../data/images.dart';
import '../../../data/keys.dart';
import '../../../data/sources.dart';
import '../../../domain/age_gate.dart';
import '../../../domain/performer.dart';
import '../../../domain/sanitize.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// البحث في المصادر الرسمية وإضافة ممثلة بنقرة: البيانات، الصورة، والأعمال.
/// بوابة +18: النتائج تُصفّى بالعمر **قبل** عرض أو تنزيل أي صورة.
class SourceSearchScreen extends ConsumerStatefulWidget {
  const SourceSearchScreen({super.key, this.initial = '', this.linkTo});
  final String initial; final String? linkTo; // linkTo: ربط ممثلة موجودة بدل الإضافة
  @override ConsumerState<SourceSearchScreen> createState() => _SourceSearchState();
}

class _SourceSearchState extends ConsumerState<SourceSearchScreen> {
  late final _q = TextEditingController(text: widget.initial);
  List<Candidate> _res = []; int _hidden = 0; String _err = ''; bool _busy = false; final Set<String> _adding = {};

  @override void initState() { super.initState(); if (widget.initial.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _search()); }
  @override void dispose() { _q.dispose(); super.dispose(); }

  Future<void> _search() async {
    final t = _q.text.trim(); if (t.length < 2) return;
    setState(() { _busy = true; _err = ''; });
    final hasS = await ApiKeys.has(ApiKeys.stash), hasT = await ApiKeys.has(ApiKeys.tpdb);
    if (!hasS && !hasT) { setState(() { _busy = false; _err = 'أضف مفتاح StashDB أو ThePornDB من «المزيد» أولًا.'; }); return; }
    final errs = <String>[]; final all = <Candidate>[];
    await Future.wait([
      if (hasS) StashDB.search(t).then(all.addAll).catchError((e) { errs.add('$e'); }),
      if (hasT) TPDB.search(t).then(all.addAll).catchError((e) { errs.add('$e'); }),
    ]);
    final adults = all.where((c) => c.adult).toList();   // ← البوابة قبل أي صورة
    if (!mounted) return;
    setState(() { _res = adults; _hidden = all.length - adults.length; _busy = false; _err = errs.join(' · '); });
  }

  Future<void> _add(Candidate c) async {
    if (!c.adult) return;
    setState(() => _adding.add('${c.source}:${c.id}'));
    try {
      final r = await addCandidate(ref, c, linkTo: widget.linkTo);
      _snack(r.$2);
      if (mounted && widget.linkTo != null && r.$1 != null) context.pop();
    } catch (e) { _snack('$e'); }
    finally { if (mounted) setState(() => _adding.remove('${c.source}:${c.id}')); }
  }

  void _snack(String m) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.linkTo != null ? 'ربط بمصدر' : 'إضافة من المصادر')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(S.s4), child: SearchBar(controller: _q, hintText: 'اسم الممثلة…', autoFocus: widget.initial.isEmpty, onSubmitted: (_) => _search(),
          leading: const Icon(Icons.travel_explore_rounded), trailing: [IconButton(onPressed: _search, icon: const Icon(Icons.arrow_back_rounded))],
          backgroundColor: const WidgetStatePropertyAll(C.surface), elevation: const WidgetStatePropertyAll(0), side: const WidgetStatePropertyAll(BorderSide(color: C.line2)))),
        if (_busy) const LinearProgressIndicator(),
        if (_err.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: S.s4), child: Text(_err, style: const TextStyle(color: C.danger))),
        if (_hidden > 0) Padding(padding: const EdgeInsets.all(S.s2), child: Text('أُخفيت $_hidden نتيجة: عمر أقل من 18 أو تاريخ ميلاد غير صالح.', style: const TextStyle(color: C.muted, fontSize: 12))),
        Expanded(child: _res.isEmpty && !_busy
          ? const EmptyState(title: 'ابحث في المصادر الرسمية', body: 'StashDB وThePornDB فقط. تُضاف الممثلة مع صورتها وأعمالها، وتُحفظ الصورة على جهازك.')
          : ListView.separated(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, 120), itemCount: _res.length, separatorBuilder: (_, _) => const SizedBox(height: S.s2), itemBuilder: (c, i) {
              final r = _res[i]; final a = sdAge(r.birth).age;
              final have = lib.any((p) => (r.source == 'stash' ? p.stashId : p.pdbId) == r.id);
              final busy = _adding.contains('${r.source}:${r.id}');
              return Card(child: Padding(padding: const EdgeInsets.all(S.s2), child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(S.rSm), child: SizedBox(width: 72, height: 96, child: Photo(r.image, name: r.name, cacheWidth: 200))),
                const SizedBox(width: S.s3),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (r.aliases.isNotEmpty) Text(r.aliases, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
                  Text([if (a != null) '$a سنة' else 'العمر غير معروف', if (r.country.isNotEmpty) r.country, r.source == 'stash' ? 'StashDB' : 'ThePornDB'].join(' · '), style: const TextStyle(color: C.muted, fontSize: 12.5)),
                ])),
                busy ? const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)))
                  : have && widget.linkTo == null ? const Icon(Icons.check_circle_rounded, color: C.ok)
                  : FilledButton.tonal(onPressed: () => _add(r), child: Text(widget.linkTo != null ? 'ربط' : 'إضافة')),
              ])));
            })),
      ]),
    );
  }
}

/// تحديث أعمال ممثلة من مصادرها المرتبطة (بوابة +18 قبل الطلب).
Future<String> refreshFromSources(WidgetRef ref, Performer p) async {
  if (p.isMinor) return 'مرفوض: العمر أقل من 18';
  if (p.stashId.isEmpty && p.pdbId.isEmpty) return 'غير مرتبطة بمصدر — استخدم «ربط بمصدر»';
  var works = p.works; var added = 0; final errs = <String>[];
  if (p.stashId.isNotEmpty) { try { final m = mergeWorks(works, await StashDB.scenes(p.stashId)); works = m.list; added += m.added; } catch (e) { errs.add('$e'); } }
  if (p.pdbId.isNotEmpty) { try { final m = mergeWorks(works, await TPDB.scenes(p.pdbId)); works = m.list; added += m.added; } catch (e) { errs.add('$e'); } }
  final cur = ref.read(libraryProvider.notifier).items.where((x) => x.id == p.id).firstOrNull ?? p;   // السجل الحالي لا اللقطة القديمة
  await ref.read(libraryProvider.notifier).upsert(cur.copyWith({'works': mergeWorks(cur.works, works).list, 'worksAt': DateTime.now().millisecondsSinceEpoch}));
  return errs.isEmpty ? (added > 0 ? 'أُضيف $added عمل جديد' : 'لا أعمال جديدة') : '${added > 0 ? 'أُضيف $added عمل · ' : ''}${errs.join(' · ')}';
}

/// إضافة مرشحة من مصدر رسمي إلى المكتبة (أو ربطها بسجل موجود): الصورة تُنزّل بدقتها الأصلية، والأعمال تُدمج.
/// البوابة: يُرفض أي سجل تاريخه يقول أقل من 18. يعيد (السجل المحفوظ، رسالة).
Future<(Performer?, String)> addCandidate(WidgetRef ref, Candidate c, {String? linkTo, List<String> extraImages = const []}) async {
  if (!c.adult) return (null, 'رُفضت: العمر أقل من 18 أو تاريخ غير صالح');
  final lib = ref.read(libraryProvider.notifier);
  final existing = linkTo != null ? lib.items.where((p) => p.id == linkTo).firstOrNull
      : lib.items.where((p) => (c.source == 'stash' ? p.stashId : p.pdbId) == c.id || norm(p.name) == norm(c.name)).firstOrNull;
  final id = existing?.id ?? const Uuid().v4();
  final photos = [...?existing?.photos];
  for (final u in [c.image, ...extraImages].where((u) => u.isNotEmpty).toSet().take(6)) {
    if (photos.length >= 30) break;
    photos.add(await downloadPhoto(u, '${id}_${DateTime.now().microsecondsSinceEpoch}'));
  }
  var works = existing?.works ?? <Map<String, dynamic>>[];
  var added = 0;
  try {
    final sc = c.source == 'stash' ? await StashDB.scenes(c.id) : await TPDB.scenes(c.id);
    final m = mergeWorks(works, sc); works = m.list; added = m.added;
  } catch (_) {}
  final base = existing?.raw ?? {'id': id, 'added': DateTime.now().millisecondsSinceEpoch, 'tags': [], 'lists': [], 'source': c.source == 'stash' ? 'StashDB' : 'ThePornDB'};
  // السجل الحالي بعد انتهاء الجلب (قد يكون عُدّل أثناءه) — لا يُستبدل بلقطة قديمة
  final now0 = existing == null ? null : lib.items.where((x) => x.id == existing.id).firstOrNull;
  if (now0 != null) { works = mergeWorks(now0.works, works).list; for (final ph in now0.photos) { if (!photos.contains(ph)) photos.insert(0, ph); } }
  final p = Performer({...(now0?.raw ?? base), 'name': now0?.name ?? existing?.name ?? c.name, if ((existing?.aliases ?? '').isEmpty && c.aliases.isNotEmpty) 'aliases': c.aliases,
    if ((existing?.birth ?? '').isEmpty && c.birth.isNotEmpty) 'birth': c.birth, if ((existing?.country ?? '').isEmpty && c.country.isNotEmpty) 'country': c.country,
    if (c.height != null) 'height': c.height, if (c.careerStart != null) 'cs': c.careerStart,
    c.source == 'stash' ? 'stashId' : 'pdbId': c.id, 'photos': photos, 'works': works, 'worksAt': DateTime.now().millisecondsSinceEpoch, 'updated': DateTime.now().millisecondsSinceEpoch});
  if (p.isMinor) return (null, 'رُفضت: العمر أقل من 18');
  await lib.upsert(p);
  return (p, '${existing == null ? 'أُضيفت' : 'رُبطت'} ${p.name} · $added عمل');
}
