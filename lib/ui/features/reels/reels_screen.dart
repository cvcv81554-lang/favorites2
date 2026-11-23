import 'dart:async';
import 'dart:ui' show ImageFilter;


import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../data/clip_prefetch.dart' show ReelsCfg;
import '../../../data/embed_sources.dart';
import '../../../data/keys.dart';
import '../../../data/stash_server.dart';
import '../../../data/platform/clip_cache.dart';
import '../../../data/privacy.dart' show blurPhotos;
import '../../../data/sources.dart';
import '../../../domain/performer.dart';
import '../../../domain/reels.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../works/works_screen.dart' show worksProvider, workTasteProvider, showWorkSheet;
import 'embed_reel.dart';
import 'full_video_screen.dart';
import 'reel_center.dart';

/// إشارات «مقاطع» (محفوظة على الجهاز فقط).
class ReelSigN extends AsyncNotifier<ReelSignals> {
  @override Future<ReelSignals> build() async => decayReels(ReelSignals.fromJson(await (await ref.watch(repoProvider.future)).kvGet('reels_sig')), reelDay());
  ReelSignals get _s => state.value ?? const ReelSignals({}, {});
  Future<void> _save(ReelSignals s) async { state = AsyncData(s); await (await ref.read(repoProvider.future)).kvSet('reels_sig', s.toJson()); }
  Future<void> view(WorkGroup g, double frac, {bool like = false}) async => _save(recordView(_s, g, frac: frac, like: like));
  Future<void> dislikeIt({String? performerId, String? studio, String? hideKey}) async => _save(dislike(_s, performerId: performerId, studio: studio, hideKey: hideKey));
  Future<void> act(WorkGroup g, String action) async => _save(recordAction(_s, g, action));
  Future<void> save(WorkGroup g) async => _save(toggleSave(_s, g));
  Future<void> unlike(WorkGroup g) async { final c = {..._s.clips}; final m = {...?c[g.key]}..remove('l'); c[g.key] = m; await _save(ReelSignals(c, _s.aff, _s.day)); }
}
final reelSigProvider = AsyncNotifierProvider<ReelSigN, ReelSignals>(ReelSigN.new);

/// جلب الإعلانات الرسمية من ThePornDB لأعمال مفضلاتك (تُدمج في أعمالهن بلا تكرار — يملأ «tr» فقط حيث ينقص).
Future<String> fetchTrailers(WidgetRef ref, {bool favsOnly = false, void Function(String)? progress}) async {
  if (!await ApiKeys.has(ApiKeys.tpdb)) return 'المقاطع تأتي من ThePornDB — أضف مفتاحه من «المزيد».';
  final lib = ref.read(libraryProvider.notifier);
  final ps = lib.items.where((p) => !p.isMinor && p.pdbIds.isNotEmpty && (!favsOnly || p.fav || p.rating >= 4)).toList();
  if (ps.isEmpty) return 'لا ممثلات مرتبطة بـ ThePornDB في ${favsOnly ? 'مفضلاتك' : 'مكتبتك'} — اربطها أولًا (تحديث من المصدرين).';
  var withTr = 0, i = 0; final changed = <Performer>[];
  for (final p in ps) {
    i++; progress?.call('جلب مقاطع ${p.name} ($i/${ps.length})…');
    var works = p.works;
    for (final id in p.pdbIds) {
      try { works = mergeWorks(works, await TPDB.scenes(id, maxPages: 40)).list; }
      on SourceError catch (e) { if (e.status == -2 || e.status == 401 || e.status == 403) return e.msg; }
    }
    final cur = lib.items.where((x) => x.id == p.id).firstOrNull ?? p;
    final merged = mergeWorks(cur.works, works).list;
    withTr += merged.where((w) => '${w['tr'] ?? ''}'.isNotEmpty).length;
    changed.add(cur.copyWith({'works': merged}));
  }
  if (changed.isNotEmpty) await lib.upsertMany(changed);
  await (await ref.read(repoProvider.future)).kvSet('reels_fetched_at', DateTime.now().millisecondsSinceEpoch);
  return withTr == 0 ? 'لم تُعثر على إعلانات رسمية لأعمال ${favsOnly ? 'مفضلاتك' : 'مكتبتك'} في ThePornDB.' : 'جاهز: $withTr مقطعًا';
}

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});
  @override ConsumerState<ReelsScreen> createState() => _ReelsState();
}

/// تركيز الخلاصة: ممثلة / استوديو / وسم (من الضغط على التعليق).
typedef ReelFocus = ({String kind, String v, String label});

class _ReelsState extends ConsumerState<ReelsScreen> {
  final _pc = PageController();
  List<Reel>? _feed; int _cur = 0; bool _favsOnly = false, _muted = true, _busy = false, _preparing = false, _tabInit = false; String _msg = '';
  Map<String, dynamic> _hosts = {}, _quality = {}; int _hidden = 0; bool _hqOnly = true;
  int _seed = DateTime.now().millisecondsSinceEpoch;
  // مثل TikTok: السرعة، الوضع النظيف (بلا أزرار)، التمرير التلقائي، والتركيز
  double _speed = 1; bool _clean = false, _auto = false; ReelFocus? _focus;

  @override void dispose() { _pc.dispose(); super.dispose(); }

  Set<String> _cached = {};
  List<WorkGroup> _server = [], _embeds = [];
  ReelSignals get _sig => ref.read(reelSigProvider).value ?? const ReelSignals({}, {});

