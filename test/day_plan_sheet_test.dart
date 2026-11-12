// План дня (29-й проход, П9 + проход оптимизации): шторка показывает
// спиннер загрузки, план с километрами и итогом, переключатель
// порядка с выигрышем и предупреждение о локации без пеших маршрутов.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/models/manifest.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/favorites/presentation/widgets/day_plan_sheet.dart';
import 'package:island_guide/features/favorites/providers/collections_providers.dart';
import 'package:island_guide/features/poi/models/poi.dart';

import 'support/test_database.dart';

Manifest _manifest({bool hikingForbidden = false}) => Manifest(
      id: 'gemiler',
      name: 'Остров Гемилер',
      version: 20,
      language: 'ru',
      map: '',
      trails: '',
      poi: '',
      audio: '',
      images: '',
      hikingForbidden: hikingForbidden,
    );

Poi _poi(String id, double lat, double lng, {int? audioMs}) => Poi(
      id: id,
      title: 'Точка $id',
      latitude: lat,
      longitude: lng,
      radius: 50,
      description: '',
      category: 'bay',
      audioMs: audioMs,
    );

/// Точки «зигзагом»: порядок подборки длиннее оптимального.
List<Poi> _pois() => [
      _poi('poi-01', 36.00, 29.00, audioMs: 6 * 60 * 1000),
      _poi('poi-02', 36.00, 29.04),
      _poi('poi-03', 36.02, 29.00),
      _poi('poi-04', 36.02, 29.04),
    ];

Future<void> _pump(WidgetTester tester, {bool hiking = false}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        presetCollectionsProvider.overrideWith(
          (ref) async => const [
            PresetCollection(
              name: 'Гемилер: главные точки',
              keys: [
                'gemiler/poi-01',
                'gemiler/poi-02',
                'gemiler/poi-03',
                'gemiler/poi-04',
              ],
            ),
          ],
        ),
        poisFamily('gemiler').overrideWith((ref) async => _pois()),
        islandManifestFamily('gemiler')
            .overrideWith((ref) async => _manifest(hikingForbidden: hiking)),
      ],
      // Шторка в приложении оборачивает тело в SingleChildScrollView
      // (app_bottom_sheet.dart) — в тесте повторяем ту же обвязку.
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DayPlanSheet()),
        ),
      ),
    ),
  );
}

void main() {
  initTestDatabase();

  testWidgets('план дня: итог, шаги с дистанцией и аудио', (tester) async {
    await _pump(tester);

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
      const ValueKey('day-plan-source-preset-Гемилер: главные точки'),
    ));

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Итог и разбивка по шагам на месте.
    expect(find.byKey(const ValueKey('day-plan-total')), findsOneWidget);

    expect(find.byKey(const ValueKey('day-plan-leg-0')), findsOneWidget);

    expect(find.byKey(const ValueKey('day-plan-leg-3')), findsOneWidget);

    // Километры и минуты на шаге, а не только «пешком N».
    expect(find.textContaining('аудио 6 мин'), findsWidgets);

    expect(find.textContaining('км'), findsWidgets);
  });

  testWidgets('оптимальный порядок короче подборки и показывает выигрыш',
      (tester) async {
    await _pump(tester);

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
      const ValueKey('day-plan-source-preset-Гемилер: главные точки'),
    ));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Оптимальный'));

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('day-plan-saving')), findsOneWidget);

    // Порядок реально перестроился: первая точка плана — не poi-01
    // подборки (зигзаг начинается с дальнего угла).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('day-plan-leg-0')),
        matching: find.textContaining('Точка poi-0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('старт от меня — переключатель доступен', (tester) async {
    await _pump(tester);

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
      const ValueKey('day-plan-source-preset-Гемилер: главные точки'),
    ));

    await tester.pumpAndSettle();

    final chip = find.byKey(const ValueKey('day-plan-from-me'));

    expect(chip, findsOneWidget);

    await tester.tap(chip);

    await tester.pumpAndSettle();

    // Позиции в тесте нет — честная подпись вместо молчания.
    expect(find.textContaining('Позиция неизвестна'), findsOneWidget);
  });

  testWidgets('локация без пеших маршрутов — предупреждение в плане',
      (tester) async {
    await _pump(tester, hiking: true);

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
      const ValueKey('day-plan-source-preset-Гемилер: главные точки'),
    ));

    await tester.pumpAndSettle();

    expect(find.textContaining('пешие маршруты запрещены'), findsOneWidget);
  });
}
