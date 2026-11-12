import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../core/widgets/error_state.dart';
import '../core/utils/logger.dart';
import '../features/content/models/region_catalog.dart';
import '../features/splash/presentation/splash_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/map/presentation/pages/map_page.dart';
import '../features/poi/presentation/pages/poi_detail_page.dart';
import '../features/trails/presentation/pages/trail_detail_page.dart';
import '../features/admin/providers/admin_providers.dart';
import '../features/admin/presentation/admin_gate.dart';
import '../features/favorites/presentation/favorites_page.dart';
import '../app/navigation/navigation_shell.dart';

/// Собирает страницу `/map` из query-параметров глубокой ссылки.
///
/// `island` прогоняется через [sanitizeIslandParam], как и в
/// маршрутах `/poi`/`/trail`: мусор из URL (локация удалена из
/// каталога, опечатка) не должен попадать в контентные провайдеры —
/// `regionOfLocation` бросает StateError, и карта падает экраном
/// «Не удалось загрузить стиль карты».
MapPage buildMapPageFromQueryParameters(
  Map<String, String> params,
) {

  final lat = double.tryParse(params['lat'] ?? '');

  final lng = double.tryParse(params['lng'] ?? '');

  final zoom = double.tryParse(params['zoom'] ?? '');

  return MapPage(
    lat: lat,
    lng: lng,
    zoom: zoom,
    islandId: sanitizeIslandParam(
      params['island'],
    ),
    highlightTrailId: params['trail'],
    highlightPoiId: params['poi'],
    // Вкладка «Поиск» (/search → /map?search=1): та же живая
    // карта, но с раскрытой шторкой поиска (P0-7).
    openSearch: params['search'] == '1',
  );
}

