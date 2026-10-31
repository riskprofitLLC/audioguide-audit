import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

/// Палитра аудиогида — «Атлас путешественника» (редизайн).
///
/// Светлая тема — чистый кремовый лист печатного атласа,
/// глубокая морская бирюза, чернильный шифер и один яркий
/// сигнальный акцент — цвет маячных огней (#E85D3F, не меняется,
/// его проверяет e2e). Тёмная — «ночной атлас»: глубокий морской
/// фон и кремовый текст.
abstract class AppColors {
  // Базовые цвета «Атласа»
  static const ink = Color(0xFF16333C);
  static const chart = Color(0xFFFAF8F2);
  static const depth = Color(0xFF19617B);
  static const depthDark = Color(0xFF0F4255);
  static const shoal = Color(0xFF4E7D6E);
  static const signal = Color(0xFFE85D3F);
  static const signalDark = Color(0xFFC44A30);
  // Красный для выделенного текста в статьях (==…==): темнее signal,
  // заметнее на кремовом фоне (контраст ~5.9:1 против ~3.5:1 у signal).
  static const redText = Color(0xFFC22318);
  static const sandLight = Color(0xFFF4EFE3);
  static const sand = Color(0xFFE9E2D0);
  static const card = Color(0xFFFFFDF8);

  // ---- Цветовые РОЛИ (B1, 8-й проход) ----
  // Виджеты используют роли, а не прямые hex: подготовка ночной
  // темы — смена набора, а не правка мест использования. Палитра
  // «Ликийского дневника» НЕ меняется (сигнал #E85D3F — e2e).

  /// Фон экрана (бумага).
  static const surface = chart;

  /// Фон карточек/шторок (лист бумаги).
  static const surfaceRaised = card;

  /// Основной текст на фоне.
  static const onSurface = ink;

  /// Приглушённый текст: не светлее ink@0.62 (контраст ≥4.5:1,
  /// см. tool/contrast_check.dart).
  static const onSurfaceMuted = Color(0xFF5D6E76);

  /// Акцент: только избранное, выделение и главное действие.
  static const accent = signal;

  /// Текст/иконки НА акценте.
  static const accentOn = Color(0xFFFFFFFF);

  /// Текст/иконки на тёмных скримах поверх фото (B3, 9-й
  /// проход): тот же белый, но осмысленная роль — при включении
  /// тёмной темы такие места меняются одной константой.
  static const onScrim = Color(0xFFFFFFFF);

  /// Тёмный скрим поверх фото/видео (B1, 11-й проход): фон
  /// полноэкранного просмотра, подложки счётчика «N / M»,
  /// прогресс-бара видео и кнопки воспроизведения. Роль, а не
  /// голый Colors.black: скримы над контентом не участвуют в
  /// ночной теме (фото остаются фото), но живут одной
  /// константой.
  static const scrimDark = Color(0xFF000000);

  /// «Чернильный» скрим поверх фото (градиент обложек карточек):
  /// тот же тёмный цвет, что чернила светлой темы, — скримы над
  /// контентом НЕ переворачиваются ночной темой (D1, замечания
  /// Sonnet), а голый AppColors.ink в UI запрещён стражем.
  static const scrimInk = Color(0xFF16333C);

  /// Информационный акцент (бирюза глубины).
  static const info = depth;

  // Семантические токены (M3 + custom)
  static const surfaceVariant = Color(0xFFF0EBDD);
  static const outline = Color(0xFF7A8A92);
  static const outlineStrong = Color(0xFF56656D);
  static const outlineVariant = Color(0xFFDCD5C2);
  static const brandPrimary = depth;
  static const brandAccent = signal;
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFF57F17);
  static const error = Color(0xFFB42318);
  static const errorContainer = Color(0xFFFCE8E6);

  // Служебные цвета карты: маркеры, маршруты, заглушки.
  // Строковые литералы MapLibre (map_layers.dart) ссылаются
  // на эти значения — собраны в одном месте.
  //
  // Маршрут — глубокая бирюза бренда с белым кейсингом:
  // маджента #C43A8C выбивалась из бирюзово-терракотовой
  // палитры. Приглушённый вариант — светлее, но читается
  // поверх воды за счёт белого кейсинга.
  static const mapPoi = Color(0xFF1668A8);
  static const mapTrail = Color(0xFF19617B);
  static const mapTrailMuted = Color(0xFF7BA7BB);
  static const mapPlaceholder = Color(0xFFE8E6DF);

  /// Маркер «Вы здесь» (B1, 17-й проход): классический синий
  /// «гугл-точки» — универсальный символ текущей позиции; от
  /// маркеров POI (#1668A8) отличается конструкцией: белое
  /// кольцо, круг точности и стрелка курса. Строковый литерал
  /// MapLibre — _mapUserColor в map_overlays.dart; легенда карты
  /// читает эту роль.
  static const mapUser = Color(0xFF2563EB);

  // Плашка запрета пеших маршрутов (тёплый тинт + жжёный
  // терракотовый глиф).
  static const alertTint = Color(0xFFFFEDD5);
  static const alertInk = Color(0xFFC2410C);
}