  void _build() {
    final sig = _sig, taste = ref.read(workTasteProvider);
    bool cached(String u) => _cached.contains(clipKeyOf(u));
    bool inFocus(WorkGroup g) => _focus == null || reelFocusMatch(g, _focus!.kind, _focus!.v);
    final favs = _favsOnly && _focus == null;
    final trailers = rankReels(ref.read(worksProvider).where(inFocus).toList(), taste, sig, favsOnly: favs, seed: _seed, n: 200,
      playable: (u) => (hostUsable(_hosts, u) || cached(u)) && qualityOk(_quality, u, hqOnly: _hqOnly), isCached: cached);
    // خادم Stash الخاص بك: مقاطع قصيرة (45 ثانية من داخل كل فيديو) وبينها فيديوهات كاملة — مرتبة بنفس الخوارزمية
    final server = <Reel>[];
    var k = 0;
    for (final r in rankReels(_server.where(inFocus).toList(), taste, sig, favsOnly: favs, seed: _seed, n: 200)) {
      final seg = shortSegment(r.g.key, r.g.du * 60);
      server.add(seg.$2 > 0 ? r.variant(start: seg.$1, len: seg.$2, src: 'Stash · مقطع قصير') : r.variant(full: true, src: 'Stash · فيديو كامل'));
      if (seg.$2 > 0 && ++k % 4 == 0) server.add(r.variant(full: true, src: 'Stash · فيديو كامل'));
    }
    // مواقع التضمين الرسمية: فيديوهات كاملة موسومة بمصدرها
    final embeds = [for (final r in rankReels(_embeds.where(inFocus).toList(), taste, sig, favsOnly: favs, seed: _seed, n: 200)) r.variant(full: true, src: '${embedSourceName(r.g.key)} · فيديو كامل')];
    _feed = weave(weave(trailers, server), embeds, bPerA: 1);
    _hidden = _scope().where((g) => !hostUsable(_hosts, g.tr) && !cached(g.tr)).length;
    _cur = 0;
    final ready = _feed!.where((r) => cached(r.url)).length;
    if (_msg.isEmpty && _focus == null) _msg = '${_feed!.length} مقطعًا${ready > 0 ? ' ($ready جاهز على جهازك)' : ''}${_hidden > 0 ? ' · $_hidden مخفي (خوادمها محجوبة على شبكتك)' : ''}';
  }

  Iterable<WorkGroup> _scope() => ref.read(worksProvider).where((g) => g.tr.isNotEmpty && (!_favsOnly || g.who.any((p) => p.fav || p.rating >= 4)));

  /// كل ما يمكن عرضه، بالمفتاح (لـ«سجلّي» و«المحفوظة»).
  Map<String, WorkGroup> _allGroups() => {for (final g in [...ref.read(worksProvider).where((g) => g.tr.isNotEmpty), ..._server, ..._embeds]) g.key: g};

  /// قبل العرض: إعدادات الصوت، المقاطع المحفوظة، وفحص الخوادم غير المفحوصة أو القديمة — فيُعرض ما يعمل والمحفوظ أولًا.
  Future<void> _prepare({bool force = false}) async {
    final cfg = await ref.read(reelsCfgProvider.future);
    _muted = !cfg.sound; _hqOnly = cfg.hqOnly; _auto = cfg.auto;
    if (!_tabInit) { _tabInit = true; _favsOnly = cfg.favTab; }
    final repo = await ref.read(repoProvider.future);
    _hosts = await loadHosts(repo);
    _quality = Map<String, dynamic>.from(await repo.kvGet('reel_quality') as Map? ?? {});
    _server = await _loadServer(cfg);
    _embeds = await _loadEmbeds(cfg);
    _cached = (await clipCacheStats()).$1;
    final todo = _scope().map((g) => g.tr);
    if (mounted) setState(() { _preparing = true; _msg = 'فحص خوادم المقاطع على شبكتك…'; });
    await probeHosts(_hosts, todo, force: force, progress: (d, t) { if (mounted) setState(() => _msg = 'فحص خوادم المقاطع على شبكتك ($d/$t)…'); });
    await saveHosts(repo, _hosts);
    if (!mounted) return;
    setState(() { _preparing = false; _msg = ''; _build(); });
    _prefetch(0); _prefetch(1);
    _autoUpdate();
  }

  /// مقاطع خادم Stash الخاص بك (إن ضُبط ومُفعّل): ربط ممثلاتك بخادمك (بمعرّف StashDB أو الاسم) مع ذاكرة، ثم جلب مقاطعهن.
  Future<List<WorkGroup>> _loadServer(ReelsCfg cfg) async {
    if (!cfg.server || !await StashServer.configured()) return const [];
    try {
      if (mounted) setState(() => _msg = 'الاتصال بخادم Stash…');
      final repo = await ref.read(repoProvider.future);
      final map = Map<String, dynamic>.from(await repo.kvGet('stash_local_map') as Map? ?? {});
      final lib = ref.read(libraryProvider).value ?? const <Performer>[];
      final want = lib.where((p) => !p.isMinor).toList();   // كل المكتبة؛ تبويب «مفضلاتي» يصفّي عند الترتيب
      var asked = 0;
      for (final p in want) {
        if (map.containsKey(p.id) || asked >= 60) continue;   // 60 ربطًا جديدًا كحد في كل فتح
        asked++; map[p.id] = await StashServer.localPerformer(p) ?? '';
      }
      await repo.kvSet('stash_local_map', map);
      final byLocal = {for (final p in want) if ('${map[p.id] ?? ''}'.isNotEmpty) '${map[p.id]}': p};
      return await StashServer.scenes(byLocal);
    } on SourceError catch (e) { if (mounted) setState(() => _msg = e.msg); return const []; }
    catch (_) { return const []; }
  }

  /// مواقع التضمين الرسمية المفعّلة: فحص الوصول (كل 6 ساعات)، ثم نتائج كل ممثلة من الذاكرة (تُجدَّد كل 3 أيام، 20 ممثلة جديدة لكل موقع في كل فتح).
  Future<List<WorkGroup>> _loadEmbeds(ReelsCfg cfg) async {
    if (cfg.emb.isEmpty) return const [];
    final repo = await ref.read(repoProvider.future);
    final reach = Map<String, dynamic>.from(await repo.kvGet('embed_reach') as Map? ?? {});
    final cache = Map<String, dynamic>.from(await repo.kvGet('embed_cache') as Map? ?? {});
    final now = DateTime.now().millisecondsSinceEpoch;
    final lib = (ref.read(libraryProvider).value ?? const <Performer>[]).where((p) => !p.isMinor).toList()..sort((x, y) => (y.fav ? 1 : 0).compareTo(x.fav ? 1 : 0));   // المفضلات أولًا
    final out = <WorkGroup>[]; var blocked = 0;
    for (final s in embedSources.where((s) => cfg.emb.contains(s.id))) {
      final st = reach[s.id] as Map?;
      if (st == null || now - ((st['t'] as num?) ?? 0) > 6 * 3600000) {
        if (mounted) setState(() => _msg = 'فحص ${s.name}…');
        reach[s.id] = {'ok': await embedReachable(s), 't': now};
      }
      if ((reach[s.id] as Map)['ok'] != true) { blocked++; continue; }
      var fetched = 0;
      for (final p in lib) {
        final k = '${s.id}:${p.id}'; final c = cache[k] as Map?;
        if ((c == null || now - ((c['at'] as num?) ?? 0) > 3 * 86400000) && fetched < 20) {
          fetched++; if (mounted) setState(() => _msg = '${s.name}: ${p.name}…');
          final l = await searchEmbeds(s, p);
          cache[k] = {'at': now, 'v': [for (final g in l.take(15)) {'k': g.key, 't': g.t, 'p': g.p, 'tr': g.tr, 'du': g.du}]};
        }
        for (final v in ((cache[k] as Map?)?['v'] as List? ?? const [])) {
          if (v is! Map) continue;
          final g = WorkGroup('${v['k']}')..t = '${v['t']}'..p = '${v['p']}'..tr = '${v['tr']}'..du = (v['du'] as num?)?.toInt() ?? 0;
          g.who.add(p); out.add(g);
        }
      }
    }
    await repo.kvSet('embed_reach', reach); await repo.kvSet('embed_cache', cache);
    if (blocked > 0 && blocked == cfg.emb.length && mounted) _msg = 'مواقع التضمين محجوبة على شبكتك (تعمل مع VPN)';
    return out;
  }

