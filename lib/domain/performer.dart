import 'age_gate.dart';
import 'sanitize.dart';

/// سجل ممثلة — مبني على Map كي تبقى **كل الحقول**، حتى غير المعروفة، عبر الاستيراد والتصدير والمزامنة
/// (قاعدة: الحقول المجهولة لا تضيع). الواجهة تقرأ عبر getters مكتوبة الأنواع.
class Performer {
  final Map<String, dynamic> raw;
  Performer(Map<String, dynamic> m) : raw = normalize(m);

  String get id => raw['id'] as String;
  String get name => (raw['name'] ?? '').toString();
  String get aliases => (raw['aliases'] ?? '').toString();
  String get country => (raw['country'] ?? '').toString();
  String get birth => (raw['birth'] ?? '').toString();
  String get notes => (raw['notes'] ?? '').toString();
  double get rating => (raw['rating'] is num) ? (raw['rating'] as num).toDouble() : 0;
  bool get fav => raw['fav'] == true;
  List<String> get tags => _strList(raw['tags']);
  List<String> get lists => _strList(raw['lists']);
  List<String> get photos => _strList(raw['photos']);
  String get thumb => (raw['thumb'] ?? '').toString();
  /// الصورة الرئيسية بأعلى دقة: أول صورة أصلية (المصغّرة 640px فقط إن لم توجد صور).
  String get cover => photos.isNotEmpty ? photos.first : thumb;
  /// بدائل إن تعطّل رابط الصورة الرئيسية: بقية الصور ثم المصغّرة.
  List<String> get coverFallbacks => [...photos.skip(1), if (thumb.isNotEmpty) thumb];
  List<Map<String, dynamic>> get works => (raw['works'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
  int get added => (raw['added'] as num?)?.toInt() ?? 0;
  int get updated => (raw['updated'] as num?)?.toInt() ?? 0;
  int get views => (raw['views'] as num?)?.toInt() ?? 0;
  String get tier => (raw['tier'] ?? '').toString();
  String get pdbId => (raw['pdbId'] ?? '').toString();
  String get stashId => (raw['stashId'] ?? '').toString();
  int? get age { final a = sdAge(birth); return a.age; }
  bool get isMinor => minorRec(raw);
  int get watchedCount => works.where((w) => w['w'] == 1 || w['w'] == true).length;

  static List<String> _strList(Object? v) => v is List ? v.whereType<String>().toList() : const [];

  /// مثل normItem: أعمال نصية ⇒ منظّمة، chem ⇒ bold، قيم افتراضية، added/updated.
  static Map<String, dynamic> normalize(Map<String, dynamic> m) {
    final x = Map<String, dynamic>.from(m);
    x['works'] = safeWorks(x['works']);
    for (final k in ['photos', 'tags', 'lists']) { if (x[k] is! List) x[k] = <String>[]; }
    final c = x['criteria'];
    if (c is Map && c.containsKey('chem') && !c.containsKey('bold')) {
      final cc = Map<String, dynamic>.from(c); cc['bold'] = cc.remove('chem'); x['criteria'] = cc;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    x['updated'] = (x['updated'] is num) ? x['updated'] : now;
    x['added'] = (x['added'] is num) ? x['added'] : x['updated'];
    x.remove('nph');
    return x;
  }

  Performer copyWith(Map<String, dynamic> changes) {
    final m = Map<String, dynamic>.from(raw)..addAll(changes);
    m['updated'] = DateTime.now().millisecondsSinceEpoch;
    return Performer(m);
  }

  /// الحقول المحلية للجهاز (لا تُزامن ولا تُستبدل من مصدر آخر).
  static const deviceLocal = {'views', 'lastView', 'nph'};
}
