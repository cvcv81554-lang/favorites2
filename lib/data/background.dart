import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../domain/performer.dart';
import '../domain/sanitize.dart';
import 'keys.dart';
import 'platform/db_factory.dart';
import 'sources.dart';
import 'studio_repo.dart';
import '../domain/age_gate.dart';
import '../domain/taste.dart' show profileFromJson, featuresOf, similarity;
import '../domain/works.dart' show sameWork;

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
  /// [rem]: تذكير بإصدارات المفضلات (مجدول على الجهاز). [tasteNew]: ممثلة جديدة قريبة جدًا من ذوقك.
  final bool on, works, photos, wifiOnly, rem, tasteNew; final int hours;
  const BgSettings({this.on = false, this.works = true, this.photos = true, this.wifiOnly = true, this.hours = 12, this.rem = true, this.tasteNew = true});
  Map<String, dynamic> toJson() => {'on': on, 'works': works, 'photos': photos, 'wifi': wifiOnly, 'h': hours, 'rem': rem, 'tn': tasteNew};
  factory BgSettings.fromJson(Map? j) => BgSettings(on: j?['on'] == true, works: j?['works'] != false, photos: j?['photos'] != false, wifiOnly: j?['wifi'] != false, hours: (j?['h'] as num?)?.toInt() ?? 12,
    rem: j?['rem'] != false, tasteNew: j?['tn'] != false);
  BgSettings copy({bool? on, bool? works, bool? photos, bool? wifiOnly, int? hours, bool? rem, bool? tasteNew}) => BgSettings(on: on ?? this.on, works: works ?? this.works, photos: photos ?? this.photos, wifiOnly: wifiOnly ?? this.wifiOnly, hours: hours ?? this.hours, rem: rem ?? this.rem, tasteNew: tasteNew ?? this.tasteNew);
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
Map<String, dynamic> buildBgInput(BgSettings s, List<Performer> lib, Set<String> studioIds, {Map<String, dynamic>? taste}) => {
  'taste': ?taste,   // {prof, fb, hidden} لكشف «ممثلة جديدة قريبة من ذوقك»
  'libS': [for (final p in lib) ...p.stashIds], 'libN': [for (final p in lib) norm(p.name)],
  'v': 1, 'settings': s.toJson(),
  'ids': [for (final p in lib) if (!p.isMinor && (p.stashId.isNotEmpty || p.pdbId.isNotEmpty)) {'id': p.id, 's': p.stashId, 't': p.pdbId, 'ss': p.stashIds, 'ts': p.pdbIds, 'k': [for (final w in p.works) wKeyOf(w)],
    'w': [for (final w in p.works) {for (final k in const ['t', 's', 'd', 'is', 'ip']) if ('${w[k] ?? ''}'.isNotEmpty) k: w[k]}]}],
  'img': studioIds.toList(),
};

Future<void> writeBgInput(BgSettings s, List<Performer> lib, Set<String> studioIds, {Map<String, dynamic>? taste}) async { if (!kIsWeb) await bgWrite('bg_input.json', jsonEncode(buildBgInput(s, lib, studioIds, taste: taste))); }

/// نتيجة جلب: أعمال جديدة لكل ممثلة + صور جديدة (لم تُدمج بعد).
class FetchResult {
  final Map<String, List<Map<String, dynamic>>> works; final List<StudioImg> images; final List<String> errors; final int nextCursor;
  /// مرشحات جديدة قريبة جدًا من ذوقك (بصيغة TasteRec JSON).
  final List<Map<String, dynamic>> recs;
  const FetchResult(this.works, this.images, this.errors, this.nextCursor, [this.recs = const []]);
  int get workCount => works.values.fold(0, (s, l) => s + l.length);
  Map<String, dynamic> toJson() => {'works': works, 'images': [for (final x in images) x.toJson()], 'err': errors, 'recs': recs, 'at': DateTime.now().millisecondsSinceEpoch};
}

