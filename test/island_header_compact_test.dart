// Шапка главной компактна по высоте (замечание владельца: блок с
// заголовком региона занимал большую часть экрана): издание —
// подписью в подстроке, заголовок — h1 одной строкой на телефоне.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/theme.dart';
import 'package:island_guide/features/home/presentation/widgets/island_header.dart';

void main() {
  testWidgets('шапка региона: подстрока с изданием и заголовок в одну строку',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: IslandHeader(
              islandName: 'Залив Фетхие',
              eyebrow: 'СРЕДИЗЕМНОЕ МОРЕ · ТУРЦИЯ',
              version: 2,
              action: SizedBox(width: 44, height: 44),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Издание — подпись в подстроке, отдельной пилюли нет.
    expect(find.text('Изд. 2'), findsOneWidget);

    // Подстрока и заголовок на одной вертикали: море и издание
    // стоят в одном ряду.
    final eyebrowRect =
        tester.getRect(find.text('СРЕДИЗЕМНОЕ МОРЕ · ТУРЦИЯ'));

    final editionRect = tester.getRect(find.text('Изд. 2'));

    expect(
      (editionRect.center.dy - eyebrowRect.center.dy).abs(),
      lessThan(2),
      reason: 'издание — в подстроке рядом с морем, не вторым рядом',
    );

    // Заголовок на телефоне — ОДНА строка h1 (28 px), а не две
    // строки display (40 px).
    final titleRect = tester.getRect(find.text('Залив Фетхие'));

    expect(titleRect.height, lessThan(40));

    // Вся шапка компактна: подстрока (с тап-целью кнопки 44) +
    // заголовок одной строкой. Прежняя шапка с пилюлей издания и
    // двухстрочным display занимала ~150 px.
    final headerRect = tester.getRect(find.byType(IslandHeader));

    expect(
      headerRect.height,
      lessThanOrEqualTo(96),
      reason: 'шапка не должна занимать большую часть экрана',
    );
  });

  testWidgets('без версии в подстроке — офлайн-пакет', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: IslandHeader(
            islandName: 'Кария',
            version: null,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('офлайн-пакет'), findsOneWidget);
  });
}
