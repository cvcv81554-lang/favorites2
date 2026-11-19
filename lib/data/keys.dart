import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// مفاتيح API في المخزن الآمن للنظام (Keychain على iOS، Keystore على أندرويد) — أكثر أمانًا من التطبيق السابق.
/// لا تدخل النسخة الاحتياطية ولا المستودع أبدًا، والمستخدم يكتبها بنفسه.
class ApiKeys {
  static const _s = FlutterSecureStorage();
  static const tpdb = 'tpdb_key', stash = 'stash_key';
  static final Map<String, String> _cache = {};

  static Future<String> get(String k) async => _cache[k] ??= (await _s.read(key: k)) ?? '';
  static Future<void> set(String k, String v) async {
    final t = v.trim();
    _cache[k] = t;
    if (t.isEmpty) { await _s.delete(key: k); } else { await _s.write(key: k, value: t); }
  }
  static Future<bool> has(String k) async => (await get(k)).isNotEmpty;
}
