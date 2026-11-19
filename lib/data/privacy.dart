import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// الخصوصية: قفل برمز (يُخزَّن بصمة مملّحة فقط في المخزن الآمن، لا الرمز نفسه)، بصمة/وجه، منع لقطات الشاشة، وتمويه الصور.
class PrivacySettings {
  final bool lock, bio, secure, blur; final int autoLockMin;
  const PrivacySettings({this.lock = false, this.bio = false, this.secure = true, this.blur = false, this.autoLockMin = 1});
  Map<String, dynamic> toJson() => {'lock': lock, 'bio': bio, 'secure': secure, 'blur': blur, 'auto': autoLockMin};
  factory PrivacySettings.fromJson(Map? j) => PrivacySettings(lock: j?['lock'] == true, bio: j?['bio'] == true, secure: j?['secure'] != false, blur: j?['blur'] == true, autoLockMin: (j?['auto'] as num?)?.toInt() ?? 1);
  PrivacySettings copy({bool? lock, bool? bio, bool? secure, bool? blur, int? autoLockMin}) => PrivacySettings(lock: lock ?? this.lock, bio: bio ?? this.bio, secure: secure ?? this.secure, blur: blur ?? this.blur, autoLockMin: autoLockMin ?? this.autoLockMin);
}

/// تمويه كل الصور (زر سريع) — يقرؤه مكوّن الصورة مباشرة.
final blurPhotos = ValueNotifier<bool>(false);

class Privacy {
  static const _s = FlutterSecureStorage();
  static const _ch = MethodChannel('favorites2/privacy');
  static final _auth = LocalAuthentication();

  static String hashPin(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<bool> hasPin() async => (await _s.read(key: 'pin_hash') ?? '').isNotEmpty;
  static Future<void> setPin(String pin) async {
    final r = Random.secure(); final salt = base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
    await _s.write(key: 'pin_salt', value: salt); await _s.write(key: 'pin_hash', value: hashPin(pin, salt)); await _s.write(key: 'pin_len', value: '${pin.length}');
  }
  static Future<void> clearPin() async { await _s.delete(key: 'pin_hash'); await _s.delete(key: 'pin_salt'); await _s.delete(key: 'pin_len'); }
  static Future<int> pinLength() async => int.tryParse(await _s.read(key: 'pin_len') ?? '') ?? 4;
  static Future<bool> checkPin(String pin) async {
    final salt = await _s.read(key: 'pin_salt'), h = await _s.read(key: 'pin_hash');
    if (salt == null || h == null) return false;
    return hashPin(pin, salt) == h;
  }

  static Future<bool> bioAvailable() async { if (kIsWeb) return false; try { return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics; } catch (_) { return false; } }
  static Future<bool> bioUnlock() async {
    try { return await _auth.authenticate(localizedReason: 'افتحي مكتبتك الخاصة', biometricOnly: false, persistAcrossBackgrounding: true); } catch (_) { return false; }
  }

  /// هل الجهاز تلفاز (Android TV: ميزة leanback)؟
  static Future<bool> isTv() async { if (kIsWeb) return false; try { return await _ch.invokeMethod<bool>('isTv') ?? false; } catch (_) { return false; } }

  /// أندرويد: FLAG_SECURE (لا لقطات شاشة، والمحتوى مخفي في قائمة التطبيقات). على المنصات الأخرى غطاء داخل التطبيق.
  static Future<void> applySecure(bool on) async { if (kIsWeb) return; try { await _ch.invokeMethod('setSecure', {'on': on}); } catch (_) {} }
}
