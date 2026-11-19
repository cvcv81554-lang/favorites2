import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/age_gate.dart';
import '../../../domain/performer.dart';
import '../../../domain/profile.dart';
import '../../core/state.dart';
import '../../core/theme.dart';

/// إضافة/تعديل ممثلة. بوابة +18 قبل الحفظ: تاريخ يقول أقل من 18 أو غير مفهوم ⇒ رفض.
Future<void> showEditSheet(BuildContext context, WidgetRef ref, {Performer? p}) => showModalBottomSheet(
  context: context, isScrollControlled: true, useSafeArea: true,
  builder: (sc) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sc).bottom), child: _EditForm(p: p)),
);

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({this.p});
  final Performer? p;
  @override ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final _name = TextEditingController(text: widget.p?.name);
  late final _aliases = TextEditingController(text: widget.p?.aliases);
  late final _birth = TextEditingController(text: widget.p?.birth);
  late final _country = TextEditingController(text: widget.p?.country);
  late final _tags = TextEditingController(text: widget.p?.tags.join('، '));
  late final _notes = TextEditingController(text: widget.p?.notes);
  late final _photo = TextEditingController();
  late final _stash = TextEditingController(text: widget.p?.stashId);
  late final _pdb = TextEditingController(text: widget.p?.pdbId);
  late final _height = TextEditingController(text: widget.p?.raw['height']?.toString() ?? '');
  late double _rating = widget.p?.rating ?? 0;
  late bool _fav = widget.p?.fav ?? false;
  late final Map<String, double> _crit = widget.p == null ? {} : criteriaOf(widget.p!);
  late final Map<String, double> _body = widget.p == null ? {} : bodyOf(widget.p!);
  late final List<Map<String, String>> _acc = widget.p == null ? [] : accountsOf(widget.p!);
  String? _err;

  @override
  void dispose() { for (final c in [_name, _aliases, _birth, _country, _tags, _notes, _photo, _stash, _pdb, _height]) { c.dispose(); } super.dispose(); }

  /// التقييم الظاهر: من المعايير إن وُجدت (قاعدة القديم)، وإلا اليدوي.
  double get _effRating => _crit.isEmpty && _body.isEmpty ? _rating : applyRatings(_crit, _body).rating;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) { setState(() => _err = 'الاسم مطلوب'); return; }
    final b = _birth.text.trim();
    if (b.isNotEmpty) {
      final a = sdAge(b);
      if (a.invalid) { setState(() => _err = 'تاريخ الميلاد غير صالح (الصيغة: 1995-04-20)'); return; }
      if ((a.age ?? 0) < 18) { setState(() => _err = 'لا يُقبل أي سجل عمره أقل من 18 سنة'); return; }
    }
    final tags = _tags.text.split(RegExp(r'[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    final photo = _photo.text.trim();
    final base = widget.p?.raw ?? {'id': const Uuid().v4(), 'added': DateTime.now().millisecondsSinceEpoch, 'works': [], 'photos': [], 'lists': [], 'source': 'إدخال يدوي'};
    final photos = [...(base['photos'] as List? ?? const []).cast<String>()];
    if (photo.startsWith('https://') && !photos.contains(photo)) photos.insert(0, photo);
    final r = applyRatings(_crit, _body);
    final h = int.tryParse(_height.text.trim());
    final p = Performer({...base, 'name': name, 'aliases': _aliases.text.trim(), 'birth': b, 'country': _country.text.trim(), 'tags': tags, 'notes': _notes.text.trim(),
      'rating': _crit.isEmpty && _body.isEmpty ? _rating : r.rating, 'criteria': r.criteria.isEmpty ? null : r.criteria, 'bodyD': _body.isEmpty ? null : _body,
      'accounts': [for (final a in _acc) if (a['v']!.trim().isNotEmpty) a], 'stashId': _stash.text.trim(), 'pdbId': _pdb.text.trim(), if (h != null && h > 100 && h < 230) 'height': h,
      'fav': _fav, 'photos': photos, 'updated': DateTime.now().millisecondsSinceEpoch});
    final ok = await ref.read(libraryProvider.notifier).upsert(p);
    if (!mounted) return;
    if (!ok) { setState(() => _err = 'رُفض الحفظ: العمر أقل من 18'); return; }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.p == null ? 'أُضيفت $name' : 'حُفظت التعديلات')));
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration d(String l, {String? h}) => InputDecoration(labelText: l, hintText: h);
    return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s5), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.p == null ? 'إضافة ممثلة' : 'تعديل ${widget.p!.name}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: S.s4),
      TextField(controller: _name, decoration: d('الاسم'), textInputAction: TextInputAction.next, autofocus: widget.p == null),
      const SizedBox(height: S.s3),
      TextField(controller: _aliases, decoration: d('أسماء أخرى', h: 'مفصولة بفواصل')),
      const SizedBox(height: S.s3),
      Row(children: [
        Expanded(child: TextField(controller: _birth, decoration: d('تاريخ الميلاد', h: '1995-04-20'), keyboardType: TextInputType.datetime)),
        const SizedBox(width: S.s3),
        Expanded(child: TextField(controller: _country, decoration: d('البلد'))),
      ]),
      const SizedBox(height: S.s3),
      TextField(controller: _tags, decoration: d('الوسوم', h: 'مفصولة بفواصل')),
      const SizedBox(height: S.s3),
      if (widget.p == null) ...[TextField(controller: _photo, decoration: d('رابط صورة (اختياري)', h: 'https://…'), keyboardType: TextInputType.url), const SizedBox(height: S.s3)],
      TextField(controller: _notes, decoration: d('ملاحظات'), maxLines: 3),
      const SizedBox(height: S.s3),
      Row(children: [
        const Text('التقييم'),
        Expanded(child: Slider(value: _effRating, min: 0, max: 5, divisions: 10, label: _effRating.toStringAsFixed(1), onChanged: _crit.isEmpty && _body.isEmpty ? (v) => setState(() => _rating = v) : null)),
        Text(_effRating == 0 ? '—' : _effRating.toStringAsFixed(1), style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700)),
      ]),
      if (_crit.isNotEmpty || _body.isNotEmpty) const Text('التقييم العام يُحسب من المعايير التفصيلية.', style: TextStyle(color: C.muted, fontSize: 12)),
      _section('التقييم التفصيلي', crit, _crit),
      _section('تفاصيل الجسم', bodyD, _body),
      ExpansionTile(tilePadding: EdgeInsets.zero, title: Text('الحسابات (${_acc.length})'), children: [
        for (var i = 0; i < _acc.length; i++) Padding(padding: const EdgeInsets.only(bottom: S.s2), child: Row(children: [
          DropdownButton<String>(value: plat.containsKey(_acc[i]['p']) ? _acc[i]['p'] : 'other', underline: const SizedBox(), items: [for (final e in plat.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))], onChanged: (v) => setState(() => _acc[i]['p'] = v ?? 'other')),
          const SizedBox(width: S.s2),
          Expanded(child: TextFormField(initialValue: _acc[i]['v'], decoration: const InputDecoration(hintText: 'اسم المستخدم أو الرابط'), onChanged: (v) => _acc[i]['v'] = v)),
          IconButton(onPressed: () => setState(() => _acc.removeAt(i)), icon: const Icon(Icons.close_rounded)),
        ])),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: () => setState(() => _acc.add({'p': 'instagram', 'v': ''})), icon: const Icon(Icons.add_rounded), label: const Text('إضافة حساب'))),
      ]),
      ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('المصادر والطول'), children: [
        TextField(controller: _stash, decoration: d('معرّف StashDB')), const SizedBox(height: S.s2),
        TextField(controller: _pdb, decoration: d('معرّف ThePornDB')), const SizedBox(height: S.s2),
        TextField(controller: _height, keyboardType: TextInputType.number, decoration: d('الطول (سم)')), const SizedBox(height: S.s2),
      ]),
      SwitchListTile(value: _fav, onChanged: (v) => setState(() => _fav = v), title: const Text('في المفضلة'), contentPadding: EdgeInsets.zero),
      if (_err != null) Padding(padding: const EdgeInsets.only(bottom: S.s3), child: Text(_err!, style: const TextStyle(color: C.danger))),
      FilledButton(onPressed: _save, child: const Text('حفظ')),
    ]));
  }

  Widget _section(String title, Map<String, String> keys, Map<String, double> vals) => ExpansionTile(tilePadding: EdgeInsets.zero, title: Text('$title${vals.isEmpty ? '' : ' · ${meanOf(vals).toStringAsFixed(1)}'}'), children: [
    for (final e in keys.entries) Row(children: [
      SizedBox(width: 110, child: Text(e.value)),
      Expanded(child: Slider(value: vals[e.key] ?? 0, min: 0, max: 5, divisions: 10, label: (vals[e.key] ?? 0).toStringAsFixed(1), onChanged: (v) => setState(() { if (v == 0) { vals.remove(e.key); } else { vals[e.key] = v; } }))),
      SizedBox(width: 32, child: Text(vals[e.key] == null ? '—' : vals[e.key]!.toStringAsFixed(1), style: const TextStyle(color: C.gold2))),
    ]),
  ]);
}
