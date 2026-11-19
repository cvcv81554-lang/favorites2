import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../domain/performer.dart';
import '../domain/sanitize.dart';
import 'keys.dart';
import 'platform/db_factory.dart';
import 'sources.dart';
import 'studio_repo.dart';

/// التحديث في الخلفية والإشعارات — يعمل والتطبيق مغلق:
///  - أندرويد: WorkManager (كل ~12 ساعة حسب الشروط: شبكة، بطارية غير منخفضة).
///  - iOS: BGAppRefresh — **النظام يقرر التوقيت** حسب استخدامك والبطارية؛ نحو 30 ثانية لكل تشغيل؛ لا يعمل إن أُغلق التطبيق قسرًا.
///
/// تصميم آمن للبيانات (لا كتابة متزامنة على قاعدة البيانات من عزلتين):
///  1) التطبيق يكتب `bg_input.json`: الإعدادات + ممثلات المكتبة **البالغات فقط** (بوابة +18 هنا، قبل أي طلب) مع ما هو معروف من أعمالهن وصور الاستديو.
///  2) مهمة الخلفية تقرأه، تسأل StashDB الرسمي لدفعة صغيرة (دوّارة)، وتكتب النتائج في `bg_out_<وقت>.json` — لا تفتح قاعدة البيانات أبدًا.
///  3) التطبيق عند فتحه/عودته يدمج النتائج في **السجلات الحالية** (لا يضيع أي تعديل) ثم يحذف الملفات.
/// نص الإشعار عام بلا أسماء ولا صور (يظهر على شاشة القفل).
const bgTaskId = 'com.favlib.favorites2.check';
const _perRun = 15;   // دفعة صغيرة تكفي ضمن ~30 ثانية في iOS

class BgSettings {
  final bool on, works, photos, wifiOnly; final int hours;
  const BgSettings({this.on = false, this.works = true, this.photos = true, this.wifiOnly = true, this.hours = 12});
  Map<String, dynamic> toJson() => {'on': on, 'works': works, 'photos': photos, 'wifi': wifiOnly, 'h': hours};
  factory BgSettings.fromJson(Map? j) => BgSettings(on: j?['on'] == true, works: j?['works'] != false, photos: j?['photos'] != false, wifiOnly: j?['wifi'] != false, hours: (j?['h'] as num?)?.toInt() ?? 12);
  BgSettings copy({bool? on, bool? works, bool? photos, bool? wifiOnly, int? hours}) => BgSettings(on: on ?? this.on, works: works ?? this.works, photos: photos ?? this.photos, wifiOnly: wifiOnly ?? this.wifiOnly, hours: hours ?? this.hours);
}

final _notif = FlutterLocalNotificationsPlugin();
bool _notifReady = false;
Future<void> _initNotif() async {
  if (_notifReady || kIsWeb) return;
  await _notif.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)));
  _notifReady = true;
}

Future<bool> requestNotifPermission() async {
  if (kIsWeb) return false;
  await _initNotif();
  final a = await _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  final i = await _notif.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
  return (a ?? i) ?? false;
}

/// مدخلات مهمة الخلفية (من التطبيق). البوابة: البالغات فقط.
Map<String, dynamic> buildBgInput(BgSettings s, List<Performer> lib, Set<String> studioIds) => {
  'v': 1, 'settings': s.toJson(),
  'ids': [for (final p in lib) if (!p.isMinor && p.stashId.isNotEmpty) {'id': p.id, 's': p.stashId, 'k': [for (final w in p.works) wKeyOf(w)]}],
  'img': studioIds.toList(),
};

Future<void> writeBgInput(BgSettings s, List<Performer> lib, Set<String> studioIds) async { if (!kIsWeb) await bgWrite('bg_input.json', jsonEncode(buildBgInput(s, lib, studioIds))); }

/// نتيجة جلب: أعمال جديدة لكل ممثلة + صور جديدة (لم تُدمج بعد).
class FetchResult {
  final Map<String, List<Map<String, dynamic>>> works; final List<StudioImg> images; final List<String> errors; final int nextCursor;
  const FetchResult(this.works, this.images, this.errors, this.nextCursor);
  int get workCount => works.values.fold(0, (s, l) => s + l.length);
  Map<String, dynamic> toJson() => {'works': works, 'images': [for (final x in images) x.toJson()], 'err': errors, 'at': DateTime.now().millisecondsSinceEpoch};
}