  /// تحديث تلقائي: إن مضى 3 أيام على آخر جلب ⇒ جلب الإعلانات الجديدة بهدوء في الخلفية.
  Future<void> _autoUpdate() async {
    final repo = await ref.read(repoProvider.future);
    final last = (await repo.kvGet('reels_fetched_at') as num?)?.toInt() ?? 0;
    if (_busy || DateTime.now().millisecondsSinceEpoch - last < 3 * 86400000 || !await ApiKeys.has(ApiKeys.tpdb)) return;
    final before = ref.read(worksProvider).where((g) => g.tr.isNotEmpty).length;
    if (mounted) setState(() => _msg = 'تحديث المقاطع في الخلفية…');
    final m = await fetchTrailers(ref);
    final added = ref.read(worksProvider).where((g) => g.tr.isNotEmpty).length - before;
    if (!mounted) return;
    setState(() => _msg = added > 0 ? 'وصل $added مقطعًا جديدًا — اضغط ↻ لعرضها' : m.startsWith('جاهز') ? '' : m);
  }

  /// خادم يحتاج تنزيلًا (المشغّل لا يصله مباشرة) ⇒ يُتذكر، ويُنزَّل التالي منه مسبقًا.
  Future<void> _markDl(String url) async {
    final h = hostOf(url); if (h.isEmpty || (_hosts[h] as Map?)?['dl'] == true) return;
    _hosts[h] = {...?(_hosts[h] as Map?), 'ok': true, 'dl': true, 't': DateTime.now().millisecondsSinceEpoch};
    await (await ref.read(repoProvider.future)).kvSet('reel_hosts', _hosts);
  }
  void _prefetch(int i) {
    final f = _feed; if (f == null || i >= f.length) return;
    if ((_hosts[hostOf(f[i].url)] as Map?)?['dl'] == true) unawaited(downloadClip(f[i].url));
  }

  Future<void> _markBlocked(String url, String why) async {
    final h = hostOf(url); if (h.isEmpty) return;
    _hosts[h] = {'ok': false, 't': DateTime.now().millisecondsSinceEpoch, 'why': why};
    await (await ref.read(repoProvider.future)).kvSet('reel_hosts', _hosts);
    if (!mounted || _feed == null) return;
    // إخفاء بقية مقاطع هذا الخادم من الخلاصة الحالية (بعد المقطع الحالي)
    setState(() { _feed = [..._feed!.take(_cur + 1), ..._feed!.skip(_cur + 1).where((r) => hostOf(r.url) != h)]; _hidden = _scope().where((g) => !hostUsable(_hosts, g.tr)).length; });
  }

  Future<void> _fetch() async {
    setState(() { _busy = true; _msg = 'جارٍ جلب المقاطع…'; });
    final m = await fetchTrailers(ref, progress: (x) { if (mounted) setState(() => _msg = x); });
    if (!mounted) return;
    setState(() { _busy = false; _msg = m; _seed++; });
    await _prepare();
  }

  void _onViewed(Reel r, double frac) => ref.read(reelSigProvider.notifier).view(r.g, frac, like: false);

  bool _isLiked(Reel r) => _sig.clips[r.g.key]?['l'] == 1;
  bool _isSaved(Reel r) => _sig.clips[r.g.key]?['s'] == 1;

  /// الإعجاب بالنقر المزدوج يُعجب فقط (كما في TikTok)؛ زر القلب يبدّل.
  void _like(Reel r, {bool toggle = false}) {
    HapticFeedback.lightImpact();
    if (_isLiked(r)) { if (toggle) ref.read(reelSigProvider.notifier).unlike(r.g); }
    else { ref.read(reelSigProvider.notifier).view(r.g, 1, like: true); }
  }

  void _save(Reel r) {
    HapticFeedback.selectionClick();
    final was = _isSaved(r);
    ref.read(reelSigProvider.notifier).save(r.g);
    _toast(was ? 'أُزيل من المحفوظة' : 'حُفظ 🔖 — تجده في «المحفوظة»');
  }

