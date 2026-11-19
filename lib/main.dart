import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'data/background.dart';
import 'ui/core/theme.dart';
import 'ui/features/discover/discover_screen.dart';
import 'ui/features/home/home_screen.dart';
import 'ui/features/library/library_screen.dart';
import 'ui/features/more/more_screen.dart';
import 'ui/features/performer/performer_screen.dart';
import 'ui/features/sources/source_search.dart';
import 'ui/features/studio/studio_screen.dart';
import 'ui/features/works/works_screen.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await initBackground(); } catch (_) {}   // لا يمنع فتح التطبيق إن تعذّر
  runApp(const ProviderScope(child: FavoritesApp()));
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (c, s, nav) => AppShell(nav: nav),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/library', builder: (_, _) => const LibraryScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/works', builder: (_, _) => const WorksScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/discover', builder: (_, _) => const DiscoverScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/studio', builder: (_, _) => const StudioScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (_, _) => const MoreScreen())]),
      ],
    ),
    GoRoute(path: '/p/:id', builder: (_, s) => PerformerScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/search', builder: (_, s) => SourceSearchScreen(initial: s.uri.queryParameters['q'] ?? '', linkTo: s.uri.queryParameters['link'])),
  ],
);

class FavoritesApp extends StatelessWidget {
  const FavoritesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'المفضلة',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    darkTheme: buildTheme(),
    themeMode: ThemeMode.dark,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: _router,
    shortcuts: {...WidgetsApp.defaultShortcuts, const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent()},
  );
}
