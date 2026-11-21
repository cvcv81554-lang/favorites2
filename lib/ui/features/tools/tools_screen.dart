import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/elo.dart';
import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../works/works_screen.dart';
import 'lists_state.dart';

/// مركز الأدوات: القوائم، المواجهة، المستويات، جلسة تقييم، الأمنيات، اكتمال المكتبة، الإنجازات، في مثل هذا اليوم، مزاج الليلة.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    final unrated = lib.where((p) => p.rating == 0).length;
    final tools = <(IconData, String, String, Widget Function())>[
      (Icons.playlist_add_check_rounded, 'قوائمي', '${ref.watch(listsProvider).value?.length ?? 0} قائمة', () => const ListsScreen()),
      (Icons.sports_mma_rounded, 'المواجهة', 'اختر الأفضل بين اثنتين — ترتيب Elo', () => const DuelScreen()),
      (Icons.leaderboard_rounded, 'المستويات', 'S · A · B · C · D', () => const TierScreen()),
      (Icons.star_half_rounded, 'جلسة تقييم', '$unrated بلا تقييم', () => const RateSession()),
      (Icons.bookmark_add_rounded, 'قائمة الأمنيات', 'أسماء تضيفها لاحقًا', () => const WishScreen()),
      (Icons.task_alt_rounded, 'اكتمال المكتبة', 'ما ينقص كل سجل', () => const CompletenessScreen()),
      (Icons.emoji_events_rounded, 'الإنجازات', 'مستويات تتقدم فيها', () => const AchievementsScreen()),
      (Icons.today_rounded, 'في مثل هذا اليوم', 'أعياد ميلاد ومشاهدات وإصدارات', () => const OnThisDayScreen()),
      (Icons.nightlife_rounded, 'مزاج الليلة', 'اقتراح عمل حسب وقتك ومزاجك', () => const MoodScreen()),
    ];
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(appBar: AppBar(title: const Text('الأدوات')), body: GridView.count(
      padding: const EdgeInsets.all(S.s4), crossAxisCount: w >= 1100 ? 4 : w >= 700 ? 3 : 2, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3, childAspectRatio: 1.25,
      children: [for (final t in tools) Material(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), clipBehavior: Clip.antiAlias, child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => t.$4())),
        child: Padding(padding: const EdgeInsets.all(S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(t.$1, color: C.gold, size: 30), const Spacer(),
          Text(t.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), Text(t.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
        ]))))],
    ));
  }
}

Future<String?> askName(BuildContext context, String title, {String initial = ''}) => showDialog<String>(context: context, builder: (c) {
  final t = TextEditingController(text: initial);
  return AlertDialog(title: Text(title), content: TextField(controller: t, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v)),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, t.text), child: const Text('حفظ'))]);
});

Widget _grid(BuildContext context, List<Performer> ps) {
  final w = MediaQuery.sizeOf(context).width;
  return GridView.builder(padding: const EdgeInsets.all(S.s4), itemCount: ps.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: w >= 900 ? 5 : w >= 600 ? 4 : 2, childAspectRatio: 3 / 4.3, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3),
    itemBuilder: (c, i) => PosterCard(p: ps[i], heroTag: 'tl-${ps[i].id}', onTap: () => c.push('/p/${ps[i].id}')));
}

