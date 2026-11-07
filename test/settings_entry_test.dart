// Вход в настройки (P0-3, 6-й проход): иконка доступна в ОБЕИХ
// состояниях «Избранного» (в пустом раньше её не было — автогид
// нельзя было выключить, не добавив ничего в избранное), плюс
// тихая строка «Настройки» внизу списка главной.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/favorites/presentation/favorites_page.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';
import 'package:island_guide/features/settings/presentation/settings_sheet.dart';

import 'support/lazy_scroll.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('настройки доступны из пустого избранного и с главной',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
      ],
    );

    addTearDown(container.dispose);

    // Контент Гемилера грузим в реальной асинхронности — паттерн
    // tree_navigation_test (см. AGENTS.md).
    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);
      await container.read(trailsFamily('gemiler').future);
      await container.read(poisFamily('gemiler').future);
    });

    rootBundle.clear();

    // --- Пустое избранное: иконка настроек в AppBar есть ---
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FavoritesPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Пока ничего не добавлено'), findsOneWidget,
        reason: 'избранное пусто — пустое состояние');

    final settingsIcon = find.byTooltip('Настройки');

    expect(settingsIcon, findsOneWidget,
        reason: 'в пустом избранном тоже есть вход в настройки');

    await tester.tap(settingsIcon);
    await tester.pumpAndSettle();

    // Открылась шторка настроек: заголовок и переключатель
    // автогида.
    expect(find.byType(SettingsSheet), findsOneWidget);

    expect(find.text('Автогид'), findsOneWidget);

    // Закрываем тапом по скриму (кнопки закрытия у шторки нет).
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsNothing);

    // --- Главная: тихая строка «Настройки» внизу списка ---
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomePage()),
      ),
    );

    await tester.pumpAndSettle();

    await scrollLazyUntilVisible(
      tester,
      find.text('Настройки'),
    );

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsOneWidget,
        reason: 'строка «Настройки» внизу главной открывает шторку');
  });
}
