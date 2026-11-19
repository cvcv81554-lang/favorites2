import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../domain/age_gate.dart';
import '../domain/performer.dart';
import '../domain/sanitize.dart';
import 'library_repo.dart';

/// النسخة الاحتياطية — نفس صيغة التطبيق السابق تمامًا (18-backup.js) في الاتجاهين:
///   {"app":"vkte-favorites","v":5,"exportedAt":ms,"lists":[],"wlists":[],"prefs":{},"items":[...]}
///   والمشفّرة {app:'vkte-enc',v:1,salt,iv,data} = AES-GCM-256 بمفتاح PBKDF2-SHA256 (200000 دورة).
/// مفاتيح API والرمز السري لا تُصدَّر أبدًا.
class BackupFile {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> lists, wlists;
  final Map<String, String> prefs;
  final int minorsSkipped, invalid;
  BackupFile(this.items, this.lists, this.wlists, this.prefs, this.minorsSkipped, this.invalid);
}

class BackupError implements Exception { final String msg; BackupError(this.msg); @override String toString() => msg; }

class Backup {
  static bool isEncrypted(String text) { try { final j = jsonDecode(text); return j is Map && j['app'] == 'vkte-enc'; } catch (_) { return false; } }

  static final _pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 200000, bits: 256);
  static final _gcm = AesGcm.with256bits();
  /// PBKDF2 (200000 دورة) في عزلة منفصلة كي لا تتجمد الواجهة (الويب: مباشرة).
  static Future<SecretKey> _key(String password, List<int> salt) async {
    if (kIsWeb) return _pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
    final b = await Isolate.run(() async => (await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 200000, bits: 256).deriveKeyFromPassword(password: password, nonce: salt)).extractBytes());
    return SecretKey(b);
  }

  static Future<String> decrypt(String text, String password) async {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['app'] != 'vkte-enc' || j['v'] != 1) throw BackupError('ملف مشفّر بصيغة غير معروفة');
    final salt = base64Decode(j['salt']), iv = base64Decode(j['iv']), data = base64Decode(j['data']);
    if (data.length < 17) throw BackupError('الملف تالف');
    final key = await _key(password, salt);
    final box = SecretBox(data.sublist(0, data.length - 16), nonce: iv, mac: Mac(data.sublist(data.length - 16)));
    try { return utf8.decode(await _gcm.decrypt(box, secretKey: key)); }
    catch (_) { throw BackupError('كلمة المرور غير صحيحة أو الملف تالف'); }
  }

  static Future<String> encrypt(String json, String password) async {
    if (password.length < 8) throw BackupError('كلمة المرور 8 أحرف على الأقل');
    final rnd = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    final iv = Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));
    final key = await _key(password, salt);
    final box = await _gcm.encrypt(utf8.encode(json), secretKey: key, nonce: iv);
    return jsonEncode({'app': 'vkte-enc', 'v': 1, 'salt': base64Encode(salt), 'iv': base64Encode(iv), 'data': base64Encode([...box.cipherText, ...box.mac.bytes])});
  }

  /// قراءة وتنقية (بلا كتابة). يرفض القاصر ويعدّها.
  static BackupFile parse(String text) {
    final Object? j;
    try { j = jsonDecode(text); } catch (_) { throw BackupError('الملف ليس JSON صالحًا'); }
    if (j is! Map || j['items'] is! List) throw BackupError('ليس ملف نسخة احتياطية من المفضلة');
    final raw = j['items'] as List;
    if (raw.length > 50000) throw BackupError('عدد السجلات أكبر من المسموح');
    final items = <Map<String, dynamic>>[]; var minors = 0, invalid = 0;
    for (final x in raw) {
      if (x is! Map || !safeId(x['id']) || x['name'] is! String || (x['name'] as String).trim().isEmpty) { invalid++; continue; }
      final m = Map<String, dynamic>.from(x);
      if (minorRec(m)) { minors++; continue; }
      m['name'] = (m['name'] as String).trim();
      if ((m['name'] as String).length > 300) m['name'] = (m['name'] as String).substring(0, 300);
      m['photos'] = (m['photos'] is List ? m['photos'] as List : const []).where(safeImg).take(30).toList();
      if (m['thumb'] != null && !safeImg(m['thumb'])) m.remove('thumb');
      m['tags'] = (m['tags'] is List ? m['tags'] as List : const []).whereType<String>().take(100).toList();
      m['works'] = safeWorks(m['works']);
      items.add(m);
    }
    List<Map<String, dynamic>> idName(Object? v) => (v is List ? v : const []).whereType<Map>().where((e) => safeId(e['id']) && e['name'] is String).map((e) => {'id': e['id'], 'name': e['name']}).toList();
    final prefs = <String, String>{};
    if (j['prefs'] is Map) { (j['prefs'] as Map).forEach((k, v) { if (k is String && k.startsWith('vkte_') && v is String) prefs[k] = v; }); }
    // لا مفاتيح API ولا رمز سري حتى لو وُجدت في ملف قديم
    prefs.removeWhere((k, _) => const {'vkte_key', 'vkte_stash', 'vkte_pin', 'vkte_pin2'}.contains(k));
    return BackupFile(items, idName(j['lists']), idName(j['wlists']), prefs, minors, invalid);
  }

  /// قواعد الدمج (لا حذف أبدًا): جديد ⇒ يُضاف؛ موجود ⇒ يُستبدل فقط إن كان أحدث، وإلا تُكمل صوره الناقصة فقط.
  static Future<({int added, int updated, int photosFixed})> apply(LibraryRepo repo, BackupFile f, List<Performer> current) async {
    final byId = {for (final p in current) p.id: p};
    final out = <Performer>[]; var added = 0, updated = 0, fixed = 0;
    for (final m in f.items) {
      final cur = byId[m['id']];
      final refs = <String>[];
      final photos = (m['photos'] as List).cast<String>();
      if (cur == null || ((m['updated'] as num?) ?? 0) > cur.updated || cur.photos.length < photos.length) {
        for (var i = 0; i < photos.length; i++) { refs.add(await LibraryRepo.storeImage(m['id'], i, photos[i])); }
      }
      if (cur == null) {
        final th = m['thumb'] is String ? await LibraryRepo.storeImage(m['id'], 99, m['thumb']) : (refs.isNotEmpty ? refs.first : '');
        out.add(Performer({...m, 'photos': refs, 'thumb': th})); added++;
      } else if (((m['updated'] as num?) ?? 0) > cur.updated) {
        final keep = {for (final k in Performer.deviceLocal) if (cur.raw.containsKey(k)) k: cur.raw[k]};
        final th = m['thumb'] is String ? await LibraryRepo.storeImage(m['id'], 99, m['thumb']) : (refs.isNotEmpty ? refs.first : cur.thumb);
        out.add(Performer({...m, ...keep, 'photos': refs, 'thumb': th})); updated++;
      } else if (cur.photos.length < photos.length) {
        out.add(Performer({...cur.raw, 'photos': refs})); fixed++;
      }
    }
    await repo.save(out);
    return (added: added, updated: updated, photosFixed: fixed);
  }

  /// تصدير بنفس الصيغة (الصور data URI) — يُقرأ في التطبيق السابق والجديد.
  static Future<String> export(List<Performer> items, {List<Map<String, dynamic>> lists = const [], List<Map<String, dynamic>> wlists = const [], Map<String, String> prefs = const {}}) async {
    final arr = <Map<String, dynamic>>[];
    for (final p in items) {
      final m = Map<String, dynamic>.from(p.raw);
      m['photos'] = [for (final r in p.photos) await LibraryRepo.exportImage(r)]..removeWhere((e) => e.isEmpty);
      if (p.thumb.isNotEmpty) m['thumb'] = await LibraryRepo.exportImage(p.thumb);
      arr.add(m);
    }
    final pr = Map<String, String>.from(prefs)..removeWhere((k, _) => const {'vkte_key', 'vkte_stash', 'vkte_pin', 'vkte_pin2'}.contains(k));
    return jsonEncode({'app': 'vkte-favorites', 'v': 5, 'exportedAt': DateTime.now().millisecondsSinceEpoch, 'lists': lists, 'wlists': wlists, 'prefs': pr, 'items': arr});
  }
}
