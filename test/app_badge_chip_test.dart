import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/theme.dart';
import 'package:island_guide/core/widgets/app_badge.dart';
import 'package:island_guide/core/widgets/app_chip.dart';

/// Единые бейджи и чипы «Атласа» (этап B): варианты, тап-цели и
/// семантика. Проверяем инварианты, а не пиксели.

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  group('AppBadge', () {
    testWidgets('варианты info/sand/scrim различаются заливкой', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              AppBadge(label: '№ 5', variant: AppBadgeVariant.info),
              AppBadge(label: 'Бухта'),
              AppBadge(label: '2,4 КМ', variant: AppBadgeVariant.scrim),
            ],
          ),
        ),
      );

      final boxes = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .toList();

      final colors = boxes
          .map((c) => (c.decoration as BoxDecoration).color)
          .whereType<Color>()
          .toList();

      expect(colors.contains(AppPalette.light.info), isTrue);
      expect(colors.contains(AppPalette.light.sandLight), isTrue);
      expect(colors.length, greaterThanOrEqualTo(3));
    });

    testWidgets('CAPS-подпись и глиф рисуются одной строкой', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppBadge(
            label: 'ПО ВОДЕ',
            variant: AppBadgeVariant.info,
            icon: Icons.sailing,
            caps: true,
          ),
        ),
      );

      expect(find.text('ПО ВОДЕ'), findsOneWidget);
      expect(find.byIcon(Icons.sailing), findsOneWidget);
    });

    testWidgets('семантическая метка переопределяется', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppBadge(
            label: '7',
            variant: AppBadgeVariant.info,
            semanticLabel: 'Точка 7',
          ),
        ),
      );

      final data = tester
          .getSemantics(find.text('7'))
          .getSemanticsData();

      expect(data.label, startsWith('Точка 7'));
    });
  });

  group('AppChip', () {
    testWidgets('тап-цель чипа ≥44 по высоте', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppChip(
            label: 'Фетхие',
            onTap: () {},
          ),
        ),
      );

      final rect = tester.getRect(find.byType(AppChip));

      expect(rect.height, greaterThanOrEqualTo(44));
    });

    testWidgets('выбранный чип — семантика selected', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppChip(
            label: 'Гемилер',
            selected: true,
            onTap: () {},
          ),
        ),
      );

      final data = tester
          .getSemantics(find.text('Гемилер'))
          .getSemanticsData();

      expect(data.flagsCollection.isSelected.toBoolOrNull(), isTrue,
          reason: 'выбранный чип объявляется скринридеру как selected');
    });

    testWidgets('статический мета-чип без onTap не является кнопкой',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppChip(
            label: 'аудио 6:33',
            icon: Icons.headphones,
            dense: true,
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.text('аудио 6:33'), findsOneWidget);
    });

    testWidgets('тёмная тема: выбранный чип берёт onInfo, не белый',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: AppChip(label: 'Кекова', selected: true, onTap: () {}),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('Кекова'));

      // Ночь: info светлая (#8FB8CE), текст на ней — тёмный onInfo.
      expect(text.style?.color, AppPalette.dark.onInfo);
    });
  });
}
