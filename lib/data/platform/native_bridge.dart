import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import '../../domain/nl_query.dart';

/// جسر الآيفون الأصلي (AppDelegate.swift): نموذج Apple اللغوي على الجهاز، وتمييز الوجوه (Vision + Core ML).
/// كل شيء على الجهاز؛ وعلى غير الآيفون أو الأجهزة غير الداعمة يعيد «غير متاح» بهدوء.
class NativeBridge {
  static const _ch = MethodChannel('favorites2/native');
  static bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<T?> _call<T>(String m, [Object? a]) async {
    if (!_ios) return null;
    try { return await _ch.invokeMethod<T>(m, a); } on MissingPluginException { return null; } on PlatformException { return null; }
  }

  // ===== نموذج Apple اللغوي (iOS 26 + Apple Intelligence) =====
  /// 'available' أو سبب عدم التوفر (جهاز غير داعم، Apple Intelligence غير مفعّل، النموذج يُنزَّل…).
  static Future<String> aiStatus() async => await _call<String>('aiStatus') ?? 'unsupported';

  /// يحوّل البحث إلى فلاتر عبر النموذج على الجهاز؛ null إن لم يتوفر أو أخفق (يُستخدم المحلّل المحلي).
  static Future<NlQuery?> aiParse(String text) async {
    final r = await _call<String>('aiParse', {'text': text, 'instructions': nlModelInstructions}).timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (r == null) return null;
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(r); if (m == null) return null;
    try { final j = jsonDecode(m.group(0)!); return j is Map ? NlQuery.fromJson(j) : null; } catch (_) { return null; }
  }

  // ===== تمييز الوجوه =====
  /// 'ready' / 'missing' (النموذج لم يُنزَّل) / 'unsupported'.
  static Future<String> faceStatus() async => await _call<String>('faceStatus') ?? 'unsupported';

  /// تجهيز النموذج من ملف .mlmodel منزَّل: يُترجَم على الجهاز ويُحفظ (مرة واحدة).
  static Future<bool> faceInstall(String mlmodelPath, String sha256Hex) async => await _call<bool>('faceInstall', {'path': mlmodelPath, 'sha256': sha256Hex}) ?? false;

  /// بصمة أكبر وجه في الصورة (512 رقمًا، مُطبَّعة) — null إن لم يوجد وجه أو تعذّر.
  /// [faces]: عدد الوجوه في الصورة (للتنبيه إن كانت صورة جماعية).
  static Future<({Float32List v, int faces})?> faceEmbed(Uint8List image) async {
    final r = await _call<Map>('faceEmbed', {'image': image});
    final v = r?['v'];
    if (v is! Float32List || v.isEmpty) return null;
    return (v: v, faces: (r?['faces'] as num?)?.toInt() ?? 1);
  }
}
