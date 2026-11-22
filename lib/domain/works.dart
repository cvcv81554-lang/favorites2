import 'performer.dart';
import 'sanitize.dart';

/// مرجع عمل داخل سجل ممثلة (للكتابة عليه).
class WorkRef { final Performer p; final int idx; const WorkRef(this.p, this.idx); }

/// عمل موحّد عبر الممثلات (مثل wAll في التطبيق السابق): نفس المفتاح wkey(t)|wkey(s) = عمل واحد.
/// القيم: أول قيمة غير فارغة تفوز، والتقييم = الأعلى، والحالات (شوهد، للمشاهدة…) = أي مرجع.
class WorkGroup {
  final String key;
  String t = '', s = '', d = '', y = '', p = '', u = '', n = '', ds = '', wd = '', tr = '';   // tr: رابط الإعلان الرسمي
  int r = 0, du = 0, a = 0;
  bool seen = false, q = false, upc = false, fav = false, rec = false;
  final Set<String> tg = {}, ls = {};
  /// تقييم بمعايير (الأداء، التصوير، القصة) — حقل اختياري جديد «rc».
  final Map<String, int> rc = {};
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
    if (tr.isEmpty) tr = s0(w['tr']);
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
    final m = w['rc']; if (m is Map) { m.forEach((k, v) { if (v is num && v > 0 && (rc['$k'] ?? 0) < v) rc['$k'] = v.toInt(); }); }
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

/// كل معرّفات العمل في المصادر الرسمية (قد يحمل الاثنين بعد الدمج).
List<String> sceneIdsOf(Map<String, dynamic> w) {
  final s = '${w['is'] ?? ''}', p = '${w['ip'] ?? ''}';
  return [if (s.isNotEmpty) 'is:$s', if (p.isNotEmpty) 'ip:$p'];
}

/// تطبيع عنوان للمقارنة بين المصدرين (حروف وأرقام فقط).
String normTitle(Object? s) => (s ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
String _compact(Object? s) => normTitle(s).replaceAll(' ', '');

/// تعارض: نفس المصدر بمعرّفين مختلفين ⇒ عملان مختلفان حتمًا.
bool idConflict(Map<String, dynamic> a, Map<String, dynamic> b) {
  bool diff(String k) { final x = '${a[k] ?? ''}', y = '${b[k] ?? ''}'; return x.isNotEmpty && y.isNotEmpty && x != y; }
  return diff('is') || diff('ip');
}
bool sharesId(Map<String, dynamic> a, Map<String, dynamic> b) { final x = sceneIdsOf(a).toSet(); return sceneIdsOf(b).any(x.contains); }

int? _days(Map<String, dynamic> a, Map<String, dynamic> b) {
  final x = DateTime.tryParse('${a['d'] ?? ''}'), y = DateTime.tryParse('${b['d'] ?? ''}');
  return x == null || y == null ? null : x.difference(y).inDays.abs();
}

/// نفس العمل؟ (للتوحيد بين StashDB وThePornDB والإدخال اليدوي)
/// - معرّف مشترك ⇒ نعم. تعارض معرّف من نفس المصدر ⇒ لا.
/// - وإلا: العنوان نفسه (بعد التطبيع) + الاستوديو متقارب (أو غائب) + التاريخ متقارب (±3 أيام) إن وُجد في الاثنين.
bool sameWork(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (sharesId(a, b)) return true;
  if (idConflict(a, b)) return false;
  final ta = normTitle(a['t']); if (ta.isEmpty || ta != normTitle(b['t'])) return false;
  final d = _days(a, b);
  if (d != null && d > 3) return false;
  final sa = _compact(a['s']), sb = _compact(b['s']);
  final studioOk = sa.isEmpty || sb.isEmpty || sa == sb || sa.contains(sb) || sb.contains(sa);
  return studioOk || d == 0;
}

/// التوحيد عبر الممثلات والمصدرين:
///  1) المعرّفات المحمولة معًا في عمل واحد تُربط (is ↔ ip).
///  2) مجموعات من مصدرين مختلفين بنفس العمل (العنوان/الاستوديو/التاريخ) تُربط إن لم يتعارض معرّفاهما.
///  3) العمل بلا معرّف يُلحق بمجموعة **وحيدة** مطابقة، وإلا يُوحَّد بالعنوان والاستوديو.
List<WorkGroup> groupWorks(Iterable<Performer> items) {
  final parent = <String, String>{};
  String find(String x) { var r = x; while (parent[r] != null && parent[r] != r) { r = parent[r]!; } var c = x; while (parent[c] != null && parent[c] != r) { final n = parent[c]!; parent[c] = r; c = n; } return r; }
  final kinds = <String, Map<String, String>>{};   // الجذر ⇒ {is: id, ip: id}
  void add(String x) { if (parent[x] == null) { parent[x] = x; kinds[x] = {x.substring(0, 2): x}; } }
  bool union(String a, String b) {
    var ra = find(a), rb = find(b); if (ra == rb) return true;
    final ka = kinds[ra]!, kb = kinds[rb]!;
    for (final k in ka.keys) { if (kb[k] != null && kb[k] != ka[k]) return false; }   // تعارض من نفس المصدر
    if (ra.startsWith('ip:') && rb.startsWith('is:')) { final t = ra; ra = rb; rb = t; }   // جذر StashDB مفضّل (مفتاح ثابت)
    parent[rb] = ra; kinds[ra] = {...kinds[rb]!, ...kinds[ra]!}; kinds.remove(rb);
    return true;
  }
  final withId = <(Map<String, dynamic>, Performer, int)>[], noId = <(Map<String, dynamic>, Performer, int)>[];
  for (final it in items) {
    final ws = it.works;
    for (var i = 0; i < ws.length; i++) {
      if (wKeyOf(ws[i]) == '|') continue;
      final ids = sceneIdsOf(ws[i]);
      if (ids.isEmpty) { noId.add((ws[i], it, i)); continue; }
      for (final x in ids) { add(x); }
      for (final x in ids.skip(1)) { union(ids.first, x); }
      withId.add((ws[i], it, i));
    }
  }
  // 2) ربط المصدرين بالعنوان (داخل نفس العنوان المطبّع فقط)
  final byT = <String, List<Map<String, dynamic>>>{};
  for (final (w, _, _) in withId) { (byT[normTitle(w['t'])] ??= []).add(w); }
  for (final l in byT.values) {
    if (l.length < 2) continue;
    for (var a = 0; a < l.length; a++) {
      for (var b = a + 1; b < l.length; b++) {
        if (find(sceneIdsOf(l[a]).first) != find(sceneIdsOf(l[b]).first) && sameWork(l[a], l[b])) union(sceneIdsOf(l[a]).first, sceneIdsOf(l[b]).first);
      }
    }
  }
  final map = <String, WorkGroup>{};
  final reps = <String, List<(String, Map<String, dynamic>)>>{};   // العنوان ⇒ (الجذر، عمل ممثّل)
  for (final (w, it, i) in withId) {
    final k = find(sceneIdsOf(w).first);
    (map[k] ??= WorkGroup(k))._absorb(w, it, i);
    final l = reps[normTitle(w['t'])] ??= [];
    if (!l.any((e) => e.$1 == k)) l.add((k, w));
  }
  for (final (w, it, i) in noId) {
    final m = (reps[normTitle(w['t'])] ?? const <(String, Map<String, dynamic>)>[]).where((e) => sameWork(e.$2, w)).map((e) => e.$1).toSet();
    final k = m.length == 1 ? m.first : wKeyOf(w);
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
