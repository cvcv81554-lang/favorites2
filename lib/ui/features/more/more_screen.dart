import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/background.dart';
import '../../../data/backup.dart';
import '../../../data/keys.dart';
import '../../../data/sources.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../privacy/lock_gate.dart';
import '../tools/lists_state.dart';
import '../studio/studio_screen.dart';
import '../../core/bg_coordinator.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});
  @override ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _busy = false;
  String _status = '';

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _askPassword(String title) => showDialog<String>(context: context, builder: (c) {
    final t = TextEditingController();
    return AlertDialog(title: Text(title), content: TextField(controller: t, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, t.text), child: const Text('متابعة'))]);
  });

  Future<void> _import() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() { _busy = true; _status = 'قراءة الملف…'; });
    try {
      var text = utf8.decode(bytes, allowMalformed: false);
      if (Backup.isEncrypted(text)) {
        final pw = await _askPassword('النسخة مشفّرة'); if (pw == null) return;
        setState(() => _status = 'فك التشفير…');
        text = await Backup.decrypt(text, pw);
      }
      setState(() => _status = 'قراءة النسخة…');
      final f = await Backup.parseAsync(text);
      if (!mounted) return;
      final go = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('استيراد النسخة'),
        content: Text('${f.items.length} ممثلة في الملف.${f.minorsSkipped > 0 ? '\nستُتجاهل ${f.minorsSkipped} (أقل من 18 أو تاريخ غير صالح).' : ''}${f.invalid > 0 ? '\n${f.invalid} سجل غير صالح.' : ''}\n\nلا يُحذف شيء من مكتبتك: الجديد يُضاف، والأحدث يُحدَّث فقط.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('استيراد'))]));
      if (go != true) return;
      setState(() => _status = 'حفظ الصور والسجلات…');
      final lib = ref.read(libraryProvider.notifier);
      final res = await Backup.apply(lib.repo, f, lib.items, onProgress: (d, n) { if (mounted && (d % 5 == 0 || d == n - 1)) setState(() => _status = 'حفظ الصور والسجلات… ${d + 1} / $n'); });
      // دمج لا استبدال (كالتطبيق السابق): القوائم بالمعرّف، والتفضيلات فقط للمفاتيح غير الموجودة
      for (final k in ['lists', 'wlists']) {
        final cur = [for (final e in (await lib.repo.kvGet(k) as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
        final ids = {for (final e in cur) e['id']};
        await lib.repo.kvSet(k, [...cur, for (final e in (k == 'lists' ? f.lists : f.wlists)) if (!ids.contains(e['id'])) e]);
      }
      final pr = Map<String, dynamic>.from(await lib.repo.kvGet('prefs') as Map? ?? const {});
      f.prefs.forEach((k, v) => pr.putIfAbsent(k, () => v));
      await lib.repo.kvSet('prefs', pr);
      ref.invalidate(listsProvider); ref.invalidate(wlistsProvider); ref.invalidate(wishProvider);
      await lib.reload();
      _snack('أُضيفت ${res.added} · حُدّثت ${res.updated}${res.photosFixed > 0 ? ' · اكتملت صور ${res.photosFixed}' : ''}');
    } on BackupError catch (e) { _snack(e.msg); }
    catch (e) { _snack('تعذّر الاستيراد: $e'); }
    finally { if (mounted) setState(() { _busy = false; _status = ''; }); }
  }

  Future<void> _export({bool encrypted = false}) async {
    String? pw;
    if (encrypted) { pw = await _askPassword('كلمة مرور النسخة (8 أحرف فأكثر)'); if (pw == null) return; }
    setState(() { _busy = true; _status = 'تجهيز النسخة…'; });
    try {
      final lib = ref.read(libraryProvider.notifier);
      final lists = ((await lib.repo.kvGet('lists')) as List? ?? const []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final wlists = ((await lib.repo.kvGet('wlists')) as List? ?? const []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final prefs = ((await lib.repo.kvGet('prefs')) as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'));
      var json = await Backup.export(lib.items, lists: lists, wlists: wlists, prefs: prefs);
      if (pw != null) json = await Backup.encrypt(json, pw);
      final d = DateTime.now(); final name = 'favorites-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.${pw != null ? 'vkte' : 'json'}';
      final path = await FilePicker.saveFile(dialogTitle: 'حفظ النسخة الاحتياطية', fileName: name, bytes: utf8.encode(json));
      _snack(path == null && !kIsWeb ? 'أُلغي الحفظ' : 'حُفظت النسخة ($name)');
    } on BackupError catch (e) { _snack(e.msg); }
    catch (e) { _snack('تعذّر التصدير: $e'); }
    finally { if (mounted) setState(() { _busy = false; _status = ''; }); }
  }

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(libraryProvider).value?.length ?? 0;
    return Scaffold(body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 140), children: [
      Row(children: [const AppLogo(size: 52), const SizedBox(width: S.s3), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('المفضلة', style: Theme.of(context).textTheme.headlineSmall), const Text('مكتبتك الخاصة · كل شيء على جهازك', style: TextStyle(color: C.muted)),
      ])]),
      const SizedBox(height: S.s5),
      if (_busy) Padding(padding: const EdgeInsets.only(bottom: S.s4), child: Column(children: [const LinearProgressIndicator(), const SizedBox(height: 6), Text(_status, style: const TextStyle(color: C.muted))])),
      _group('النسخ الاحتياطي', [
        _tile(Icons.download_rounded, 'استيراد نسخة احتياطية', 'من التطبيق السابق أو هذا التطبيق (JSON أو مشفّرة .vkte). لا يُحذف شيء.', _busy ? null : _import),
        _tile(Icons.upload_rounded, 'تصدير نسخة احتياطية', 'نفس الصيغة — تُقرأ في التطبيقين. $n ممثلة.', _busy || n == 0 ? null : _export),
        _tile(Icons.lock_rounded, 'تصدير نسخة مشفّرة', 'AES-256 بكلمة مرور. مفاتيح API لا تُصدَّر أبدًا.', _busy || n == 0 ? null : () => _export(encrypted: true)),
      ]),
      _group('مكتبتي', [_tile(Icons.handyman_rounded, 'الأدوات', 'القوائم، المواجهة، المستويات، الأمنيات، الإنجازات، مزاج الليلة…', () => context.push('/tools')),
        _tile(Icons.insights_rounded, 'الإحصائيات وملخّص السنة', 'أكثر من شاهدتِ، سلاسل المشاهدة، البلدان، الأعمار…', () => context.push('/stats')),
        _tile(Icons.tv_rounded, 'المزامنة مع الشاشة', 'أرسلي مكتبتك إلى Android TV على نفس الشبكة', () => context.push('/sync'))]),
      _group('الإشعارات والتحديث في الخلفية', [const _BgSection()]),
      _group('المصادر الرسمية', [
        _KeyTile(name: 'StashDB', k: ApiKeys.stash, test: StashDB.test),
        _KeyTile(name: 'ThePornDB', k: ApiKeys.tpdb, test: TPDB.test),
      ]),
      _group('الخصوصية', [
        const PrivacySection(),
        _tile(Icons.verified_user_rounded, 'بوابة +18', 'أي سجل عمره أقل من 18، أو تاريخه غير صالح، يُرفض في الحفظ والاستيراد والعرض.', null),
        _tile(Icons.phonelink_lock_rounded, 'بياناتك على جهازك', 'لا حسابات ولا خوادم. الصور تُحفظ ملفات داخل التطبيق.', null),
      ]),
      _group('عن الإصدار', [
        _tile(Icons.auto_awesome_rounded, 'المفضلة 2 · Flutter', 'إعادة بناء كاملة. أقسام الأعمال واكتشف والاستديو والإشعارات تُنقل تباعًا.', null),
      ]),
    ])));
  }

  Widget _group(String t, List<Widget> c) => Padding(padding: const EdgeInsets.only(bottom: S.s5), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(bottom: S.s2, right: S.s1), child: Text(t, style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700))),
    Card(child: Column(children: c)),
  ]));
  Widget _tile(IconData i, String t, String s, VoidCallback? onTap) => ListTile(leading: Icon(i, color: C.gold), title: Text(t), subtitle: Text(s, style: const TextStyle(color: C.muted)), onTap: onTap, enabled: onTap != null || true);
}


