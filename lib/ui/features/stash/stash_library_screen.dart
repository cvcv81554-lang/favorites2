import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/sources.dart' show SourceError;
import '../../../data/stash_server.dart';
import '../../../domain/performer.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../reels/full_video_screen.dart';

/// «مكتبة Stash»: كل فيديوهات خادمك على الآيفون — بحث، ترتيب، «ممثلاتي فقط»، ممثلات الخادم، و«تابع المشاهدة».
/// التشغيل: الملف مباشرة إن كان يعمل على الآيفون، وإلا بث HLS يحوّله الخادم (mkv/wmv…).
class StashLibraryScreen extends ConsumerStatefulWidget {
  const StashLibraryScreen({super.key, this.performer, this.performerName = ''});
  final String? performer; final String performerName;   // فتحها مصفّاة على ممثلة من الخادم
  @override ConsumerState<StashLibraryScreen> createState() => _StashLibraryState();
}

const _sorts = [('random', 'عشوائي'), ('date', 'الأحدث'), ('created_at', 'أُضيف حديثًا'), ('play_count', 'الأكثر مشاهدة'), ('last_played_at', 'آخر ما شاهدته'), ('title', 'العنوان')];

class _StashLibraryState extends ConsumerState<StashLibraryScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  final _q = TextEditingController(); Timer? _deb;
  String _sort = 'random', _msg = ''; bool _mine = false, _loading = false, _ready = false;
  String? _perf; String _perfName = '';
  final _items = <WorkGroup>[]; int _count = 0, _page = 0;
  final _resume = <WorkGroup>[];
  final _perfs = <({String id, String name, String image, int scenes, bool fav})>[]; int _perfCount = 0, _perfPage = 0;
  Map<String, Performer> _byLocal = {};
  int _seed = 0;

  @override
  void initState() {
    super.initState();
    _perf = widget.performer; _perfName = widget.performerName;
    _init();
  }
  @override void dispose() { _tabs.dispose(); _q.dispose(); _deb?.cancel(); super.dispose(); }

  Future<void> _init() async {
    if (!await StashServer.configured()) { setState(() { _ready = true; _msg = 'أضف عنوان خادم Stash من «الشبكة والمقاطع» أولًا.'; }); return; }
    final repo = await ref.read(repoProvider.future);
    final map = Map<String, dynamic>.from(await repo.kvGet('stash_local_map') as Map? ?? {});
    final lib = ref.read(libraryProvider).value ?? const <Performer>[];
    _byLocal = {for (final p in lib) if (!p.isMinor && '${map[p.id] ?? ''}'.isNotEmpty) '${map[p.id]}': p};
    setState(() => _ready = true);
    await Future.wait([_reload(), _loadResume(), _loadPerfs(reset: true)]);
  }

  Future<void> _reload() async { _page = 0; _items.clear(); _count = 0; await _more(); }

  Future<void> _more() async {
    if (_loading || (_page > 0 && _items.length >= _count)) return;
    setState(() { _loading = true; _msg = ''; });
    try {
      final r = await StashServer.browse(query: _q.text.trim(), sort: _sort == 'random' ? 'random_$_seed' : _sort, desc: _sort != 'title', page: _page + 1,
        performer: _perf, mine: _mine && _perf == null ? _byLocal.keys.toList() : null, byLocal: _byLocal);
      _page++; _items.addAll(r.$1); _count = r.$2;
      if (_mine && _perf == null && _byLocal.isEmpty) _msg = 'لم تُربط ممثلات مكتبتك بخادمك بعد — افتح «مقاطع» مرة ليتم الربط.';
    } on SourceError catch (e) { _msg = e.msg; }
    catch (e) { _msg = '$e'; }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadResume() async {
    try { final r = await StashServer.browse(mode: 'resume', sort: 'last_played_at', perPage: 60, byLocal: _byLocal); _resume..clear()..addAll(r.$1); } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadPerfs({bool reset = false}) async {
    if (reset) { _perfs.clear(); _perfPage = 0; _perfCount = 0; }
    if (_perfPage > 0 && _perfs.length >= _perfCount) return;
    try { final r = await StashServer.performers(query: _tabs.index == 1 ? _q.text.trim() : '', page: _perfPage + 1); _perfPage++; _perfs.addAll(r.$1); _perfCount = r.$2; } catch (_) {}
    if (mounted) setState(() {});
  }

  void _search(String _) { _deb?.cancel(); _deb = Timer(const Duration(milliseconds: 450), () { if (_tabs.index == 1) { _loadPerfs(reset: true); } else { _reload(); } }); }

  void _play(WorkGroup g) {
    final ex = StashServer.extra[g.key];
    final resume = (ex?.resume ?? 0) > 10 ? ex!.resume.round() : 0;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FullVideoScreen(url: g.tr, title: g.t, start: resume, source: 'Stash', stashId: ex?.id ?? '', vtt: ex?.vtt ?? '',
      onClosed: ex == null ? null : (x) { StashServer.extra[g.key] = ex.withResume(x); if (mounted) { setState(() {}); _loadResume(); } })));
  }

  void _openPerformer(String id, String name) {
    setState(() { _perf = id; _perfName = name; _mine = false; _q.clear(); });
    _tabs.animateTo(0); _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مكتبة Stash'), bottom: TabBar(controller: _tabs, onTap: (_) => setState(() {}), tabs: [
      Tab(text: _count > 0 ? 'الفيديوهات ($_count)' : 'الفيديوهات'), Tab(text: _perfCount > 0 ? 'الممثلات ($_perfCount)' : 'الممثلات'), Tab(text: 'تابع المشاهدة (${_resume.length})'),
    ])),
    body: !_ready ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabs, children: [_scenesTab(), _perfsTab(), _resumeTab()]),
  );

  Widget _searchBox(String hint) => Padding(padding: const EdgeInsets.fromLTRB(S.s3, S.s3, S.s3, S.s2), child: TextField(controller: _q, onChanged: _search,
    decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded), isDense: true,
      suffixIcon: _q.text.isEmpty ? null : IconButton(onPressed: () { _q.clear(); _search(''); setState(() {}); }, icon: const Icon(Icons.close_rounded)))));

  Widget _scenesTab() => Column(children: [
    _searchBox('ابحث في عناوين خادمك…'),
    SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s3), children: [
      if (_perf != null) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: InputChip(label: Text(_perfName), avatar: const Icon(Icons.person_rounded, size: 18), onDeleted: () { setState(() { _perf = null; _perfName = ''; }); _reload(); }))
      else Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: FilterChip(label: const Text('ممثلاتي فقط'), selected: _mine, onSelected: (v) { setState(() => _mine = v); _reload(); })),
      for (final s in _sorts) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(label: Text(s.$2), selected: _sort == s.$1, onSelected: (_) { setState(() { _sort = s.$1; _seed++; }); _reload(); })),
    ])),
    if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.all(S.s3), child: Text(_msg, style: const TextStyle(color: C.gold))),
    Expanded(child: _items.isEmpty && !_loading ? const Center(child: Text('لا فيديوهات', style: TextStyle(color: C.muted)))
      : NotificationListener<ScrollNotification>(onNotification: (n) { if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _more(); return false; },
        child: RefreshIndicator(onRefresh: () async { _seed++; await _reload(); }, child: GridView.builder(padding: const EdgeInsets.all(S.s2),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, childAspectRatio: 16 / 13.5, mainAxisSpacing: 8, crossAxisSpacing: 8),
          itemCount: _items.length + (_loading ? 1 : 0),
          itemBuilder: (_, i) => i >= _items.length ? const Center(child: CircularProgressIndicator()) : _SceneCard(g: _items[i], onTap: () => _play(_items[i]),
            onPerformer: (p) => p.id.startsWith('stashp:') ? _openPerformer(p.id.substring(7), p.name) : context.push('/p/${p.id}')))))),
  ]);

  Widget _perfsTab() => Column(children: [
    _searchBox('ابحث عن ممثلة في خادمك…'),
    Expanded(child: NotificationListener<ScrollNotification>(onNotification: (n) { if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _loadPerfs(); return false; },
      child: ListView.builder(itemCount: _perfs.length, itemBuilder: (_, i) {
        final p = _perfs[i]; final inLib = _byLocal.containsKey(p.id);
        return ListTile(
          leading: CircleAvatar(radius: 24, backgroundColor: C.surface, child: p.image.isEmpty ? Text(p.name.isEmpty ? '?' : p.name.characters.first) : ClipOval(child: SizedBox(width: 48, height: 48, child: Photo(p.image, name: p.name, cacheWidth: 144)))),
          title: Text(p.name), subtitle: Text('${p.scenes} فيديو${inLib ? ' · في مكتبتك' : ''}'),
          trailing: inLib ? const Icon(Icons.star_rounded, color: C.gold) : p.fav ? const Icon(Icons.favorite_rounded, color: C.rose, size: 18) : null,
          onTap: () => _openPerformer(p.id, p.name));
      }))),
  ]);

  Widget _resumeTab() => _resume.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(S.s5), child: Text('لا فيديوهات متوقفة في منتصفها — يشمل ما بدأته في Stash على حاسوبك.', textAlign: TextAlign.center, style: TextStyle(color: C.muted))))
    : RefreshIndicator(onRefresh: _loadResume, child: ListView(children: [for (final g in _resume) _resumeTile(g)]));

  Widget _resumeTile(WorkGroup g) {
    final ex = StashServer.extra[g.key]; final d = g.du * 60;
    return ListTile(
      leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 96, height: 54, child: g.p.isEmpty ? const ColoredBox(color: Colors.black) : WorkImage(g.p, name: g.s))),
      title: Text(g.t, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(g.who.map((p) => p.name).take(2).join('، '), maxLines: 1),
        if (d > 0 && ex != null) Padding(padding: const EdgeInsets.only(top: 4), child: LinearProgressIndicator(value: (ex.resume / d).clamp(0.0, 1.0), minHeight: 3)),
      ]),
      onTap: () => _play(g));
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.g, required this.onTap, required this.onPerformer});
  final WorkGroup g; final VoidCallback onTap; final void Function(Performer) onPerformer;
  @override
  Widget build(BuildContext context) {
    final ex = StashServer.extra[g.key]; final d = g.du * 60;
    return GestureDetector(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(aspectRatio: 16 / 9, child: ClipRRect(borderRadius: BorderRadius.circular(S.rMd), child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black), if (g.p.isNotEmpty) WorkImage(g.p, name: g.s),
        Positioned(left: 6, bottom: 6, child: _pill([if (g.du > 0) '${g.du} د', if ((ex?.height ?? 0) >= 2000) '4K' else if ((ex?.height ?? 0) >= 1000) 'HD', if (ex != null && !ex.direct) 'HLS'].join(' · '))),
        if ((ex?.plays ?? 0) > 0) Positioned(right: 6, top: 6, child: _pill('👁 ${ex!.plays}')),
        if (ex != null && ex.resume > 10 && d > 0) Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: (ex.resume / d).clamp(0.0, 1.0), minHeight: 3, backgroundColor: Colors.black45)),
      ]))),
      const SizedBox(height: 4),
      Text(g.t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      Wrap(spacing: 6, children: [for (final p in g.who.take(2)) GestureDetector(onTap: () => onPerformer(p), child: Text(p.name, style: TextStyle(color: p.id.startsWith('stashp:') ? C.muted : C.gold2, fontSize: 12)))]),
    ]));
  }
  Widget _pill(String t) => t.isEmpty ? const SizedBox() : Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(99)),
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11)));
}
