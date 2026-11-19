import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/sembast.dart';

import '../domain/age_gate.dart';
import '../domain/performer.dart';
import 'platform/db_factory.dart';

/// مصدر الحقيقة الوحيد لسجلات المكتبة (مثل save() في التطبيق السابق: نقطة الكتابة الوحيدة، وتُرفض القاصر دائمًا).
class LibraryRepo {
  LibraryRepo._(this._db);
  final Database _db;
  final _recs = stringMapStoreFactory.store('recs');
  final _kv = StoreRef<String, Object?>('kv');

  /// للاختبارات (قاعدة في الذاكرة).
  factory LibraryRepo.withDb(Database db) => LibraryRepo._(db);

  static Future<LibraryRepo> open({String name = 'favorites2'}) async {
    await warmPhotoDir();
    return LibraryRepo._(await openAppDb(name));
  }

  Future<List<Performer>> loadAll() async {
    final rows = await _recs.find(_db);
    final out = <Performer>[];
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r.value);
      if (minorRec(m)) continue; // لا يُعرض سجل قاصر أبدًا (ولا يُحذف تلقائيًا)
      out.add(Performer(m));
    }
    return out;
  }

  /// يحفظ ويعيد ما حُفظ فعلًا (القاصر تُرفض).
  Future<List<Performer>> save(Iterable<Performer> ps) async {
    final ok = ps.where((p) => !p.isMinor).toList();
    await _db.transaction((tx) async {
      for (final p in ok) { await _recs.record(p.id).put(tx, _jsonSafe(p.raw)); }
    });
    return ok;
  }

  Future<void> delete(String id) async {
    final r = await _recs.record(id).get(_db);
    await _recs.record(id).delete(_db);
    for (final ref in (r?['photos'] as List? ?? const [])) { if (ref is String) await deletePhoto(ref); }
    final th = r?['thumb']; if (th is String) await deletePhoto(th);
  }

  Future<Object?> kvGet(String k) => _kv.record(k).get(_db);
  Future<void> kvSet(String k, Object? v) => _kv.record(k).put(_db, v);

  /// يحوّل صورة data URI إلى ملف على الجهاز (على الويب تبقى كما هي).
  static Future<String> storeImage(String pid, int n, String ref) async {
    if (!ref.startsWith('data:image/')) return ref;
    final comma = ref.indexOf(',');
    final mime = ref.substring(11, ref.indexOf(';'));
    final ext = mime == 'png' ? 'png' : mime == 'webp' ? 'webp' : mime == 'gif' ? 'gif' : 'jpg';
    final bytes = base64Decode(ref.substring(comma + 1));
    final h = bytes.length.toRadixString(36);
    return storePhotoBytes('${pid}_${n}_$h.$ext', Uint8List.fromList(bytes));
  }

  /// يعيد الصورة data URI (للتصدير).
  static Future<String> exportImage(String ref) async {
    if (!ref.startsWith('file:')) return ref;
    final b = await readPhotoBytes(ref);
    if (b == null) return '';
    final ext = ref.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'png' : ext == 'webp' ? 'webp' : ext == 'gif' ? 'gif' : 'jpeg';
    return 'data:image/$mime;base64,${base64Encode(b)}';
  }

  static Map<String, dynamic> _jsonSafe(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
}
