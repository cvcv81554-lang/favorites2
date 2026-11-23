// اختبار على محاكي الآيفون (في GitHub): يفتح التطبيق الحقيقي ببيانات تجريبية محايدة (DEMO) ويمر على الأقسام الجديدة،
// ويتأكد أنها تُبنى بلا أخطاء، ويلتقط صورة لكل شاشة.
import 'package:favorites2/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' show Scaffold;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 1500]) async { for (var i = 0; i < ms ~/ 100; i++) { await t.pump(const Duration(milliseconds: 100)); } }

  Future<void> shot(WidgetTester t, String name) async {
    await binding.convertFlutterSurfaceToImage();
    await t.pump();
    await binding.takeScreenshot(name);
  }

  Future<void> go(WidgetTester t, String route) async {
    GoRouter.of(t.element(find.byType(Scaffold).first)).push(route);
    await settle(t);
  }

  Future<void> back(WidgetTester t) async {
    GoRouter.of(t.element(find.byType(Scaffold).last)).pop();
    await settle(t, 600);
  }

  testWidgets('الأقسام الجديدة تعمل على الآيفون', (t) async {
    app.main();
    await settle(t, 4000);
    expect(t.takeException(), isNull);
    await shot(t, '01-home');

    // البحث باللغة الطبيعية: رقائق «فهمت»
    await go(t, '/find');
    await t.enterText(find.byType(EditableText).first, 'شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق');
    await settle(t, 1200);
    expect(find.text('شقراء'), findsWidgets);
    expect(find.text('العمر 20–25'), findsOneWidget);
    await shot(t, '02-nl-search');
    await back(t);

    for (final (route, name, text) in [
      ('/journal', '03-journal', 'ملخص الشهر'),
      ('/stash', '04-stash', 'مكتبة Stash'),
      ('/missing', '05-missing', 'الأعمال الناقصة'),
      ('/faces', '06-faces', 'ابحث بصورة'),
      ('/reels', '07-reels', 'لك'),
      ('/network', '08-network', 'الشبكة والمقاطع'),
    ]) {
      await go(t, route);
      expect(t.takeException(), isNull, reason: route);
      expect(find.text(text), findsWidgets, reason: route);
      await shot(t, name);
      await back(t);
    }
  });
}