  void _toast(String m) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m), duration: const Duration(milliseconds: 1600), behavior: SnackBarBehavior.floating));

  void _profile(Reel r, [Performer? p]) {
    final who = p ?? r.g.who.first;
    ref.read(reelSigProvider.notifier).act(r.g, 'profile');
    context.push('/p/${who.id}');
  }

  /// ＋ على صورة الممثلة: إضافتها للمفضلة (مثل «متابعة»).
  Future<void> _follow(Reel r) async {
    final lib = ref.read(libraryProvider.notifier);
    final p = lib.items.where((x) => x.id == r.g.who.first.id).firstOrNull; if (p == null || p.fav) return;
    HapticFeedback.mediumImpact();
    if (await lib.upsert(p.copyWith({'fav': true}))) {
      ref.read(reelSigProvider.notifier).act(r.g, 'follow');
      _toast('أُضيفت ${p.name} لمفضلاتك ⭐');
      if (mounted) setState(() {});
    }
  }

  void _setFocus(ReelFocus? f) {
    HapticFeedback.selectionClick();
    setState(() { _focus = f; _seed++; _msg = ''; _build(); });
    if (_pc.hasClients) _pc.jumpToPage(0);
    if (f != null && (_feed?.isEmpty ?? true)) _toast('لا مقاطع متاحة لـ${f.label} الآن');
  }

  Future<void> _setTab(bool favs) async {
    if (favs == _favsOnly && _focus == null) { _seed++; setState(_build); if (_pc.hasClients) _pc.jumpToPage(0); return; }   // الضغط على التبويب الحالي = تحديث
    setState(() { _favsOnly = favs; _focus = null; _seed++; _msg = ''; _build(); });
    if (_pc.hasClients) _pc.jumpToPage(0);
    final c = await ref.read(reelsCfgProvider.future);
    await ref.read(reelsCfgProvider.notifier).set(c.copy(favTab: favs));
  }

  Future<void> _setAuto(bool v) async {
    setState(() => _auto = v);
    final c = await ref.read(reelsCfgProvider.future);
    await ref.read(reelsCfgProvider.notifier).set(c.copy(auto: v));
  }

  /// الضغط المطوّل (مثل TikTok): السرعة، غير مهتم، أقل منها/من الاستوديو، الحفظ، الوضع النظيف، التمرير التلقائي.
  void _menu(Reel r) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(context: context, showDragHandle: true, builder: (c) => SafeArea(child: StatefulBuilder(builder: (c, set) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s2), child: Row(children: [
        const Text('السرعة'), const Spacer(),
        SegmentedButton<double>(showSelectedIcon: false, segments: const [ButtonSegment(value: .5, label: Text('0.5')), ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 1.5, label: Text('1.5')), ButtonSegment(value: 2, label: Text('2'))],
          selected: {_speed}, onSelectionChanged: (v) { setState(() => _speed = v.first); set(() {}); }),
      ])),
      ListTile(leading: const Icon(Icons.heart_broken_rounded), title: const Text('غير مهتم'), subtitle: const Text('يخفي هذا المقطع ويقلل ما يشبهه'),
        onTap: () { Navigator.pop(c); ref.read(reelSigProvider.notifier).act(r.g, 'nope'); _toast('سنعرض أقل من هذا'); _remove(r); }),
      for (final p in r.g.who) ListTile(leading: const Icon(Icons.person_remove_rounded), title: Text('أقل من ${p.name}'),
        onTap: () { Navigator.pop(c); ref.read(reelSigProvider.notifier).dislikeIt(performerId: p.id); _skip(); }),
      if (r.g.s.isNotEmpty) ListTile(leading: const Icon(Icons.business_rounded), title: Text('أقل من ${r.g.s}'),
        onTap: () { Navigator.pop(c); ref.read(reelSigProvider.notifier).dislikeIt(studio: r.g.s); _skip(); }),
      ListTile(leading: Icon(_isSaved(r) ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded), title: Text(_isSaved(r) ? 'إزالة من المحفوظة' : 'حفظ'), onTap: () { Navigator.pop(c); _save(r); }),
      ListTile(leading: const Icon(Icons.visibility_off_rounded), title: const Text('إخفاء هذا المقطع'),
        onTap: () { Navigator.pop(c); ref.read(reelSigProvider.notifier).dislikeIt(hideKey: r.g.key); _remove(r); }),
      SwitchListTile(secondary: const Icon(Icons.fullscreen_rounded), title: const Text('الوضع النظيف'), subtitle: const Text('بلا أزرار ولا نصوص'), value: _clean, onChanged: (v) { setState(() => _clean = v); set(() {}); }),
      SwitchListTile(secondary: const Icon(Icons.swipe_up_rounded), title: const Text('تمرير تلقائي'), subtitle: const Text('ينتقل للتالي عند انتهاء المقطع'), value: _auto, onChanged: (v) { _setAuto(v); set(() {}); }),
    ])))));
  }

  /// إزالة مقطع من الخلاصة الحالية والانتقال للتالي.
  void _remove(Reel r) {
    final f = _feed; if (f == null) return;
    final i = f.indexWhere((x) => x.key == r.key); if (i < 0) return;
    setState(() { _feed = [...f]..removeAt(i); if (_cur >= _feed!.length) _cur = (_feed!.length - 1).clamp(0, 1 << 30); });
  }

  /// «سجلّي» / «المحفوظة» / «أعجبتني»: اختيار مقطع يعرضه الآن.
  Future<void> _openLibrary(int tab) async {
    final all = _allGroups();
    final key = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _ReelsLibrary(groups: all, tab: tab)));
    if (key == null || !mounted) return;
    final f = _feed ?? const <Reel>[];
    final i = f.indexWhere((r) => r.g.key == key);
    if (i >= 0) { _pc.jumpToPage(i); return; }
    final g = all[key]; if (g == null) { _toast('هذا المقطع غير متاح الآن'); return; }
    final r = Reel(g, g.tr, 'من سجلّك', src: g.key.startsWith('stash:') ? 'Stash · فيديو كامل' : g.key.startsWith('emb:') ? '${embedSourceName(g.key)} · فيديو كامل' : 'ThePornDB · إعلان', full: g.key.startsWith('stash:'));
    setState(() => _feed = [...f.take(_cur + 1), r, ...f.skip(_cur + 1)]);
    _pc.animateToPage(_cur + 1, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  /// جودة مقاسة عند التشغيل: الارتفاع، والصوت (1/0، أو غير معروف). المعاينة تُتخطى في وضع «إعلانات حقيقية فقط».
  Future<void> _onQuality(Reel r, int h, int? audio) async {
    _quality[r.url] = {'h': h, 'a': ?audio};
    await (await ref.read(repoProvider.future)).kvSet('reel_quality', _quality);
    if (!mounted || !_hqOnly || _feed == null || r.g.key.startsWith('stash:')) return;
    if (isPreviewClip(_quality[r.url] as Map)) {
      final host = hostOf(r.url); final drop = isPreviewHost(_quality, host);
      setState(() { _feed = [..._feed!.take(_cur + 1), ..._feed!.skip(_cur + 1).where((x) => qualityOk(_quality, x.url, hqOnly: true) && (!drop || hostOf(x.url) != host))]; });
      if (_feed!.isNotEmpty && _feed![_cur].key == r.key) { setState(() => _msg = 'تخطّينا معاينة ${audio == 0 ? 'بلا صوت' : '${h}p'} — نعرض الإعلانات الحقيقية فقط'); _skip(); }
    }
  }

  Future<void> _toggleSound() async {
    setState(() => _muted = !_muted);
    final c = await ref.read(reelsCfgProvider.future);
    await ref.read(reelsCfgProvider.notifier).set(c.copy(sound: !_muted));
  }

  void _skip() { if (_feed != null && _cur + 1 < _feed!.length) _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut); }

  @override
  Widget build(BuildContext context) {
    final sigReady = ref.watch(reelSigProvider).hasValue && ref.watch(libraryProvider).hasValue;
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    if (sigReady && _feed == null && !_preparing) { _feed = const []; _preparing = true; Future.microtask(_prepare); }
    final feed = _feed ?? const <Reel>[];
    bool isFav(Reel r) => lib.where((x) => x.id == r.g.who.first.id).firstOrNull?.fav ?? true;
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      if (!sigReady || (_preparing && feed.isEmpty)) Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: S.s3), Text(_msg, style: const TextStyle(color: Colors.white70))]))
      else if (feed.isEmpty) _empty()
      else PageView.builder(controller: _pc, scrollDirection: Axis.vertical, itemCount: feed.length,
        onPageChanged: (i) { setState(() => _cur = i); _prefetch(i + 1); },
        itemBuilder: (c, i) => (i - _cur).abs() > 1 ? const ColoredBox(color: Colors.black)   // لا يُحمَّل إلا الحالي والمجاوران
          : feed[i].g.key.startsWith('emb:') ? EmbedReel(key: ValueKey(feed[i].key), reel: feed[i], active: i == _cur, liked: _isLiked(feed[i]),
              onViewed: (f) => _onViewed(feed[i], f), onLike: () => _like(feed[i], toggle: true), onMenu: () => _menu(feed[i]), onProfile: () => _profile(feed[i]))
          : _ReelPage(key: ValueKey(feed[i].key), reel: feed[i], active: i == _cur, muted: _muted, liked: _isLiked(feed[i]), saved: _isSaved(feed[i]), fav: isFav(feed[i]),
              speed: _speed, clean: _clean, auto: _auto,
              onViewed: (f) => _onViewed(feed[i], f), onLike: (toggle) => _like(feed[i], toggle: toggle), onSave: () => _save(feed[i]), onMenu: () => _menu(feed[i]), onMute: _toggleSound,
              onProfile: (p) => _profile(feed[i], p), onFollow: () => _follow(feed[i]), onFocus: _setFocus, onEnded: () { if (i == _cur) _skip(); },
              onFull: () => ref.read(reelSigProvider.notifier).act(feed[i].g, 'full'),
              preferDownload: (_hosts[hostOf(feed[i].url)] as Map?)?['dl'] == true, onDownloaded: () => _markDl(feed[i].url),
              onQuality: (h, a) => _onQuality(feed[i], h, a),
              onError: (why) { _markBlocked(feed[i].url, why.isEmpty ? 'تعذّر التشغيل والتنزيل' : why); if (i == _cur) Future<void>.delayed(const Duration(seconds: 2), () { if (mounted && _cur == i) _skip(); }); })),
      // الشريط العلوي (مثل TikTok: «مفضلاتي | لك» في الوسط)
      if (!_clean) SafeArea(child: SizedBox(height: 52, child: Stack(children: [
        Align(alignment: AlignmentDirectional.centerStart, child: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded, color: Colors.white, shadows: [Shadow(blurRadius: 8)]))),
        Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          _tab('مفضلاتي', _favsOnly && _focus == null, () => _setTab(true)),
          Container(width: 1, height: 14, color: Colors.white30),
          _tab('لك', !_favsOnly && _focus == null, () => _setTab(false)),
        ])),
        Align(alignment: AlignmentDirectional.centerEnd, child: PopupMenuButton<String>(icon: const Icon(Icons.more_vert_rounded, color: Colors.white, shadows: [Shadow(blurRadius: 8)]),
          onSelected: (v) async {
            switch (v) {
              case 'h': _openLibrary(0);
              case 's': _openLibrary(1);
              case 'l': _openLibrary(2);
              case 'f': if (!_busy) _fetch();
              case 'a': _setAuto(!_auto);
              case 'c': setState(() => _clean = true);
              case 'n': await context.push('/network'); if (mounted) { setState(() => _msg = ''); _prepare(); }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'h', child: ListTile(leading: Icon(Icons.history_rounded), title: Text('سجلّي'))),
            const PopupMenuItem(value: 's', child: ListTile(leading: Icon(Icons.bookmark_rounded), title: Text('المحفوظة'))),
            const PopupMenuItem(value: 'l', child: ListTile(leading: Icon(Icons.favorite_rounded), title: Text('أعجبتني'))),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'a', child: ListTile(leading: Icon(_auto ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded), title: const Text('تمرير تلقائي'))),
            const PopupMenuItem(value: 'c', child: ListTile(leading: Icon(Icons.fullscreen_rounded), title: Text('الوضع النظيف'))),
            const PopupMenuItem(value: 'f', child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('جلب مقاطع جديدة'))),
            const PopupMenuItem(value: 'n', child: ListTile(leading: Icon(Icons.network_check_rounded), title: Text('الشبكة والمقاطع'))),
          ])),
      ]))),
      // التركيز الحالي (ممثلة/استوديو/وسم)
      if (_focus != null && !_clean) Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.only(top: 54), child: Center(child: InputChip(
        avatar: Icon(_focus!.kind == 'pf' ? Icons.person_rounded : _focus!.kind == 'st' ? Icons.business_rounded : Icons.tag_rounded, size: 18),
        label: Text(_focus!.label), onDeleted: () => _setFocus(null), onPressed: () => _setFocus(null)))))),
      if (_clean) SafeArea(child: Align(alignment: AlignmentDirectional.topEnd, child: IconButton(onPressed: () => setState(() => _clean = false), icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white54)))),
      if (_msg.isNotEmpty && !_clean && (_busy || feed.isNotEmpty)) Positioned(top: 100, left: S.s4, right: S.s4, child: SafeArea(child: Container(padding: const EdgeInsets.all(S.s2),
        decoration: BoxDecoration(color: const Color(0xCC0A0810), borderRadius: BorderRadius.circular(S.rMd)),
        child: Row(children: [Expanded(child: Text(_msg, style: const TextStyle(color: Colors.white70, fontSize: 12.5))), if (!_busy) IconButton(onPressed: () => setState(() => _msg = ''), icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54))])))),
    ]));
  }

  Widget _tab(String t, bool on, VoidCallback f) => GestureDetector(onTap: f, behavior: HitTestBehavior.opaque, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Text(t, style: TextStyle(color: on ? Colors.white : Colors.white60, fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 16.5, shadows: const [Shadow(blurRadius: 8)])),
    const SizedBox(height: 4),
    AnimatedContainer(duration: const Duration(milliseconds: 200), width: on ? 22 : 0, height: 2.5, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
  ])));

  Widget _empty() => Center(child: Padding(padding: const EdgeInsets.all(S.s5), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.slow_motion_video_rounded, color: C.gold, size: 56),
    const SizedBox(height: S.s3),
    const Text('مقاطع ممثلاتك', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
    const SizedBox(height: S.s2),
    Text(_msg.isNotEmpty && !_busy ? _msg : 'إعلانات أعمال ${_favsOnly ? 'مفضلاتك' : 'مكتبتك'} من ThePornDB، وفيديوهات خادمك ومواقع التضمين إن فعّلتها — مرتبة بخوارزمية تتعلم من مشاهدتك على جهازك فقط.',
      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.6)),
    const SizedBox(height: S.s4),
    FilledButton.icon(onPressed: _busy ? null : _fetch, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded), label: Text(_busy ? _msg : 'جلب المقاطع')),
    if (_focus != null) TextButton(onPressed: () => _setFocus(null), child: const Text('رجوع لكل المقاطع')),
    if (!_favsOnly || _focus == null) TextButton(onPressed: () => context.push('/network'), child: const Text('الشبكة والمقاطع')),
  ])));
}

