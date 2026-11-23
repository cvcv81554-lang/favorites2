import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;

import '../domain/performer.dart';
import 'library_repo.dart';
import 'photo_hash.dart' show storedPhotoBytes;
import 'platform/model_download.dart';
import 'platform/native_bridge.dart';

/// تمييز الوجوه — على الجهاز فقط: بصمة الوجه (512 رقمًا) من نموذج AuraFace (Apache-2.0) عبر Core ML.
/// لا تُرسل أي صورة لأي جهة؛ الطلب الوحيد للشبكة هو تنزيل النموذج نفسه (مرة واحدة).
/// البصمات محفوظة في قاعدة التطبيق المحلية (kv: face_emb)، ولا تدخل النسخة الاحتياطية.
class Faces {
  /// مثبّت على نسخة محددة (commit) ومُتحقق من بصمته وحجمه قبل التثبيت — لا يُشغَّل ملف غير مطابق.
  static const modelUrl = 'https://huggingface.co/RuiSumida/AuraFace-v1-CoreML/resolve/fac7fea8becbb1963b80670cad1ee1eca4b38fb7/FaceEmbedding.mlmodel';
  static const modelSha256 = '9cb10bef2141a36619bb1fdbf1e0e14e2519c6da4b7e9b9969a4d67702d7122b';
  static const modelBytes = 130356005;
  static const modelMb = 130;
  /// عتبات التشابه (جيب التمام): لنماذج ArcFace عادةً نفس الشخص > 0.4، وشخصان مختلفان < 0.25.
  static const same = .45, maybe = .30;

  static Future<String> status() => NativeBridge.faceStatus();

  /// تنزيل النموذج (130 م.ب) ثم ترجمته على الجهاز.
  static Future<bool> install({void Function(double)? onProgress}) async {
    final path = await downloadModelFile(modelUrl, 'FaceEmbedding.mlmodel', sha256Hex: modelSha256, size: modelBytes, onProgress: onProgress);
    if (path == null) return false;
    return NativeBridge.faceInstall(path, modelSha256);
  }

  static String _key(String ref) => sha1.convert(utf8.encode(ref)).toString().substring(0, 20);

  /// بصمة صورة مخزنة (رابط أو ملف على الجهاز) — مع ذاكرة. [cache] تُحفظ لاحقًا دفعة واحدة.
  static Future<Float32List?> ofPhoto(String ref, Map<String, dynamic> cache) async {
    final k = _key(ref);
    final c = cache[k];
    if (c is String) return c.isEmpty ? null : Float32List.view(base64Decode(c).buffer);
    final b = await storedPhotoBytes(ref);
    if (b == null) return null;
    final e = await NativeBridge.faceEmbed(b);
    cache[k] = e == null || e.faces > 1 ? '' : base64Encode(e.v.buffer.asUint8List());   // صورة جماعية أو بلا وجه ⇒ تُتخطى
    return cache[k] == '' ? null : e!.v;
  }

  static Future<Map<String, dynamic>> loadCache(LibraryRepo repo) async => Map<String, dynamic>.from(await repo.kvGet('face_emb') as Map? ?? {});
  static Future<void> saveCache(LibraryRepo repo, Map<String, dynamic> c) => repo.kvSet('face_emb', c);
}

double cosine(Float32List a, Float32List b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var s = 0.0; for (var i = 0; i < a.length; i++) { s += a[i] * b[i]; }
  return s;   // البصمات مُطبَّعة مسبقًا
}

Float32List _normalized(List<double> v) {
  final n = sqrt(v.fold<double>(0, (a, x) => a + x * x));
  return Float32List.fromList([for (final x in v) n == 0 ? 0 : x / n]);
}