/// الجلب فقط (بلا أي كتابة على القاعدة) — من مدخلات bg_input. [limit]: دفعة دوّارة.
Future<FetchResult> fetchUpdates(Map<String, dynamic> input, {int cursor = 0, int? limit}) async {
  final s = BgSettings.fromJson(input['settings'] as Map?);
  final ids = [for (final e in (input['ids'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
  final known = {...((input['img'] as List?) ?? const []).cast<String>()};
  final works = <String, List<Map<String, dynamic>>>{}; final imgs = <StudioImg>[]; final errs = <String>[];
  if (ids.isEmpty || !await ApiKeys.has(ApiKeys.stash)) return FetchResult(works, imgs, ['لا ممثلات مرتبطة أو لا مفتاح StashDB'], 0);
  final n = limit ?? ids.length; final now = DateTime.now().millisecondsSinceEpoch;
  var i = 0;
  for (; i < n && i < ids.length; i++) {
    final e = ids[(cursor + i) % ids.length];
    try {
      if (s.works) {
        final keys = {...((e['k'] as List?) ?? const []).cast<String>()};
        final fresh = [for (final w in await StashDB.scenes('${e['s']}', maxPages: 1)) if (!keys.contains(wKeyOf(w))) w];
        if (fresh.isNotEmpty) works['${e['id']}'] = fresh;
      }
      if (s.photos) {
        final d = await StashDB.q(r'query($id:ID!){findPerformer(id:$id){images{url width height}}}', {'id': e['s']});
        for (final m in ((d['findPerformer'] as Map?)?['images'] as List? ?? const [])) {
          if (m is! Map || !safeHttps(m['url'])) continue; final id = StudioRepo.idOf('${m['url']}'); if (known.contains(id)) continue; known.add(id);
          imgs.add(StudioImg(id: id, pid: '${e['id']}', url: '${m['url']}', src: 'stash', kind: 'portrait', w: (m['width'] as num?)?.toInt() ?? 0, h: (m['height'] as num?)?.toInt() ?? 0, found: now));
        }
        for (final w in works['${e['id']}'] ?? const <Map<String, dynamic>>[]) {   // صور المشاهد الجديدة أيضًا
          final u = '${w['p'] ?? ''}'; if (!safeHttps(u)) continue; final id = StudioRepo.idOf(u); if (known.contains(id)) continue; known.add(id);
          imgs.add(StudioImg(id: id, pid: '${e['id']}', url: u, src: 'scene', kind: 'still', found: now));
        }
      }
    } on SourceError catch (x) { if (x.status == 401 || x.status == 403) { errs.add(x.msg); break; } }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return FetchResult(works, imgs, errs, ids.isEmpty ? 0 : (cursor + i) % ids.length);
}

Future<void> _notify(int works, int photos) async {
  if (kIsWeb || (works == 0 && photos == 0)) return;
  await _initNotif();
  final parts = [if (works > 0) '$works عمل جديد', if (photos > 0) '$photos صورة جديدة'];
  await _notif.show(id: 4201, title: 'المفضلة', body: 'تحديثات جديدة في مكتبتك · ${parts.join(' · ')}',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails('updates', 'تحديثات المكتبة', channelDescription: 'أعمال وصور جديدة (بلا أسماء)', importance: Importance.defaultImportance, visibility: NotificationVisibility.private),
      iOS: DarwinNotificationDetails()));
}

/// مهمة الخلفية: تقرأ المدخلات، تجلب دفعة، وتكتب النتائج ملفًا. لا تفتح أي قاعدة بيانات.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final raw = await bgRead('bg_input.json'); if (raw == null) return true;
      final inp = jsonDecode(raw) as Map<String, dynamic>;
      if (!BgSettings.fromJson(inp['settings'] as Map?).on) return true;
      final st = jsonDecode(await bgRead('bg_state.json') ?? '{}') as Map;
      final r = await fetchUpdates(inp, cursor: (st['cursor'] as num?)?.toInt() ?? 0, limit: _perRun);
      await bgWrite('bg_state.json', jsonEncode({'cursor': r.nextCursor, 'at': DateTime.now().millisecondsSinceEpoch, 'works': r.workCount, 'photos': r.images.length, 'err': r.errors.join(' · ')}));
      if (r.workCount > 0 || r.images.isNotEmpty) {
        await bgWrite('bg_out_${DateTime.now().millisecondsSinceEpoch}.json', jsonEncode(r.toJson()));
        await _notify(r.workCount, r.images.length);
      }
      return true;
    } catch (_) { return false; }   // يعيد النظام المحاولة لاحقًا
  });
}

Future<void> initBackground() async { if (!kIsWeb) await Workmanager().initialize(callbackDispatcher); }

/// تفعيل/إيقاف الجدولة حسب الإعدادات.
Future<void> applyBackground(BgSettings s) async {
  if (kIsWeb) return;
  if (!s.on) { await Workmanager().cancelByUniqueName(bgTaskId); return; }
  await Workmanager().registerPeriodicTask(bgTaskId, bgTaskId, frequency: Duration(hours: s.hours), initialDelay: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: s.wifiOnly ? NetworkType.unmetered : NetworkType.connected, requiresBatteryNotLow: true, requiresStorageNotLow: true));
}

/// ملفات نتائج تنتظر الدمج (من مهمة الخلفية).
Future<List<FetchResult>> takePendingResults() async {
  final out = <FetchResult>[];
  for (final name in await bgList('bg_out_')) {
    try {
      final j = jsonDecode(await bgRead(name) ?? '{}') as Map;
      out.add(FetchResult(
        {for (final e in ((j['works'] as Map?) ?? const {}).entries) '${e.key}': [for (final w in e.value as List) Map<String, dynamic>.from(w as Map)]},
        [for (final x in (j['images'] as List? ?? const [])) StudioImg.fromJson(Map<String, dynamic>.from(x as Map))], const [], 0));
    } catch (_) {}
    await bgRemove(name);
  }
  return out;
}

Future<Map<String, dynamic>?> lastBgState() async { final r = await bgRead('bg_state.json'); return r == null ? null : Map<String, dynamic>.from(jsonDecode(r) as Map); }