/// مقطع واحد (واجهة TikTok): نقرة = إيقاف، نقرتان = ♥ مكان الإصبع، سحب لليسار = ملفها، ضغط مطوّل = القائمة.
class _ReelPage extends ConsumerStatefulWidget {
  const _ReelPage({super.key, required this.reel, required this.active, required this.muted, required this.liked, required this.saved, required this.fav,
    required this.speed, required this.clean, required this.auto,
    required this.onViewed, required this.onLike, required this.onSave, required this.onMenu, required this.onMute, required this.onProfile, required this.onFollow,
    required this.onFocus, required this.onEnded, required this.onFull, required this.onError, this.preferDownload = false, required this.onDownloaded, required this.onQuality});
  final Reel reel; final bool active, muted, liked, saved, fav, preferDownload, clean, auto; final double speed;
  final VoidCallback onDownloaded, onSave, onMenu, onMute, onFollow, onEnded, onFull; final void Function(int h, int? audio) onQuality;
  final void Function(double) onViewed; final void Function(bool toggle) onLike; final void Function(String why) onError;
  final void Function(Performer p) onProfile; final void Function(ReelFocus f) onFocus;
  @override ConsumerState<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<_ReelPage> {
  VideoPlayerController? _c; bool _err = false, _paused = false, _ended = false; String _why = '';
  Duration _maxPos = Duration.zero; int _loops = 0; Duration _last = Duration.zero;
  final _hearts = <(int, Offset)>[]; int _heartId = 0; Offset _tapAt = Offset.zero;
  String? _savedPath;

  double? _dl;   // تقدم التنزيل (عند الحاجة)

  @override
  void initState() { super.initState(); _start(); }

  /// التشغيل الذكي: محفوظ على الجهاز ⇒ مباشرة من الشبكة ⇒ (إن فشل) تنزيل عبر شبكات النظام ثم تشغيل من الجهاز.
  Future<void> _start() async {
    final url = widget.reel.url;
    final saved = await cachedClipPath(url);
    if (saved != null) { if (await _open(_fileController(saved))) { _savedPath = saved; return; } }
    if (!widget.preferDownload) {
      final ok = await _open(VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false)));
      if (ok) return;
    }
    if (clipCacheSupported && !widget.reel.g.key.startsWith('stash:')) {
      if (mounted) setState(() { _err = false; _dl = 0; });
      final path = await downloadClip(url, onProgress: (p) { if (mounted) setState(() => _dl = p); });
      if (!mounted) return;
      if (path != null && await _open(_fileController(path))) { _dl = null; _savedPath = path; widget.onDownloaded(); return; }
    }
    if (mounted) { setState(() { _dl = null; _err = true; }); widget.onError(_why); }
  }

  VideoPlayerController _fileController(String path) {
    final f = fileVideoSource(path);
    return f == null ? VideoPlayerController.networkUrl(Uri.file(path)) : VideoPlayerController.file(f as dynamic, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
  }

  String _badge = '';
  /// يقيس الدقة الحقيقية ووجود مسار صوتي (إن دعم النظام ذلك) — يظهر عند الإيقاف.
  Future<void> _measure(VideoPlayerController c) async {
    final h = c.value.size.height.round();
    int? audio;
    try { audio = (await c.getAudioTracks()).isEmpty ? 0 : 1; } catch (_) {}
    if (!mounted) return;
    setState(() => _badge = '${h > 0 ? '${h}p' : '?'}${audio == null ? '' : audio == 1 ? ' · 🔊' : ' · بلا صوت'}');
    if (h > 0) widget.onQuality(h, audio);
  }

  Future<bool> _open(VideoPlayerController c) async {
    try {
      await c.initialize();
      if (!mounted) { await c.dispose(); return false; }
      _c?.removeListener(_tick); final old = _c; _c = c; await old?.dispose();
      c.setLooping(true); c.setVolume(widget.muted ? 0 : 1); c.setPlaybackSpeed(widget.speed); c.addListener(_tick);
      if (widget.reel.start > 0) { await c.seekTo(Duration(seconds: widget.reel.start)); _maxPos = Duration(seconds: widget.reel.start); _last = _maxPos; }
      if (widget.active && !_paused) c.play();
      setState(() { _err = false; });
      _measure(c);
      return true;
    } catch (e) { _why = '$e'; try { await c.dispose(); } catch (_) {} return false; }
  }

  void _loopDone() {
    _loops++;
    if (widget.auto && widget.active && !_ended) { _ended = true; widget.onEnded(); }
  }

  void _tick() {
    final c = _c!; final v = c.value; if (!v.isInitialized) return;
    final r = widget.reel;
    if (r.len > 0 && v.position >= Duration(seconds: r.start + r.len)) { _loopDone(); _last = Duration(seconds: r.start); c.seekTo(Duration(seconds: r.start)); return; }   // مقطع قصير يتكرر
    if (v.position < _last - const Duration(seconds: 1)) _loopDone();   // رجع للبداية ⇒ إعادة
    _last = v.position; if (v.position > _maxPos) _maxPos = v.position;
    if (mounted) setState(() {});   // شريط التقدم
  }

  double get _frac {
    final r = widget.reel;
    if (r.len > 0) return _loops + ((_maxPos.inMilliseconds - r.start * 1000) / (r.len * 1000)).clamp(0.0, 1.0);
    final d = _c?.value.duration ?? Duration.zero; if (d.inMilliseconds <= 0) return 0; return _loops + _maxPos.inMilliseconds / d.inMilliseconds;
  }

  @override
  void didUpdateWidget(covariant _ReelPage o) {
    super.didUpdateWidget(o);
    final c = _c; if (c == null || !c.value.isInitialized) { return; }
    if (o.muted != widget.muted) c.setVolume(widget.muted ? 0 : 1);
    if (o.speed != widget.speed) c.setPlaybackSpeed(widget.speed);
    if (o.active && !widget.active) { c.pause(); widget.onViewed(_frac); _maxPos = Duration.zero; _loops = 0; _ended = false; c.seekTo(Duration(seconds: widget.reel.start)); }
    if (!o.active && widget.active) { if (_err) { widget.onError(_why); } else if (c.value.isInitialized && !_paused) { c.play(); } }
  }

  @override
  void dispose() { if (widget.active) widget.onViewed(_frac); _c?.removeListener(_tick); _c?.dispose(); super.dispose(); }

  void _doubleTap() {
    widget.onLike(false);
    final id = ++_heartId;
    setState(() => _hearts.add((id, _tapAt)));
    Future<void>.delayed(const Duration(milliseconds: 800), () { if (mounted) setState(() => _hearts.removeWhere((h) => h.$1 == id)); });
  }

  void _openFull() {
    final r = widget.reel, c = _c;
    final at = c != null && c.value.isInitialized ? c.value.position.inSeconds : r.start;
    c?.pause(); setState(() => _paused = true);
    widget.onFull();
    final f = _savedPath == null ? null : fileVideoSource(_savedPath!);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FullVideoScreen(url: r.url, title: r.g.t, start: at, source: r.src.split(' · ').first, file: f)));
  }

  String _t(Duration d) => '${d.inMinutes}:${'${d.inSeconds % 60}'.padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final r = widget.reel, g = r.g, c = _c;
    final ready = c != null && c.value.isInitialized;
    final wide = ready && c.value.aspectRatio > 1.15;
    final p0 = g.who.first;
    Widget video = ready ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))) : Stack(fit: StackFit.expand, children: [
      Center(child: _err ? Padding(padding: const EdgeInsets.all(S.s5), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تعذّر تشغيل هذا المقطع — ننتقل للتالي…', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Text('الخادم: ${Uri.tryParse(widget.reel.url)?.host ?? '?'}\n${_why.length > 160 ? _why.substring(0, 160) : _why}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]))
        : _dl != null ? Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(value: _dl! > 0 ? _dl : null), const SizedBox(height: 8), Text(_dl! > 0 ? 'تحميل المقطع ${(_dl! * 100).round()}٪' : 'تحميل المقطع…', style: const TextStyle(color: Colors.white70))])
        : const CircularProgressIndicator()),
    ]);
    final pos = ready ? c.value.position : Duration.zero, dur = ready ? c.value.duration : Duration.zero;
    final segStart = Duration(seconds: r.start), segLen = r.len > 0 ? Duration(seconds: r.len) : dur;
    final prog = segLen.inMilliseconds <= 0 ? 0.0 : ((pos - (r.len > 0 ? segStart : Duration.zero)).inMilliseconds / segLen.inMilliseconds).clamp(0.0, 1.0);
    return ValueListenableBuilder<bool>(valueListenable: blurPhotos, builder: (_, blur, _) => GestureDetector(
      onTap: () { if (!ready) return; setState(() { _paused = !_paused; _paused ? c.pause() : c.play(); }); },
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _doubleTap,
      onLongPress: widget.onMenu,
      onHorizontalDragEnd: (d) { if ((d.primaryVelocity ?? 0) < -350) widget.onProfile(p0); },   // سحب لليسار ⇒ ملفها (كما في TikTok)
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        // خلفية ضبابية من صورة العمل خلف المقاطع العرضية (بدل الحواف السوداء)
        if (g.p.isNotEmpty) ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: Opacity(opacity: .45, child: WorkImage(g.p, name: g.s))),
        blur ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: video) : video,
        if (wide && !widget.clean) Align(alignment: const Alignment(0, .32), child: OutlinedButton.icon(onPressed: _openFull,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), backgroundColor: const Color(0x66000000), shape: const StadiumBorder()),
          icon: const Icon(Icons.screen_rotation_rounded, size: 18), label: const Text('ملء الشاشة'))),
        if (_paused) const Center(child: Icon(Icons.play_arrow_rounded, size: 84, color: Colors.white70)),
        for (final h in _hearts) Positioned(left: h.$2.dx - 50, top: h.$2.dy - 90, child: IgnorePointer(child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 800),
          builder: (_, t, _) => Opacity(opacity: t < .7 ? 1 : (1 - t) / .3, child: Transform.translate(offset: Offset(0, -40 * t), child: Transform.rotate(angle: (h.$1.isEven ? -.25 : .25) * (1 - t), child: Transform.scale(scale: t < .2 ? .6 + t * 3 : 1.2, child: const Icon(Icons.favorite_rounded, size: 100, color: C.rose)))))))),
        if (!widget.clean) ...[
          if (_paused && _badge.isNotEmpty) Positioned(top: 104, right: 12, child: SafeArea(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0x990A0810), borderRadius: BorderRadius.circular(99)), child: Text(_badge, style: const TextStyle(color: Colors.white70, fontSize: 11))))),
          // التعليق (أسفل) والأزرار (جانبًا)
          Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(S.s4, 60, S.s3, S.s5),
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xD9000000)])),
            child: SafeArea(top: false, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _caption(r, g)),
              const SizedBox(width: S.s3),
              Column(mainAxisSize: MainAxisSize.min, children: [
                _avatar(p0),
                const SizedBox(height: S.s3),
                _side(widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, 'إعجاب', widget.liked ? C.rose : Colors.white, () => widget.onLike(true)),
                _side(widget.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, 'حفظ', widget.saved ? C.gold : Colors.white, widget.onSave),
                if (r.len > 0) _side(Icons.smart_display_rounded, 'كاملًا', C.gold2, _openFull)
                else if (!g.key.startsWith('stash:') && !g.key.startsWith('emb:')) _side(Icons.sticky_note_2_rounded, 'العمل', Colors.white, () => showWorkSheet(context, ref, g.key)),
                _side(widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, widget.muted ? 'صامت' : 'صوت', Colors.white, widget.onMute),
              ]),
            ])))),
        ],
        // شريط التقدم: رفيع أثناء التشغيل، سميك مع الوقت عند الإيقاف (للتقديم)
        if (ready) Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_paused) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('${_t(pos - (r.len > 0 ? segStart : Duration.zero))} / ${_t(segLen)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]))),
          GestureDetector(
            onHorizontalDragUpdate: (d) { final w = context.size?.width ?? 1; final f = (d.localPosition.dx / w).clamp(0.0, 1.0); final x = Directionality.of(context) == TextDirection.rtl ? 1 - f : f;
              c.seekTo((r.len > 0 ? segStart : Duration.zero) + Duration(milliseconds: (segLen.inMilliseconds * x).round())); if (!_paused) setState(() => _paused = true); c.pause(); },
            child: Container(height: 18, alignment: Alignment.bottomCenter, color: Colors.transparent, child: AnimatedContainer(duration: const Duration(milliseconds: 150), height: _paused ? 6 : 2,
              child: LinearProgressIndicator(value: prog, backgroundColor: Colors.white12, color: _paused ? Colors.white : C.gold, minHeight: _paused ? 6 : 2))),
          ),
        ]))),
      ])));
  }

  Widget _caption(Reel r, WorkGroup g) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Wrap(spacing: 8, children: [for (final p in g.who.take(3)) GestureDetector(onTap: () => widget.onFocus((kind: 'pf', v: p.id, label: p.name)),
      child: Text('@${p.name}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, shadows: [Shadow(blurRadius: 6)])))]),
    const SizedBox(height: 2),
    Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
    if (g.tg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Wrap(spacing: 6, children: [for (final t in g.tg.take(4)) GestureDetector(onTap: () => widget.onFocus((kind: 'tg', v: t, label: '#$t')),
      child: Text('#$t', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)))])),
    const SizedBox(height: 4),
    Text(r.why, style: TextStyle(color: r.explore ? C.rose : C.gold2, fontSize: 12)),
    const SizedBox(height: 4),
    // سطر الاستوديو (مكان «الصوت» في TikTok): الضغط يعرض مقاطعه
    GestureDetector(onTap: g.s.isEmpty ? null : () => widget.onFocus((kind: 'st', v: g.s, label: g.s)), child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.business_rounded, size: 14, color: Colors.white70),
      const SizedBox(width: 4),
      Flexible(child: Text([if (g.s.isNotEmpty) g.s, if (g.y.isNotEmpty) g.y, r.src].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12))),
    ])),
  ]);

  /// صورة الممثلة مع ＋ (إضافة للمفضلة) — مثل زر المتابعة.
  Widget _avatar(Performer p) => SizedBox(width: 52, height: 60, child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
    GestureDetector(onTap: () => widget.onProfile(p), child: Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
      child: ClipOval(child: p.photos.isEmpty ? Container(color: C.surface, alignment: Alignment.center, child: Text(p.name.isEmpty ? '?' : p.name.characters.first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))
        : Photo(p.photos.first, name: p.name, cacheWidth: 144)))),
    if (!widget.fav) Positioned(bottom: 0, child: GestureDetector(onTap: widget.onFollow, child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: C.rose, shape: BoxShape.circle),
      child: const Icon(Icons.add_rounded, size: 16, color: Colors.white)))),
  ]));

  Widget _side(IconData i, String t, Color col, VoidCallback f) => Padding(padding: const EdgeInsets.only(bottom: S.s3), child: GestureDetector(onTap: f, child: Column(children: [
    AnimatedSwitcher(duration: const Duration(milliseconds: 180), transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
      child: Icon(i, key: ValueKey('$i$col'), color: col, size: 32, shadows: const [Shadow(blurRadius: 6)])),
    Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(blurRadius: 6)])),
  ])));
}

