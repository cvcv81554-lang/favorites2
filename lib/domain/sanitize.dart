// تنقية كل ما يدخل من ملف أو مزامنة أو API (منقولة من 01a: safeId / safeImg / safeWorks، و01c: ydOf / wkey).

final _safeId = RegExp(r'^[\w.:-]{1,128}$');
bool safeId(Object? v) => v is String && _safeId.hasMatch(v);

final _imgData = RegExp(r'^data:image/(png|jpe?g|webp|gif|avif);base64,', caseSensitive: false);
final _badImgChars = RegExp(r'["<>`\\]');

/// صورة مقبولة: https/http أو data:image بصيغة معروفة، بلا رموز خطرة. (مسار ملف محلي `file:` يُقبل داخليًا فقط.)
bool safeImg(Object? v) {
  if (v is! String || v.isEmpty) return false;
  if (_badImgChars.hasMatch(v)) return false;
  if (v.startsWith('https://') || v.startsWith('http://')) return true;
  return _imgData.hasMatch(v);
}

bool safeHttps(Object? v) => v is String && v.startsWith('https://') && !_badImgChars.hasMatch(v);

/// مفتاح العمل عبر الممثلات: الحروف والأرقام فقط (Unicode) بأحرف صغيرة.
final _notAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
String wkey(Object? t) => (t ?? '').toString().toLowerCase().replaceAll(_notAlnum, '');
String wKeyOf(Map<String, dynamic> w) => '${wkey(w['t'])}|${wkey(w['s'])}';

/// تطبيع اسم للمقارنة (بحث، تطابق).
String norm(Object? s) => (s ?? '').toString().toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

String _p2(int n) => n.toString().padLeft(2, '0');

/// تاريخ عمل: يقبل YYYY-M-D و D-M-YYYY و YYYY-M و YYYY ⇒ {d, y}.
Map<String, String> ydOf(Object? raw) {
  final s = (raw ?? '').toString().trim();
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
  if (m != null) return {'d': '${m[1]}-${_p2(int.parse(m[2]!))}-${_p2(int.parse(m[3]!))}', 'y': m[1]!};
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})').firstMatch(s);
  if (m != null) return {'d': '${m[3]}-${_p2(int.parse(m[2]!))}-${_p2(int.parse(m[1]!))}', 'y': m[3]!};
  m = RegExp(r'^(\d{4})[-/.](\d{1,2})$').firstMatch(s);
  if (m != null) return {'y': m[1]!};
  m = RegExp(r'^(\d{4})$').firstMatch(s);
  if (m != null) return {'y': m[1]!};
  return {};
}

String todayStr([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
}

/// تنقية قائمة أعمال واردة: حقول معروفة الأنواع، روابط https فقط، وحدود الأحجام.
List<Map<String, dynamic>> safeWorks(Object? v) {
  if (v is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final x in v.take(5000)) {
    if (x is String) {
      // صيغة قديمة: "عنوان | موقع | سنة" أو "عنوان (YYYY)"
      final parts = x.split('|').map((e) => e.trim()).toList();
      if (parts.isEmpty || parts[0].isEmpty) continue;
      final w = <String, dynamic>{'t': parts[0]};
      if (parts.length > 1 && parts[1].isNotEmpty) w['s'] = parts[1];
      if (parts.length > 2 && RegExp(r'^\d{4}$').hasMatch(parts[2])) w['y'] = parts[2];
      final ym = RegExp(r'^(.*)\((\d{4})\)\s*$').firstMatch(parts[0]);
      if (ym != null) { w['t'] = ym[1]!.trim(); w['y'] = ym[2]; }
      out.add(w);
      continue;
    }
    if (x is! Map) continue;
    final w = Map<String, dynamic>.from(x);
    final t = (w['t'] ?? '').toString().trim();
    if (t.isEmpty) continue;
    w['t'] = t.length > 400 ? t.substring(0, 400) : t;
    if (w['p'] != null && !safeHttps(w['p'])) w.remove('p');
    if (w['u'] != null && !safeHttps(w['u'])) w.remove('u');
    for (final k in ['ip', 'is']) { if (w[k] != null && !RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch('${w[k]}')) w.remove(k); }
    if (w['im'] != null && !RegExp(r'^tt\d{5,10}$').hasMatch('${w['im']}')) w.remove('im');
    if (w['tm'] != null && !RegExp(r'^\d{1,10}$').hasMatch('${w['tm']}')) w.remove('tm');
    if (w['tg'] is List) { w['tg'] = (w['tg'] as List).whereType<String>().toSet().take(10).toList(); } else { w.remove('tg'); }
    if (w['ls'] is List) { w['ls'] = (w['ls'] as List).whereType<String>().toList(); } else { w.remove('ls'); }
    out.add(w);
  }
  return out;
}
