import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../content/models/region_catalog.dart';
import '../services/favorites_store.dart';


/// Контроллер избранного.
///
/// Хранит актуальный набор id выбранных объектов
/// (POI и маршруты) и синхронизирует его с хранилищем.

class FavoritesController extends StateNotifier<Set<String>> {

  FavoritesController(
    this._store,
  ) : super(const {});


  final FavoritesStore _store;


  /// Загружает избранное из хранилища.
  ///
  /// Ключи локаций, которых больше нет в каталоге (локация удалена
  /// или переименована, напр. «karacaoren»), отбрасываются и удаляются
  /// из хранилища: они роняли `FavoritesPage` (StateError в
  /// `regionOfLocation`) и не могли ничего показать.
  Future<void> load() async {

    final loaded = await _store.loadFavoriteIds();

    final (:byLocation, :staleKeys) = groupFavoriteKeys(loaded);

    if (staleKeys.isNotEmpty) {

      await _store.removeFavorites(staleKeys);
    }

    final loadedKeys = <String>{
      for (final entry in byLocation.entries)
        for (final itemId in entry.value) '${entry.key}/$itemId',
    };

    // Объединяем с текущим состоянием, а не перезаписываем его:
    // тогглы, сделанные до окончания загрузки (звезда нажата на
    // старте приложения), не должны теряться её результатом.
    state = loadedKeys.union(state);
  }


  /// Переключает объект: добавляет в избранное,
  /// если его там нет, иначе убирает.
  ///
  /// [cascadeKeys] — дополнительные ключи, которые при добавлении
  /// [itemId] тоже попадают в избранное (например, все
  /// достопримечательности маршрута). При удалении [itemId]
  /// дополнительные ключи не трогаются.
  ///
  /// Новое состояние вычисляется и фиксируется СИНХРОННО, до любых
  /// await: параллельные тапы (двойной клик, гонка страниц) читают
  /// уже актуальное состояние, а не устаревшее, и запись в
  /// хранилище идёт ПОСЛЕ — ошибка записи не рассинхронизирует UI.
  Future<void> toggle(
    String itemId, {
    Iterable<String>? cascadeKeys,
  }) async {

    final next = Set<String>.of(state);

    final wasFavorite = next.contains(itemId);

    final toPersist = <String>[];

    if (wasFavorite) {

      next.remove(itemId);

      toPersist.add(itemId);

    } else {

      final keys = <String>{itemId};

      if (cascadeKeys != null) {
        keys.addAll(cascadeKeys);
      }

      next.addAll(keys);

      // Каскад пишется одним батчем (см. FavoritesStore).
      toPersist.addAll(keys);
    }

    state = next;

    try {

      if (wasFavorite) {

        await _store.removeFavorite(itemId);

      } else {

        await _store.addFavorites(toPersist);
      }

    } catch (error, stackTrace) {

      AppLogger.error(
        'Не удалось записать избранное: $itemId',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }


  /// Удаляет перечисленные ключи из избранного (например, чистка
  /// устаревших ключей локаций, которых больше нет в каталоге).
  Future<void> removeAll(Iterable<String> keys) async {

    if (keys.isEmpty) {
      return;
    }

    await _store.removeFavorites(keys);

    final next = Set<String>.of(state);
    next.removeAll(keys);
    state = next;
  }


  /// Удаляет все избранное.
  Future<void> clearAll() async {
    await _store.clearAll();
    state = const {};
  }


  /// Есть ли объект в избранном.
  bool isFavorite(
    String itemId,
  ) {
    return state.contains(itemId);
  }
}


/// Делит ключи избранного по локациям, отбрасывая недействительные.
///
/// Ключ — `'<locationId>/<itemId>'`. Ключи с локацией, которой нет
/// в [kLocationIds] (или без `/`), попадают в [staleKeys]: по ним
/// нельзя открыть контент — манифест и `regionOfLocation` не найдут
/// локацию.
({
  Map<String, List<String>> byLocation,
  List<String> staleKeys,
}) groupFavoriteKeys(Iterable<String> favorites) {

  final byLocation = <String, List<String>>{};

  final staleKeys = <String>[];

  for (final key in favorites) {

    final slash = key.indexOf('/');

    if (slash <= 0 || slash == key.length - 1) {

      staleKeys.add(key);

      continue;
    }

    final locationId = key.substring(0, slash);

    if (!kLocationIds.contains(locationId)) {

      staleKeys.add(key);

      continue;
    }

    byLocation
        .putIfAbsent(locationId, () => [])
        .add(key.substring(slash + 1));
  }

  return (byLocation: byLocation, staleKeys: staleKeys);
}
