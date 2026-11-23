import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/clip_prefetch.dart';
import '../../../data/keys.dart';
import '../../../data/platform/clip_cache.dart';
import '../../../data/sources.dart';
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