/// الجلب فقط (بلا أي كتابة على القاعدة) — من مدخلات bg_input. [limit]: دفعة دوّارة.
Future<FetchResult> fetchUpdates(Map<String, dynamic> input, {int cursor = 0, int? limit}) async {
  final s = BgSettings.fromJson(input['settings'] as Map?);
  final ids = [for (final e in (input['ids'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
  final known = {...((input['img'] as List?) ?? const []).cast<String>()};
  final works = <String, List<Map<String, dynamic>>>{}; final imgs = <StudioImg>[]; final errs = <String>[];
  final hasS = await ApiKeys.has(ApiKeys.stash), hasT = await ApiKeys.has(ApiKeys.tpdb);
  if (ids.isEmpty || (!hasS && !hasT)) return FetchResult(works, imgs, ['لا ممثلات مرتبطة أو لا مفتاح StashDB/ThePornDB'], 0);
  final n = limit ?? ids.length; final now = DateTime.now().millisecondsSinceEpoch;
  var i = 0;
  for (; i < n && i < ids.length; i++) {
    final e = ids[(cursor + i) % ids.length];
    try {
      if (s.works) {
        final keys = {...((e['k'] as List?) ?? const []).cast<String>()};
        final known = [for (final w in (e['w'] as List? ?? const [])) Map<String, dynamic>.from(w as Map)];
        // المصدران معًا، والعمل الموجود من المصدر الآخر لا يُعدّ جديدًا
        var got = <Map<String, dynamic>>[];
        // كل سجلاتها (أسماؤها الأخرى أيضًا)
        final ss = {'${e['s'] ?? ''}', ...((e['ss'] as List?) ?? const []).map((x) => '$x')}..remove('');
        final ts = {'${e['t'] ?? ''}', ...((e['ts'] as List?) ?? const []).map((x) => '$x')}..remove('');
        if (hasS) { for (final id in ss) { got = mergeWorks(got, await StashDB.scenes(id, maxPages: 1)).list; } }
        if (hasT) { for (final id in ts) { try { got = mergeWorks(got, await TPDB.scenes(id, maxPages: 1)).list; } on SourceError catch (x) { if (x.status == 401 || x.status == 403) errs.add(x.msg); } } }
        final fresh = [for (final w in got) if (!keys.contains(wKeyOf(w)) && !known.any((k) => sameWork(k, w))) w];
        if (fresh.isNotEmpty) works['${e['id']}'] = fresh;
      }
      if (s.photos && hasS && '${e['s'] ?? ''}'.isNotEmpty) {
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

/// حالة إذن الإشعارات الفعلية من النظام: (مسموحة؟، وصف مقروء).
Future<(bool, String)> notifStatus() async {
  if (kIsWeb) return (false, 'الويب: لا إشعارات');
  await _initNotif();
  final ios = _notif.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
  if (ios != null) {
    final p = await ios.checkPermissions();
    if (p == null) return (false, 'تعذّر قراءة الإذن');
    if (!p.isEnabled) return (false, 'الإشعارات مرفوضة في إعدادات الآيفون');
    return (true, [if (p.isAlertEnabled) 'تنبيه', if (p.isSoundEnabled) 'صوت', if (p.isBadgeEnabled) 'شارة'].join(' + ').ifEmpty('مسموحة (بلا تنبيه مرئي)'));
  }
  final a = _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  final ok = await a?.areNotificationsEnabled() ?? false;
  return (ok, ok ? 'مسموحة' : 'الإشعارات مرفوضة في إعدادات أندرويد');
}

const _testDetails = NotificationDetails(
  android: AndroidNotificationDetails('test', 'إشعار تجريبي', channelDescription: 'للتأكد من وصول الإشعارات', importance: Importance.high, priority: Priority.high),
  iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true));

/// إشعار تجريبي: فوري، أو مجدول بعد [delay] (يصل والتطبيق في الخلفية أو مغلق — يجدوله النظام نفسه).
Future<void> testNotification({Duration delay = Duration.zero}) async {
  if (kIsWeb) return;
  await _initNotif();
  if (delay == Duration.zero) {
    await _notif.show(id: 4290, title: 'المفضلة · إشعار تجريبي', body: 'الإشعارات تعمل ✓ (والتطبيق مفتوح)', notificationDetails: _testDetails);
    return;
  }
  tzdata.initializeTimeZones();
  await _notif.zonedSchedule(id: 4291, title: 'المفضلة · إشعار تجريبي', body: 'وصل بعد ${delay.inSeconds} ثانية ✓ — يعمل والتطبيق في الخلفية أو مغلق',
    scheduledDate: tz.TZDateTime.now(tz.UTC).add(delay), notificationDetails: _testDetails, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
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
      final r0 = await fetchUpdates(inp, cursor: (st['cursor'] as num?)?.toInt() ?? 0, limit: _perRun);
      final told = {...((st['told'] as List?) ?? const []).cast<String>()};
      final fresh = await findTasteNew(inp, told);
      final r = FetchResult(r0.works, r0.images, r0.errors, r0.nextCursor, fresh);
      told.addAll(fresh.map((x) => '${x['id']}'));
      await bgWrite('bg_state.json', jsonEncode({'cursor': r.nextCursor, 'at': DateTime.now().millisecondsSinceEpoch, 'works': r.workCount, 'photos': r.images.length, 'err': r.errors.join(' · '),
        'told': told.toList().reversed.take(400).toList()}));
      if (r.workCount > 0 || r.images.isNotEmpty || fresh.isNotEmpty) {
        await bgWrite('bg_out_${DateTime.now().millisecondsSinceEpoch}.json', jsonEncode(r.toJson()));
        if (r.workCount > 0 || r.images.isNotEmpty) await _notify(r.workCount, r.images.length);
        if (fresh.isNotEmpty) await _notifyTaste(fresh.length, ((fresh.first['score'] as num) * 58 + 40).round().clamp(40, 98));
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
  await Workmanager().registerPeriodicTask(bgTaskId, bgTaskId, frequency: Duration(hours: defaultTargetPlatform == TargetPlatform.iOS ? 2 : s.hours), initialDelay: const Duration(minutes: 30),
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
        [for (final x in (j['images'] as List? ?? const [])) StudioImg.fromJson(Map<String, dynamic>.from(x as Map))], const [], 0,
        [for (final x in (j['recs'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)]));
    } catch (_) {}
    await bgRemove(name);
  }
  return out;
}

Future<Map<String, dynamic>?> lastBgState() async { final r = await bgRead('bg_state.json'); return r == null ? null : Map<String, dynamic>.from(jsonDecode(r) as Map); }

extension _E on String { String ifEmpty(String o) => isEmpty ? o : this; }


// ===================== تنبيهات أذكى =====================

/// تذكير بإصدار: (المعرّف، الوقت المحلي، العنوان، النص) — نص عام بلا أسماء (يظهر على شاشة القفل).
typedef Reminder = (int, DateTime, String, String);

/// إصدارات مفضلاتك القادمة (★ أو تقييم 4+، بتاريخ يوم كامل خلال 60 يومًا) ⇒ تذكير مساء اليوم السابق (8م) وصباح يوم الإصدار (9ص).
/// حد أقصى 40 تذكيرًا (iOS يقبل 64 مجدولًا).
List<Reminder> computeReminders(List<Performer> lib, DateTime now) {
  final byDay = <String, Set<String>>{};   // اليوم ⇒ مفاتيح الأعمال
  final today = DateTime(now.year, now.month, now.day);
  for (final p in lib) {
    if (p.isMinor || !(p.fav || p.rating >= 4)) continue;
    for (final w in p.works) {
      final d = '${w['d'] ?? ''}';
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) || w['w'] == 1 || w['w'] == true) continue;
      final day = DateTime.tryParse(d); if (day == null) continue;
      final diff = day.difference(today).inDays;
      if (diff < 0 || diff > 60) continue;
      (byDay[d] ??= {}).add(wKeyOf(w));
    }
  }
  final out = <Reminder>[]; var id = 5000;
  for (final d in (byDay.keys.toList()..sort())) {
    final day = DateTime.parse(d), n = byDay[d]!.length;
    final eve = DateTime(day.year, day.month, day.day - 1, 20), morn = DateTime(day.year, day.month, day.day, 9);
    if (eve.isAfter(now)) out.add((id++, eve, 'المفضلة · غدًا', n == 1 ? 'يصدر غدًا عمل جديد لمفضلة لديك' : 'يصدر غدًا $n أعمال جديدة لمفضلاتك'));
    if (morn.isAfter(now)) out.add((id++, morn, 'المفضلة · صدر اليوم', n == 1 ? 'صدر اليوم عمل جديد لمفضلة لديك' : 'صدرت اليوم $n أعمال جديدة لمفضلاتك'));
    if (out.length >= 40) break;
  }
  return out;
}

const _remDetails = NotificationDetails(
  android: AndroidNotificationDetails('releases', 'إصدارات المفضلات', channelDescription: 'تذكير بإصدارات مفضلاتك القادمة (بلا أسماء)', importance: Importance.defaultImportance, visibility: NotificationVisibility.private),
  iOS: DarwinNotificationDetails());

/// يعيد جدولة تذكيرات الإصدارات (يلغي القديمة أولًا). بلا إنترنت — مجدولة على الجهاز.
Future<int> scheduleReleaseReminders(List<Performer> lib, BgSettings s) async {
  if (kIsWeb) return 0;
  await _initNotif();
  for (var i = 5000; i < 5045; i++) { await _notif.cancel(id: i); }
  if (!s.on || !s.rem) return 0;
  final rs = computeReminders(lib, DateTime.now());
  tzdata.initializeTimeZones();
  for (final r in rs) {
    await _notif.zonedSchedule(id: r.$1, title: r.$3, body: r.$4, scheduledDate: tz.TZDateTime.from(r.$2.toUtc(), tz.UTC), notificationDetails: _remDetails, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
  }
  return rs.length;
}

/// «ممثلة جديدة قريبة من ذوقك»: أحدث الوجوه في StashDB (ترتيب الظهور) ⇒ بوابة +18 ⇒ تشابه مع ملف ذوقك المحفوظ ≥ 82٪ ⇒ اقتراح.
/// لا يُعاد التنبيه لنفس الممثلة، ولا لمن في مكتبتك أو أخفيتها.
Future<List<Map<String, dynamic>>> findTasteNew(Map<String, dynamic> input, Set<String> told) async {
  final s = BgSettings.fromJson(input['settings'] as Map?);
  final t = input['taste'] as Map?;
  final prof = profileFromJson(t?['prof']);
  if (!s.tasteNew || prof == null || !prof.sufficient || !await ApiKeys.has(ApiKeys.stash)) return const [];
  final fb = {for (final e in ((t?['fb'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toDouble()};
  final skip = {...told, ...((input['libS'] as List?) ?? const []).cast<String>(), ...((t?['hidden'] as List?) ?? const []).cast<String>()};
  final names = {...((input['libN'] as List?) ?? const []).cast<String>()};
  final out = <Map<String, dynamic>>[];
  try {
    final d = await StashDB.q('query{queryPerformers(input:{gender:FEMALE,sort:DEBUT,direction:DESC,per_page:40}){performers{id name aliases gender birth_date country ethnicity hair_color eye_color height cup_size band_size waist_size hip_size breast_type career_start_year career_end_year tattoos{location} piercings{location} images{url width height}}}}');
    for (final x in ((d['queryPerformers'] as Map?)?['performers'] as List? ?? const [])) {
      if (x is! Map) continue;
      final m = Map<String, dynamic>.from(x); final id = '${m['id']}';
      if (skip.contains(id) || names.contains(norm(m['name']))) continue;
      if (m['gender'] != null && m['gender'] != 'FEMALE') continue;
      if (!adultOk({'birth': m['birth_date']})) continue;                         // بوابة +18 قبل أي صورة
      final ft = featuresOf(m); final sim = similarity(prof, ft, fb: fb);
      if (sim.score < .82 || sim.why.isEmpty) continue;
      final imgs = stashImages(m);
      out.add({'id': id, 'name': '${m['name']}', 'birth': '${m['birth_date'] ?? ''}', 'country': '${m['country'] ?? ''}', 'image': imgs.isEmpty ? '' : imgs.first,
        'score': sim.score, 'why': ['ظهرت حديثًا في المجال', ...sim.why.take(3)], 'diff': sim.diff.take(2).toList(), 'f': ft, 'tags': ['new', 'debut']});
    }
  } catch (_) {}
  out.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
  return out.take(5).toList();
}

Future<void> _notifyTaste(int n, int pct) async {
  if (kIsWeb) return;
  await _initNotif();
  await _notif.show(id: 4202, title: 'المفضلة · اكتشف', body: n == 1 ? 'ممثلة جديدة قريبة جدًا من ذوقك ($pct٪) — افتح «اكتشف»' : '$n ممثلات جديدات قريبات من ذوقك — افتح «اكتشف»',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails('taste', 'اقتراحات حسب ذوقك', channelDescription: 'ممثلة جديدة قريبة من ذوقك (بلا أسماء)', importance: Importance.defaultImportance, visibility: NotificationVisibility.private),
      iOS: DarwinNotificationDetails()));
}