/// مفتاح API: يُكتب ويُختبر ويُحفظ في المخزن الآمن. لا يظهر كاملًا ولا يُصدَّر.
class _KeyTile extends StatefulWidget {
  const _KeyTile({required this.name, required this.k, required this.test});
  final String name, k; final Future<bool> Function(String) test;
  @override State<_KeyTile> createState() => _KeyTileState();
}
class _KeyTileState extends State<_KeyTile> {
  bool _has = false;
  @override void initState() { super.initState(); ApiKeys.has(widget.k).then((v) { if (mounted) setState(() => _has = v); }); }
  Future<void> _edit() async {
    final t = TextEditingController(); String err = ''; bool busy = false;
    await showDialog(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: Text('مفتاح ${widget.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: t, obscureText: true, autofocus: true, decoration: InputDecoration(labelText: 'المفتاح', hintText: _has ? 'محفوظ — اكتب مفتاحًا جديدًا لاستبداله' : '')),
        const SizedBox(height: 8),
        const Text('يُحفظ في المخزن الآمن لجهازك فقط، ولا يدخل النسخة الاحتياطية.', style: TextStyle(color: C.muted, fontSize: 12)),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: C.danger))),
      ]),
      actions: [
        if (_has) TextButton(onPressed: () async { await ApiKeys.set(widget.k, ''); if (c.mounted) Navigator.pop(c); setState(() => _has = false); }, child: const Text('حذف المفتاح', style: TextStyle(color: C.danger))),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: busy ? null : () async {
          final v = t.text.trim(); if (v.isEmpty) return;
          set(() { busy = true; err = ''; });
          try { await widget.test(v); await ApiKeys.set(widget.k, v); if (c.mounted) Navigator.pop(c); setState(() => _has = true);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('مفتاح ${widget.name} يعمل ✓'))); }
          catch (e) { set(() { busy = false; err = '$e'; }); }
        }, child: Text(busy ? 'جارٍ الاختبار…' : 'اختبار وحفظ')),
      ])));
    t.dispose();
  }
  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(Icons.key_rounded, color: _has ? C.ok : C.gold), title: Text(widget.name), subtitle: Text(_has ? 'مفعّل ✓' : 'لم يُضف بعد', style: const TextStyle(color: C.muted)), trailing: const Icon(Icons.chevron_right_rounded), onTap: _edit);
}

