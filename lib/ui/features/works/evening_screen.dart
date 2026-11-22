import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/insights.dart';
import '../../../domain/sanitize.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'works_screen.dart';

/// «سهرة»: اختر مزاجًا ووقتًا ⇒ ثلاثة أعمال لم تشاهدها (من ممثلات مختلفات) بسبب كل واحد. «شاهدته» يسجّلها في يومياتك.
class EveningScreen extends ConsumerStatefulWidget {
  const EveningScreen({super.key});
  @override ConsumerState<EveningScreen> createState() => _EveningState();
}

class _EveningState extends ConsumerState<EveningScreen> {
  EveningMood mood = EveningMood.taste; int minutes = 0; int seed = DateTime.now().day;
  final _done = <String>{};

  Future<void> _watched(WorkGroup g) async {
    final changed = applyToGroup(g, (w) { w['w'] = 1; w['wd'] = todayStr(); w.remove('q'); });
    await ref.read(libraryProvider.notifier).upsertMany(changed);
    setState(() => _done.add(g.key));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سُجّلت في يومياتك ✓ — قيّمها من تفاصيلها ليتعلم ذوقك')));
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(worksProvider);
    final picks = eveningPicks(all, ref.watch(workTasteProvider), mood: mood, maxMinutes: minutes, seed: seed);
    return Scaffold(
      appBar: AppBar(title: const Text('🌙 سهرة')),
      body: ListView(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, 40), children: [
        const Text('ماذا تحب الليلة؟', style: TextStyle(color: C.muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final e in eveningMoods.entries) ChoiceChip(label: Text(e.value), selected: mood == e.key, onSelected: (_) => setState(() { mood = e.key; _done.clear(); }))]),
        const SizedBox(height: S.s3),
        const Text('كم معك من وقت؟', style: TextStyle(color: C.muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [for (final m in const [0, 30, 60, 90]) ChoiceChip(label: Text(m == 0 ? 'أي مدة' : 'حتى $m د'), selected: minutes == m, onSelected: (_) => setState(() => minutes = m))]),
        if (minutes > 0) const Padding(padding: EdgeInsets.only(top: 4), child: Text('تُستبعد الأعمال بلا مدة معروفة.', style: TextStyle(color: C.muted, fontSize: 11.5))),
        const SizedBox(height: S.s4),
        if (picks.isEmpty) const EmptyState(title: 'لا شيء يناسب الآن', body: 'جرّب مزاجًا آخر أو مدة أطول — أو حدّث أعمال ممثلاتك لتظهر أعمال جديدة.')
        else for (final x in picks) Padding(padding: const EdgeInsets.only(bottom: S.s3), child: Container(
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: _done.contains(x.g.key) ? C.ok : C.line)), clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(onTap: () => showWorkSheet(context, ref, x.g.key), child: AspectRatio(aspectRatio: 16 / 9, child: WorkImage(x.g.p, name: x.g.s.isNotEmpty ? x.g.s : x.g.t))),
            Padding(padding: const EdgeInsets.all(S.s3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text([x.g.who.map((p) => p.name).take(2).join('، '), if (x.g.s.isNotEmpty) x.g.s, if (x.g.du > 0) '${x.g.du} د'].join(' · '), style: const TextStyle(color: C.muted)),
              if (x.why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(x.why.first, style: const TextStyle(color: C.gold2, fontSize: 12.5))),
              const SizedBox(height: S.s2),
              Row(children: [
                Expanded(child: _done.contains(x.g.key)
                  ? const FilledButton(onPressed: null, child: Text('شوهد ✓'))
                  : FilledButton.icon(onPressed: () => _watched(x.g), icon: const Icon(Icons.check_rounded), label: const Text('شاهدته'))),
                const SizedBox(width: S.s2),
                OutlinedButton(onPressed: () => showWorkSheet(context, ref, x.g.key), child: const Text('التفاصيل')),
              ]),
            ])),
          ]))),
        if (picks.isNotEmpty) OutlinedButton.icon(onPressed: () => setState(() { seed++; _done.clear(); }), icon: const Icon(Icons.casino_rounded), label: const Text('غيّرها')),
      ]),
    );
  }
}
