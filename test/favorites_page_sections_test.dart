// Секции избранного (P0-8, 5-й проход):
// - порядок локаций — по каталогу (kLocationIds), а не по
//   вставке ключей в Set;
// - локация с устаревшими ключами (ни один id не найден в
//   контенте) не рисует заголовок-одиночку.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/favorites/presentation/favorites_page.dart';
import 'package:island_guide/features/favorites/providers/favorites_providers.dart';

import 'support/test_database.dart';

void main() {

  initTestDatabase();

  test('sortedFavoriteLocationIds сортирует по каталогу', () {
    // Вставка: даламан раньше гемилера — порядок НЕ сохраняется,
    // каталог говорит: gemiler (1) раньше kekova (3) и dalaman (4).
    final sorted = sortedFavoriteLocationIds(
      ['dalaman', 'gemiler', 'kekova'],
    );

    expect(sorted, ['gemiler', 'kekova', 'dalaman']);
  });

  testWidgets('секции идут по каталогу, пустые скрыты',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);

      // Локации с избранным: dalaman (poi-01) и gemiler (poi-01).
      // bay/poi-99 — устаревший id: локация существует, объекта нет.
      for (final location in ['gemiler', 'bay', 'dalaman']) {
        await container.read(poisFamily(location).future);
        await container.read(trailsFamily(location).future);
      }

      final favorites =
          container.read(favoritesControllerProvider.notifier);

      await favorites.toggle('dalaman/poi-01');
      await favorites.toggle('gemiler/poi-01');
      await favorites.toggle('bay/poi-99');
    });

    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: FavoritesPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Порядок по каталогу: Гемилер раньше Даламана, хотя в
    // Set первым попал Даламан.
    final gemilerY = tester.getTopLeft(find.text('Гемилер')).dy;
    final dalamanY = tester.getTopLeft(find.text('Даламан')).dy;

    expect(gemilerY, lessThan(dalamanY),
        reason: 'секции идут в порядке каталога');

    // Секция локации с устаревшими ключами скрыта целиком.
    expect(
      find.text('Фетхие и Гёчек'),
      findsNothing,
      reason: 'пустая секция не рисует заголовок',
    );

    // Звезда прямо в списке: снимаем без захода на страницу,
    // SnackBar предлагает «Отменить» (P1-5).
    final starTooltips = find.byTooltip('Убрать из избранного');

    expect(starTooltips, findsNWidgets(2),
        reason: 'по звезде на каждой строке (POI gemiler + dalaman)');

    await tester.tap(starTooltips.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Удалено из избранного'), findsOneWidget);

    // Строка исчезла из списка.
    expect(starTooltips, findsNWidgets(1));

    await tester.tap(find.byType(SnackBarAction));
    await tester.pumpAndSettle();

    expect(starTooltips, findsNWidgets(2),
        reason: 'отмена возвращает объект в список');
  });
}
