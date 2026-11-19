import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../domain/performer.dart';
import 'keys.dart';
import 'library_repo.dart';
import 'sources.dart';
import 'studio_repo.dart';

/// التحديث في الخلفية والإشعارات — يعمل والتطبيق مغلق:
///  - أندرويد: WorkManager (النظام يشغّله كل ~12 ساعة حسب الشروط: شبكة، بطارية غير منخفضة).
///  - iOS: BGAppRefresh — **النظام يقرر التوقيت** حسب استخدامك والبطارية؛ قد يتأخر أو لا يعمل إن أُغلق التطبيق قسرًا.
/// ما يفعله: أعمال جديدة لممثلات مكتبتك (StashDB)، وصور جديدة للاستديو. بوابة +18 قبل أي طلب (البالغات فقط).
/// نص الإشعار عام بلا أسماء ولا صور (يظهر على شاشة القفل).
const bgTaskId = 'com.favlib.favorites2.check';

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

/// نتيجة فحص.
class CheckResult { final int works, photos; final List<String> errors; const CheckResult(this.works, this.photos, this.errors); bool get any => works > 0 || photos > 0; }

/// الفحص نفسه — يُستدعى من مهمة الخلفية ومن زر «افحص الآن».
Future<CheckResult> runCheck({required BgSettings s, bool notify = true}) async {
  final repo = await LibraryRepo.open();
  final lib = await repo.loadAll();                  // البالغات فقط (loadAll يستبعد القاصر)
  final adults = lib.where((p) => !p.isMinor).toList();
  var works = 0, photos = 0; final errs = <String>[];
  final hasStash = await ApiKeys.has(ApiKeys.stash);
  if (s.works && hasStash) {
    final linked = adults.where((p) => p.stashId.isNotEmpty).toList();
    final changed = <Performer>[];
    for (final p in linked) {
      try {
        final m = mergeWorks(p.works, await StashDB.scenes(p.stashId, maxPages: 1));   // أحدث 100 مشهد يكفي للجديد
        if (m.added > 0) { works += m.added; changed.add(p.copyWith({'works': m.list, 'worksAt': DateTime.now().millisecondsSinceEpoch})); }
      } on SourceError catch (e) { if (e.status == 401 || e.status == 403) { errs.add(e.msg); break; } }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (changed.isNotEmpty) await repo.save(changed);
  }
  if (s.photos) {
    try { photos = await (await StudioRepo.open()).discover(await repo.loadAll(), network: hasStash); } catch (e) { errs.add('$e'); }
  }
  await repo.kvSet('bg_last', {'at': DateTime.now().millisecondsSinceEpoch, 'works': works, 'photos': photos, 'err': errs.join(' · ')});
  if (notify && (works > 0 || photos > 0) && !kIsWeb) {
    await _initNotif();
    final parts = [if (works > 0) '$works عمل جديد', if (photos > 0) '$photos صورة جديدة'];
    await _notif.show(id: 4201, title: 'المفضلة', body: 'تحديثات جديدة في مكتبتك · ${parts.join(' · ')}',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('updates', 'تحديثات المكتبة', channelDescription: 'أعمال وصور جديدة (بلا أسماء)', importance: Importance.defaultImportance, visibility: NotificationVisibility.private),
        iOS: DarwinNotificationDetails()));
  }
  return CheckResult(works, photos, errs);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final repo = await LibraryRepo.open();
      final s = BgSettings.fromJson(await repo.kvGet('bg') as Map?);
      if (!s.on) return true;
      await runCheck(s: s);
      return true;
    } catch (_) { return false; }   // يعيد النظام المحاولة لاحقًا
  });
}

Future<void> initBackground() async {
  if (kIsWeb) return;
  await Workmanager().initialize(callbackDispatcher);
}

/// تفعيل/إيقاف الجدولة حسب الإعدادات.
Future<void> applyBackground(BgSettings s) async {
  if (kIsWeb) return;
  if (!s.on) { await Workmanager().cancelByUniqueName(bgTaskId); return; }
  await Workmanager().registerPeriodicTask(bgTaskId, bgTaskId, frequency: Duration(hours: s.hours), initialDelay: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: s.wifiOnly ? NetworkType.unmetered : NetworkType.connected, requiresBatteryNotLow: true, requiresStorageNotLow: true));
}
