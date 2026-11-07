// Баннер ошибки инициализации на главной (P0-5, 5-й проход):
// человеческий текст вместо сырого '$error', техническая
// деталь — в сворачиваемой строке «Подробнее».

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/providers.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';

import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets('баннер показывает человеческий текст, деталь — по запросу',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        initErrorProvider.overrideWith((ref) => StateError('disk I/O error')),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);
      await container.read(trailsFamily('gemiler').future);
      await container.read(poisFamily('gemiler').future);
    });

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

    // Человекочитаемое сообщение вместо сырого исключения.
    expect(
      find.textContaining('Не удалось открыть базу данных контента'),
      findsOneWidget,
    );

    // Кнопка повтора доступна.
    expect(find.text('Повторить'), findsOneWidget);

    // Сырая деталь скрыта до тапа по «Подробнее».
    expect(find.textContaining('disk I/O error'), findsNothing);

    await tester.tap(find.text('Подробнее'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bad state: disk I/O error'), findsOneWidget);
  });
}