/// إعدادات التحديث في الخلفية والإشعارات — مع حدود كل منصة بصراحة.
class _BgSection extends ConsumerStatefulWidget {
  const _BgSection();
  @override ConsumerState<_BgSection> createState() => _BgSectionState();
}
class _BgSectionState extends ConsumerState<_BgSection> {
  BgSettings _s = const BgSettings(); Map? _last; bool _busy = false; (bool, String)? _perm;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final repo = await ref.read(repoProvider.future);
    final s = BgSettings.fromJson(await repo.kvGet('bg') as Map?); final l = await repo.kvGet('bg_last') as Map?; final b = await lastBgState();
    final lastAt = [(l?['at'] as num?) ?? 0, (b?['at'] as num?) ?? 0].reduce((x, y) => x > y ? x : y);
    final perm = kIsWeb ? null : await notifStatus();
    if (mounted) setState(() { _s = s; _perm = perm; _last = lastAt == 0 ? null : {...?l, 'at': lastAt}; });
  }
  Future<void> _set(BgSettings s) async {
    if (s.on && !_s.on) { final ok = await requestNotifPermission(); if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الإشعارات غير مسموحة — سيعمل التحديث بلا تنبيه'))); }
    final repo = await ref.read(repoProvider.future); await repo.kvSet('bg', s.toJson());
    try { await writeInput(ref, lib: ref.read(libraryProvider.notifier).items); await applyBackground(s); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّرت الجدولة: $e'))); }
    setState(() => _s = s);
  }
  Future<void> _now() async {
    setState(() => _busy = true);
    try {
      final lib = ref.read(libraryProvider.notifier).items;
      final ids = {for (final x in await (await ref.read(studioRepoProvider.future)).all()) x.id};
      final f = await fetchUpdates(buildBgInput(_s.copy(works: true, photos: true), lib, ids), limit: 40);
      final r = await applyFetch(ref, [f]);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.works > 0 || r.photos > 0 ? 'وُجد ${r.works} عمل و${r.photos} صورة جديدة' : (f.errors.isEmpty ? 'لا جديد الآن' : f.errors.join(' · ')))));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _busy = false); _load(); }
  }
  Future<void> _fixPerm() async {
    final ok = await requestNotifPermission();
    if (!ok) { await launchUrl(Uri.parse('app-settings:')); }   // رُفض سابقًا ⇒ النظام لا يسأل مجددًا: نفتح إعدادات التطبيق
    await _load();
  }
  Future<void> _test() async {
    var p = await notifStatus();
    if (!p.$1) { await requestNotifPermission(); p = await notifStatus(); }
    if (!p.$1) { if (mounted) { setState(() => _perm = p); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${p.$2} — اضغطي «السماح» ثم فعّليها من الإعدادات'))); } return; }
    try {
      await testNotification();
      await testNotification(delay: const Duration(seconds: 20));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 6), content: Text('أُرسل إشعار الآن، وآخر بعد 20 ثانية — اخرجي من التطبيق الآن لتجربة وصوله في الخلفية')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر الإرسال: $e'))); }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final last = _last?['at'] as num?;
    return Column(children: [
      SwitchListTile(value: _s.on, onChanged: kIsWeb ? null : (v) => _set(_s.copy(on: v)), secondary: const Icon(Icons.notifications_active_rounded, color: C.gold),
        title: const Text('تحديث تلقائي وإشعارات'), subtitle: Text(kIsWeb ? 'متاح في تطبيق الجوال' : 'أعمال وصور جديدة لممثلات مكتبتك، والتطبيق مغلق', style: const TextStyle(color: C.muted))),
      if (_s.on) ...[
        CheckboxListTile(value: _s.works, onChanged: (v) => _set(_s.copy(works: v)), title: const Text('أعمال جديدة (StashDB)'), dense: true),
        CheckboxListTile(value: _s.photos, onChanged: (v) => _set(_s.copy(photos: v)), title: const Text('صور جديدة للاستديو'), dense: true),
        CheckboxListTile(value: _s.wifiOnly, onChanged: (v) => _set(_s.copy(wifiOnly: v)), title: const Text('على Wi-Fi فقط'), dense: true),
      ],
      ListTile(leading: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded, color: C.gold), title: const Text('افحص الآن'),
        subtitle: Text(last == null ? 'لم يُفحص بعد' : 'آخر فحص: ${DateTime.fromMillisecondsSinceEpoch(last.toInt()).toString().substring(0, 16)} · ${_last?['works'] ?? 0} عمل · ${_last?['photos'] ?? 0} صورة', style: const TextStyle(color: C.muted)),
        onTap: _busy ? null : _now),
      if (!kIsWeb) ListTile(
        leading: Icon(_perm?.$1 == true ? Icons.verified_rounded : Icons.notifications_off_rounded, color: _perm?.$1 == true ? C.gold : C.danger),
        title: Text(_perm == null ? 'إذن الإشعارات…' : _perm!.$1 ? 'الإشعارات مسموحة' : 'الإشعارات غير مسموحة'),
        subtitle: Text(_perm?.$2 ?? '', style: const TextStyle(color: C.muted)),
        trailing: _perm?.$1 == false ? TextButton(onPressed: _fixPerm, child: const Text('السماح')) : null),
      if (!kIsWeb) ListTile(leading: const Icon(Icons.campaign_rounded, color: C.gold), title: const Text('إرسال إشعار تجريبي'),
        subtitle: const Text('فوري (والتطبيق مفتوح) + آخر بعد 20 ثانية — اخرجي من التطبيق أو أغلقيه لتتأكدي أنه يصل', style: TextStyle(color: C.muted)),
        onTap: _test),
      const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text('الإشعار عام بلا أسماء ولا صور. أندرويد: كل ~12 ساعة عند توفر الشروط. آيفون: النظام يقرر التوقيت حسب استخدامك والبطارية، ولا يعمل إن أغلقتِ التطبيق قسرًا من قائمة التطبيقات.', style: TextStyle(color: C.muted, fontSize: 12, height: 1.5))),
    ]);
  }
}
