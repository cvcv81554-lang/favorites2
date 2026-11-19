import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/privacy.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class PrivacyN extends AsyncNotifier<PrivacySettings> {
  @override
  Future<PrivacySettings> build() async {
    final repo = await ref.watch(repoProvider.future);
    final s = PrivacySettings.fromJson(await repo.kvGet('privacy') as Map?);
    blurPhotos.value = s.blur; await Privacy.applySecure(s.secure);
    return s;
  }
  Future<void> set(PrivacySettings s) async {
    await (await ref.read(repoProvider.future)).kvSet('privacy', s.toJson());
    blurPhotos.value = s.blur; await Privacy.applySecure(s.secure);
    state = AsyncData(s);
  }
}
final privacyProvider = AsyncNotifierProvider<PrivacyN, PrivacySettings>(PrivacyN.new);

/// بوابة القفل: تقفل عند الفتح، وعند العودة بعد مدة الغياب المختارة، وتغطي المحتوى عند مغادرة التطبيق.
/// أثناء نافذة البصمة/الوجه.
bool bioInFlight = false;

class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;
  @override ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  bool _locked = true, _cover = false; DateTime? _away;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    final s = ref.read(privacyProvider).value; if (s == null) return;
    if (bioInFlight) return;   // نافذة البصمة/الوجه نفسها تجعل التطبيق inactive — لا تُحتسب غيابًا
    if (st == AppLifecycleState.inactive) {
      // لا غطاء هنا: سحب لوحة الإشعارات ومربعات النظام تجعل التطبيق inactive. على أندرويد FLAG_SECURE يخفي المعاينة أصلًا.
    } else if (st == AppLifecycleState.hidden || st == AppLifecycleState.paused) {
      _away ??= DateTime.now();
      if (s.secure || s.lock) setState(() => _cover = true);
    } else if (st == AppLifecycleState.resumed) {
      final gone = _away == null ? Duration.zero : DateTime.now().difference(_away!);
      _away = null;
      setState(() { _cover = false; if (s.lock && gone.inMinutes >= s.autoLockMin) _locked = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(privacyProvider);
    return s.when(
      loading: () => const Scaffold(body: Center(child: AppLogo(size: 84))),
      error: (_, _) => widget.child,
      data: (p) { if (!p.lock) _locked = false;   // تفعيل القفل من الإعدادات لا يقفل فورًا؛ يبدأ من الغياب التالي
        final hide = (p.lock && _locked) || _cover;
        if (hide) WidgetsBinding.instance.addPostFrameCallback((_) => FocusManager.instance.primaryFocus?.unfocus());
        return Stack(children: [
        // المحتوى تحت القفل: لا تركيز (ريموت/لوحة مفاتيح)، لا قارئ شاشة، ولا حركة
        ExcludeFocus(excluding: hide, child: ExcludeSemantics(excluding: hide, child: TickerMode(enabled: !hide, child: widget.child))),
        if (p.lock && _locked) Positioned.fill(child: _LockScreen(bio: p.bio, onOk: () => setState(() => _locked = false))),
        if (_cover && !(p.lock && _locked)) const Positioned.fill(child: ColoredBox(color: C.bg, child: Center(child: AppLogo(size: 96)))),
      ]); },
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.bio, required this.onOk});
  final bool bio; final VoidCallback onOk;
  @override State<_LockScreen> createState() => _LockScreenState();
}
class _LockScreenState extends State<_LockScreen> {
  String _pin = ''; String _err = ''; int _fails = 0, _len = 4; DateTime? _until;
  @override void initState() { super.initState(); Privacy.pinLength().then((l) { if (mounted) setState(() => _len = l); }); if (widget.bio && !kIsWeb) WidgetsBinding.instance.addPostFrameCallback((_) => _bio()); }
  Future<void> _bio() async { bioInFlight = true; try { if (await Privacy.bioUnlock()) widget.onOk(); } finally { Future<void>.delayed(const Duration(milliseconds: 800), () => bioInFlight = false); } }
  Future<void> _tap(String d) async {
    if (_until != null && DateTime.now().isBefore(_until!)) return;
    setState(() { _pin += d; _err = ''; });
    if (_pin.length < _len) return;
    if (await Privacy.checkPin(_pin)) { widget.onOk(); return; }
    {
      _fails++;
      setState(() { _pin = ''; _err = 'رمز غير صحيح'; if (_fails >= 5) { _until = DateTime.now().add(Duration(seconds: 30 * (_fails - 4))); _err = 'محاولات كثيرة — انتظري ${30 * (_fails - 4)} ثانية'; } });
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: C.bg, body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const AppLogo(size: 88), const SizedBox(height: S.s4),
    Text('المفضلة مقفلة', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: S.s4),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < _len; i++) Container(margin: const EdgeInsets.all(5), width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: i < _pin.length ? C.gold : C.line2))]),
    SizedBox(height: 24, child: Text(_err, style: const TextStyle(color: C.danger))),
    for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) _key(d)]),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 84, height: 72, child: widget.bio && !kIsWeb ? IconButton(onPressed: _bio, icon: const Icon(Icons.fingerprint_rounded, size: 34, color: C.gold)) : null),
      _key('0'),
      SizedBox(width: 84, height: 72, child: IconButton(onPressed: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)), icon: const Icon(Icons.backspace_outlined))),
    ]),
  ])))));
  Widget _key(String d) => Padding(padding: const EdgeInsets.all(6), child: SizedBox(width: 72, height: 60, child: OutlinedButton(autofocus: d == '1', onPressed: () => _tap(d), child: Text(d, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)))));
}