// ---------------- القوائم ----------------
class ListsScreen extends ConsumerWidget {
  const ListsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ls = ref.watch(listsProvider).value ?? const <NamedList>[];
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    return Scaffold(
      appBar: AppBar(title: const Text('قوائمي')),
      floatingActionButton: FloatingActionButton(onPressed: () async { final n = await askName(context, 'قائمة جديدة'); if (n != null && n.trim().isNotEmpty) ref.read(listsProvider.notifier).add(n); }, child: const Icon(Icons.add_rounded)),
      body: ls.isEmpty ? const EmptyState(title: 'لا قوائم بعد', body: 'أنشئ قوائم مثل «الأفضل» أو «للمراجعة»، ثم أضف إليها من صفحة أي ممثلة.')
        : ListView(padding: const EdgeInsets.all(S.s4), children: [for (final l in ls) () {
            final members = lib.where((p) => p.lists.contains(l.id)).toList();
            return Card(child: ListTile(
              leading: SizedBox(width: 56, height: 56, child: ClipRRect(borderRadius: BorderRadius.circular(S.rSm), child: members.isEmpty ? const Initials('') : Photo(members.first.cover, name: members.first.name, cacheWidth: 160))),
              title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${members.length} ممثلة', style: const TextStyle(color: C.muted)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(l.name)), body: members.isEmpty ? const EmptyState(title: 'القائمة فارغة', body: 'من صفحة الممثلة ⋮ ← القوائم') : _grid(context, members)))),
              trailing: PopupMenuButton<String>(onSelected: (v) async {
                if (v == 'r') { final n = await askName(context, 'إعادة تسمية', initial: l.name); if (n != null && n.trim().isNotEmpty) ref.read(listsProvider.notifier).rename(l.id, n); }
                if (v == 'd') ref.read(listsProvider.notifier).remove(l.id);
              }, itemBuilder: (_) => const [PopupMenuItem(value: 'r', child: Text('إعادة تسمية')), PopupMenuItem(value: 'd', child: Text('حذف القائمة (الممثلات تبقى)'))]),
            ));
          }()]),
    );
  }
}

/// ورقة اختيار قوائم ممثلة (من صفحتها).
Future<void> showListsSheet(BuildContext context, WidgetRef ref, Performer p) => showModalBottomSheet(context: context, builder: (c) => Consumer(builder: (c, ref, _) {
  final ls = ref.watch(listsProvider).value ?? const <NamedList>[];
  final cur = ref.watch(libraryProvider).value?.where((x) => x.id == p.id).firstOrNull ?? p;
  return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s5), children: [
    Text('قوائم ${cur.name}', style: Theme.of(c).textTheme.titleLarge),
    for (final l in ls) CheckboxListTile(value: cur.lists.contains(l.id), title: Text(l.name), onChanged: (v) {
      final nl = v == true ? {...cur.lists, l.id}.toList() : cur.lists.where((x) => x != l.id).toList();
      ref.read(libraryProvider.notifier).upsert(cur.copyWith({'lists': nl}));
    }),
    TextButton.icon(onPressed: () async { final n = await askName(c, 'قائمة جديدة'); if (n != null && n.trim().isNotEmpty) { final l = await ref.read(listsProvider.notifier).add(n); await ref.read(libraryProvider.notifier).upsert(cur.copyWith({'lists': {...cur.lists, l.id}.toList()})); } }, icon: const Icon(Icons.add_rounded), label: const Text('قائمة جديدة')),
  ]);
}));

