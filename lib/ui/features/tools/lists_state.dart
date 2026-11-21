import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/state.dart';

/// قوائم الممثلات (نفس صيغة القديم: {id, name} في kv «lists»، والعضوية في حقل lists بكل سجل).
class NamedList { final String id, name; const NamedList(this.id, this.name); Map<String, dynamic> toJson() => {'id': id, 'name': name}; }

class ListsN extends AsyncNotifier<List<NamedList>> {
  @override
  Future<List<NamedList>> build() async {
    final repo = await ref.watch(repoProvider.future);
    return [for (final e in (await repo.kvGet('lists') as List? ?? const [])) if (e is Map) NamedList('${e['id']}', '${e['name']}')];
  }
  Future<void> _save(List<NamedList> l) async { await (await ref.read(repoProvider.future)).kvSet('lists', [for (final x in l) x.toJson()]); state = AsyncData(l); }
  Future<NamedList> add(String name) async { final x = NamedList(const Uuid().v4(), name.trim()); await _save([...?state.value, x]); return x; }
  Future<void> rename(String id, String name) => _save([for (final x in state.value ?? const <NamedList>[]) x.id == id ? NamedList(id, name.trim()) : x]);
  /// حذف قائمة: تُزال من القوائم ومن عضوية الممثلات (لا تُحذف أي ممثلة).
  Future<void> remove(String id) async {
    await _save([for (final x in state.value ?? const <NamedList>[]) if (x.id != id) x]);
    final lib = ref.read(libraryProvider.notifier);
    final touched = [for (final p in lib.items) if (p.lists.contains(id)) p.copyWith({'lists': p.lists.where((l) => l != id).toList()})];
    if (touched.isNotEmpty) await lib.upsertMany(touched);
  }
}
final listsProvider = AsyncNotifierProvider<ListsN, List<NamedList>>(ListsN.new);

/// قائمة الأمنيات: أسماء تريد إضافتها لاحقًا ({n, t}، حتى 500). تُزال تلقائيًا عند إضافة ممثلة بنفس الاسم.
class WishN extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final repo = await ref.watch(repoProvider.future);
    final lib = ref.watch(libraryProvider).value ?? const [];
    final names = {for (final p in lib) p.name.trim().toLowerCase()};
    return [for (final e in (await repo.kvGet('wish') as List? ?? const [])) if (e is Map && !names.contains('${e['n']}'.trim().toLowerCase())) Map<String, dynamic>.from(e)];
  }
  Future<void> _save(List<Map<String, dynamic>> l) async { await (await ref.read(repoProvider.future)).kvSet('wish', l.take(500).toList()); state = AsyncData(l); }
  Future<void> add(String n) async { final t = n.trim(); if (t.isEmpty || (state.value ?? const []).any((e) => '${e['n']}'.toLowerCase() == t.toLowerCase())) return; await _save([{'n': t, 't': DateTime.now().millisecondsSinceEpoch}, ...?state.value]); }
  Future<void> remove(String n) => _save([for (final e in state.value ?? const <Map<String, dynamic>>[]) if (e['n'] != n) e]);
}
final wishProvider = AsyncNotifierProvider<WishN, List<Map<String, dynamic>>>(WishN.new);

/// قوائم الأعمال (wlists).
class WListsN extends AsyncNotifier<List<NamedList>> {
  @override
  Future<List<NamedList>> build() async {
    final repo = await ref.watch(repoProvider.future);
    return [for (final e in (await repo.kvGet('wlists') as List? ?? const [])) if (e is Map) NamedList('${e['id']}', '${e['name']}')];
  }
  Future<NamedList> add(String name) async {
    final x = NamedList(const Uuid().v4(), name.trim()); final l = [...?state.value, x];
    await (await ref.read(repoProvider.future)).kvSet('wlists', [for (final e in l) e.toJson()]); state = AsyncData(l); return x;
  }
}
final wlistsProvider = AsyncNotifierProvider<WListsN, List<NamedList>>(WListsN.new);