/// «سجلّي» / «المحفوظة» / «أعجبتني»: شبكة صور المقاطع، والضغط يعرض المقطع.
class _ReelsLibrary extends ConsumerWidget {
  const _ReelsLibrary({required this.groups, required this.tab});
  final Map<String, WorkGroup> groups; final int tab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sig = ref.watch(reelSigProvider).value ?? const ReelSignals({}, {});
    final lists = [reelHistory(sig), reelSaved(sig), reelLiked(sig)];
    Widget grid(List<String> keys) {
      final gs = [for (final k in keys) ?groups[k]];
      if (gs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(S.s5), child: Text('لا شيء هنا بعد', style: TextStyle(color: C.muted))));
      return GridView.builder(padding: const EdgeInsets.all(2), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 9 / 14, mainAxisSpacing: 2, crossAxisSpacing: 2),
        itemCount: gs.length, itemBuilder: (_, i) => GestureDetector(onTap: () => Navigator.pop(context, gs[i].key), child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black), if (gs[i].p.isNotEmpty) WorkImage(gs[i].p, name: gs[i].s),
          Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(6), color: const Color(0x99000000),
            child: Text(gs[i].who.map((p) => p.name).take(2).join('، '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5)))),
        ])));
    }
    return DefaultTabController(length: 3, initialIndex: tab, child: Scaffold(
      appBar: AppBar(title: const Text('مقاطعي'), bottom: TabBar(tabs: [Tab(text: 'سجلّي (${lists[0].length})'), Tab(text: 'المحفوظة (${lists[1].length})'), Tab(text: 'أعجبتني (${lists[2].length})')])),
      body: TabBarView(children: [for (final l in lists) grid(l)])));
  }
}