// ---------------- المواجهة ----------------
class DuelScreen extends ConsumerStatefulWidget {
  const DuelScreen({super.key});
  @override ConsumerState<DuelScreen> createState() => _DuelState();
}
class _DuelState extends ConsumerState<DuelScreen> {
  final _rnd = Random(); (Performer, Performer)? _pair; Set<String> _last = {}; bool _board = false;
  void _next(List<Performer> pool) { _pair = pickPair(pool, _rnd, last: _last); }
  Future<void> _vote(Performer w, Performer l) async {
    HapticFeedback.selectionClick();
    final (a, b) = eloUpdate(eloOf(w), eloOf(l));
    await ref.read(libraryProvider.notifier).upsertMany([
      Performer({...w.raw, 'elo': a.round(), 'duels': duelsOf(w) + 1, 'dw': ((w.raw['dw'] as num?)?.toInt() ?? 0) + 1}),
      Performer({...l.raw, 'elo': b.round(), 'duels': duelsOf(l) + 1}),
    ]);
    _last = {w.id, l.id};
    setState(() => _next((ref.read(libraryProvider).value ?? const []).where((p) => p.cover.isNotEmpty).toList()));
  }
  @override
  Widget build(BuildContext context) {
    final pool = (ref.watch(libraryProvider).value ?? const <Performer>[]).where((p) => p.cover.isNotEmpty).toList();
    if (_pair == null && pool.length >= 2) _next(pool);
    final board = [...pool]..sort((a, b) => eloOf(b).compareTo(eloOf(a)));
    return Scaffold(appBar: AppBar(title: const Text('المواجهة'), actions: [TextButton(onPressed: () => setState(() => _board = !_board), child: Text(_board ? 'العب' : 'الترتيب'))]),
      body: pool.length < 2 ? const EmptyState(title: 'تحتاج ممثلتين بصور على الأقل', body: '')
        : _board ? ListView.builder(itemCount: min(100, board.length), itemBuilder: (c, i) => ListTile(
            leading: Text('${i + 1}', style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 18)),
            title: Text(board[i].name), subtitle: Text('${duelsOf(board[i])} مواجهة · ${(board[i].raw['dw'] as num?) ?? 0} فوز', style: const TextStyle(color: C.muted)),
            trailing: Text('${eloOf(board[i]).round()}', style: const TextStyle(fontWeight: FontWeight.w700))))
        : Padding(padding: const EdgeInsets.all(S.s4), child: Column(children: [
            const Text('اختر المفضلة لديك', style: TextStyle(color: C.muted)), const SizedBox(height: S.s3),
            Expanded(child: Row(children: [
              for (final (w, l) in [(_pair!.$1, _pair!.$2), (_pair!.$2, _pair!.$1)]) Expanded(child: Padding(padding: const EdgeInsets.all(S.s2), child: PosterCard(p: w, heroTag: 'duel-${w.id}', onTap: () => _vote(w, l)))),
            ])),
            TextButton(onPressed: () => setState(() => _next(pool)), child: const Text('تخطَّ')),
          ])));
  }
}

// ---------------- المستويات ----------------
class TierScreen extends ConsumerWidget {
  const TierScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    const tiers = ['S', 'A', 'B', 'C', 'D'];
    return Scaffold(appBar: AppBar(title: const Text('المستويات'), actions: [TextButton(onPressed: () async {
      final ch = [for (final p in lib) if (p.tier.isEmpty && tierFromRating(p.rating).isNotEmpty) p.copyWith({'tier': tierFromRating(p.rating)})];
      await ref.read(libraryProvider.notifier).upsertMany(ch);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('رُتّبت ${ch.length} تلقائيًا من تقييمها')));
    }, child: const Text('تلقائي من التقييم'))]),
      body: ListView(padding: const EdgeInsets.all(S.s4), children: [
        for (final t in [...tiers, '']) () {
          final m = lib.where((p) => p.tier == t).toList(); if (m.isEmpty) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(bottom: S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.isEmpty ? 'بلا مستوى' : 'المستوى $t', style: TextStyle(color: t == 'S' ? C.gold2 : C.text, fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: S.s2),
            Wrap(spacing: S.s2, runSpacing: S.s2, children: [for (final p in m) InputChip(
              avatar: CircleAvatar(backgroundColor: C.surface2, child: ClipOval(child: SizedBox.expand(child: Photo(p.cover, name: p.name, cacheWidth: 96)))),
              label: Text(p.name), onPressed: () async {
                final v = await showDialog<String>(context: context, builder: (c) => SimpleDialog(title: Text(p.name), children: [for (final x in [...tiers, '']) SimpleDialogOption(onPressed: () => Navigator.pop(c, x), child: Text(x.isEmpty ? 'بلا مستوى' : x))]));
                if (v != null) ref.read(libraryProvider.notifier).upsert(p.copyWith({'tier': v}));
              })]),
          ]));
        }(),
      ]));
  }
}

