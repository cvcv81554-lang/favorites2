import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme.dart';
import 'core/widgets.dart';

/// غلاف تكيّفي: شريط سفلي على الجوال، وشريط جانبي على الشاشات العريضة (الحاسوب/التلفاز/الآيباد).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.nav});
  final StatefulNavigationShell nav;

  static const dests = [
    (Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'المكتبة'),
    (Icons.movie_outlined, Icons.movie_rounded, 'الأعمال'),
    (Icons.explore_outlined, Icons.explore_rounded, 'اكتشف'),
    (Icons.photo_library_outlined, Icons.photo_library_rounded, 'الاستديو'),
    (Icons.tune_outlined, Icons.tune_rounded, 'المزيد'),
  ];

  void _go(int i) => nav.goBranch(i, initialLocation: i == nav.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (!wide) {
      return Scaffold(
        extendBody: true,
        body: nav,
        bottomNavigationBar: NavigationBar(
          selectedIndex: nav.currentIndex, onDestinationSelected: _go,
          destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
        ),
      );
    }
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: nav.currentIndex, onDestinationSelected: _go, labelType: NavigationRailLabelType.all,
          leading: const Padding(padding: EdgeInsets.only(top: S.s4, bottom: S.s5), child: AppLogo(size: 44)),
          groupAlignment: -.7,
          destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
        ),
        const VerticalDivider(width: 1, color: C.line),
        Expanded(child: nav),
      ]),
    );
  }
}

/// صفحة قسم قادم (بنيت هيكلته، والمحتوى في مرحلة لاحقة) — بصدق، بلا بيانات وهمية.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: EmptyState(title: title, body: body)));
}
