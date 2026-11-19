import 'performer.dart';

/// التقييم التفصيلي ومنصات الحسابات — نفس مفاتيح التطبيق السابق (CRIT / BODY / PLAT) كي تبقى البيانات متوافقة.
const crit = {'beauty': 'الجمال', 'charisma': 'الكاريزما', 'perf': 'الأداء', 'seduce': 'الإغراء', 'body': 'الجسم', 'screen': 'الحضور على الشاشة', 'bold': 'الجرأة', 'heat': 'الإثارة'};
const bodyD = {'face': 'الوجه', 'hair': 'الشعر', 'skin': 'البشرة', 'figure': 'القوام العام', 'chest': 'الصدر', 'waist': 'الخصر', 'hips': 'الأرداف', 'legs': 'الأرجل'};
const plat = <String, (String, String)>{
  'instagram': ('Instagram', 'https://instagram.com/'), 'x': ('X', 'https://x.com/'), 'tiktok': ('TikTok', 'https://tiktok.com/@'),
  'onlyfans': ('OnlyFans', 'https://onlyfans.com/'), 'fansly': ('Fansly', 'https://fansly.com/'), 'snapchat': ('Snapchat', 'https://snapchat.com/add/'),
  'telegram': ('Telegram', 'https://t.me/'), 'reddit': ('Reddit', 'https://reddit.com/user/'), 'youtube': ('YouTube', 'https://youtube.com/@'),
  'twitch': ('Twitch', 'https://twitch.tv/'), 'linktree': ('Linktree', 'https://linktr.ee/'), 'website': ('موقع', ''), 'other': ('أخرى', ''),
};

Map<String, double> criteriaOf(Performer p) => _nums(p.raw['criteria']);
Map<String, double> bodyOf(Performer p) => _nums(p.raw['bodyD']);
Map<String, double> _nums(Object? m) => m is Map ? {for (final e in m.entries) if (e.value is num && (e.value as num) > 0) '${e.key}': (e.value as num).toDouble()} : {};

double _round05(double v) => (v * 2).round() / 2;
double meanOf(Map<String, double> m) => m.isEmpty ? 0 : m.values.reduce((a, b) => a + b) / m.length;

/// قاعدة القديم: مع وجود الجسم التفصيلي يصبح criteria.body متوسطه، والتقييم العام = متوسط المعايير المعبأة مقرّبًا لـ 0.5.
({Map<String, double> criteria, double rating}) applyRatings(Map<String, double> c, Map<String, double> b) {
  final cc = Map<String, double>.from(c);
  if (b.isNotEmpty) cc['body'] = _round05(meanOf(b));
  return (criteria: cc, rating: cc.isEmpty ? 0 : _round05(meanOf(cc)));
}

List<Map<String, String>> accountsOf(Performer p) => [for (final a in (p.raw['accounts'] as List? ?? const [])) if (a is Map && '${a['v'] ?? ''}'.trim().isNotEmpty) {'p': '${a['p'] ?? 'other'}', 'v': '${a['v']}'.trim()}];

/// رابط الحساب (مثل accUrl): رابط كامل يُستخدم كما هو؛ وإلا اسم مستخدم آمن + أساس المنصة. لا شيء غير https.
String? accUrl(Map<String, String> a) {
  final v = a['v']!.trim();
  if (v.startsWith('https://')) return v;
  if (v.startsWith('http://')) return null;
  final base = plat[a['p']]?.$2 ?? '';
  if (base.isEmpty) { return RegExp(r'^[\w.-]+\.[a-z]{2,}(/\S*)?$', caseSensitive: false).hasMatch(v) ? 'https://$v' : null; }
  final u = v.replaceAll(RegExp(r'^[@/]+|/+$'), '');
  return RegExp(r'^[\w.\-]+$').hasMatch(u) ? '$base$u' : null;
}