// ---------------- جلسة تقييم ----------------
class RateSession extends ConsumerStatefulWidget {
  const RateSession({super.key});
  @override ConsumerState<RateSession> createState() => _RateState();
}
class _RateState extends ConsumerState<RateSession> {
  final Set<String> _skip = {};
  @override
  Widget build(BuildContext context) {
    final q = (ref.watch(libraryProvider).value ?? const <Performer>[]).where((p) => p.rating == 0 && !_skip.contains(p.id)).toList();
    return Scaffold(appBar: AppBar(title: Text('جلسة تقييم · ${q.length}')), body: q.isEmpty ? const EmptyState(title: 'كلها مقيّمة 🎉', body: '') : Padding(padding: const EdgeInsets.all(S.s4), child: Column(children: [
      Expanded(child: Center(child: AspectRatio(aspectRatio: 3 / 4.3, child: PosterCard(p: q.first, heroTag: 'rate-${q.first.id}', onTap: () => context.push('/p/${q.first.id}'))))),
      const SizedBox(height: S.s3),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 1; i <= 5; i++) IconButton(iconSize: 40, tooltip: '$i', onPressed: () => ref.read(libraryProvider.notifier).upsert(q.first.copyWith({'rating': i.toDouble()})), icon: const Icon(Icons.star_rounded, color: C.gold))]),
      TextButton(onPressed: () => setState(() => _skip.add(q.first.id)), child: const Text('لاحقًا')),
    ])));
  }
}

// ---------------- الأمنيات ----------------
class WishScreen extends ConsumerWidget {
  const WishScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(wishProvider).value ?? const <Map<String, dynamic>>[];
    return Scaffold(appBar: AppBar(title: const Text('قائمة الأمنيات')),
      floatingActionButton: FloatingActionButton(onPressed: () async { final n = await askName(context, 'اسم تريد إضافته لاحقًا'); if (n != null) ref.read(wishProvider.notifier).add(n); }, child: const Icon(Icons.add_rounded)),
      body: l.isEmpty ? const EmptyState(title: 'لا أمنيات', body: 'سجّل أسماء لتبحث عنها لاحقًا. تُزال وحدها عند إضافتها للمكتبة.')
        : ListView(children: [for (final e in l) ListTile(title: Text('${e['n']}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'بحث في المصادر', onPressed: () => context.push('/search?q=${Uri.encodeQueryComponent('${e['n']}')}'), icon: const Icon(Icons.travel_explore_rounded, color: C.gold)),
              IconButton(tooltip: 'إزالة', onPressed: () => ref.read(wishProvider.notifier).remove('${e['n']}'), icon: const Icon(Icons.close_rounded)),
            ]))]));
  }
}

// ---------------- اكتمال المكتبة ----------------
class CompletenessScreen extends ConsumerWidget {
  const CompletenessScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    final checks = [for (final p in lib) (p, completeness(p))];
    final total = checks.fold<int>(0, (s, x) => s + x.$2.where((c) => c.$2).length), all = lib.length * 7;
    final missing = (checks.where((x) => x.$2.any((c) => !c.$2)).toList()..sort((a, b) => a.$2.where((c) => c.$2).length.compareTo(b.$2.where((c) => c.$2).length)));
    return Scaffold(appBar: AppBar(title: const Text('اكتمال المكتبة')), body: ListView(padding: const EdgeInsets.all(S.s4), children: [
      Center(child: SizedBox(width: 140, height: 140, child: Stack(fit: StackFit.expand, children: [
        CircularProgressIndicator(value: all == 0 ? 0 : total / all, strokeWidth: 12, backgroundColor: C.surface2, color: C.gold),
        Center(child: Text('${all == 0 ? 0 : (total * 100 / all).round()}٪', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700))),
      ]))),
      const SizedBox(height: S.s4),
      for (final (p, c) in missing.take(100)) ListTile(onTap: () => context.push('/p/${p.id}'),
        leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 56, child: Photo(p.cover, name: p.name, cacheWidth: 120))),
        title: Text(p.name), subtitle: Text('ينقص: ${c.where((x) => !x.$2).map((x) => x.$1).join('، ')}', style: const TextStyle(color: C.muted, fontSize: 12))),
    ]));
  }
}

