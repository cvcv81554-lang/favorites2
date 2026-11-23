import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/clip_prefetch.dart';
import '../../../data/embed_sources.dart';
import '../../../data/keys.dart';
import '../../../data/platform/clip_cache.dart';
import '../../../data/sources.dart';
import '../../../data/stash_server.dart';
import '../../../domain/reels.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../works/works_screen.dart' show worksProvider;
import 'reel_center.dart';

/// «الشبكة والمقاطع»: حالة المصدرين وخوادم المقاطع على شبكتك، المقاطع المحفوظة، والتحميل المسبق ووضع اللحاق.
class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key});
  @override ConsumerState<NetworkScreen> createState() => _NetworkState();
}

class _NetworkState extends ConsumerState<NetworkScreen> {
  Map<String, dynamic> _hosts = {}; (bool, String)? _s, _t; bool _checking = false, _probing = false; String _probeMsg = '';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    _hosts = await loadHosts(await ref.read(repoProvider.future));
    await ref.read(prefetchProvider.notifier).refreshStats();
    if (mounted) setState(() {});
  }

  Future<void> _checkSources() async {
    setState(() => _checking = true);
    final ks = await ApiKeys.get(ApiKeys.stash), kt = await ApiKeys.get(ApiKeys.tpdb);
    final r = await Future.wait([
      ks.isEmpty ? Future.value((false, 'لا مفتاح')) : checkSource(() => StashDB.test(ks)),
      kt.isEmpty ? Future.value((false, 'لا مفتاح')) : checkSource(() => TPDB.test(kt)),
    ]);
    if (mounted) setState(() { _s = r[0]; _t = r[1]; _checking = false; });
  }

  Future<void> _recheck() async {
    setState(() { _probing = true; _probeMsg = 'فحص الخوادم…'; });
    final repo = await ref.read(repoProvider.future);
    final opened = await probeHosts(_hosts, allTrailerUrls(ref.read(worksProvider)), force: true, progress: (d, t) { if (mounted) setState(() => _probeMsg = 'فحص الخوادم ($d/$t)…'); });
    await saveHosts(repo, _hosts);
    if (!mounted) return;
    setState(() { _probing = false; _probeMsg = opened.isEmpty ? 'اكتمل الفحص' : 'صار ${opened.length} خادمًا متاحًا الآن — اضغط «حمّل الآن» لحفظ مقاطعها'; });
  }

  String _size(int b) => b >= 1 << 30 ? '${(b / (1 << 30)).toStringAsFixed(1)} GB' : '${(b / (1 << 20)).round()} MB';

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(reelsCfgProvider).value ?? const ReelsCfg();
    final cn = ref.read(reelsCfgProvider.notifier);
    final pf = ref.watch(prefetchProvider);
    final count = <String, int>{};
    for (final u in allTrailerUrls(ref.watch(worksProvider))) { final h = hostOf(u); if (h.isNotEmpty) count[h] = (count[h] ?? 0) + 1; }
    final hosts = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
    final okN = hosts.where((h) => (_hosts[h] as Map?)?['ok'] == true).fold<int>(0, (s, h) => s + count[h]!);
    final badN = hosts.where((h) => (_hosts[h] as Map?)?['ok'] == false).fold<int>(0, (s, h) => s + count[h]!);
    Widget card(String title, List<Widget> children) => Container(margin: const EdgeInsets.only(bottom: S.s3), padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 6), ...children]));
    Widget st((bool, String)? r, String name) => Text('$name: ${r == null ? '—' : r.$1 ? 'يعمل ✓' : 'لا يعمل ✕ — ${r.$2}'}', style: TextStyle(color: r == null ? C.muted : r.$1 ? C.ok : C.gold, height: 1.5));

    return Scaffold(
      appBar: AppBar(title: const Text('الشبكة والمقاطع')),
      body: ListView(padding: const EdgeInsets.all(S.s4), children: [
        card('المصدران', [
          st(_s, 'StashDB'), st(_t, 'ThePornDB'),
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: _checking ? null : _checkSources,
            icon: _checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check_rounded), label: const Text('فحص الآن'))),
        ]),
        card('المقاطع المحفوظة على جهازك', [
          Text('${pf.cachedCount} مقطعًا · ${_size(pf.bytes)} من ${cfg.gb} GB', style: const TextStyle(fontSize: 15)),
          if (pf.want > 0) Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: pf.want == 0 ? 0 : pf.have / pf.want)),
          if (pf.msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(pf.msg, style: const TextStyle(color: C.muted, fontSize: 12.5))),
          Row(children: [
            pf.running ? TextButton.icon(onPressed: () => ref.read(prefetchProvider.notifier).stop(), icon: const Icon(Icons.stop_rounded), label: const Text('إيقاف'))
              : TextButton.icon(onPressed: () => ref.read(prefetchProvider.notifier).run(force: true), icon: const Icon(Icons.download_rounded), label: const Text('حمّل الآن')),
            const Spacer(),
            TextButton(onPressed: pf.running ? null : () async { await clearClipCache(); await ref.read(prefetchProvider.notifier).refreshStats(); }, child: const Text('مسح المحفوظ', style: TextStyle(color: C.danger))),
          ]),
        ]),
        const _StashServerCard(),
        const _EmbedCard(),
        card('الجودة', [
          SwitchListTile(contentPadding: EdgeInsets.zero, value: cfg.hqOnly, onChanged: (v) => cn.set(cfg.copy(hqOnly: v)), title: const Text('إعلانات حقيقية فقط'),
            subtitle: const Text('يتخطى المعاينات القصيرة بلا صوت أو أقل من 480p (تُقاس عند التشغيل)، ويستبعد الخادم الذي معظم مقاطعه معاينات', style: TextStyle(color: C.muted, fontSize: 12.5))),
        ]),
        card('التحميل المسبق', [
          SwitchListTile(contentPadding: EdgeInsets.zero, value: cfg.prefetch, onChanged: (v) => cn.set(cfg.copy(prefetch: v)), title: const Text('حمّل المقاطع القادمة مسبقًا'),
            subtitle: const Text('على Wi-Fi فقط، أثناء استخدامك للتطبيق — فتعمل فورًا بلا انتظار ولا انقطاع', style: TextStyle(color: C.muted, fontSize: 12.5))),
          const Text('عدد المقاطع', style: TextStyle(color: C.muted, fontSize: 12.5)),
          Wrap(spacing: 6, children: [for (final n in const [30, 60, 100, 200]) ChoiceChip(label: Text('$n'), selected: cfg.count == n, onSelected: (_) => cn.set(cfg.copy(count: n)))]),
          const SizedBox(height: 6),
          const Text('أقصى مساحة', style: TextStyle(color: C.muted, fontSize: 12.5)),
          Wrap(spacing: 6, children: [for (final g in const [1, 2, 3, 5, 10]) ChoiceChip(label: Text('$g GB'), selected: cfg.gb == g, onSelected: (_) => cn.set(cfg.copy(gb: g)))]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: cfg.night, onChanged: cfg.prefetch ? (v) => cn.set(cfg.copy(night: v)) : null, title: const Text('التحميل الليلي'),
            subtitle: const Text('أثناء الشحن وعلى Wi-Fi والتطبيق مغلق — iOS يقرر التوقيت (غالبًا ليلًا)', style: TextStyle(color: C.muted, fontSize: 12.5))),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: cfg.catchUp, onChanged: (v) => cn.set(cfg.copy(catchUp: v)), title: const Text('وضع اللحاق'),
            subtitle: const Text('إن صارت شبكتك تصل لخوادم كانت محجوبة (مثل تشغيلك VPN بنفسك) يحمّل مقاطعها فورًا لتعمل لاحقًا بدونها', style: TextStyle(color: C.muted, fontSize: 12.5))),
        ]),
        card('خوادم المقاطع على شبكتك', [
          Text('${count.values.fold<int>(0, (a, b) => a + b)} مقطعًا · ${hosts.length} خادمًا · يعمل $okN · محجوب $badN', style: const TextStyle(color: C.muted)),
          const Text('مقاطع الخوادم المحجوبة تُخفى، ويُعاد فحصها كل 6 ساعات — وتظهر تلقائيًا متى صارت شبكتك تصلها.', style: TextStyle(color: C.muted, fontSize: 12)),
          Row(children: [
            TextButton.icon(onPressed: _probing ? null : _recheck, icon: _probing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded), label: const Text('إعادة الفحص')),
            if (_probeMsg.isNotEmpty) Expanded(child: Text(_probeMsg, style: const TextStyle(color: C.muted, fontSize: 12))),
          ]),
          for (final h in hosts) () { final s = _hosts[h] as Map?;
            return ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: Icon(s == null ? Icons.help_outline_rounded : s['ok'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded, color: s == null ? C.muted : s['ok'] == true ? C.ok : C.danger),
              title: Text('$h · ${count[h]}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(s == null ? 'لم يُفحص بعد' : '${s['ok'] == true && s['dl'] == true ? 'يعمل بالتنزيل · ' : ''}${s['why'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted))); }(),
        ]),
      ]),
    );
  }
}


