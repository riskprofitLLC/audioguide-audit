import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../controllers/favorites_controller.dart';
import '../services/favorites_store.dart';


/// Хранилище избранного.
final favoritesStoreProvider =
    Provider<FavoritesStore>((ref) {
  return FavoritesStore();
});


/// Набор id избранных объектов.
final favoritesControllerProvider =
    StateNotifierProvider<FavoritesController, Set<String>>((ref) {

  final controller = FavoritesController(
    ref.watch(favoritesStoreProvider),
  );

  // Загрузка нужна «в фоне»: её результат не требуется создателю
  // провайдера. Ошибки обязательно ловим: упавший load() иначе
  // оставался бы необработанным исключением (битая база роняла бы
  // приложение), а избранное просто останется пустым до перезапуска.
  unawaited(
    () async {
      try {
        await controller.load();
      } catch (error, stackTrace) {
        AppLogger.error(
          'Не удалось загрузить избранное',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }(),
  );

  return controller;
});


/// Включённый фильтр-звёздочка избранного для локации.
///
/// Ключ — `'$islandId'` (id локации: остров или прибрежная зона).
/// Если ключ в наборе, главный экран показывает
/// только достопримечательности локации из избранного — как внутри
/// каждого маршрута, так и в группе «Локации». Это чисто
/// состояние показа (не избранное локации) — переживает перестроение
/// страницы и переключение локаций, но не перезапуск приложения
/// (как и остальной временный UI-стейт).
final islandStarFilterProvider =
    StateProvider<Set<String>>((ref) => const {});

