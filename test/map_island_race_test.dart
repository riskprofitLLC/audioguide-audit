// Тест быстрого переключения локации на главном экране, пока карта
// ещё грузится (гонка из map_widget.dart / map_camera.dart).
//
// Смена локации происходит ДО завершения загрузки данных карты
// (под FakeAsync стили/тайлы карты не дочитываются — загрузка как
// раз «в полёте»). Раньше сброс состояния карты в этот момент
// пропускался (`_islandId` заполнялся только после загрузки), и
// карта получала камеру/данные прежней локации. Теперь сброс
// привязан к ключу настроенной локации и срабатывает сразу
// (didUpdateWidget + ref.listen), а future загрузки данных
// привязан к локации (KeyedFutureSlot — см. keyed_future_slot_test).
//
// Файл отдельный (первый контент-тест в файле): rootBundle под
// FakeAsync надёжен только в первом тесте, см. AGENTS.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';

import 'support/lazy_scroll.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'смена локации во время загрузки карты не ломает главную',
    (WidgetTester tester) async {
      // Стартуем с Гемилера, затем переключаемся на Бей, НЕ дожидаясь
      // загрузки данных карты (под FakeAsync она не завершается) —
      // сброс состояния карты должен отработать в этом окне.
      //
      // Контент обеих локаций сеем в реальной зоне (паттерн
      // tree_navigation_test): poi.json больше ~50 КБ не грузится
      // под FakeAsync.
      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
      );

      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await container.read(regionsProvider.future);
        await container.read(islandsProvider.future);
        await container.read(trailsFamily('gemiler').future);
        await container.read(poisFamily('gemiler').future);

        // Бей сеем тоже: после переключения контент локации должен
        // полностью появиться, а не зависнуть спиннером.
        await container.read(trailsFamily('bay').future);
        await container.read(poisFamily('bay').future);
      });

      // Будущие ассетов, созданные в зоне runAsync, под FakeAsync не
      // завершаются (колбэки .then идут в зону создания Future).
      // Чистим кеш — холодные дочитывания пойдут уже в зоне теста.
      rootBundle.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Главная жива и показывает Гемилер. Списки ленивые (B15):
      // карточку маршрута подводим в кадр перед проверкой.
      await scrollLazyUntilVisible(
        tester,
        find.text('Маршрут по острову Гемилер'),
      );

      expect(find.text('Маршрут по острову Гемилер'), findsOneWidget);

      // Переключение на Бей — карта (превью на главной) ещё грузит
      // данные, сброс состояния идёт именно «в полёте».
      container.read(currentIslandIdProvider.notifier).state = 'bay';

      await tester.pumpAndSettle();

      // Контент Бея на месте, приложение не показало ошибок.
      expect(container.read(currentIslandIdProvider), 'bay');

      // Списки ленивые (B15): точки Бея подводим в кадр.
      await scrollLazyUntilVisible(
        tester,
        find.text('Город Фетхие'),
      );

      expect(find.text('Город Фетхие'), findsWidgets);

      expect(tester.takeException(), isNull);

      // Обратное переключение: сброс состояния в другую сторону.
      container.read(currentIslandIdProvider.notifier).state = 'gemiler';

      await tester.pumpAndSettle();

      await scrollLazyUntilVisible(
        tester,
        find.text('Маршрут по острову Гемилер'),
      );

      expect(find.text('Маршрут по острову Гемилер'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );
}
