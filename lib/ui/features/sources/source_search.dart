import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../data/dual_source.dart';
import '../../../data/photo_hash.dart';
import '../../../data/platform/db_factory.dart' show deletePhoto;
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
  List<Candidate> _res = []; final Map<String, Candidate> _twin = {}; int _hidden = 0; String _err = ''; bool _busy = false; final Set<String> _adding = {};

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
    // نفس الممثلة في المصدرين ⇒ نتيجة واحدة (مطابقة محافظة: الاسم + تاريخ الميلاد)
    final ss = adults.where((c) => c.source == 'stash').toList(), ts = adults.where((c) => c.source == 'tpdb').toList();
    final used = <Candidate>{}; final res = <Candidate>[]; _twin.clear();
    for (final s in ss) {
      final m = ts.where((t) => !used.contains(t) && samePerson(s, t)).toList();
      if (m.length == 1) { used.add(m.first); _twin['stash:${s.id}'] = m.first; }
      res.add(s);
    }
    res.addAll(ts.where((t) => !used.contains(t)));
    setState(() { _res = res; _hidden = all.length - adults.length; _busy = false; _err = errs.join(' · '); });
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
          ? const EmptyState(title: 'ابحث في المصدرين معًا', body: 'StashDB وThePornDB معًا: تُجمع المعلومات والأعمال والصور من الاثنين وتُحذف المكررات، وتُحفظ الصور على جهازك.')
          : ListView.separated(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, 120), itemCount: _res.length, separatorBuilder: (_, _) => const SizedBox(height: S.s2), itemBuilder: (c, i) {
              final r = _res[i]; final a = sdAge(r.birth).age;
              final tw = _twin['${r.source}:${r.id}'];
              final have = lib.any((p) => (r.source == 'stash' ? p.stashId : p.pdbId) == r.id || (tw != null && p.pdbId == tw.id));
              final busy = _adding.contains('${r.source}:${r.id}');
              return Card(child: Padding(padding: const EdgeInsets.all(S.s2), child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(S.rSm), child: SizedBox(width: 72, height: 96, child: Photo(r.image, name: r.name, cacheWidth: 200))),
                const SizedBox(width: S.s3),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (r.aliases.isNotEmpty) Text(r.aliases, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
                  Text([if (a != null) '$a سنة' else 'العمر غير معروف', if (r.country.isNotEmpty) r.country, tw != null ? 'StashDB + ThePornDB' : r.source == 'stash' ? 'StashDB' : 'ThePornDB'].join(' · '), style: const TextStyle(color: C.muted, fontSize: 12.5)),
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

/// تحديث ممثلة من المصدرين معًا (معلومات + أعمال + صور، بلا تكرار). بوابة +18 قبل أي طلب صور/أعمال.
Future<String> refreshFromSources(WidgetRef ref, Performer p, {void Function(String)? progress}) async {
  if (p.isMinor) return 'مرفوض: العمر أقل من 18';
  if (p.stashId.isEmpty && p.pdbId.isEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(p.birth)) return 'غير مرتبطة بمصدر — استخدم «ربط بمصدر»';
  return (await syncFromSources(ref, existing: p, progress: progress)).$2;
}

/// إضافة مرشحة من أي مصدر — تُجلب من المصدرين معًا وتُدمج بلا تكرار. يعيد (السجل المحفوظ، رسالة).
Future<(Performer?, String)> addCandidate(WidgetRef ref, Candidate c, {String? linkTo, List<String> extraImages = const [], void Function(String)? progress}) =>
  syncFromSources(ref, c: c, linkTo: linkTo, extraImages: extraImages, progress: progress);

/// المسار الموحّد للإضافة والربط والتحديث في كل التطبيق:
/// 1) يحدد المعرّفين (StashDB وThePornDB) ويبحث عن الممثلة نفسها في المصدر الآخر بمطابقة محافظة (الاسم + تاريخ الميلاد).
/// 2) يجلب من الاثنين: المعلومات ⇒ بوابة +18 ⇒ الأعمال والصور.
/// 3) يدمج بلا تكرار: الأعمال (بالمعرّف ثم العنوان/الاستوديو/التاريخ)، والصور (بالرابط والبايتات والبصمة المرئية — الأوضح يبقى)،
///    والمعلومات تملأ الناقص فقط — لا تُستبدل بياناتك ولا تُحذف تقييماتك أو مشاهداتك أو ملاحظاتك.
/// [deep]: البحث عن كل سجلاتها بكل أسمائها (يُتخطى في التحديث الجماعي إن بُحث خلال آخر 30 يومًا).
Future<(Performer?, String)> syncFromSources(WidgetRef ref, {Performer? existing, Candidate? c, String? linkTo, List<String> extraImages = const [], void Function(String)? progress, bool deep = true}) async {
  if (c != null && !c.adult) return (null, 'رُفضت: العمر أقل من 18 أو تاريخ غير صالح');
  final lib = ref.read(libraryProvider.notifier);
  Performer? base = existing ?? (linkTo != null ? lib.items.where((p) => p.id == linkTo).firstOrNull : null);
  var sid = base?.stashId ?? '', pid = base?.pdbId ?? '';
  if (c != null) { if (c.source == 'stash') { sid = c.id; } else { pid = c.id; } }
  Performer? match() => lib.items.where((p) => (sid.isNotEmpty && p.stashId == sid) || (pid.isNotEmpty && p.pdbId == pid)).firstOrNull;
  base ??= match() ?? (c == null ? null : lib.items.where((p) => norm(p.name) == norm(c.name) && (p.birth.isEmpty || c.birth.isEmpty || p.birth.startsWith(c.birth.length >= 10 ? c.birth.substring(0, 10) : c.birth))).firstOrNull);
  if (base != null) { if (sid.isEmpty) sid = base.stashId; if (pid.isEmpty) pid = base.pdbId; }
  if (base != null && base.isMinor) return (null, 'مرفوض: العمر أقل من 18');
  // كل سجلاتها في المصدرين (بالاسم وكل أسمائها الأخرى)
  var sIds = <String>{if (sid.isNotEmpty) sid, ...?base?.stashIds}, tIds = <String>{if (pid.isNotEmpty) pid, ...?base?.pdbIds};
  final recent = DateTime.now().millisecondsSinceEpoch - ((base?.raw['linkedAt'] as num?) ?? 0) < 30 * 86400000;
  if (deep || !recent || sIds.isEmpty || tIds.isEmpty) {
    final noId = sid.isEmpty && pid.isEmpty;
    final probe = c ?? Candidate(source: sid.isNotEmpty ? 'stash' : pid.isNotEmpty ? 'tpdb' : 'name', id: sid.isNotEmpty ? sid : pid, name: base?.name ?? '', aliases: base?.aliases ?? '', birth: base?.birth ?? '', country: base?.country ?? '');
    // ممثلة بلا أي معرّف: الربط بالاسم وحده خطر الخلط ⇒ لا بد من تاريخ ميلاد كامل مطابق
    if (probe.name.isNotEmpty && (!noId || RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(probe.birth))) {
      final all = await findAllRecords(probe, progress: progress);
      bool ok(Candidate x) => !noId || x.birth.startsWith(probe.birth.substring(0, 10));
      sIds.addAll(all.stash.where(ok).map((x) => x.id)); tIds.addAll(all.tpdb.where(ok).map((x) => x.id));
    }
  }
  if (sid.isEmpty && sIds.isNotEmpty) sid = sIds.first;
  if (pid.isEmpty && tIds.isNotEmpty) pid = tIds.first;
  base ??= match();
  if (sid.isEmpty && pid.isEmpty) return (null, base != null && base.birth.length < 10 ? 'غير مرتبطة بمصدر — استخدم «ربط بمصدر» (أو أضف تاريخ ميلادها الكامل للربط التلقائي)' : 'لم تُعثر عليها في StashDB ولا ThePornDB');
  progress?.call('جلب كل المعلومات والأعمال والصور من ${sIds.length + tIds.length} سجل…');
  final d = await fetchBoth(stashId: sid, pdbId: pid, moreStash: sIds.toList(), morePdb: tIds.toList());
  if (d.minor) return (null, 'رُفضت: العمر أقل من 18 أو تاريخ غير صالح');
  if (d.sources.isEmpty) return (null, d.errors.isEmpty ? 'أضف مفتاح StashDB أو ThePornDB من «المزيد»' : d.errors.join(' · '));
  final id = base?.id ?? const Uuid().v4();
  // الصور: إزالة المكرر الموجود ثم إضافة الجديد بلا تكرار
  progress?.call('الصور (بلا تكرار)…');
  final (clean, removedP) = await dedupePhotos(base?.photos ?? const []);
  final imgs = [if (c != null && c.image.isNotEmpty) c.image, ...extraImages, ...d.images];
  final (photos0, addedP, dupP, replaced) = await addPhotosNoDup(clean, imgs, id, maxNew: base == null ? 6 : 4);
  // الأعمال: إزالة المكرر الموجود ثم دمج المصدرين
  final w0 = dedupeWorks(base?.works ?? const []);
  final m = mergeWorks(w0.list, d.works);
  // السجل الحالي بعد انتهاء الجلب (قد يكون عُدّل أثناءه) — لا يُستبدل بلقطة قديمة
  final now0 = base == null ? null : lib.items.where((x) => x.id == base!.id).firstOrNull;
  var works = m.list; final photos = [...photos0];
  if (now0 != null) {
    works = mergeWorks(dedupeWorks(now0.works).list, works).list;
    for (final ph in now0.photos) { if (!photos.contains(ph) && !removedP.contains(ph) && !replaced.contains(ph)) photos.add(ph); }
  }
  final cur = now0 ?? base;
  String keep(String k, String v) => '${cur?.raw[k] ?? ''}'.isNotEmpty ? '${cur!.raw[k]}' : v;
  final aliases = <String>{for (final a in '${cur?.aliases ?? ''}, ${d.info['aliases'] ?? ''}${c != null ? ', ${c.aliases}' : ''}'.split(',')) if (a.trim().isNotEmpty && norm(a) != norm(cur?.name ?? c?.name ?? '')) a.trim()}.join(', ');
  final p = Performer({
    ...(cur?.raw ?? {'id': id, 'added': DateTime.now().millisecondsSinceEpoch, 'tags': [], 'lists': [], 'source': d.sources.join(' + ')}),
    'name': cur?.name ?? c?.name ?? '',
    if (aliases.isNotEmpty) 'aliases': aliases,
    'birth': keep('birth', '${d.info['birth'] ?? c?.birth ?? ''}'),
    'country': keep('country', '${d.info['country'] ?? c?.country ?? ''}'),
    if (cur?.raw['height'] == null && (d.info['height'] ?? c?.height) != null) 'height': d.info['height'] ?? c?.height,
    if (cur?.raw['cs'] == null && (d.info['cs'] ?? c?.careerStart) != null) 'cs': d.info['cs'] ?? c?.careerStart,
    if (sid.isNotEmpty) 'stashId': sid, if (pid.isNotEmpty) 'pdbId': pid,
    if (d.stashIds.length > 1) 'stashIds': d.stashIds, if (d.pdbIds.length > 1) 'pdbIds': d.pdbIds,
    'linkedAt': DateTime.now().millisecondsSinceEpoch,
    'photos': photos, 'works': works, 'worksAt': DateTime.now().millisecondsSinceEpoch, 'updated': DateTime.now().millisecondsSinceEpoch,
  });
  if (p.isMinor) return (null, 'رُفضت: العمر أقل من 18');
  await lib.upsert(p);
  for (final r in {...removedP, ...replaced}) { if (!photos.contains(r)) { try { await deletePhoto(r); } catch (_) {} } }   // ملفات المكرر فقط
  final dups = w0.removed + removedP.length + dupP;
  return (p, [
    '${cur == null ? 'أُضيفت' : 'حُدّثت'} ${p.name}',
    '${d.sources.join(' + ')} (${d.stashIds.length + d.pdbIds.length} سجل)',
    '${m.added} عمل جديد',
    if (addedP > 0) '$addedP صورة',
    if (dups > 0) 'حُذف $dups مكرر',
    if (d.errors.isNotEmpty) d.errors.join(' · '),
  ].join(' · '));
}