/// Тема приложения.
///
/// `flex_color_scheme` остаётся базой для консистентности M3,
/// но поверх — ручные оверрайды аудиогида. Дисплей — Prata
/// (кириллический антикв, офлайн): названия регионов, точек и
/// маршрутов. Остальное — Manrope Variable: жёсткая иерархия
/// 700/800, eyebrow-трекинг, табличные цифры.
///
/// Светлая и тёмная темы собираются ОДНИМ билдером [build] из
/// ролевого набора [AppPalette] (B5, 11-й проход): светлая —
/// «Ликийский дневник», тёмная — чернильная (перевёрнутые роли,
/// подготовлена, включается отладочным флагом APP_DARK).
class AppTheme {
  AppTheme._();

  /// Анимация показа/скрытия нижних панелей (шторок) — плавное
  /// выезжание вместо резкого дефолтного.
  static const AnimationStyle sheetAnimationStyle = AnimationStyle(
    duration: Duration(milliseconds: 300),
    reverseDuration: Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Светлая тема — «Ликийский дневник».
  ///
  /// Кешируется (Б15, замечание Sonnet): ThemeData собирается
  /// один раз — обращение из каждого build пересобирало её
  /// заново (сборка flex_color_scheme не из дешёвых).
  static ThemeData? _lightCache;

  static ThemeData get light =>
      _lightCache ??= _build(
        brightness: Brightness.light,
        palette: AppPalette.light,
      );

  /// Тёмная тема (B5, 11-й проход): чернильный фон, пергаментный
  /// текст, светлая бирюза. Подставляется ТОЛЬКО отладочным
  /// флагом `--dart-define=APP_DARK=true` (app.dart); релиз
  /// всегда светлый. Превью для поиска мест с хардкодом цвета.
  static ThemeData? _darkCache;

  static ThemeData get dark =>
      _darkCache ??= _build(
        brightness: Brightness.dark,
        palette: AppPalette.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
  }) {
    final isDark = brightness == Brightness.dark;

    // Ролевые алиасы: светлая тема получает ровно те же
    // значения, что были до параметризации (байт-в-байт).
    final inkColor = palette.onSurface;
    final paperColor = palette.surface;
    final sheetColor = palette.surfaceRaised;
    final sandColor = palette.sand;
    final sandLightColor = palette.sandLight;
    final mutedColor = palette.onSurfaceMuted;
    final primaryColor = palette.info;
    final outlineColor = palette.outline;
    final outlineVariantColor =
        isDark ? const Color(0xFF2E4149) : AppColors.outlineVariant;
    // Подложка снекбара/тултипа: днём — чернильная, ночью —
    // глубокая тёмная (светлый «инк» ночной темы здесь был бы
    // фоном-беленом с белым же текстом).
    final scrimInkColor =
        isDark ? const Color(0xFF08151B) : AppColors.ink;

    final base = isDark
        ? FlexThemeData.dark(
            scheme: FlexScheme.aquaBlue,
            useMaterial3: true,
            visualDensity: FlexColorScheme.comfortablePlatformDensity,
          )
        : FlexThemeData.light(
            scheme: FlexScheme.aquaBlue,
            surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
            blendLevel: 12,
            appBarStyle: FlexAppBarStyle.primary,
            appBarOpacity: 1,
            useMaterial3: true,
            visualDensity: FlexColorScheme.comfortablePlatformDensity,
          );

    // Ручной ColorScheme поверх aquaBlue — ликийский дневник.
    final scheme = base.colorScheme.copyWith(
      primary: primaryColor,
      // Ночная тема: primary — СВЕТЛАЯ бирюза, текст на ней —
      // тёмный чернильный (пергамент на #7BA7BB давал 2.6:1,
      // D3-контраст).
      onPrimary: isDark ? const Color(0xFF06272B) : AppColors.accentOn,
      primaryContainer: sandLightColor,
      onPrimaryContainer: inkColor,
      secondary: isDark ? const Color(0xFF6FA392) : AppColors.shoal,
      onSecondary: isDark ? const Color(0xFF06272B) : AppColors.accentOn,
      secondaryContainer:
          isDark ? const Color(0xFF1E3B36) : const Color(0xFFDCE9E3),
      onSecondaryContainer: inkColor,
      tertiary: palette.accent,
      onTertiary: palette.accentOn,
      tertiaryContainer:
          isDark ? const Color(0xFF4A2620) : const Color(0xFFFBE3DC),
      onTertiaryContainer: inkColor,
      surface: sheetColor,
      onSurface: inkColor,
      surfaceContainerLow: sheetColor,
      surfaceContainer: sandLightColor,
      surfaceContainerHigh: sandColor,
      surfaceContainerHighest:
          isDark ? const Color(0xFF2B3F47) : AppColors.surfaceVariant,
      outline: outlineColor,
      outlineVariant: outlineVariantColor,
      error: palette.error,
      errorContainer:
          isDark ? const Color(0xFF52241E) : AppColors.errorContainer,
      onError: isDark ? const Color(0xFFF6CEC7) : base.colorScheme.onError,
      onErrorContainer: isDark
          ? const Color(0xFFF6CEC7)
          : base.colorScheme.onErrorContainer,
    );

    final text = base.textTheme.apply(
      fontFamily: 'Manrope',
      displayColor: inkColor,
      bodyColor: inkColor,
    );

    return base.copyWith(
      colorScheme: scheme,
      extensions: [palette],
      scaffoldBackgroundColor: paperColor,
      // Фокус-кольцо клавиатурной навигации — бирюзовое, заметное
      // на бумаге (B12).
      focusColor: primaryColor.withValues(alpha: 0.14),
      appBarTheme: AppBarTheme(
        backgroundColor: paperColor,
        foregroundColor: inkColor,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        // Титульные AppBar — серифным Prata: «Избранное» набрано
        // тем же шрифтом, что и заголовки страниц. У Prata один
        // вес — вес/трекинг не переопределяются.
        titleTextStyle: TextStyle(
          fontFamily: 'Prata',
          fontSize: 18,
          height: 1.15,
          color: inkColor,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariantColor.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
        indent: 0,
        endIndent: 0,
      ),
      textTheme: text.copyWith(
        // Дисплей — Prata: названия регионов, POI и маршрутов.
        // Единственный серифный акцент, вес не переопределять
        // (у Prata один вес, синтетический bold её портит).
        displayLarge: text.displayLarge?.copyWith(
          fontFamily: 'Prata',
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.1,
          color: inkColor,
          fontSize: 36,
        ),
        displayMedium: text.displayMedium?.copyWith(
          fontFamily: 'Prata',
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.12,
          color: inkColor,
          fontSize: 30,
        ),
        displaySmall: text.displaySmall?.copyWith(
          fontFamily: 'Prata',
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.15,
          color: inkColor,
          fontSize: 24,
        ),
        headlineLarge: text.headlineLarge?.copyWith(
          fontFamily: 'Prata',
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.15,
          color: inkColor,
          fontSize: 22,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontFamily: 'Prata',
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.12,
          color: inkColor,
          fontSize: 20,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontFamily: 'Prata',
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.15,
          color: inkColor,
          fontSize: 18,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.15,
          color: inkColor,
          fontSize: 18,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: inkColor,
          fontSize: 16,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
          color: inkColor,
          fontSize: 14,
        ),
        // Eyebrow — надписи «МАРШРУТ • 2.4 КМ»
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: inkColor.withValues(alpha: 0.7),
          fontSize: 11,
          height: 1.2,
        ),
        labelMedium: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: inkColor.withValues(alpha: 0.7),
          fontSize: 11,
        ),
        labelSmall: text.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          // Мелкие метки >=11 px: alpha >=0.72 держит контраст
          // >=4.5:1 на песочных плашках (B12, P1-1 5-го прохода).
          color: inkColor.withValues(alpha: 0.72),
          fontSize: 11,
          height: 1.2,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          height: 1.62,
          letterSpacing: -0.1,
          color: inkColor.withValues(alpha: 0.87),
          fontSize: 16,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          height: 1.55,
          letterSpacing: 0,
          color: inkColor.withValues(alpha: 0.8),
          fontSize: 14,
        ),
        bodySmall: text.bodySmall?.copyWith(
          letterSpacing: 0.15,
          color: inkColor.withValues(alpha: 0.7),
          fontSize: 12,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: sheetColor,
        shadowColor: isDark
            ? Colors.black.withValues(alpha: 0.4)
            : AppColors.ink.withValues(alpha: 0.08),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: sandColor.withValues(alpha: 0.9),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: sandLightColor,
        side: BorderSide(color: sandColor, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelStyle: text.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: inkColor,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 40,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: isDark ? const Color(0xFF06272B) : AppColors.accentOn,
          elevation: 0,
          shadowColor: isDark
              ? Colors.black.withValues(alpha: 0.3)
              : AppColors.ink.withValues(alpha: 0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          // Подписи кнопок — 14.5 px w800, а не eyebrow-размер
          // labelLarge (11 px): раньше кнопки выглядели мелкими.
          textStyle: AppText.button,
          minimumSize: const Size(88, 44),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: isDark ? const Color(0xFF06272B) : AppColors.accentOn,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: AppText.button,
          minimumSize: const Size(88, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: AppText.button,
          minimumSize: const Size(88, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: AppText.button,
          minimumSize: const Size(64, 40),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: inkColor.withValues(alpha: 0.7),
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          padding: const EdgeInsets.all(12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: palette.accentOn,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sheetColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: sandColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: sandColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: palette.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: palette.error, width: 2),
        ),
        labelStyle: text.bodyMedium?.copyWith(
          color: inkColor.withValues(alpha: 0.6),
        ),
        hintStyle: text.bodyMedium?.copyWith(
          color: mutedColor,
        ),
        errorStyle: text.bodySmall?.copyWith(
          color: palette.error,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheetColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
        modalBackgroundColor: sheetColor,
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sheetColor,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: text.titleLarge?.copyWith(
          color: inkColor,
        ),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: inkColor.withValues(alpha: 0.87),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scrimInkColor.withValues(alpha: 0.92),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: AppColors.onScrim,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scrimInkColor.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(
          color: AppColors.onScrim,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        preferBelow: true,
        verticalOffset: 8,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: sandColor,
        circularTrackColor: sandColor,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: sandColor,
        thumbColor: primaryColor,
        overlayColor: primaryColor.withValues(alpha: 0.12),
        valueIndicatorColor: primaryColor,
        valueIndicatorTextStyle: text.bodySmall?.copyWith(
          color: isDark ? const Color(0xFF06272B) : AppColors.accentOn,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: mutedColor,
        indicatorColor: primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        dividerColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sheetColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: primaryColor.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return text.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: primaryColor,
            );
          }
          return text.labelSmall?.copyWith(
            color: inkColor.withValues(alpha: 0.6),
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sheetColor,
        elevation: 0,
        indicatorColor: primaryColor.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(
          color: primaryColor,
          size: 24,
        ),
        unselectedIconTheme: IconThemeData(
          color: mutedColor,
          size: 24,
        ),
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: text.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: primaryColor,
        ),
        unselectedLabelTextStyle: text.labelSmall?.copyWith(
          color: inkColor.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

/// Ролевая палитра экрана (B1, 8-й проход).
///
/// Архитектура «ночной карты»: набор ролей в ThemeExtension, чтобы
/// переключение на тёмную тему (этап 7, по остатку времени) меняло
/// ОДИН набор, а не все виджеты. Светлая тема — это роли «Ликийского
/// дневника» (surface = бумага, onSurface = чернила); тёмная —
/// перевёрнутая: фон — чернильный #0F2128, текст — пергамент,
/// бирюза светлее, сигнал тот же (e2e).
///
/// Читается как `Theme.of(context).extension<AppPalette>()!` либо
/// `AppPalette.of(context)`; новые виджеты берут цвета отсюда, а не
/// прямыми hex (Colors.white в новом коде запрещён).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surface,
    required this.surfaceRaised,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.accent,
    required this.accentOn,
    this.accentDark = AppColors.signalDark,
    required this.info,
    required this.sand,
    required this.sandLight,
    required this.outline,
    required this.success,
    required this.warning,
    required this.error,
  });

  /// Светлая тема — роли «Ликийского дневника».
  static const AppPalette light = AppPalette(
    surface: AppColors.chart,
    surfaceRaised: AppColors.card,
    onSurface: AppColors.ink,
    onSurfaceMuted: AppColors.onSurfaceMuted,
    accent: AppColors.signal,
    accentOn: Colors.white,
    info: AppColors.depth,
    sand: AppColors.sand,
    sandLight: AppColors.sandLight,
    outline: AppColors.outline,
    success: AppColors.success,
    warning: AppColors.warning,
    error: AppColors.error,
  );

  /// Тёмная тема — «ночной атлас»: глубокий морской фон,
  /// кремовый текст, светлая бирюза, тот же сигнал
  /// (#E85D3F — не меняется, его проверяет e2e).
  static const AppPalette dark = AppPalette(
    surface: Color(0xFF0B1B26),
    surfaceRaised: Color(0xFF132633),
    onSurface: Color(0xFFF5EFE3),
    onSurfaceMuted: Color(0xFFA9BCC4),
    accent: AppColors.signal,
    accentOn: Colors.white,
    // На тёмном фоне «тёмный край» читается только СВЕТЛЕЕ.
    accentDark: Color(0xFFD08568),
    info: Color(0xFF8FB8CE),
    // «Песок» ночной темы: тёмные шаги той же температуры,
    // что песочные плашки дневной.
    sand: Color(0xFF1C2E3A),
    sandLight: Color(0xFF14252F),
    outline: Color(0xFF4E6470),
    success: Color(0xFF81C995),
    warning: Color(0xFFF9A95D),
    error: Color(0xFFF2A69E),
  );

  /// Палитра текущей темы (светлая, пока переключатель не подан).
  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? light;
  }

  final Color surface;

  final Color surfaceRaised;

  final Color onSurface;

  final Color onSurfaceMuted;

  final Color accent;

  final Color accentOn;

  /// Более тёмный край акцента (ободок избранного на карте;
  /// в светлой теме — глубокий терракотовый signalDark).
  final Color accentDark;

  final Color info;

  /// Песочные плашки (бейджи, чипы, подложки).
  final Color sand;

  /// Светлый песок: поверхности контейнеров.
  final Color sandLight;

  final Color outline;

  final Color success;

  final Color warning;

  final Color error;

  @override
  AppPalette copyWith({
    Color? surface,
    Color? surfaceRaised,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? accent,
    Color? accentOn,
    Color? accentDark,
    Color? info,
    Color? sand,
    Color? sandLight,
    Color? outline,
    Color? success,
    Color? warning,
    Color? error,
  }) {
    return AppPalette(
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      accent: accent ?? this.accent,
      accentOn: accentOn ?? this.accentOn,
      // accentDark — тоже (баг 3, замечания Sonnet): при
      // анимированной смене темы ободок избранного получал
      // дефолт signalDark в тёмной теме.
      accentDark: accentDark ?? this.accentDark,
      info: info ?? this.info,
      sand: sand ?? this.sand,
      sandLight: sandLight ?? this.sandLight,
      outline: outline ?? this.outline,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) {
      return this;
    }

    return AppPalette(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised:
          Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted:
          Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentOn: Color.lerp(accentOn, other.accentOn, t)!,
      // accentDark — тоже (баг 3): lerp обязан переносить все поля,
      // иначе анимация смены темы роняет ободок в дефолт.
      accentDark: Color.lerp(accentDark, other.accentDark, t)!,
      info: Color.lerp(info, other.info, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      sandLight: Color.lerp(sandLight, other.sandLight, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}