// ---------------- الإنجازات ----------------
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    final works = ref.watch(worksProvider);
    final lists = ref.watch(listsProvider).value?.length ?? 0;
    final fams = <(String, IconData, int, List<int>)>[
      ('جامعة', Icons.collections_rounded, lib.length, [10, 50, 100, 250]),
      ('ناقدة', Icons.star_rounded, lib.where((p) => p.rating > 0).length, [10, 50, 150]),
      ('مشاهِدة', Icons.visibility_rounded, works.where((g) => g.seen).length, [25, 100, 500, 1000]),
      ('ناقدة أعمال', Icons.rate_review_rounded, works.where((g) => g.r > 0).length, [10, 50, 200]),
      ('مبارِزة', Icons.sports_mma_rounded, lib.fold<int>(0, (s, p) => s + duelsOf(p)) ~/ 2, [20, 100, 500]),
      ('مرتِّبة', Icons.leaderboard_rounded, lib.where((p) => p.tier.isNotEmpty).length, [10, 50]),
      ('مصوِّرة', Icons.photo_library_rounded, lib.fold<int>(0, (s, p) => s + p.photos.length), [50, 250, 1000]),
      ('منظِّمة', Icons.playlist_add_check_rounded, lists, [3, 10]),
      ('مكمِّلة', Icons.task_alt_rounded, lib.where((p) => completeness(p).where((c) => c.$2).length >= 6).length, [10, 50]),
      ('كاتبة', Icons.edit_note_rounded, works.where((g) => g.n.isNotEmpty).length, [5, 25]),
    ];
    return Scaffold(appBar: AppBar(title: const Text('الإنجازات')), body: ListView(padding: const EdgeInsets.all(S.s4), children: [for (final (n, ic, v, lv) in fams) () {
      final reached = lv.where((x) => v >= x).length; final next = reached < lv.length ? lv[reached] : null;
      return Card(child: ListTile(leading: Icon(ic, color: reached > 0 ? C.gold : C.muted, size: 32),
        title: Text('$n ${reached > 0 ? '· المستوى $reached' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 6), LinearProgressIndicator(value: next == null ? 1 : v / next, color: C.gold, backgroundColor: C.surface2),
          const SizedBox(height: 4), Text(next == null ? 'اكتمل ($v) 🏆' : '$v / $next', style: const TextStyle(color: C.muted, fontSize: 12)),
        ])));
    }()]));
  }
}

// ---------------- في مثل هذا اليوم ----------------
class OnThisDayScreen extends ConsumerWidget {
  const OnThisDayScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    final works = ref.watch(worksProvider);
    final n = DateTime.now(); final md = '-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    final bday = lib.where((p) => p.birth.length == 10 && p.birth.endsWith(md) && !p.isMinor).toList();
    final watched = works.where((g) => g.wd.endsWith(md) && !g.wd.startsWith('${n.year}')).toList();
    final released = works.where((g) => g.d.endsWith(md) && !g.d.startsWith('${n.year}')).toList();
    final added = lib.where((p) { final d = DateTime.fromMillisecondsSinceEpoch(p.added); return d.month == n.month && d.day == n.day && d.year < n.year; }).toList();
    Widget sec(String t, List<Widget> c) => c.isEmpty ? const SizedBox.shrink() : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SectionHeader(t), ...c]);
    final empty = bday.isEmpty && watched.isEmpty && released.isEmpty && added.isEmpty;
    return Scaffold(appBar: AppBar(title: const Text('في مثل هذا اليوم')), body: empty ? const EmptyState(title: 'لا ذكريات اليوم', body: 'عد غدًا — كلما كبرت مكتبتك كثرت الذكريات.') : ListView(children: [
      sec('🎂 أعياد ميلاد', [for (final p in bday) ListTile(title: Text(p.name), subtitle: Text('تكمل ${p.age} سنة', style: const TextStyle(color: C.muted)), onTap: () => context.push('/p/${p.id}'))]),
      sec('👁 شاهدت في مثل هذا اليوم', [for (final g in watched) ListTile(title: Text(g.t), subtitle: Text('${g.wd.substring(0, 4)} · ${g.who.map((p) => p.name).join('، ')}', style: const TextStyle(color: C.muted)), onTap: () => showWorkSheet(context, ref, g.key))]),
      sec('🎬 صدر في مثل هذا اليوم', [for (final g in released.take(30)) ListTile(title: Text(g.t), subtitle: Text(g.d.substring(0, 4), style: const TextStyle(color: C.muted)), onTap: () => showWorkSheet(context, ref, g.key))]),
      sec('➕ أضفتها في مثل هذا اليوم', [for (final p in added) ListTile(title: Text(p.name), subtitle: Text('${DateTime.fromMillisecondsSinceEpoch(p.added).year}', style: const TextStyle(color: C.muted)), onTap: () => context.push('/p/${p.id}'))]),
    ]));
  }
}

