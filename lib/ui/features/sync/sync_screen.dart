import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/backup.dart';
import '../../../data/privacy.dart';
import '../../../data/sync.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final isTvProvider = FutureProvider<bool>((ref) => Privacy.isTv());

/// المزامنة: الشاشة «تستقبل» (عنوان + رمز)، والجوال «يرسل» مكتبته بصيغة النسخة الاحتياطية.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});
  @override ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _srv = SyncServer(); final _host = TextEditingController(), _code = TextEditingController();
  String _log = ''; bool _busy = false; bool? _receive;

  @override void dispose() { _srv.stop(); _host.dispose(); _code.dispose(); super.dispose(); }

  Future<void> _startReceive() async {
    final lib = ref.read(libraryProvider.notifier);
    setState(() { _busy = true; _log = ''; });
    try {
      await _srv.start(repo: lib.repo, current: () async => lib.items, onEvent: (m) { if (mounted) setState(() => _log = m); if (m.startsWith('وصلت')) lib.reload(); });
    } catch (e) { _log = '$e'; }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _send() async {
    setState(() { _busy = true; _log = 'تجهيز المكتبة…'; });
    try {
      final lib = ref.read(libraryProvider.notifier);
      final json = await Backup.export(lib.items);
      setState(() => _log = 'جارٍ الإرسال…');
      final r = await pushToTv(host: _host.text, code: _code.text, json: json);
      if (mounted) setState(() => _log = r);
    } catch (e) { if (mounted) setState(() => _log = '$e'.replaceFirst('Invalid argument(s): ', '').replaceFirst('Bad state: ', '')); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final tv = ref.watch(isTvProvider).value ?? false;
    final receive = _receive ?? tv;
    return Scaffold(appBar: AppBar(title: const Text('المزامنة مع الشاشة')), body: !syncSupported
      ? const EmptyState(title: 'غير متاح هنا', body: 'المزامنة تعمل بين تطبيق الجوال وتطبيق الشاشة على نفس الشبكة.')
      : ListView(padding: const EdgeInsets.all(S.s4), children: [
          SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('إرسال (الجوال)'), icon: Icon(Icons.send_to_mobile_rounded)), ButtonSegment(value: true, label: Text('استقبال (الشاشة)'), icon: Icon(Icons.tv_rounded))],
            selected: {receive}, onSelectionChanged: (s) => setState(() => _receive = s.first)),
          const SizedBox(height: S.s5),
          if (receive) ...[
            if (!_srv.running) FilledButton.icon(autofocus: true, onPressed: _busy ? null : _startReceive, icon: const Icon(Icons.wifi_tethering_rounded), label: const Text('ابدأ الاستقبال'))
            else Card(child: Padding(padding: const EdgeInsets.all(S.s5), child: Column(children: [
              const Text('على الجوال: المزيد ← المزامنة ← إرسال', style: TextStyle(color: C.muted)),
              const SizedBox(height: S.s4), const Text('العنوان'), SelectableText(_srv.address, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.gold2)),
              const SizedBox(height: S.s3), const Text('الرمز'), Text(_srv.code, style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w700, letterSpacing: 8)),
              const SizedBox(height: S.s3), OutlinedButton(onPressed: () async { await _srv.stop(); setState(() {}); }, child: const Text('إيقاف')),
            ]))),
          ] else ...[
            TextField(controller: _host, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'عنوان الشاشة', hintText: '192.168.1.20:8787')),
            const SizedBox(height: S.s3),
            TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'الرمز الظاهر على الشاشة')),
            FilledButton.icon(onPressed: _busy ? null : _send, icon: const Icon(Icons.send_rounded), label: const Text('أرسل مكتبتي')),
          ],
          const SizedBox(height: S.s4),
          if (_busy) const LinearProgressIndicator(),
          if (_log.isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s3), child: Text(_log, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
          const SizedBox(height: S.s5),
          const Text('على نفس شبكة Wi-Fi فقط. الإرسال بصيغة النسخة الاحتياطية: لا يُحذف شيء من الشاشة، والأحدث يفوز، وأي سجل أقل من 18 يُرفض. لا تُرسَل مفاتيح API ولا رمز القفل.', style: TextStyle(color: C.muted, height: 1.6)),
        ]));
  }
}
