// StickyAppBar: липкая шапка страниц деталей. Заголовочная часть
// (контролы) видна только при showTitle, а «назад»-пилюля — всегда;
// звезда/шеринг/дерево зовут свои колбэки.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/core/widgets/sticky_app_bar.dart';

Widget wrap({
  required bool showTitle,
  required bool isFavorite,
  VoidCallback? onBack,
  VoidCallback? onFavorite,
  VoidCallback? onShare,
  VoidCallback? onTree,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 200,
        child: StickyAppBar(
          showTitle: showTitle,
          title: 'Бухта',
          onBack: onBack ?? () {},
          onFavorite: onFavorite ?? () {},
          onShare: onShare ?? () {},
          onTree: onTree ?? () {},
          isFavorite: isFavorite,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('без showTitle контролы шапки скрыты', (tester) async {
    await tester.pumpWidget(wrap(showTitle: false, isFavorite: false));
    await tester.pumpAndSettle();

    // заголовочный блок гаснет (opacity 0) и не ловит тапы
    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(opacity.opacity, 0);
    expect(find.text('Бухта'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('с showTitle заголовок и контролы на месте', (tester) async {
    await tester.pumpWidget(wrap(showTitle: true, isFavorite: false));
    await tester.pumpAndSettle();

    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(opacity.opacity, 1);
    expect(find.text('Бухта'), findsOne);
    expect(find.byTooltip('Поделиться'), findsOne);
    expect(find.byTooltip('Навигация по проекту'), findsOne);
  });

  testWidgets('пилюля «назад» видна всегда и зовёт onBack', (tester) async {
    var back = 0;
    await tester.pumpWidget(
      wrap(showTitle: false, isFavorite: false, onBack: () => back++),
    );
    await tester.pumpAndSettle();

    // пилюля «назад» — круг 44 с семантикой; в этом режиме
    // chevronLeft в дереве один (только пилюля)
    // chevronLeft в дереве два: пилюля + кнопка заголовка (та гаснет)
    expect(find.byIcon(LucideIcons.chevronLeft), findsNWidgets(2));
    final node = tester.getSemantics(find.byIcon(LucideIcons.chevronLeft).last);
    expect(node.label, contains('Назад'));

    await tester.tap(find.byIcon(LucideIcons.chevronLeft).last);
    expect(back, 1);
  });

  testWidgets('звезда избранного зовёт onFavorite', (tester) async {
    var fav = 0;
    await tester.pumpWidget(
      wrap(showTitle: true, isFavorite: false, onFavorite: () => fav++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('В избранное'));
    expect(fav, 1);
  });

  testWidgets('шеринг и дерево зовут свои колбэки', (tester) async {
    var shares = 0;
    var trees = 0;
    await tester.pumpWidget(
      wrap(
        showTitle: true,
        isFavorite: false,
        onShare: () => shares++,
        onTree: () => trees++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.share2));
    await tester.tap(find.byIcon(LucideIcons.listTree));
    expect(shares, 1);
    expect(trees, 1);
  });

  testWidgets('в избранном тултип звезды меняется', (tester) async {
    await tester.pumpWidget(wrap(showTitle: true, isFavorite: true));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Убрать из избранного'), findsOne);
  });
}
