// Дерево навигации открывается ПОЛНОСТЬЮ свёрнутым (замечание
// владельца, 11.2026): ни один узел не раскрыт по умолчанию.
//
// Раньше панель была раскрыта целиком: первое открытие дерева
// подписывалось на poisFamily/trailsFamily ВСЕХ 9 локаций — на
// native это холодный сидинг всех пакетов (bay — 122 КБ).
// Теперь любой контент грузится лениво при раскрытии узла.
//
// Детектор: ProviderObserver фиксирует создание членов семей
// poisFamily/trailsFamily — при открытии дерева новых быть не
// должно; раскрытие локации создаёт её провайдеры лениво.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/core/widgets.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/navigation/presentation/tree_navigation_button.dart';

import 'support/test_database.dart';

/// Запоминает создание контентных провайдеров (паттерн
/// search_index_no_seeding_test): у членов семей в Riverpod 2 имя
/// пустое — различаем по типу.
class _FamilySpy extends ProviderObserver {
  final List<String> created = [];

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    final type = provider.runtimeType.toString();

    if (type.contains('FutureProvider<List<Poi>>')) {
      created.add('pois');
    } else if (type.contains('FutureProvider<List<Trail>>')) {
      created.add('trails');
    } else if (type.contains('MapDataRepository')) {
      created.add('repo');
    }
  }
}

void main() {
  initTestDatabase();

  testWidgets(
    'открытие дерева не создаёт провайдеры свёрнутых локаций (A6)',
    (WidgetTester tester) async {
      final spy = _FamilySpy();

      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
        observers: [spy],
      );

      addTearDown(container.dispose);

      // Греем ТОЛЬКО текущую локацию (остальные — как на реальном
      // старте: холодные).
      await tester.runAsync(() async {
        await container.read(regionsProvider.future);
        await container.read(islandsProvider.future);
        await container.read(poisFamily('gemiler').future);
        await container.read(trailsFamily('gemiler').future);
      });

      rootBundle.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IslandGuideApp(),
        ),
      );

      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      // Главная и превью карты создали провайдеры gemiler.
      final beforeTree = spy.created.length;

      expect(beforeTree, greaterThan(0));

      // Открываем дерево: свёрнутые локации НЕ подписываются на
      // контент — новых провайдеров быть не должно.
      final treeButton = find.byType(TreeNavigationButton);

      await tester.ensureVisible(treeButton);
      await tester.tap(treeButton);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(
        spy.created.length,
        beforeTree,
        reason: 'полностью свёрнутое дерево не будит '
            'контентные провайдеры',
      );

      // Раскрытие СВЁРНУТОГО региона — строки локаций из статичного
      // каталога, контентные провайдеры не создаются.
      final lykiaRegion = find.byKey(const ValueKey('tree-region-lykia'));

      await tester.ensureVisible(lykiaRegion);
      await tester.pumpAndSettle();
      await tester.tap(lykiaRegion);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tree-lykia/kekova')), findsOneWidget);

      expect(
        spy.created.length,
        beforeTree,
        reason: 'строки локаций — из статичного каталога, без контента',
      );

      // Раскрытие локации — ленивая загрузка её контента.
      // Под FakeAsync холодная загрузка не завершается
      // (крупный poi.json), поэтому детерминистичный маркер —
      // создание контентных провайдеров и скелетон загрузки.
      final kekovaRow = find.byKey(const ValueKey('tree-lykia/kekova'));

      await tester.ensureVisible(kekovaRow);
      await tester.pumpAndSettle();
      await tester.tap(kekovaRow);
      await tester.pumpAndSettle();

      expect(
        spy.created.length,
        greaterThan(beforeTree),
        reason: 'раскрытие локации лениво создаёт её провайдеры',
      );

      expect(
        find.byType(SkeletonRow),
        findsWidgets,
        reason: 'контент раскрытой локации грузится (скелетон)',
      );
    },
  );
}
