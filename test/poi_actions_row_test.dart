// A7 (9-й проход): ряд действий POI — Wrap на узких экранах.
//
// 320 px при textScale 1.6: «Поделиться» виден (раньше уезжал за
// край горизонтального скролла без подсказки), переполнения нет,
// высота ряда единая.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/presentation/pages/poi_detail_page.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('ряд действий на 320 px: Wrap, «Поделиться» виден (A7)',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(poisFamily('gemiler').future);
    });

    rootBundle.clear();

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) {
            // textScale clamp как в приложении (1.6, 6-й проход).
            final media = MediaQuery.of(context);

            return MediaQuery(
              data: media.copyWith(
                textScaler: media.textScaler.clamp(
                  minScaleFactor: 1.0,
                  maxScaleFactor: 1.6,
                ),
              ),
              child: child!,
            );
          },
          home: const PoiDetailPage(
            poiId: 'poi-06',
            islandId: 'gemiler',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Все действия ряда построены и доступны (Wrap переносит,
    // а не прячет за краем). Второй «Поделиться» — в шапке,
    // сверяемся именно с рядом действий.
    expect(find.text('Слушать'), findsOneWidget);
    expect(find.text('На карте'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('detail-actions-row')),
        matching: find.text('Погода'),
      ),
      findsOneWidget,
      reason: 'кнопка погоды точки живёт в ряду действий',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('detail-actions-row')),
        matching: find.byTooltip('Поделиться'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('detail-actions-row')),
        matching: find.byKey(const ValueKey('favorite-button')),
      ),
      findsOneWidget,
    );

    // Все кнопки ряда — одной высоты 44 (A7/B5): Material-дефолт 40
    // ниже тап-цели проекта.
    final listenHeight = tester.getSize(
      find.widgetWithText(FilledButton, 'Слушать'),
    ).height;

    expect(tester.takeException(), isNull,
        reason: 'Wrap не переполняет 320 px при textScale 1.6');

    // «Поделиться» в пределах экрана, а не уехавшим за кромку.
    final share = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('detail-actions-row')),
        matching: find.byTooltip('Поделиться'),
      ),
    );

    expect(share.right, lessThanOrEqualTo(320),
        reason: 'кнопка не выходит за правый край');

    // Высоты ряда: Filled «Слушать» и иконка «Поделиться» —
    // не ниже 44 (при textScale 1.6 кнопка растёт выше).
    expect(listenHeight, greaterThanOrEqualTo(44),
        reason: 'кнопки ряда — тап-цель не ниже 44 (A7/B5)');

    expect(share.height, greaterThanOrEqualTo(44),
        reason: 'иконка «Поделиться» — тап-цель не ниже 44');
  });
}
