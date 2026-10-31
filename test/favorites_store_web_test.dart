// Тест web-хранилища избранного (localStorage).
//
// Запускается только на платформе chrome:
//   flutter test --platform chrome test/favorites_store_web_test.dart

@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/favorites/services/favorites_store.dart';

void main() {
  test('избранное переживает перезагрузку (localStorage)', () async {
    final store = FavoritesStore();

    await store.clearAll();

    await store.addFavorites(['gemiler/poi-01', 'gemiler/trail-01']);

    // «Перезагрузка страницы» — новый экземпляр хранилища.
    final reloaded = FavoritesStore();

    expect(
      await reloaded.loadFavoriteIds(),
      containsAll(['gemiler/poi-01', 'gemiler/trail-01']),
    );

    await reloaded.removeFavorite('gemiler/poi-01');

    expect(
      await FavoritesStore().loadFavoriteIds(),
      ['gemiler/trail-01'],
    );

    await store.clearAll();
  });
}