/// بصمة الممثلة: أكبر مجموعة متشابهة من صورها (الإجماع)، ثم متوسطها — فلا تُفسدها صورة لشخص آخر.
/// يعيد null إن كانت البصمات أقل من 2 أو لا إجماع.
Float32List? consensus(List<Float32List> es, {double link = Faces.maybe}) {
  if (es.isEmpty) return null;
  if (es.length == 1) return es.first;
  var best = <int>[];
  for (var i = 0; i < es.length; i++) {
    final g = [for (var j = 0; j < es.length; j++) if (i == j || cosine(es[i], es[j]) >= link) j];
    if (g.length > best.length) best = g;
  }
  if (best.length < 2) return null;
  final sum = List<double>.filled(es.first.length, 0);
  for (final i in best) { for (var k = 0; k < sum.length; k++) { sum[k] += es[i][k]; } }
  return _normalized(sum);
}

enum FaceVerdict { same, maybe, other, none }
FaceVerdict verdict(double? sim) => sim == null ? FaceVerdict.none : sim >= Faces.same ? FaceVerdict.same : sim >= Faces.maybe ? FaceVerdict.maybe : FaceVerdict.other;

/// فحص صور ممثلة: تشابه كل صورة مع بصمتها (الإجماع). [progress]: (تم، المجموع).
Future<List<({String ref, double? sim})>> checkAlbum(Performer p, LibraryRepo repo, {void Function(int, int)? progress}) async {
  if (p.isMinor) return const [];   // بوابة +18
  final cache = await Faces.loadCache(repo);
  final es = <String, Float32List>{};
  var i = 0;
  for (final r in p.photos) {
    progress?.call(++i, p.photos.length);
    final e = await Faces.ofPhoto(r, cache); if (e != null) es[r] = e;
  }
  await Faces.saveCache(repo, cache);
  final c = consensus(es.values.toList());
  return [for (final r in p.photos) (ref: r, sim: c == null || es[r] == null ? null : cosine(es[r]!, c))];
}

/// بصمات الممثلات (للبحث بصورة): تُبنى من حتى 6 صور لكل ممثلة، مع ذاكرة (kv: face_prof).
Future<Map<String, Float32List>> buildProfiles(List<Performer> ps, LibraryRepo repo, {void Function(int, int, String)? progress, bool Function()? cancelled}) async {
  final cache = await Faces.loadCache(repo);
  final prof = Map<String, dynamic>.from(await repo.kvGet('face_prof') as Map? ?? {});
  final out = <String, Float32List>{};
  var i = 0;
  for (final p in ps) {
    i++;
    if (p.isMinor || p.photos.isEmpty) continue;
    final sig = sha1.convert(utf8.encode(p.photos.take(6).join('|'))).toString().substring(0, 12);
    final c = prof[p.id];
    if (c is Map && c['s'] == sig) { if ('${c['v']}'.isNotEmpty) out[p.id] = Float32List.view(base64Decode('${c['v']}').buffer); continue; }
    if (cancelled?.call() == true) break;
    progress?.call(i, ps.length, p.name);
    final es = <Float32List>[];
    for (final r in p.photos.take(6)) { final e = await Faces.ofPhoto(r, cache); if (e != null) es.add(e); }
    final v = consensus(es) ?? (es.length == 1 ? es.first : null);
    prof[p.id] = {'s': sig, 'v': v == null ? '' : base64Encode(v.buffer.asUint8List())};
    if (v != null) out[p.id] = v;
    if (i % 10 == 0) { await Faces.saveCache(repo, cache); await repo.kvSet('face_prof', prof); }
  }
  await Faces.saveCache(repo, cache); await repo.kvSet('face_prof', prof);
  return out;
}

/// أقرب الممثلات لوجه في صورة: (الممثلة، التشابه) مرتبة.
List<(Performer, double)> rankByFace(Float32List face, Map<String, Float32List> profiles, List<Performer> lib, {int n = 10}) {
  final byId = {for (final p in lib) p.id: p};
  final l = [for (final e in profiles.entries) if (byId[e.key] != null && !byId[e.key]!.isMinor) (byId[e.key]!, cosine(face, e.value))]..sort((a, b) => b.$2.compareTo(a.$2));
  return l.take(n).toList();
}
