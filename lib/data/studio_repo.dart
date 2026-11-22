import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sembast/sembast.dart';

import '../domain/performer.dart';
import '../domain/sanitize.dart';
import 'platform/db_factory.dart';
import 'sources.dart';

/// صورة في الاستديو (قاعدة مستقلة عن المكتبة).
class StudioImg {
  final String id, pid, url, src, kind; // src: stash | tpdb | scene ; kind: portrait | still
  final int w, h, found;
  int seen; bool like; List<String> albums;
  /// مخفية بالفرز السريع (حقل اختياري جديد «hid» — تبقى في القاعدة ولا تظهر في المعرض).
  bool hid;
  StudioImg({required this.id, required this.pid, required this.url, required this.src, required this.kind, this.w = 0, this.h = 0, required this.found, this.seen = 0, this.like = false, this.hid = false, List<String>? albums}) : albums = albums ?? [];
  int get longSide => w > h ? w : h;
  Map<String, dynamic> toJson() => {'id': id, 'pid': pid, 'url': url, 'src': src, 'kind': kind, 'w': w, 'h': h, 'found': found, 'seen': seen, 'like': like, 'albums': albums, if (hid) 'hid': true};
  factory StudioImg.fromJson(Map<String, dynamic> j) => StudioImg(id: '${j['id']}', pid: '${j['pid']}', url: '${j['url']}', src: '${j['src'] ?? ''}', kind: '${j['kind'] ?? 'portrait'}',
      w: (j['w'] as num?)?.toInt() ?? 0, h: (j['h'] as num?)?.toInt() ?? 0, found: (j['found'] as num?)?.toInt() ?? 0, seen: (j['seen'] as num?)?.toInt() ?? 0, like: j['like'] == true, hid: j['hid'] == true, albums: ((j['albums'] as List?) ?? const []).cast<String>());

  /// صورة الشبكة: StashDB يدعم رسميًا ?size=300|600|1280 (stash-box routes_image.go) — أخف بكثير من الأصل.
  String get thumb => sized(url, 600);
  /// للبطاقات العريضة (لقطات المشاهد): 1280 — حادة على شاشات 3x.
  String get wide => sized(url, 1280);
  static String sized(String u, int n) {
    final x = Uri.tryParse(u);
    if (x == null || !RegExp(r'(^|\.)stashdb\.org$').hasMatch(x.host) || !x.path.contains('/images/') || x.queryParameters.containsKey('size')) return u;
    return x.replace(queryParameters: {...x.queryParameters, 'size': '$n'}).toString();
  }
}

class StudioRepo {
  StudioRepo._(this._db);
  final Database _db;
  final _img = StoreRef<String, Map<String, Object?>>('img');
  final _kv = StoreRef<String, Object?>('kv');
  static Future<StudioRepo> open() async => StudioRepo._(await openAppDb('favorites2_studio'));
  /// للاختبارات (قاعدة في الذاكرة).
  factory StudioRepo.withDb(Database db) => StudioRepo._(db);

  Future<List<StudioImg>> all() async => [for (final r in await _img.find(_db)) StudioImg.fromJson(Map<String, dynamic>.from(r.value))];
  Future<void> put(Iterable<StudioImg> l) => _db.transaction((tx) async { for (final x in l) { await _img.record(x.id).put(tx, x.toJson()); } });
  Future<Object?> kvGet(String k) => _kv.record(k).get(_db);
  Future<void> kvSet(String k, Object? v) => _kv.record(k).put(_db, v);
  Future<void> removePerformer(String pid) async { await _img.delete(_db, finder: Finder(filter: Filter.and([Filter.equals('pid', pid), Filter.equals('like', false)]))); }

  static String idOf(String url) => sha1.convert(utf8.encode(url)).toString().substring(0, 20);

  /// اكتشاف الصور لممثلات المكتبة (البالغات فقط — البوابة قبل أي طلب):
  ///  - صور الممثلة من StashDB (findPerformer.images) للمرتبطات.
  ///  - صور مشاهدها الموجودة أصلًا في أعمالها (بلا طلب شبكة).
  /// لا يعيد إضافة صورة موجودة (المعرّف = بصمة الرابط).
  Future<int> discover(List<Performer> lib, {void Function(String)? progress, bool network = true, bool tpdb = false}) async {
    final have = {for (final x in await all()) x.id};
    final now = DateTime.now().millisecondsSinceEpoch; final add = <StudioImg>[];
    void push(String pid, String url, String src, String kind, int w, int h) {
      if (!safeHttps(url)) return; final id = idOf(url); if (have.contains(id)) return; have.add(id);
      add.add(StudioImg(id: id, pid: pid, url: url, src: src, kind: kind, w: w, h: h, found: now));
    }
    final adults = lib.where((p) => !p.isMinor).toList();
    for (final p in adults) { for (final w in p.works) { final u = '${w['p'] ?? ''}'; if (u.isNotEmpty) push(p.id, u, 'scene', 'still', 0, 0); } }
    if (network) {
      final linked = adults.where((p) => p.stashId.isNotEmpty).toList();
      var i = 0;
      for (final p in linked) {
        progress?.call('صور ${p.name} (${++i}/${linked.length})');
        try {
          final d = await StashDB.q(r'query($id:ID!){findPerformer(id:$id){images{url width height}}}', {'id': p.stashId});
          for (final m in ((d['findPerformer'] as Map?)?['images'] as List? ?? const [])) {
            if (m is Map) push(p.id, '${m['url']}', 'stash', 'portrait', (m['width'] as num?)?.toInt() ?? 0, (m['height'] as num?)?.toInt() ?? 0);
          }
        } on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    // ThePornDB الرسمي: صور الممثلة (posters) لمن لها معرّف — البالغات فقط
    if (tpdb) {
      final linked = adults.where((p) => p.pdbId.isNotEmpty).toList();
      var i = 0;
      for (final p in linked) {
        progress?.call('ThePornDB: ${p.name} (${++i}/${linked.length})');
        try {
          final d = await TPDB.get('/performers/${Uri.encodeComponent(p.pdbId)}');
          for (final u in tpdbPerformerImages(d)) { push(p.id, u, 'tpdb', 'portrait', 0, 0); }
        } on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (add.isNotEmpty) await put(add);
    await kvSet('last', now);
    return add.length;
  }
}

/// صور ممثلة من رد ThePornDB (/performers/{id}): posters[].url ثم image/thumbnail — روابط https فقط.
List<String> tpdbPerformerImages(Map<String, dynamic> d) {
  final p = (d['data'] is Map ? d['data'] : d) as Map;
  final out = <String>[];
  for (final x in (p['posters'] as List? ?? const [])) { final u = x is Map ? '${x['url'] ?? x['large'] ?? ''}' : '$x'; if (safeHttps(u) && !out.contains(u)) out.add(u); }
  for (final k in ['image', 'face', 'thumbnail']) { final u = '${p[k] ?? ''}'; if (safeHttps(u) && !out.contains(u)) out.add(u); }
  return out.take(30).toList();
}
