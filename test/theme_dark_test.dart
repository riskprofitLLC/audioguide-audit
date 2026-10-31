// B5 (11-й проход): тёмная тема собирается и несёт AppPalette.dark;
// светлая после параметризации билдера НЕ изменилась — роли те же.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/theme.dart';

void main() {
  test('светлая тема: роли «Ликийского дневника» на месте (регрессия B5)',
      () {
    final theme = AppTheme.light;

    expect(theme.scaffoldBackgroundColor, AppColors.chart);
    expect(theme.colorScheme.surface, AppColors.card);
    expect(theme.colorScheme.onSurface, AppColors.ink);
    expect(theme.colorScheme.primary, AppColors.brandPrimary);
    expect(theme.colorScheme.onPrimary, AppColors.accentOn);
    expect(theme.colorScheme.errorContainer, AppColors.errorContainer);
    expect(theme.appBarTheme.backgroundColor, AppColors.chart);
    expect(theme.bottomSheetTheme.backgroundColor, AppColors.card);

    final palette = theme.extension<AppPalette>();

    expect(palette, isNotNull);
    expect(palette!.surface, AppColors.chart);
    expect(palette.sand, AppColors.sand);
    expect(palette.sandLight, AppColors.sandLight);
    expect(palette.onSurface, AppColors.ink);
  });

  test('тёмная тема: чернильный фон, пергаментный текст, AppPalette.dark (B5)',
      () {
    final theme = AppTheme.dark;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppPalette.dark.surface);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0B1B26));
    expect(theme.colorScheme.onSurface, AppPalette.dark.onSurface);
    expect(theme.colorScheme.surface, AppPalette.dark.surfaceRaised);

    final palette = theme.extension<AppPalette>();

    expect(palette, AppPalette.dark);
    expect(palette!.onSurface, const Color(0xFFF5EFE3));
    expect(palette.sandLight, const Color(0xFF14252F));

    // Кнопки в ночи: светлая бирюза + тёмная подпись (D3:
    // пергамент на светлой бирюзе давал 2.6:1 — тёмный
    // чернильный держит AA).
    expect(theme.colorScheme.primary, AppPalette.dark.info);
    expect(theme.colorScheme.onPrimary, const Color(0xFF06272B));
  });

  test('lerp переносит ВСЕ поля, включая accentDark (баг 3, замечания '
      'Sonnet)', () {
    // t=1: анимированная смена темы обязана закончиться ТОЧНО
    // тёмной палитрой — раньше accentDark выпадал из lerp и
    // ободок избранного сбрасывался в дефолт signalDark.
    final lerped = AppPalette.light.lerp(AppPalette.dark, 1.0);

    expect(lerped.surface, AppPalette.dark.surface);
    expect(lerped.surfaceRaised, AppPalette.dark.surfaceRaised);
    expect(lerped.onSurface, AppPalette.dark.onSurface);
    expect(lerped.onSurfaceMuted, AppPalette.dark.onSurfaceMuted);
    expect(lerped.accent, AppPalette.dark.accent);
    expect(lerped.accentOn, AppPalette.dark.accentOn);
    expect(lerped.accentDark, AppPalette.dark.accentDark);
    expect(lerped.info, AppPalette.dark.info);
    expect(lerped.sand, AppPalette.dark.sand);
    expect(lerped.sandLight, AppPalette.dark.sandLight);
    expect(lerped.outline, AppPalette.dark.outline);
    expect(lerped.success, AppPalette.dark.success);
    expect(lerped.warning, AppPalette.dark.warning);
    expect(lerped.error, AppPalette.dark.error);

    // t=0 — светлая.
    final zero = AppPalette.light.lerp(AppPalette.dark, 0.0);

    expect(zero.accentDark, AppPalette.light.accentDark);
    expect(zero.accentDark, AppColors.signalDark);

    // Середина — честный lerp accentDark, а не дефолт.
    final mid = AppPalette.light.lerp(AppPalette.dark, 0.5);

    expect(
      mid.accentDark,
      Color.lerp(
        AppPalette.light.accentDark,
        AppPalette.dark.accentDark,
        0.5,
      ),
    );
  });

  test('copyWith без аргументов сохраняет accentDark (баг 3)', () {
    final copied = AppPalette.dark.copyWith();

    expect(copied.accentDark, AppPalette.dark.accentDark);

    final overridden = AppPalette.dark.copyWith(
      accentDark: const Color(0xFF123456),
    );

    expect(overridden.accentDark, const Color(0xFF123456));
  });
}