/// يفحص رابط مقطع بطلب أول 1 كيلوبايت (نفس شبكات النظام): (يعمل؟، الوصف).
Future<(bool, String)> probeVideoUrl(String url) async {
  try {
    final r = await sourceClient.get(Uri.parse(url), headers: {'Range': 'bytes=0-1023'}).timeout(const Duration(seconds: 15));
    final ct = r.headers['content-type'] ?? '?';
    if (r.statusCode == 403 || r.statusCode == 401) return (false, 'الخادم يرفض (${r.statusCode}) — رابط منتهٍ أو يمنع التشغيل خارج موقعه');
    if (r.statusCode == 404 || r.statusCode == 410) return (false, 'غير موجود (${r.statusCode}) — حُذف المقطع');
    if (r.statusCode >= 400) return (false, 'خطأ من الخادم (${r.statusCode})');
    final b = r.bodyBytes;
    final mp4 = b.length > 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70;   // ftyp
    final webm = b.length > 4 && b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3;
    final hls = String.fromCharCodes(b.take(7)) == '#EXTM3U';
    if (webm) return (false, 'صيغة WebM — لا يشغّلها الآيفون');
    if (ct.contains('text/html')) return (false, 'الرابط صفحة ويب وليس ملف فيديو');
    if (mp4 || hls || ct.startsWith('video/') || ct.contains('mpegurl')) return (true, 'يعمل (${hls ? 'HLS' : mp4 ? 'MP4' : ct})');
    return (true, 'قد يعمل — نوع غير معتاد ($ct) يُجرَّب في المشغّل');
  } on SourceError catch (e) { return (false, e.msg); }
  catch (e) {
    final s = '$e';
    if (looksBlocked(s)) return (false, 'محجوب على شبكتك (الاتصال يُقطع أثناء التشفير)');
    if (s.contains('Timeout')) return (false, 'لا رد (مهلة)');
    return (false, s.length > 90 ? s.substring(0, 90) : s);
  }
}
