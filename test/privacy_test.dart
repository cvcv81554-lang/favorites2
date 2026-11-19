// الخصوصية: الرمز يُخزَّن بصمة مملّحة فقط، والتحقق، وحفظ الإعدادات.
import 'package:favorites2/data/privacy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    switch (c.method) { case 'read': return store[a['key']]; case 'write': store[a['key']] = a['value']; return null; case 'delete': store.remove(a['key']); return null; }
    return null;
  });

  test('الرمز لا يُخزَّن نصًا، والتحقق يعمل، والملح عشوائي', () async {
    await Privacy.setPin('2468');
    expect(store.values.contains('2468'), isFalse);
    expect(await Privacy.checkPin('2468'), isTrue);
    expect(await Privacy.checkPin('1357'), isFalse);
    expect(await Privacy.pinLength(), 4);
    final h1 = store['pin_hash']; await Privacy.setPin('2468');
    expect(store['pin_hash'] == h1, isFalse); // ملح جديد ⇒ بصمة مختلفة
    await Privacy.clearPin();
    expect(await Privacy.hasPin(), isFalse); expect(await Privacy.checkPin('2468'), isFalse);
  });

  test('إعدادات الخصوصية: افتراضيًا منع اللقطات مفعّل والقفل متوقف، وتُحفظ بلا فقد', () {
    const d = PrivacySettings();
    expect(d.secure, isTrue); expect(d.lock, isFalse);
    final s = PrivacySettings.fromJson(const PrivacySettings(lock: true, bio: true, secure: false, blur: true, autoLockMin: 5).toJson());
    expect([s.lock, s.bio, s.secure, s.blur, s.autoLockMin], [true, true, false, true, 5]);
  });
}