/// إعداد خادم Stash الخاص بك: العنوان + المفتاح (المخزن الآمن) + اختبار + إظهار مقاطعه.
class _StashServerCard extends ConsumerStatefulWidget {
  const _StashServerCard();
  @override ConsumerState<_StashServerCard> createState() => _StashServerCardState();
}
class _StashServerCardState extends ConsumerState<_StashServerCard> {
  final _url = TextEditingController(), _key = TextEditingController();
  String _msg = ''; bool _busy = false, _ok = false;
  @override void initState() { super.initState(); () async { _url.text = await ApiKeys.get(StashServer.urlKey); _key.text = await ApiKeys.get(StashServer.apiKey); if (mounted) setState(() {}); }(); }
  @override void dispose() { _url.dispose(); _key.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() { _busy = true; _msg = 'اختبار الاتصال…'; });
    try {
      final v = await StashServer.test(_url.text, _key.text);
      await ApiKeys.set(StashServer.urlKey, StashServer.normalize(_url.text)); await ApiKeys.set(StashServer.apiKey, _key.text);
      final repo = await ref.read(repoProvider.future); await repo.kvSet('stash_local_map', {});   // يُعاد ربط الممثلات بالخادم الجديد
      setState(() { _ok = true; _msg = 'متصل ✓ — Stash $v. افتح «مقاطع» لتظهر فيديوهات ممثلاتك.'; });
    } on SourceError catch (e) { setState(() { _ok = false; _msg = e.msg; }); }
    catch (e) { setState(() { _ok = false; _msg = '$e'; }); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(reelsCfgProvider).value ?? const ReelsCfg();
    return Container(margin: const EdgeInsets.only(bottom: S.s3), padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('خادم Stash الخاص بك', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('فيديوهاتك الكاملة ومقاطع قصيرة منها — من برنامج Stash المجاني على حاسوبك (نفس عائلة StashDB). يعمل والجوال على نفس شبكة المنزل.', style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: S.s2),
        TextField(controller: _url, keyboardType: TextInputType.url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'عنوان الخادم', hintText: '192.168.1.10:9999')),
        const SizedBox(height: S.s2),
        TextField(controller: _key, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'API Key (إن كان للخادم كلمة مرور)')),
        const SizedBox(height: S.s2),
        Row(children: [
          FilledButton.tonalIcon(onPressed: _busy ? null : _save, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded), label: const Text('حفظ واختبار')),
          const Spacer(),
          const Text('إظهار مقاطعه'), Switch(value: cfg.server, onChanged: (v) => ref.read(reelsCfgProvider.notifier).set(cfg.copy(server: v))),
        ]),
        if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg, style: TextStyle(color: _ok ? C.ok : C.gold, fontSize: 12.5))),
        const SizedBox(height: 6),
        const Text('الإعداد: ثبّت Stash على حاسوبك وأضف مجلد فيديوهاتك ← اربط ممثلاتك بـ StashDB داخله (Tagger) ← انسخ عنوانه (مثل 192.168.1.10:9999) والـ API Key من Settings ← Security.',
          style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.5)),
      ]));
  }
}