class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  /// Контекст root-навигатора (Б1, замечание Sonnet): мини-плеер
  /// живёт в `MaterialApp.builder` НАД Navigator'ом роутера —
  /// модальные шторки из него обязаны открываться через контекст
  /// НАД навигатором, иначе `Navigator.of` бросает исключение
  /// «context that does not include a Navigator».
  static BuildContext? get rootNavigatorContext =>
      _rootNavigatorKey.currentContext;

  // Ветви шелла: у каждой свой навигатор — вкладки живут в
  // IndexedStack и НЕ пересоздаются при переключении (P0-7).
  static final _homeNavigatorKey = GlobalKey<NavigatorState>();

  static final _mapNavigatorKey = GlobalKey<NavigatorState>();

  static final _favoritesNavigatorKey = GlobalKey<NavigatorState>();

  /// Индекс подсвеченной вкладки по адресу: /map?search=1 — это
  /// вкладка «Поиск», хотя активна ветвь карты.
  static int _shellTabIndex(Uri uri) {
    final path = uri.path;

    if (path.startsWith('/map')) {
      return uri.queryParameters['search'] == '1' ? 3 : 1;
    }

    if (path.startsWith('/favorites')) {
      return 2;
    }

    return 0;
  }

  /// Переход вкладок шелла — fade-through: лёгкое затухание
  /// без направления (вкладки равнозначны).
  static CustomTransitionPage<void> _shellPage(Widget child) {
    return CustomTransitionPage<void>(
      // Корень ветки: системный «Назад» с не-домашней вкладки
      // возвращает на главную, а не закрывает приложение
      // (P0-11, 6-й проход). Раньше единственный роут ветки
      // «пузырил» back до SystemNavigator.pop.
      child: _HomeReturnScope(child: child),
      transitionDuration: AppMotion.normal,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.curve,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Переход страниц деталей — shared-axis по горизонтали:
  /// деталь «приезжает» справа с лёгкой прозрачностью.
  static CustomTransitionPage<void> _detailPage(Widget child) {
    return CustomTransitionPage<void>(
      child: child,
      transitionDuration: AppMotion.slow,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.curve,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
    );
  }

  static final router = GoRouter(
    initialLocation: '/',

    navigatorKey: _rootNavigatorKey,

    redirect: (context, state) {
      final path = state.uri.path;

      // Вкладка «Поиск» — НЕ отдельная страница, а живая карта с
      // раскрытой шторкой поиска: /search редиректится в /map с
      // параметром. pageKey у /map зависит только от пути, поэтому
      // MapPage переиспользуется (didUpdateWidget) — камера и
      // данные карты не сбрасываются, второй MapPage не строится
      // (P0-7, 5-й проход).
      if (path == '/search') {
        return '/map?search=1';
      }

      // Несуществующий URL молча ведёт на главную: раньше
      // errorBuilder подменял страницу, и «битый» адрес оставался
      // в истории/строке браузера (P0-7).
      if (state.error != null) {
        return '/home';
      }

      return null;
    },

    // Последний рубеж — ошибка сборки самого роута (не «битый»
    // URL: тот уходит redirect'ом выше).
    errorBuilder: (context, state) {
      return _RouterErrorScreen(
        onHome: () => context.go('/home'),
      );
    },

    routes: [
      // Splash screen - no shell
      GoRoute(
        path: '/',
        builder: (context, state) {
          return const SplashPage();
        },
      ),

      // Shell с постоянной навигацией. Ветви живут в
      // IndexedStack: позиция скролла главной и камера карты
      // НЕ сбрасываются при переключении вкладок (P0-7).
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return NavigationShell(
            selectedIndex: _shellTabIndex(state.uri),
            child: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) {
                  return _shellPage(const HomePage());
                },
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _mapNavigatorKey,
            routes: [
              GoRoute(
                path: '/map',
                pageBuilder: (context, state) {
                  final params = state.uri.queryParameters;
                  AppLogger.info(
                    '[Router] /map uri=${state.uri} island=${params['island']}',
                  );
                  return _shellPage(
                    buildMapPageFromQueryParameters(params),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _favoritesNavigatorKey,
            routes: [
              GoRoute(
                path: '/favorites',
                pageBuilder: (context, state) {
                  return _shellPage(const FavoritesPage());
                },
              ),
            ],
          ),
        ],
      ),

      // Админка не входит в публичный release-бандл: роуты
      // /admin* регистрируются только в debug / с ADMIN_ENABLED.
      if (kAdminEnabled) ...[
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminGate(),
        ),
        GoRoute(
          path: '/admin/login',
          builder: (context, state) => const AdminGate(),
        ),
        GoRoute(
          path: '/admin/poi/:id',
          builder: (context, state) {
            return AdminGate(
              islandId: sanitizeIslandParam(
                state.uri.queryParameters['island'],
              ),
              poiId: state.pathParameters['id'] ?? '',
            );
          },
        ),
      ],
      // Detail pages - outside shell (full screen)
      GoRoute(
        path: '/poi/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          AppLogger.info(
            '[Router] /poi id=${state.pathParameters['id']} '
            'island=${state.uri.queryParameters['island']}',
          );
          return _detailPage(PoiDetailPage(
            poiId: state.pathParameters['id'] ?? '',
            islandId: sanitizeIslandParam(
              state.uri.queryParameters['island'],
            ),
            // Hero-полёт из избранного — по тегу ветки избранного
            // (P1-4, 6-й проход).
            heroFromFavorites:
                state.uri.queryParameters['hero'] == 'fav',
          ));
        },
      ),
      GoRoute(
        path: '/trail/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          AppLogger.info(
            '[Router] /trail id=${state.pathParameters['id']} '
            'island=${state.uri.queryParameters['island']}',
          );
          return _detailPage(TrailDetailPage(
            trailId: state.pathParameters['id'] ?? '',
            islandId: sanitizeIslandParam(
              state.uri.queryParameters['island'],
            ),
          ));
        },
      ),
    ],
  );
}

/// Корень ветки шелла: перехват системного «Назад» (P0-11,
/// 6-й проход).
///
/// На главной back работает как обычно (выход). На карте и в
/// избранном — сначала возврат на главную; повторный back уже
/// с главной закрывает приложение. Модальные шторки веток
/// закрываются бэком раньше (их роут выше роута ветки).
class _HomeReturnScope extends StatelessWidget {
  const _HomeReturnScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onHome = GoRouterState.of(context).uri.path == '/home';

    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          context.go('/home');
        }
      },
      child: child,
    );
  }
}

/// Экран ошибки роута: не «тихая» подмена главной, а явное
/// сообщение с выходом (P0-7).
class _RouterErrorScreen extends StatelessWidget {
  const _RouterErrorScreen({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ErrorState(
          message: 'Страница не найдена',
          description: 'Возможно, ссылка устарела',
          onRetry: onHome,
        ),
      ),
    );
  }
}
