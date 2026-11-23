import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'data/background.dart';
import 'ui/core/bg_coordinator.dart';
import 'ui/core/theme.dart';
import 'ui/core/user_font.dart';
import 'ui/features/discover/candidate_screen.dart';
import 'ui/features/discover/discover_screen.dart';
import 'ui/features/discover/taste_map_screen.dart';
import 'ui/features/find/find_screen.dart';
import 'ui/features/home/home_screen.dart';
import 'ui/features/library/library_screen.dart';
import 'ui/features/more/more_screen.dart';
import 'ui/features/performer/performer_screen.dart';
import 'ui/features/privacy/lock_gate.dart';
import 'ui/features/reels/network_screen.dart';
import 'ui/features/reels/reels_screen.dart';
import 'ui/features/sources/source_search.dart';
import 'ui/features/stash/stash_library_screen.dart';
import 'ui/features/stats/stats_screen.dart';
import 'ui/features/studio/studio_screen.dart';
import 'ui/features/sync/sync_screen.dart';
import 'ui/features/tools/tools_screen.dart';
import 'ui/features/works/evening_screen.dart';
import 'ui/features/works/works_screen.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await initBackground(); } catch (_) {}   // لا يمنع فتح التطبيق إن تعذّر
  // اختبار آلي على الويب فقط (?qa=1): شجرة إتاحة كي يضغط Playwright الأزرار بأسمائها
  if (kIsWeb && Uri.base.queryParameters['qa'] == '1') SemanticsBinding.instance.ensureSemantics();
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
    GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
    GoRoute(path: '/tools', builder: (_, _) => const ToolsScreen()),
    GoRoute(path: '/stats', builder: (_, _) => const StatsScreen()),
    GoRoute(path: '/find', builder: (_, _) => const FindScreen()),
    GoRoute(path: '/evening', builder: (_, _) => const EveningScreen()),
    GoRoute(path: '/reels', builder: (_, _) => const ReelsScreen()),
    GoRoute(path: '/network', builder: (_, _) => const NetworkScreen()),
    GoRoute(path: '/stash', builder: (_, _) => const StashLibraryScreen()),
    GoRoute(path: '/taste-map', builder: (_, s) => TasteMapScreen(tab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
    GoRoute(path: '/c/:sid', builder: (_, s) => CandidateScreen(stashId: s.pathParameters['sid']!, why: (s.extra as List?)?.cast<String>() ?? const [])),
    GoRoute(path: '/search', builder: (_, s) => SourceSearchScreen(initial: s.uri.queryParameters['q'] ?? '', linkTo: s.uri.queryParameters['link'])),
  ],
);

class FavoritesApp extends ConsumerWidget {
  const FavoritesApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final font = ref.watch(userFontProvider).value == true ? userFontFamily : 'Plex';   // خط المستخدم (ثمانية) إن استورده
    return MaterialApp.router(
    title: 'المفضلة',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(font: font),
    darkTheme: buildTheme(font: font),
    themeMode: ThemeMode.dark,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (c, child) {
      final tv = ref.watch(isTvProvider).value ?? false;   // شاشة 10 أقدام: نص أكبر
      final w = LockGate(child: BgCoordinator(child: child!));
      return tv ? MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.25)), child: w) : w;
    },
    routerConfig: _router,
    shortcuts: {...WidgetsApp.defaultShortcuts, const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent()},
  );
  }
}
