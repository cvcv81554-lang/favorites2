import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/faces.dart';
import '../../../data/platform/native_bridge.dart';
import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../performer/photos.dart' show removePhoto;

/// بوابة نموذج الوجوه: إن لم يُنزَّل بعد ⇒ شرح + تنزيل (130 م.ب، مرة واحدة)؛ وإلا يعرض [child].
class _ModelGate extends StatefulWidget {
  const _ModelGate({required this.child});
  final Widget child;
  @override State<_ModelGate> createState() => _ModelGateState();
}
class _ModelGateState extends State<_ModelGate> {
  String _st = ''; double? _p; bool _fail = false;
  @override void initState() { super.initState(); Faces.status().then((s) { if (mounted) setState(() => _st = s); }); }
  Future<void> _install() async {
    setState(() { _p = 0; _fail = false; });
    final ok = await Faces.install(onProgress: (x) { if (mounted) setState(() => _p = x); });
    if (!mounted) return;
    setState(() { _p = null; _fail = !ok; if (ok) _st = 'ready'; });
  }
  @override
  Widget build(BuildContext context) {
    if (_st == 'ready') return widget.child;
    if (_st.isEmpty) return const Center(child: CircularProgressIndicator());
    return Center(child: Padding(padding: const EdgeInsets.all(S.s5), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.face_retouching_natural_rounded, size: 56, color: C.gold),
      const SizedBox(height: S.s3),
      const Text('تمييز الوجوه', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: S.s2),
      Text(_st == 'unsupported' ? 'تمييز الوجوه يعمل على الآيفون فقط.'
        : 'يحتاج نموذج تمييز الوجوه (AuraFace، ترخيص Apache-2.0) — ${Faces.modelMb} م.ب تُنزَّل مرة واحدة من Hugging Face ويُفضَّل على Wi-Fi.\n\nبعدها كل شيء على جهازك: لا تُرسل أي صورة لأي جهة.',
        textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.6)),
      const SizedBox(height: S.s4),
      if (_st != 'unsupported') _p != null
        ? Column(children: [LinearProgressIndicator(value: _p! > 0 ? _p : null, minHeight: 8, borderRadius: BorderRadius.circular(9)), const SizedBox(height: 8),
            Text(_p! >= .999 ? 'تجهيز النموذج على جهازك…' : 'تنزيل ${(_p! * Faces.modelMb).round()} من ${Faces.modelMb} م.ب', style: const TextStyle(color: C.muted))])
        : FilledButton.icon(onPressed: _install, icon: const Icon(Icons.download_rounded), label: Text('تنزيل النموذج (${Faces.modelMb} م.ب)')),
      if (_fail) const Padding(padding: EdgeInsets.only(top: S.s3), child: Text('تعذّر التنزيل أو التجهيز — تأكد من الاتصال وحاول مجددًا.', style: TextStyle(color: C.rose))),
    ])));
  }
}

String _pct(double s) => '${(s.clamp(0, 1) * 100).round()}٪';
Color _col(FaceVerdict v) => switch (v) { FaceVerdict.same => C.ok, FaceVerdict.maybe => C.gold, FaceVerdict.other => C.rose, FaceVerdict.none => C.muted };
String _word(FaceVerdict v) => switch (v) { FaceVerdict.same => 'هي', FaceVerdict.maybe => 'محتمل', FaceVerdict.other => 'شخص آخر؟', FaceVerdict.none => 'بلا وجه واضح' };

/// «فحص صورها بالوجه»: تشابه كل صورة مع وجهها (إجماع صورها) — الصور المشكوك فيها أولًا، مع إزالتها بتأكيد.
class FaceAlbumScreen extends ConsumerStatefulWidget {
  const FaceAlbumScreen({super.key, required this.performerId});
  final String performerId;
  @override ConsumerState<FaceAlbumScreen> createState() => _FaceAlbumState();
}
class _FaceAlbumState extends ConsumerState<FaceAlbumScreen> {
  List<({String ref, double? sim})>? _r; String _prog = '';
  Performer? get _p => (ref.read(libraryProvider).value ?? const <Performer>[]).where((x) => x.id == widget.performerId).firstOrNull;

  Future<void> _run() async {
    final p = _p; if (p == null) return;
    setState(() { _r = null; _prog = 'تحليل الصور…'; });
    final repo = await ref.read(repoProvider.future);
    final r = await checkAlbum(p, repo, progress: (d, t) { if (mounted) setState(() => _prog = 'تحليل الصور ($d/$t)…'); });
    if (mounted) setState(() => _r = r);
  }

