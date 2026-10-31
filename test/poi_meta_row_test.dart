// A6 (11-й проход): у точки без категории, аудио и времени
// чтения мета-строка не рисует пустой Text — остаётся только
// кнопка «Подробнее» с координатами.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/models/poi.dart';
import 'package:island_guide/features/poi/presentation/pages/poi_detail_page.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('пустая мета-строка: без текста, координаты доступны (A6)',
      (tester) async {
    // POI без категории, без аудио, описание короче 30 слов —
    // ни одной меты для строки «категория · аудио · чтение».
    final bare = const Poi(
      id: 'poi-99',
      title: 'Безымянный мыс',
      latitude: 36.55,
      longitude: 29.07,
      description: 'Короткое описание точки.',
    );

    final container = ProviderContainer(
      overrides: [
        poisFamily('gemiler').overrideWith((ref) async => [bare]),
      ],
    );

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PoiDetailPage(
            poiId: 'poi-99',
            islandId: 'gemiler',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Безымянный мыс'), findsOneWidget);

    // Ни одного пустого Text — раньше здесь жил Text('') из
    // parts.join(' · ') при пустой мете (A6).
    final emptyTexts = find.byWidgetPredicate(
      (w) => w is Text && (w.data?.isEmpty ?? false),
    );

    expect(
      emptyTexts,
      findsNothing,
      reason: 'мета-строка без данных не рисует пустой Text (A6)',
    );

    // Кнопка координат на месте — единственный способ увидеть
    // «Подробнее» с координатами.
    final coordsButton = find.byTooltip('Координаты точки');

    expect(coordsButton, findsOneWidget);

    await tester.ensureVisible(coordsButton);
    await tester.tap(coordsButton);
    await tester.pumpAndSettle();

    // Координаты раскрылись, есть копирование.
    expect(find.textContaining('36.55'), findsOneWidget);
    expect(find.text('Скопировать'), findsOneWidget);
  });
}
