import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/theme.dart';

/// WCAG-контраст ключевых пар палитры (B5, замечания Sonnet).
///
/// Считается по формуле relative luminance из WCAG 2.1:
///   L = 0.2126·R + 0.7152·G + 0.0722·B, где каналы линейные
///   (sRGB → линейный по порогу 0.03928).
/// Контраст = (Lmax + 0.05) / (Lmin + 0.05).
///
/// Пороги: ≥4.5:1 для обычного текста, ≥3:1 для значимой графики
/// (крупный текст, иконки-индикаторы, обводки, маркеры).

double _channel(double v) {
  final c = v / 255.0;

  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(int argb) {
  final r = ((argb >> 16) & 0xFF).toDouble();
  final g = ((argb >> 8) & 0xFF).toDouble();
  final b = (argb & 0xFF).toDouble();

  return 0.2126 * _channel(r) +
      0.7152 * _channel(g) +
      0.0722 * _channel(b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a.toARGB32());
  final lb = _luminance(b.toARGB32());

  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;

  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('контраст палитры', () {
    for (final entry in {
      'light': AppPalette.light,
      'dark': AppPalette.dark,
    }.entries) {
      final name = entry.key;
      final palette = entry.value;

      test('$name: onSurface/surface — текст ≥4.5:1', () {
        expect(
          _contrast(palette.onSurface, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('$name: onSurfaceMuted на surface/surfaceRaised/sandLight '
          '— текст ≥4.5:1', () {
        for (final bg in [
          palette.surface,
          palette.surfaceRaised,
          palette.sandLight,
        ]) {
          expect(
            _contrast(palette.onSurfaceMuted, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'onSurfaceMuted на $bg',
          );
        }
      });

      test('$name: onInfo/info — текст ≥4.5:1', () {
        expect(
          _contrast(palette.onInfo, palette.info),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('$name: accentOn/accent — графика ≥3:1', () {
        expect(
          _contrast(palette.accentOn, palette.accent),
          greaterThanOrEqualTo(3.0),
        );
      });

      // accentDark/accent — «ободок на заливке» (избранное на
      // карте): обе роли внутри одного шарика различаются формой и
      // смещением, а не контрастом текста — WCAG-порог неприменим,
      // намеренно не проверяем.
    }

    test('текст акцентом читаем в обеих темах (B3)', () {
      // Текст ошибки/«не верно» идёт ролью error — проверяем её на
      // бумаге и на ночной поверхности.
      for (final palette in [AppPalette.light, AppPalette.dark]) {
        expect(
          _contrast(palette.error, palette.surface),
          greaterThanOrEqualTo(4.5),
        );

        expect(
          _contrast(palette.error, palette.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );

        expect(
          _contrast(palette.success, palette.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('сигнал #E85D3F как графика читаем в обеих темах', () {
      // Сам signal остаётся цветом ЗАЛИВОК и маркеров (e2e), но как
      // значимая графика он обязан давать ≥3:1 к фону.
      for (final palette in [AppPalette.light, AppPalette.dark]) {
        expect(
          _contrast(AppColors.signal, palette.surface),
          greaterThanOrEqualTo(3.0),
        );
      }
    });
  });
}
