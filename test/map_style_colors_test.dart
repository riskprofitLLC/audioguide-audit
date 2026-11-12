// Решение владельца: карта не затемняется вместе с тёмной темой
// приложения — палитра слоёв офлайн-карты ВСЕГДА светлая.
//
// Раньше здесь жила проверка реактивности `_PlatformBrightnessNotifier`
// (ночная карта следовала за темой телефона); наблюдатель яркости
// удалён вместе с ночной палитрой карты, поэтому тесты переписаны на
// инвариант «карта одна при любой теме».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/config/offline_map_style.dart';
import 'package:island_guide/features/map/providers/map_provider.dart';
import 'package:island_guide/features/settings/providers/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('палитра карты светлая в любой теме приложения', (tester) async {
    final container = ProviderContainer();

    try {
      // Дефолт (настройка темы не записана).
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(container.read(mapStyleColorsProvider), MapStyleColors.light);

      for (final mode in ThemeMode.values) {
        container.read(themeModeProvider.notifier).setMode(mode);

        await tester.pump(const Duration(milliseconds: 50));

        expect(
          container.read(mapStyleColorsProvider),
          MapStyleColors.light,
          reason: 'режим темы $mode не должен затемнять карту',
        );
      }
    } finally {
      container.dispose();

      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('тёмная тема платформы не меняет карту', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;

    final container = ProviderContainer();

    try {
      container.read(themeModeProvider.notifier).setMode(ThemeMode.system);

      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(mapStyleColorsProvider), MapStyleColors.light);

      // Смена темы телефона на светлую и обратно — карта та же.
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;

      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(mapStyleColorsProvider), MapStyleColors.light);

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;

      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(mapStyleColorsProvider), MapStyleColors.light);
    } finally {
      container.dispose();

      await tester.pump(const Duration(milliseconds: 50));

      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();

      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