  Future<void> _remove(String photo) async {
    final p = _p; if (p == null) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('إزالة الصورة؟'), content: const Text('تُزال من صورها في مكتبتك.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('إزالة'))]));
    if (ok != true) return;
    final i = p.photos.indexOf(photo); if (i < 0) return;
    await removePhoto(ref, p, i);
    setState(() => _r = _r?.where((x) => x.ref != photo).toList());
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: Text('فحص صور ${p?.name ?? ''} بالوجه')),
      body: _ModelGate(child: Builder(builder: (_) {
        if (_r == null && _prog.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
        final r = _r;
        if (r == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: S.s3), Text(_prog, style: const TextStyle(color: C.muted))]));
        final sorted = [...r]..sort((a, b) => (a.sim ?? 2).compareTo(b.sim ?? 2));
        final odd = r.where((x) => verdict(x.sim) == FaceVerdict.other).length;
        final known = r.where((x) => x.sim != null).length;
        return ListView(padding: const EdgeInsets.all(S.s3), children: [
          Text(known < 2 ? 'لا توجد صور كافية بوجه واضح لبناء بصمتها (تحتاج صورتين على الأقل).'
            : odd == 0 ? '✓ كل الصور تبدو لنفس الشخص' : '$odd صورة قد لا تكون لها — راجعها (الأقل تشابهًا أولًا)',
            style: TextStyle(fontWeight: FontWeight.w700, color: odd == 0 ? C.ok : C.gold)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('التشابه مع بصمة وجهها المكوّنة من أغلب صورها. المكياج والإضاءة والزاوية تؤثر — القرار لك.', style: TextStyle(color: C.muted, fontSize: 12))),
          GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 3 / 4.6, children: [
            for (final x in sorted) () {
              final v = verdict(x.sim);
              return Column(children: [
                Expanded(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(S.rMd), border: Border.all(color: _col(v), width: 2.5)),
                  child: ClipRRect(borderRadius: BorderRadius.circular(S.rMd - 2), child: Photo(x.ref, name: p?.name ?? '', cacheWidth: 360)))),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(child: Text(x.sim == null ? _word(v) : '${_pct(x.sim!)} · ${_word(v)}', style: TextStyle(color: _col(v), fontSize: 11.5, fontWeight: FontWeight.w600))),
                  if (v == FaceVerdict.other || v == FaceVerdict.maybe) InkWell(onTap: () => _remove(x.ref), child: const Icon(Icons.delete_outline_rounded, size: 18, color: C.muted)),
                ]),
              ]);
            }(),
          ]),
        ]);
      })),
    );
  }
}

/// «ابحث بصورة»: اختر صورة من معرضك ⇒ أقرب ممثلات مكتبتك وجهًا (على جهازك فقط).
class FaceSearchScreen extends ConsumerStatefulWidget {
  const FaceSearchScreen({super.key});
  @override ConsumerState<FaceSearchScreen> createState() => _FaceSearchState();
}
class _FaceSearchState extends ConsumerState<FaceSearchScreen> {
  Map<String, Float32List>? _prof; String _prog = ''; bool _building = false, _favOnly = true, _stop = false;
  Uint8List? _img; List<(Performer, double)>? _res; String _msg = '';

  @override void dispose() { _stop = true; super.dispose(); }

  Future<void> _build() async {
    setState(() { _building = true; _stop = false; });
    final lib = (ref.read(libraryProvider).value ?? const <Performer>[]).where((p) => !p.isMinor && p.photos.isNotEmpty && (!_favOnly || p.fav || p.rating >= 4)).toList();
    final repo = await ref.read(repoProvider.future);
    final pr = await buildProfiles(lib, repo, cancelled: () => _stop, progress: (d, t, n) { if (mounted) setState(() => _prog = 'بصمة $n ($d/$t)'); });
    if (!mounted) return;
    setState(() { _prof = pr; _building = false; _prog = ''; });
    if (_img != null) _match();
  }

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 92);
    if (f == null) return;
    final b = await f.readAsBytes();
    setState(() { _img = b; _res = null; _msg = ''; });
    _match();
  }

  Future<void> _match() async {
    final b = _img, pr = _prof; if (b == null || pr == null) return;
    final e = await NativeBridge.faceEmbed(b);
    if (!mounted) return;
    if (e == null) { setState(() => _msg = 'لم يُعثر على وجه واضح في الصورة'); return; }
    final lib = ref.read(libraryProvider).value ?? const <Performer>[];
    setState(() { _res = rankByFace(e.v, pr, lib); _msg = e.faces > 1 ? 'في الصورة ${e.faces} وجوه — استُخدم أكبرها' : ''; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ابحث بصورة')),
    body: _ModelGate(child: ListView(padding: const EdgeInsets.all(S.s4), children: [
      if (_prof == null) ...[
        const Text('أولًا: بصمات وجوه ممثلاتك من صورهن في مكتبتك (مرة واحدة، تُحفظ على جهازك وتتحدث مع صورهن).', style: TextStyle(color: C.muted, height: 1.6)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('المفضلات فقط (أسرع)'), value: _favOnly, onChanged: _building ? null : (v) => setState(() => _favOnly = v)),
        if (_building) ...[const LinearProgressIndicator(), const SizedBox(height: 6), Text(_prog, style: const TextStyle(color: C.muted)), TextButton(onPressed: () => _stop = true, child: const Text('إيقاف'))]
        else FilledButton.icon(onPressed: _build, icon: const Icon(Icons.face_rounded), label: const Text('تجهيز البصمات')),
      ] else ...[
        Text('${_prof!.length} ممثلة جاهزة للمقارنة', style: const TextStyle(color: C.muted)),
        const SizedBox(height: S.s3),
        FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.photo_library_rounded), label: Text(_img == null ? 'اختر صورة' : 'صورة أخرى')),
      ],
      if (_img != null) Padding(padding: const EdgeInsets.only(top: S.s3), child: ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: Image.memory(_img!, height: 220, fit: BoxFit.contain))),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s2), child: Text(_msg, style: const TextStyle(color: C.gold))),
      if (_res != null) ...[
        const SizedBox(height: S.s3),
        Text(_res!.isEmpty || _res!.first.$2 < Faces.maybe ? 'لا تشبه أيًا من ممثلات مكتبتك بوضوح' : 'الأقرب في مكتبتك', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        for (final (p, s) in _res!) ListTile(contentPadding: EdgeInsets.zero, onTap: () => context.push('/p/${p.id}'),
          leading: CircleAvatar(radius: 24, backgroundColor: C.surface, child: ClipOval(child: SizedBox(width: 48, height: 48, child: Photo(p.cover, name: p.name, cacheWidth: 144)))),
          title: Text(p.name), subtitle: Text(_word(verdict(s)), style: TextStyle(color: _col(verdict(s)))),
          trailing: Text(_pct(s), style: TextStyle(fontWeight: FontWeight.w800, color: _col(verdict(s))))),
      ],
    ])),
  );
}
