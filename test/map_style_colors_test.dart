// Баг 1 (замечания Sonnet): _PlatformBrightnessNotifier.
//
// 1. Раньше класс «implements WidgetsBindingObserver» закрывал все
//    коллбэки через noSuchMethod, возвращающий null: didPopRoute
//    (Future<bool>) и didRequestAppExit при системном «Назад»
//    давали TypeError. Теперь наблюдатель — миксин, дефолты
//    коллбэков штатные.
// 2. Провайдер яркости платформы реактивен: при ThemeMode.system
//    палитра карты (mapStyleColorsProvider) следует за сменой
//    светлой/тёмной темы телефона без перезапуска.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/config/offline_map_style.dart';
import 'package:island_guide/features/map/providers/map_provider.dart';
import 'package:island_guide/features/settings/providers/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('системный «Назад» не роняет наблюдателя тем (TypeError)',
      (tester) async {
    final container = ProviderContainer();

    try {
      // Чтение стиля карты регистрирует наблюдателя платформенной
      // яркости (дефолт темы — светлая, настройка не записана).
      expect(container.read(themeModeProvider), ThemeMode.light);

      expect(
        container.read(mapStyleColorsProvider),
        MapStyleColors.light,
      );

      // Системный «Назад»: наблюдатель в списке binding'а — его
      // didPopRoute обязан вернуть штатный Future(false), а не
      // упасть TypeError-ом из noSuchMethod.
      final handled = await tester.binding.handlePopRoute();

      expect(handled, isFalse);

      await tester.pump(const Duration(milliseconds: 50));
    } finally {
      container.dispose();

      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('палитра карты следует за яркостью платформы (system)',
      (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;

    final container = ProviderContainer();

    try {
      // Явный выбор «Системная» — только тогда палитра карты
      // следует за темой телефона (дефолт приложения — светлая).
      container.read(themeModeProvider.notifier).setMode(ThemeMode.system);

      expect(container.read(mapStyleColorsProvider), MapStyleColors.dark);

      // Смена темы телефона на светлую — без перезапуска.
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;

      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(mapStyleColorsProvider), MapStyleColors.light);

      // …и обратно в тёмную.
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;

      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(mapStyleColorsProvider), MapStyleColors.dark);
    } finally {
      container.dispose();

      await tester.pump(const Duration(milliseconds: 50));

      tester.binding.platformDispatcher
          .clearPlatformBrightnessTestValue();

      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('режимы light/dark не зависят от платформы', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;

    final container = ProviderContainer();

    try {
      container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(mapStyleColorsProvider), MapStyleColors.light);

      container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(mapStyleColorsProvider), MapStyleColors.dark);
    } finally {
      container.dispose();

      await tester.pump(const Duration(milliseconds: 50));

      tester.binding.platformDispatcher
          .clearPlatformBrightnessTestValue();

      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
