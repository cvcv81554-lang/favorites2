import 'performer.dart';
import 'sanitize.dart';

/// مرجع عمل داخل سجل ممثلة (للكتابة عليه).
class WorkRef { final Performer p; final int idx; const WorkRef(this.p, this.idx); }

/// عمل موحّد عبر الممثلات (مثل wAll في التطبيق السابق): نفس المفتاح wkey(t)|wkey(s) = عمل واحد.
/// القيم: أول قيمة غير فارغة تفوز، والتقييم = الأعلى، والحالات (شوهد، للمشاهدة…) = أي مرجع.
class WorkGroup {
  final String key;
  String t = '', s = '', d = '', y = '', p = '', u = '', n = '', ds = '', wd = '';
  int r = 0, du = 0, a = 0;
  bool seen = false, q = false, upc = false, fav = false, rec = false;
  final Set<String> tg = {}, ls = {};
  final List<Performer> who = [];
  final List<WorkRef> refs = [];
  WorkGroup(this.key);

  String get date => d.isNotEmpty ? d : (y.isNotEmpty ? '$y-01-01' : '');
  bool get isUpcoming {
    if (seen) return false;
    if (upc) return true;
    final t0 = todayStr();
    if (d.isNotEmpty) return d.compareTo(t0) > 0;
    final yy = int.tryParse(y); return yy != null && yy > DateTime.now().year;
  }
  int? get daysUntil { if (d.isEmpty) return null; final x = DateTime.tryParse(d); if (x == null) return null; final n = DateTime.now(); return x.difference(DateTime(n.year, n.month, n.day)).inDays; }

  void _absorb(Map<String, dynamic> w, Performer it, int idx) {
    String s0(Object? v) => (v ?? '').toString();
    if (t.isEmpty) t = s0(w['t']);
    if (s.isEmpty) s = s0(w['s']);
    if (d.isEmpty && s0(w['d']).isNotEmpty) { d = s0(w['d']); y = d.substring(0, 4); }
    if (y.isEmpty) y = s0(w['y']);
    if (p.isEmpty) p = s0(w['p']);
    if (u.isEmpty) u = s0(w['u']);
    if (n.isEmpty) n = s0(w['n']);
    if (ds.isEmpty) ds = s0(w['ds']);
    final rr = (w['r'] as num?)?.toInt() ?? 0; if (rr > r) r = rr;
    final dd = (w['du'] as num?)?.toInt() ?? 0; if (du == 0 && dd > 0) du = dd;
    final aa = (w['a'] as num?)?.toInt() ?? 0; if (aa > a) a = aa;
    bool on(Object? v) => v == 1 || v == true;
    if (on(w['w'])) { seen = true; if (s0(w['wd']).isNotEmpty && s0(w['wd']).compareTo(wd) > 0) wd = s0(w['wd']); }
    if (on(w['q'])) q = true;
    if (on(w['upc'])) upc = true;
    if (on(w['fav'])) fav = true;
    if (on(w['rec'])) rec = true;
    for (final x in (w['tg'] as List? ?? const [])) { if (x is String) tg.add(x); }
    for (final x in (w['ls'] as List? ?? const [])) { if (x is String) ls.add(x); }
    if (!who.contains(it)) who.add(it);
    refs.add(WorkRef(it, idx));
  }
}

/// معرّف المشهد في مصدر رسمي (الأدق للتوحيد): StashDB ثم ThePornDB.
String? sceneIdOf(Map<String, dynamic> w) {
  final s = '${w['is'] ?? ''}', p = '${w['ip'] ?? ''}';
  return s.isNotEmpty ? 'is:$s' : p.isNotEmpty ? 'ip:$p' : null;
}

/// التوحيد عبر الممثلات:
///  1) الأعمال ذات معرّف مشهد تُوحَّد بالمعرّف (مشهدان مختلفان بنفس العنوان والاستوديو لا يندمجان أبدًا).
///  2) العمل بلا معرّف يُلحق بمجموعة معرّف **وحيدة** لها نفس العنوان والاستوديو، وإلا يُوحَّد بالعنوان والاستوديو.
List<WorkGroup> groupWorks(Iterable<Performer> items) {
  final map = <String, WorkGroup>{};
  final byTitle = <String, Set<String>>{};   // wKey → مفاتيح مجموعات المعرّفات
  final noId = <(Map<String, dynamic>, Performer, int)>[];
  for (final it in items) {
    final ws = it.works;
    for (var i = 0; i < ws.length; i++) {
      final wk = wKeyOf(ws[i]); if (wk == '|') continue;
      final sid = sceneIdOf(ws[i]);
      if (sid == null) { noId.add((ws[i], it, i)); continue; }
      (map[sid] ??= WorkGroup(sid))._absorb(ws[i], it, i);
      (byTitle[wk] ??= {}).add(sid);
    }
  }
  for (final (w, it, i) in noId) {
    final wk = wKeyOf(w); final ids = byTitle[wk];
    final k = (ids != null && ids.length == 1) ? ids.first : wk;
    (map[k] ??= WorkGroup(k))._absorb(w, it, i);
  }
  return map.values.toList();
}

/// مفتاح مجموعة عمل محدد (ممثلة + موضعه) — لفتح ورقته من صفحة الممثلة.
String? groupKeyOf(List<WorkGroup> groups, String pid, int idx) {
  for (final g in groups) { for (final r in g.refs) { if (r.p.id == pid && r.idx == idx) return g.key; } }
  return null;
}

/// يطبّق تعديلًا على كل نسخ العمل عند كل الممثلات ويعيد السجلات المعدّلة (للحفظ).
List<Performer> applyToGroup(WorkGroup g, void Function(Map<String, dynamic> w) fn) {
  final byP = <String, List<int>>{};
  for (final r in g.refs) { (byP[r.p.id] ??= []).add(r.idx); }
  final out = <Performer>[];
  for (final e in byP.entries) {
    final p = g.refs.firstWhere((r) => r.p.id == e.key).p;
    final ws = [for (final w in p.works) Map<String, dynamic>.from(w)];
    for (final i in e.value) { if (i < ws.length) fn(ws[i]); }
    out.add(p.copyWith({'works': ws}));
  }
  return out;
}