// ---------------- مزاج الليلة ----------------
class MoodScreen extends ConsumerStatefulWidget {
  const MoodScreen({super.key});
  @override ConsumerState<MoodScreen> createState() => _MoodState();
}
class _MoodState extends ConsumerState<MoodScreen> {
  int _dur = 0; bool _fav = false, _top = false; String _studio = '';
  @override
  Widget build(BuildContext context) {
    final works = ref.watch(worksProvider).where((g) => !g.seen && !g.isUpcoming).toList();
    final studios = (works.map((g) => g.s).where((s) => s.isNotEmpty).toSet().toList()..sort()).take(30).toList();
    final scored = <(dynamic, double, List<String>)>[];
    for (final g in works) {
      if (_dur > 0 && g.du > 0 && g.du > _dur + 10) continue;
      if (_studio.isNotEmpty && g.s != _studio) continue;
      if (_fav && !g.who.any((p) => p.fav)) continue;
      final best = g.who.fold<double>(0, (m, p) => max(m, p.rating));
      if (_top && best < 4) continue;
      final why = <String>[if (g.q) 'في قائمة المشاهدة', if (best >= 4) 'مع ممثلة تقييمها ${best.toStringAsFixed(1)}', if (g.du > 0 && _dur > 0) '${g.du} دقيقة'];
      scored.add((g, (g.q ? 2 : 0) + best + (g.du > 0 && _dur > 0 ? 1 - (g.du - _dur).abs() / 60 : 0), why));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return Scaffold(appBar: AppBar(title: const Text('مزاج الليلة')), body: ListView(padding: const EdgeInsets.all(S.s4), children: [
      const Text('كم من الوقت لديك؟'), const SizedBox(height: S.s2),
      SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('أي مدة')), ButtonSegment(value: 20, label: Text('20 د')), ButtonSegment(value: 40, label: Text('40 د')), ButtonSegment(value: 60, label: Text('ساعة'))], selected: {_dur}, onSelectionChanged: (s) => setState(() => _dur = s.first)),
      const SizedBox(height: S.s3),
      Wrap(spacing: S.s2, children: [
        FilterChip(label: const Text('مع مفضلاتي'), selected: _fav, onSelected: (v) => setState(() => _fav = v)),
        FilterChip(label: const Text('تقييم 4+'), selected: _top, onSelected: (v) => setState(() => _top = v)),
        if (studios.isNotEmpty) DropdownButton<String>(value: _studio, underline: const SizedBox(), items: [const DropdownMenuItem(value: '', child: Text('كل الاستوديوهات')), for (final s in studios) DropdownMenuItem(value: s, child: Text(s))], onChanged: (v) => setState(() => _studio = v ?? '')),
      ]),
      SectionHeader('أفضل 3 لليلة', sub: '${scored.length} عمل مناسب'),
      if (scored.isEmpty) const Text('لا أعمال تطابق — خفّف الشروط.', style: TextStyle(color: C.muted)),
      for (final (g, _, why) in scored.take(3)) Padding(padding: const EdgeInsets.only(bottom: S.s3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 112, child: WorkCard(g: g)), if (why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(why.join(' · '), style: const TextStyle(color: C.gold, fontSize: 12))),
      ])),
    ]));
  }
}
