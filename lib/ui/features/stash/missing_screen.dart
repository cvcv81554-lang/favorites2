import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/sources.dart' show SourceError;
import '../../../data/stash_server.dart';
import '../../../domain/performer.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// «الأعمال الناقصة»: أعمال ممثلاتك في StashDB وThePornDB التي لا تملكها في خادم Stash — معلومات فقط (لا تنزيل).
class MissingScreen extends ConsumerStatefulWidget {
  const MissingScreen({super.key, this.performerId});
  final String? performerId;   // فتحها على ممثلة واحدة
  @override ConsumerState<MissingScreen> createState() => _MissingState();
}

typedef _Row = ({Performer p, List<Map<String, dynamic>> missing, int have, int total});

class _MissingState extends ConsumerState<MissingScreen> {
  List<_Row>? _rows; String _msg = '', _progress = ''; bool _favs = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _rows = null; _msg = ''; });
    if (!await StashServer.configured()) { setState(() { _rows = const []; _msg = 'أضف عنوان خادم Stash من «الشبكة والمقاطع» أولًا.'; }); return; }
    try {
      final repo = await ref.read(repoProvider.future);
      final map = Map<String, dynamic>.from(await repo.kvGet('stash_local_map') as Map? ?? {});
      final lib = ref.read(libraryProvider).value ?? const <Performer>[];
      final want = lib.where((p) => !p.isMinor && p.works.isNotEmpty && (widget.performerId != null ? p.id == widget.performerId : (!_favs || p.fav || p.rating >= 4))).toList();
      var i = 0;
      for (final p in want) {   // ربط من لم تُربط بعد بخادمك (بمعرّف StashDB أو الاسم)
        i++;
        if (map.containsKey(p.id)) continue;
        if (mounted) setState(() => _progress = 'ربط ${p.name} بخادمك ($i/${want.length})…');
        map[p.id] = await StashServer.localPerformer(p) ?? '';
      }
      await repo.kvSet('stash_local_map', map);
      if (mounted) setState(() => _progress = 'مقارنة أعمالهن بما في خادمك…');
      final ids = [for (final p in want) if ('${map[p.id] ?? ''}'.isNotEmpty) '${map[p.id]}'];
      final owned = await StashServer.owned(ids);
      final rows = <_Row>[];
      for (final p in want) {
        final local = '${map[p.id] ?? ''}';
        final m = missingWorks(p.works, local.isEmpty ? const [] : owned[local] ?? const []);
        rows.add((p: p, missing: m.missing, have: local.isEmpty ? -1 : m.have, total: m.total));
      }
      rows.sort((a, b) => b.missing.length.compareTo(a.missing.length));
      if (mounted) setState(() { _rows = rows; _progress = ''; });
    } on SourceError catch (e) { if (mounted) setState(() { _rows = const []; _msg = e.msg; _progress = ''; }); }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final totalMissing = rows?.fold<int>(0, (a, r) => a + (r.have < 0 ? 0 : r.missing.length)) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('الأعمال الناقصة'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: rows == null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: S.s3), Text(_progress, style: const TextStyle(color: C.muted))]))
        : ListView(padding: const EdgeInsets.all(S.s3), children: [
          if (_msg.isNotEmpty) Text(_msg, style: const TextStyle(color: C.gold)),
          if (widget.performerId == null) Row(children: [
            Expanded(child: Text(rows.isEmpty ? '' : 'ينقصك $totalMissing عملًا لـ${rows.length} ممثلة', style: const TextStyle(fontWeight: FontWeight.w700))),
            FilterChip(label: const Text('المفضلات فقط'), selected: _favs, onSelected: (v) { setState(() => _favs = v); _load(); }),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('مقارنة أعمالها في StashDB وThePornDB بما في خادمك (بالمعرّف، وإلا العنوان والاستوديو والتاريخ). القادمة لا تُحسب.', style: TextStyle(color: C.muted, fontSize: 12))),
          for (final r in rows) _tile(r, expanded: widget.performerId != null),
        ]),
    );
  }

  Widget _tile(_Row r, {bool expanded = false}) {
    final unlinked = r.have < 0;
    final header = Row(children: [
      CircleAvatar(radius: 22, backgroundColor: C.surface, child: r.p.photos.isEmpty ? Text(r.p.name.characters.first) : ClipOval(child: SizedBox(width: 44, height: 44, child: Photo(r.p.photos.first, name: r.p.name, cacheWidth: 132)))),
      const SizedBox(width: S.s3),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (unlinked) const Text('غير موجودة في خادمك', style: TextStyle(color: C.muted, fontSize: 12))
        else ...[
          LinearProgressIndicator(value: r.total == 0 ? 0 : r.have / r.total, minHeight: 5, borderRadius: BorderRadius.circular(9)),
          const SizedBox(height: 2),
          Text('لديك ${r.have} من ${r.total}${r.missing.isEmpty ? ' ✓ مكتملة' : ' · ينقص ${r.missing.length}'}', style: const TextStyle(color: C.muted, fontSize: 12)),
        ],
      ])),
    ]);
    final list = [for (final w in r.missing) ListTile(contentPadding: EdgeInsets.zero, dense: true,
      leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 88, height: 50, child: '${w['p'] ?? ''}'.isEmpty ? const ColoredBox(color: C.surface) : WorkImage('${w['p']}', name: '${w['s'] ?? ''}'))),
      title: Text('${w['t'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([if ('${w['s'] ?? ''}'.isNotEmpty) '${w['s']}', if ('${w['d'] ?? ''}'.isNotEmpty) '${w['d']}'].join(' · ')),
      trailing: '${w['u'] ?? ''}'.startsWith('https://') ? IconButton(tooltip: 'صفحته في المصدر', onPressed: () => launchUrl(Uri.parse('${w['u']}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new_rounded, size: 20)) : null)];
    return Card(margin: const EdgeInsets.only(bottom: S.s2), child: unlinked || r.missing.isEmpty ? Padding(padding: const EdgeInsets.all(S.s3), child: header)
      : ExpansionTile(initiallyExpanded: expanded, tilePadding: const EdgeInsets.all(S.s3), title: header, childrenPadding: const EdgeInsets.symmetric(horizontal: S.s3), children: list));
  }
}
