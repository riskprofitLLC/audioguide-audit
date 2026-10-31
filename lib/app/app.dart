import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';
import '../features/settings/providers/listened_providers.dart';
import '../features/settings/providers/settings_providers.dart';
import '../features/audio/presentation/widgets/mini_player.dart';

class IslandGuideApp extends ConsumerStatefulWidget {
  const IslandGuideApp({super.key});

  @override
  ConsumerState<IslandGuideApp> createState() => _IslandGuideAppState();
}

class _IslandGuideAppState extends ConsumerState<IslandGuideApp> {
  /// Отладочный флаг ночной темы (B5, 11-й проход):
  /// `flutter run --dart-define=APP_DARK=true` подставляет
  /// [AppTheme.dark] и [AppPalette.dark] — превью для поиска мест
  /// с хардкодом цвета. В release не действует: релиз всегда
  /// светлый.
  static const bool _appDarkFlag = bool.fromEnvironment('APP_DARK');
  @override
  void initState() {
    super.initState();

    // Слежение за «прослушанностью» треков (B2.2, 8-й проход):
    // keepAlive-провайдер, один раз за сессию — события приходят
    // и от автогида, и от мини-плеера, и от карточки плеера.
    ref.read(listenedWatcherProvider);

    // Сохранённая скорость плеера — к глобальному плееру сразу
    // (Б4, замечание Sonnet): раньше провайдер читался только в
    // build AudioGuidePlayer — автогид и мини-плеер играли 1×,
    // пока пользователь не открывал страницу точки.
    ref.read(playbackSpeedProvider);
  }


  @override
  Widget build(BuildContext context) {

    // Автозапуск голосового гида при входе в радиус POI слушается
    // на экране карты (MapPage): GPS не запрашивается с самого
    // запуска приложения, а только после осознанного открытия карты.

    final themeMode = ref.watch(themeModeProvider);

    // Ночное превью отладочным флагом (B5) жёстко перекрывает
    // настройку; иначе — настройка из шторки (D3).
    final effectiveMode = _appDarkFlag && !kReleaseMode
        ? ThemeMode.dark
        : themeMode;

    return MaterialApp.router(
      title: 'Island Guide',

      debugShowCheckedModeBanner: false,

      theme: AppTheme.light,

      // Ночная тема — из настройки шторки (D3) или превью-флага.
      darkTheme: AppTheme.dark,
      themeMode: effectiveMode,

      // Приложение одноязычное (русское), но системные строки
      // Material (тултипы, контекстные меню, a11y-объявления,
      // «Показать ещё» у чипсов и т.п.) должны быть тоже русскими:
      // без delegates они остаются английскими при любой системной
      // локали.
      locale: const Locale('ru'),

      supportedLocales: const [
        Locale('ru'),
      ],

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      routerConfig: AppRouter.router,

      builder: (context, child) => MediaQuery.withClampedTextScaling(
        // Крупные системные шрифты ломали фиксированные высоты —
        // но обрезка на 1.3 резала настройки доступности
        // (пользователи ставят 1.5–2.0). Поднято до 1.6 (P1-5,
        // 6-й проход): переполнения чипов/капсулы/строк дерева
        // закрыты, layout-тесты гоняются на textScale 1.6.
        minScaleFactor: 1.0,
        maxScaleFactor: 1.6,
        child: Stack(
          children: [
            // Глобальный SafeArea не ставим: hero-галереи деталей
            // уходят под статус-бар, страницы сами уважают отступы
            // (home — MediaQuery, карта — свой SafeArea, AppBar — M3).
            // Фон — из ТЕМЫ (B5): ночное превью не рвётся белой
            // подложкой, светлая тема получает ту же бумагу.
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: child!,
              ),
            ),

            // Мини-плеер играет поверх всех маршрутов, пока трек
            // звучит вне страницы своего POI.
            const MiniPlayerOverlay(),
          ],
        ),
      ),
    );
  }
}