/// مواقع التضمين الرسمية: تفعيل كل موقع وحالته على شبكتك.
class _EmbedCard extends ConsumerStatefulWidget {
  const _EmbedCard();
  @override ConsumerState<_EmbedCard> createState() => _EmbedCardState();
}
class _EmbedCardState extends ConsumerState<_EmbedCard> {
  final _st = <String, bool?>{}; bool _busy = false;
  Future<void> _check() async {
    setState(() => _busy = true);
    final repo = await ref.read(repoProvider.future);
    final reach = Map<String, dynamic>.from(await repo.kvGet('embed_reach') as Map? ?? {});
    for (final s in embedSources) { final ok = await embedReachable(s); _st[s.id] = ok; reach[s.id] = {'ok': ok, 't': DateTime.now().millisecondsSinceEpoch}; if (mounted) setState(() {}); }
    await repo.kvSet('embed_reach', reach);
    if (mounted) setState(() => _busy = false);
  }
  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(reelsCfgProvider).value ?? const ReelsCfg();
    return Container(margin: const EdgeInsets.only(bottom: S.s3), padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('مواقع التضمين الرسمية', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 15)),
        const Text('فيديوهات كاملة لممثلاتك عبر واجهات المواقع الرسمية ومشغّل التضمين الذي تسمح به (بلا تنزيل). كل مقطع موسوم بمصدره. المطابقة بالاسم الكامل فقط.', style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.5)),
        for (final s in embedSources) SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, value: cfg.emb.contains(s.id),
          onChanged: (v) => ref.read(reelsCfgProvider.notifier).set(cfg.copy(emb: v ? [...cfg.emb, s.id] : cfg.emb.where((x) => x != s.id).toList())),
          title: Text(s.name), subtitle: Text(_st[s.id] == null ? '' : _st[s.id]! ? 'متاح على شبكتك ✓' : 'محجوب على شبكتك — يعمل مع VPN', style: TextStyle(color: _st[s.id] == true ? C.ok : C.gold, fontSize: 12))),
        TextButton.icon(onPressed: _busy ? null : _check, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check_rounded), label: const Text('فحص الوصول')),
      ]));
  }
}