/// إعدادات الخصوصية (في «المزيد»).
class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(privacyProvider).value ?? const PrivacySettings();
    final n = ref.read(privacyProvider.notifier);
    return Column(children: [
      SwitchListTile(value: p.lock, secondary: const Icon(Icons.lock_rounded, color: C.gold), title: const Text('قفل التطبيق برمز'), subtitle: const Text('4–8 أرقام. يُحفظ بصمة مملّحة فقط، لا الرمز نفسه.', style: TextStyle(color: C.muted)),
        onChanged: (v) async {
          if (v) { final pin = await _askNewPin(context); if (pin == null) return; await Privacy.setPin(pin); await n.set(p.copy(lock: true)); }
          else { await Privacy.clearPin(); await n.set(p.copy(lock: false, bio: false)); }
        }),
      if (p.lock) SwitchListTile(value: p.bio, secondary: const Icon(Icons.fingerprint_rounded, color: C.gold), title: const Text('الفتح بالبصمة أو الوجه'),
        onChanged: (v) async { if (v && !await Privacy.bioAvailable()) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('البصمة/الوجه غير متاحة على هذا الجهاز'))); return; } await n.set(p.copy(bio: v)); }),
      if (p.lock) ListTile(leading: const Icon(Icons.timer_outlined, color: C.gold), title: const Text('القفل التلقائي بعد الغياب'),
        trailing: DropdownButton<int>(value: p.autoLockMin, underline: const SizedBox(), items: const [DropdownMenuItem(value: 0, child: Text('فورًا')), DropdownMenuItem(value: 1, child: Text('دقيقة')), DropdownMenuItem(value: 5, child: Text('5 دقائق')), DropdownMenuItem(value: 15, child: Text('15 دقيقة'))], onChanged: (v) => n.set(p.copy(autoLockMin: v)))),
      SwitchListTile(value: p.secure, secondary: const Icon(Icons.screenshot_monitor_rounded, color: C.gold), title: const Text('منع لقطات الشاشة وإخفاء المعاينة'), subtitle: const Text('أندرويد: يمنع اللقطات ويخفي المحتوى في قائمة التطبيقات. آيفون: غطاء عند المغادرة.', style: TextStyle(color: C.muted)), onChanged: (v) => n.set(p.copy(secure: v))),
      SwitchListTile(value: p.blur, secondary: const Icon(Icons.blur_on_rounded, color: C.gold), title: const Text('تمويه كل الصور'), subtitle: const Text('مفيد أمام الآخرين', style: TextStyle(color: C.muted)), onChanged: (v) => n.set(p.copy(blur: v))),
    ]);
  }

  static Future<String?> _askNewPin(BuildContext context) async {
    final a = TextEditingController(), b = TextEditingController(); String err = '';
    final r = await showDialog<String>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('رمز جديد'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: a, keyboardType: TextInputType.number, obscureText: true, maxLength: 8, decoration: const InputDecoration(labelText: 'الرمز (4–8 أرقام)')),
        TextField(controller: b, keyboardType: TextInputType.number, obscureText: true, maxLength: 8, decoration: const InputDecoration(labelText: 'أعيدي الرمز')),
        if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.danger)),
        const Text('لا يمكن استرجاع الرمز إن نُسي — بياناتك تبقى، لكن ستحتاجين إعادة تثبيت أو نسخة احتياطية.', style: TextStyle(color: C.muted, fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () {
        if (!RegExp(r'^\d{4,8}$').hasMatch(a.text)) { set(() => err = '4 إلى 8 أرقام'); return; }
        if (a.text != b.text) { set(() => err = 'الرمزان غير متطابقين'); return; }
        Navigator.pop(c, a.text);
      }, child: const Text('حفظ'))])));
    a.dispose(); b.dispose(); return r;
  }
}
