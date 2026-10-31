import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_initializer.dart';
import '../core/services/database_service.dart';
import '../features/map/services/map_glyphs_service.dart';
import '../features/map/services/map_style_service.dart';
import '../features/map/services/map_tile_service.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService.instance;
});

final mapTileServiceProvider = Provider<MapTileService>((ref) {
  return MapTileService.instance;
});

final mapGlyphsServiceProvider = Provider<MapGlyphsService>((ref) {
  return MapGlyphsService.instance;
});

final mapStyleServiceProvider = Provider<MapStyleService>((ref) {
  return MapStyleService.instance;
});

/// Ошибка инициализации приложения (SQLite и сервисы).
///
/// Читает [AppInitializer.lastError]. Пока непусто — главный экран
/// показывает баннер с текстом ошибки и кнопкой «Повторить» вместо
/// молчаливой деградации (пустые списки контента и т.п.).
final initErrorProvider = StateProvider<Object?>((ref) {
  return AppInitializer.lastError;
});
