import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/demo.dart';

import '../../data/library_repo.dart';
import '../../domain/performer.dart';
import '../../domain/sanitize.dart';

final repoProvider = FutureProvider<LibraryRepo>((ref) => LibraryRepo.open());

/// المكتبة كلها في الذاكرة (مئات السجلات) مع الحفظ عبر نقطة كتابة واحدة.
class Library extends AsyncNotifier<List<Performer>> {
  LibraryRepo? _repo;
  @override
  Future<List<Performer>> build() async {
    _repo = await ref.watch(repoProvider.future);
    // وضع العرض التجريبي (ويب فقط، ?demo=1): بيانات محايدة في الذاكرة، لا تُحفظ
    if (kIsWeb && Uri.base.queryParameters['demo'] == '1') { _demo = true; return demoLibrary(); }
    return _repo!.loadAll();
  }
  bool _demo = false;

  LibraryRepo get repo => _repo!;
  List<Performer> get items => state.value ?? const [];

  /// يعيد false إن رُفض الحفظ (سجل قاصر).
  Future<bool> upsert(Performer p) async {
    final saved = _demo ? (p.isMinor ? <Performer>[] : [p]) : await repo.save([p]);
    if (saved.isEmpty) return false;
    final l = [...items]; final i = l.indexWhere((x) => x.id == p.id);
    if (i >= 0) { l[i] = p; } else { l.insert(0, p); }
    state = AsyncData(l);
    return true;
  }

  Future<void> remove(String id) async { if (!_demo) await repo.delete(id); state = AsyncData(items.where((x) => x.id != id).toList()); }
  Future<void> reload() async { state = AsyncData(await repo.loadAll()); }
}

final libraryProvider = AsyncNotifierProvider<Library, List<Performer>>(Library.new);

Performer? performerById(WidgetRef ref, String id) => ref.watch(libraryProvider).value?.where((p) => p.id == id).firstOrNull;

// ---------- حالة شاشة المكتبة (بحث، فلتر ذكي، ترتيب) ----------
enum SortBy { updated, added, name, rating, age, works }

class LibQuery {
  final String q; final String smart; final SortBy sort; final bool favOnly;
  const LibQuery({this.q = '', this.smart = '', this.sort = SortBy.updated, this.favOnly = false});
  LibQuery copy({String? q, String? smart, SortBy? sort, bool? favOnly}) => LibQuery(q: q ?? this.q, smart: smart ?? this.smart, sort: sort ?? this.sort, favOnly: favOnly ?? this.favOnly);
}

class LibQueryN extends Notifier<LibQuery> {
  @override LibQuery build() => const LibQuery();
  void set(LibQuery q) => state = q;
}
final libQueryProvider = NotifierProvider<LibQueryN, LibQuery>(LibQueryN.new);

/// الفلاتر الذكية — نفس قواعد التطبيق السابق (SMART في 01c).
final smartFilters = <String, (String, bool Function(Performer))>{
  'top': ('تقييم ممتاز', (p) => p.rating >= 4.5),
  'unrated': ('بلا تقييم', (p) => p.rating == 0),
  'unseen': ('أعمال لم تُشاهد', (p) => p.works.any((w) => w['w'] != 1 && w['w'] != true)),
  'upcoming': ('أعمال قادمة', (p) => p.works.any(isUpcoming)),
  'recent30': ('أُضيفت حديثًا', (p) => DateTime.now().millisecondsSinceEpoch - p.added < 30 * 86400000),
  'bday': ('عيد ميلادها هذا الشهر', (p) => p.birth.length >= 7 && int.tryParse(p.birth.substring(5, 7)) == DateTime.now().month),
  'manyworks': ('5 أعمال فأكثر', (p) => p.works.length >= 5),
  'nophoto': ('بلا صور', (p) => p.photos.isEmpty),
  'noworks': ('بلا أعمال', (p) => p.works.isEmpty),
  'nobirth': ('بلا تاريخ ميلاد', (p) => p.birth.isEmpty),
};

bool isUpcoming(Map<String, dynamic> w) {
  if (w['w'] == 1 || w['w'] == true) return false;
  if (w['upc'] == 1 || w['upc'] == true) return true;
  final t = todayStr(); final d = (w['d'] ?? '').toString();
  if (d.isNotEmpty) return d.compareTo(t) > 0;
  final y = int.tryParse((w['y'] ?? '').toString());
  return y != null && y > DateTime.now().year;
}

final _searchCache = Expando<(int, String)>();
String searchText(Performer p) {
  final c = _searchCache[p]; if (c != null && c.$1 == p.updated) return c.$2;
  final s = [p.name, p.aliases, p.country, p.tags.join(' '), p.notes, p.works.map((w) => '${w['t'] ?? ''} ${w['s'] ?? ''}').join(' ')].join(' ').toLowerCase();
  _searchCache[p] = (p.updated, s); return s;
}

final filteredLibraryProvider = Provider<List<Performer>>((ref) {
  final all = ref.watch(libraryProvider).value ?? const <Performer>[];
  final q = ref.watch(libQueryProvider);
  Iterable<Performer> l = all;
  if (q.favOnly) l = l.where((p) => p.fav);
  final sm = smartFilters[q.smart]; if (sm != null) l = l.where(sm.$2);
  final s = q.q.trim().toLowerCase(); if (s.isNotEmpty) l = l.where((p) => searchText(p).contains(s));
  final out = l.toList();
  int cmp(Performer a, Performer b) => switch (q.sort) {
    SortBy.updated => b.updated.compareTo(a.updated),
    SortBy.added => b.added.compareTo(a.added),
    SortBy.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    SortBy.rating => b.rating.compareTo(a.rating),
    SortBy.age => (a.age ?? 999).compareTo(b.age ?? 999),
    SortBy.works => b.works.length.compareTo(a.works.length),
  };
  out.sort(cmp);
  return out;
});
