// Поведение звезды избранного (P0-4, 5-й проход):
// pop-анимация и haptic — только по тапу пользователя
// (сигнал из onPressed контейнера), а не при смене `filled`
// из данных (подгрузка избранного при старте раньше
// «вибрировала» списком и мигала десятком звёзд).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/content_tile.dart';
import 'package:island_guide/features/favorites/presentation/widgets/favorite_star.dart';

void main() {
  testWidgets('смена filled без тапа не даёт ни haptic, ни pop',
      (tester) async {
    final haptics = <MethodCall>[];

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );

    Widget wrap(bool filled) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: FavoriteStar(filled: filled),
            ),
          ),
        );

    await tester.pumpWidget(wrap(false));
    await tester.pumpAndSettle();

    // «Подгрузка избранного»: filled сменился БЕЗ тапа —
    // звезда не должна ни вибрировать, ни пружинить.
    await tester.pumpWidget(wrap(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(haptics, isEmpty,
        reason: 'смена filled из данных не даёт тактильный отклик');

    // В покое масштаб единичный — анимации нет.
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(FavoriteStar),
        matching: find.byType(Transform),
      ),
    );
    expect(transform.transform.isIdentity(), isTrue,
        reason: 'без тапа звезда не пружинит');
  });

  testWidgets('тап по звезде плитки даёт haptic, pop и toggle',
      (tester) async {
    final haptics = <MethodCall>[];

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );

    var toggles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ContentTile(
              title: 'Точка',
              isFavorite: false,
              onFavoriteToggle: () => toggles++,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('В избранное'));
    await tester.pump();

    expect(toggles, 1, reason: 'нажатие переключает избранное');
    expect(haptics, hasLength(1),
        reason: 'тап даёт ровно один тактильный отклик');

    // Pop запущен: в середине анимации масштаб не единичный.
    await tester.pump(const Duration(milliseconds: 30));

    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(FavoriteStar),
        matching: find.byType(Transform),
      ),
    );

    expect(transform.transform.isIdentity(), isFalse,
        reason: 'по тапу звезда пружинит');

    await tester.pumpAndSettle();

    final settled = tester.widget<Transform>(
      find.descendant(
        of: find.byType(FavoriteStar),
        matching: find.byType(Transform),
      ),
    );

    expect(settled.transform.isIdentity(), isTrue,
        reason: 'после pop звезда возвращается к единичному масштабу');
  });
}
