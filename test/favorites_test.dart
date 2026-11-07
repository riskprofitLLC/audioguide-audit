import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/services/database_service.dart';
import 'package:island_guide/features/favorites/controllers/favorites_controller.dart';
import 'package:island_guide/features/favorites/services/favorites_store.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('island_guide_fav_test');
  });

  tearDown(() {
    DatabaseService.instance.close();
    tmp.deleteSync(recursive: true);
  });

  test('хранилище добавляет, читает и удаляет избранное', () async {
    await DatabaseService.instance.initialize(databaseDirectory: tmp.path);

    final store = FavoritesStore(database: DatabaseService.instance);

    expect(await store.loadFavoriteIds(), isEmpty);

    await store.addFavorite('poi-01');
    await store.addFavorite('trail-03');

    final ids = await store.loadFavoriteIds();
    expect(ids, containsAll(['poi-01', 'trail-03']));

    await store.removeFavorite('poi-01');
    expect(await store.loadFavoriteIds(), {'trail-03'});
  });

  test('контроллер переключает избранное', () async {
    await DatabaseService.instance.initialize(databaseDirectory: tmp.path);

    final controller = FavoritesController(
      FavoritesStore(database: DatabaseService.instance),
    );
    await controller.load();

    await controller.toggle('poi-05');
    expect(controller.isFavorite('poi-05'), isTrue);

    await controller.toggle('poi-05');
    expect(controller.isFavorite('poi-05'), isFalse);
  });

  test('два параллельных toggle видят результат друг друга (атомарность)',
      () async {
    await DatabaseService.instance.initialize(databaseDirectory: tmp.path);

    final controller = FavoritesController(
      FavoritesStore(database: DatabaseService.instance),
    );
    await controller.load();

    // Модель «двойной тап» по одной звёздочке: второй тап стартует,
    // пока первый не завершил запись в хранилище. Раньше оба читали
    // ОДНО устаревшее состояние, оба решали «добавить» — и второй
    // тап не снимал избранное, а оставлял его.
    final first = controller.toggle('poi-05');
    final second = controller.toggle('poi-05');

    await Future.wait([first, second]);

    expect(controller.state, isEmpty,
        reason: 'двойной тап должен добавлять и сразу снимать, '
            'а не «залипать» в избранном');
  });

  test('включение маршрута добавляет в избранное и его достопримечательности',
      () async {
    await DatabaseService.instance.initialize(databaseDirectory: tmp.path);

    final controller = FavoritesController(
      FavoritesStore(database: DatabaseService.instance),
    );
    await controller.load();

    await controller.toggle(
      'gemiler/trail-01',
      cascadeKeys: const [
        'gemiler/poi-01',
        'gemiler/poi-03',
        'gemiler/poi-05',
      ],
    );

    expect(controller.isFavorite('gemiler/trail-01'), isTrue);
    expect(controller.isFavorite('gemiler/poi-01'), isTrue);
    expect(controller.isFavorite('gemiler/poi-03'), isTrue);
    expect(controller.isFavorite('gemiler/poi-05'), isTrue);

    // Повторное выключение убирает только маршрут, достопримечательности
    // остаются (они добавились в избранное тоже).
    await controller.toggle('gemiler/trail-01');

    expect(controller.isFavorite('gemiler/trail-01'), isFalse);
    expect(controller.isFavorite('gemiler/poi-01'), isTrue);
  });

  test('load отбрасывает ключи удалённых локаций и чистит хранилище', () async {
    await DatabaseService.instance.initialize(databaseDirectory: tmp.path);

    final store = FavoritesStore(database: DatabaseService.instance);

    // «karacaoren» удалён из каталога локаций; «gemiler» — действующий.
    // Раньше такой ключ ронял FavoritesPage StateError'ом из
    // regionOfLocation (firstWhere без orElse).
    await store.addFavorite('karacaoren/poi-01');
    await store.addFavorite('gemiler/poi-02');
    await store.addFavorite('poi-без-локации');

    final controller = FavoritesController(store);
    await controller.load();

    expect(controller.state, {'gemiler/poi-02'});

    // Хранилище тоже чистится — стейл-ключи не возвращаются
    // после перезапуска.
    expect(await store.loadFavoriteIds(), {'gemiler/poi-02'});
  });

  test('groupFavoriteKeys делит ключи по локациям и собирает стейл', () {
    final (:byLocation, :staleKeys) = groupFavoriteKeys([
      'gemiler/poi-01',
      'gemiler/trail-01',
      'bay/poi-03',
      'karacaoren/poi-01',
      'мусор-без-слэша',
    ]);

    expect(byLocation['gemiler'], containsAll(['poi-01', 'trail-01']));
    expect(byLocation['bay'], ['poi-03']);
    expect(byLocation.containsKey('karacaoren'), isFalse);

    expect(staleKeys, containsAll(['karacaoren/poi-01', 'мусор-без-слэша']));
  });

  test('toggle во время загрузки не затирается её результатом', () async {
    await DatabaseService.instance.initialize(databaseDirectory: tmp.path);

    final store = FavoritesStore(database: DatabaseService.instance);

    // В хранилище уже что-то есть (избранное с прошлого запуска).
    await store.addFavorite('gemiler/poi-01');

    final controller = FavoritesController(store);

    // Загрузка стартует и уходит в ожидание хранилища…
    final loading = controller.load();

    // …а пользователь уже тогглит: приложение стартует, избранное
    // ещё не подгрузилось, а звезду уже нажали.
    await controller.toggle('gemiler/poi-09');

    await loading;

    // Оба ключа живы: результат загрузки объединяется с текущим
    // состоянием, а не перезаписывает его.
    expect(
      controller.state,
      containsAll(['gemiler/poi-01', 'gemiler/poi-09']),
      reason: 'результат load() не должен затирать тогглы, '
          'сделанные до его окончания',
    );
  });
}
