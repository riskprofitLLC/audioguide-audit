import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/logger.dart';


/// Нужно ли перезаписывать локальную копию ассета: файла ещё нет,
/// или его размер не совпал (ассет обновился в новой сборке).
///
/// Вынесено в функцию ради теста: сама проверка живёт на «горячем»
/// пути каждого запуска приложения.
@visibleForTesting
bool needsAssetRewrite({
  required bool fileExists,
  required int fileSize,
  required int assetSize,
}) {
  return !fileExists || fileSize != assetSize;
}


/// Сервис доступа к архивам PMTiles на нативных платформах.
///
/// Копирует `map.pmtiles` из ассетов в каталог приложения
/// и возвращает URL вида `pmtiles:///абс/путь/файл.pmtiles`
/// (maplibre-native читает локальный архив по этому протоколу).
///
/// Имя локального файла строится из пути ассета, поэтому
/// разные острова не конфликтуют между собой.
///
/// Копия хранится в support-каталоге приложения (не Documents) и
/// перезаписывается ТОЛЬКО при изменении размера ассета: раньше
/// каждый запуск перезаписывал 2–5 МБ на регион впустую.
final class MapTileService {

  MapTileService._();

  static final MapTileService instance =
      MapTileService._();


  final Map<String, String> _cachedUrls = {};


  /// Выполнена ли одноразовая чистка старого кеша из Documents
  /// (до переноса копий в support-каталог).
  bool _legacyCleanupDone = false;


  Future<String> pmtilesUrl(
    String assetPath,
  ) async {

    final cached = _cachedUrls[assetPath];

    if (cached != null) {
      return cached;
    }

    final bytes = await rootBundle.load(
      assetPath,
    );

    // Support-каталог: файлы приложения, невидимые пользователю,
    // не попадающие в бэкапы iOS (Documents им засорялся).
    final appDir =
        await getApplicationSupportDirectory();

    final dir = Directory(
      p.join(appDir.path, 'island_guide'),
    );

    await dir.create(
      recursive: true,
    );

    await _removeLegacyDocumentsCache();

    // Уникальное имя: `content_gemiler_map.pmtiles`.
    final fileName =
        assetPath.replaceAll('/', '_');

    final file = File(
      p.join(dir.path, fileName),
    );

    final assetBytes = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );

    final exists = await file.exists();

    if (needsAssetRewrite(
      fileExists: exists,
      fileSize: exists ? await file.length() : 0,
      assetSize: assetBytes.length,
    )) {

      await file.writeAsBytes(
        assetBytes,
        flush: true,
      );

    } else {

      AppLogger.info(
        '[MapTileService] $fileName уже актуален '
        '(${assetBytes.length} байт), перезапись пропущена',
      );
    }

    final url = 'pmtiles:///${file.path}';

    _cachedUrls[assetPath] = url;

    return url;
  }


  /// Одноразовая чистка старого кеша, который прежние версии
  /// приложения держали в Documents (`island_guide/` с pmtiles
  /// и шрифтами, ~15 МБ, попадало в бэкапы iCloud).
  Future<void> _removeLegacyDocumentsCache() async {

    if (_legacyCleanupDone) {
      return;
    }

    _legacyCleanupDone = true;

    try {

      final docs =
          await getApplicationDocumentsDirectory();

      final legacy = Directory(
        p.join(docs.path, 'island_guide'),
      );

      if (await legacy.exists()) {

        await legacy.delete(
          recursive: true,
        );

        AppLogger.info(
          '[MapTileService] старый кеш из Documents удалён',
        );
      }
    } catch (error) {

      // Чистка необязательна: старые файлы не мешают работе,
      // просто занимают место.
      AppLogger.info(
        '[MapTileService] не удалось удалить старый кеш: $error',
      );
    }
  }
}
