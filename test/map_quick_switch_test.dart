// Тест быстрого двойного переключения острова на главном экране.
//
// Проверяет, что два последовательных смены currentIslandIdProvider
// без pump между ними (имитация реальной гонки пользователя) не
// застревают на промежуточном острове и не бросают исключений.
//
// Файл отдельный, чтобы быть ПЕРВЫМ контент-тестом: rootBundle.loadString
// под FakeAsync надёжен только в первом тесте файла (см. AGENTS.md).

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
    'двойное быстрое переключение острова не оставляет карту в гонке',
    (WidgetTester tester) async {
      // Стартуем с Гемилера, затем дважды меняем остров ПОДРЯД без
      // pump между сменами — имитация гонки _dataFuture: первый остров
      // ещё не успел показаться, а второй уже должен. Сброс оверлеев
      // (_resetOverlaysIfIslandChanged) обнуляет _dataFuture; старый
      // Future может ещё висеть в _ensureFitData/_loadOverlays, но его
      // результат не должен примениться к новому острову.
      //
      // poi.json Гемилера (~55 КБ) не грузится под FakeAsync (порог
      // ~50 КБ, см. AGENTS.md), поэтому контент сеем в runAsync и
      // читаем из кеша провайдеров (паттерн tree_navigation_test).
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

      // Два переключения подряд: bay -> gemiler, без пауз.
      // bay/poi.json большой и под FakeAsync не грузится —
      // гонка получается «застывшей», что и проверяем.
      container.read(currentIslandIdProvider.notifier).state = 'bay';
      container.read(currentIslandIdProvider.notifier).state = 'gemiler';

      await tester.pumpAndSettle();

      // Финальное состояние — последний выбранный остров, а не
      // застрявшая гонка на промежуточном bay.
      expect(
        container.read(currentIslandIdProvider),
        'gemiler',
      );

      // Контент Гемилера на месте, приложение не показало ошибок.
      // Списки теперь ленивые (B15): карточка маршрута строится
      // при подведении в кадр — прокручиваем к ней.
      await scrollLazyUntilVisible(
        tester,
        find.text('Маршрут по острову Гемилер'),
      );

      expect(find.text('Маршрут по острову Гемилер'), findsOneWidget);
    },
  );
}
