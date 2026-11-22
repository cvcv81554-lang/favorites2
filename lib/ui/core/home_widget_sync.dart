import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/photo_hash.dart' show storedPhotoBytes, fetchImageBytes;
import '../../domain/performer.dart';
import '../../domain/sanitize.dart';

/// ويدجت الشاشة الرئيسية (iPhone): «نجمة اليوم» + أقرب إصدار لمفضلاتك.
/// البيانات تُكتب في مجموعة التطبيق المشتركة ليقرأها الويدجت؛ في الوضع الخاص بلا صورة ولا اسم ولا عنوان عمل.
const widgetAppGroup = 'group.com.favlib.favorites2';
const widgetIosName = 'FavWidget';

/// أقرب إصدار قادم لمفضلاتك (★ أو 4+): (العنوان، كم يومًا، عدد إصدارات الأسبوع).
(String, int, int)? nextRelease(List<Performer> lib, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final seen = <String>{}; (String, int)? best; var week = 0;
  for (final p in lib) {
    if (p.isMinor || !(p.fav || p.rating >= 4)) continue;
    for (final w in p.works) {
      final d = DateTime.tryParse('${w['d'] ?? ''}'); if (d == null || w['w'] == 1 || w['w'] == true) continue;
      final days = DateTime(d.year, d.month, d.day).difference(today).inDays;
      if (days < 0 || !seen.add(wKeyOf(w))) continue;
      if (days <= 7) week++;
      if (best == null || days < best.$2) best = ('${w['t'] ?? ''}', days);
    }
  }
  return best == null ? null : (best.$1, best.$2, week);
}

String whenText(int days) => days == 0 ? 'اليوم' : days == 1 ? 'غدًا' : 'بعد $days أيام';

Future<void> syncHomeWidget(List<Performer> lib, {required bool private}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await HomeWidget.setAppGroupId(widgetAppGroup);
    final now = DateTime.now();
    final spot = pickSpotlight(lib, now);
    final nx = nextRelease(lib, now);
    final a = spot?.age;
    await Future.wait([
      HomeWidget.saveWidgetData<bool>('priv', private),
      HomeWidget.saveWidgetData<String>('spot_id', private ? '' : spot?.id ?? ''),
      HomeWidget.saveWidgetData<String>('spot_name', private ? '' : spot?.name ?? ''),
      HomeWidget.saveWidgetData<String>('spot_meta', private || spot == null ? '' : [if (a != null) '$a سنة', if (spot.country.isNotEmpty) spot.country, '${spot.works.length} عمل'].join(' · ')),
      HomeWidget.saveWidgetData<String>('next_title', private ? '' : nx?.$1 ?? ''),
      HomeWidget.saveWidgetData<String>('next_when', nx == null ? '' : whenText(nx.$2)),
      HomeWidget.saveWidgetData<int>('next_week', nx?.$3 ?? 0),
      HomeWidget.saveWidgetData<int>('total', lib.where((p) => !p.isMinor).length),
      HomeWidget.saveWidgetData<String>('day', '${now.year}-${now.month}-${now.day}'),
    ]);
    // الصورة: تُفك مسبقًا ثم تُرسم كما هي (RawImage) — بلا انتظار تحميل أثناء الرسم
    ui.Image? img;
    if (!private && spot != null && spot.cover.isNotEmpty) {
      final b = spot.cover.startsWith('https://') ? await fetchImageBytes(spot.cover) : await storedPhotoBytes(spot.cover);
      if (b != null) { final c = await ui.instantiateImageCodec(b, targetWidth: 720); img = (await c.getNextFrame()).image; }
    }
    if (img != null) {
      await HomeWidget.renderFlutterWidget(SizedBox(width: 360, height: 360, child: RawImage(image: img, fit: BoxFit.cover, alignment: const Alignment(0, -.5))), key: 'spot_img', logicalSize: const Size(360, 360), pixelRatio: 2);
    } else {
      await HomeWidget.saveWidgetData<String>('spot_img', null);
    }
    await HomeWidget.updateWidget(iOSName: widgetIosName);
  } catch (_) {}   // نسخة بلا ويدجت (Favorites2.ipa) أو بلا مجموعة تطبيق: لا شيء يتعطل
}
