import 'package:flutter/services.dart';

import 'markdown_blocks.dart';

import '../../../core/utils/logger.dart';


/// Загрузка полных текстов достопримечательностей из офлайн-пакета.
///
/// Один код на io и web (иначе копия в каждом из репозиториев
/// карты): поиск файла `text/NN - <имя>.md` через AssetManifest
/// и вырезание markdown-заголовка.
///
/// [basePath] — путь пакета локации (`content/<регион>/<локация>`,
/// см. `locationAssetBase`).

class PoiTextLoader {

  const PoiTextLoader._();

  /// Кеш манифеста ассетов: он общий для всего приложения и не
  /// меняется в рантайме, а его парсинг — сотни записей — не должен
  /// повторяться при каждом открытии полного текста POI.
  static Future<AssetManifest>? _manifestFuture;


  static Future<AssetManifest> _loadManifest() {
    if (_manifestFuture != null) {
      return _manifestFuture!;
    }

    // Упавший future не кешируется (P2, 6-й проход): иначе
    // первая же ошибка загрузки манифеста держала бы битый кеш
    // до конца сессии — полные тексты не открывались бы никогда.
    final future = AssetManifest.loadFromAssetBundle(rootBundle);

    future.then(
      (_) {},
      onError: (_) {
        if (identical(_manifestFuture, future)) {
          _manifestFuture = null;
        }
      },
    );

    return _manifestFuture = future;
  }


  /// Подходит ли ассет под полный текст POI с номером [folderNumber].
  ///
  /// Сопоставление — по НАЧАЛУ имени файла (`NN - `): раньше матчили
  /// `key.contains('$numStr - ')`, и при поиске «01 - …» ложно
  /// находился «101 - …» (contains-ловушка на подстроке).
  ///
  /// Публичный ради тестов (ассеты манифеста в тесте не подменить).
  static bool matchesTextAsset(
    String assetKey,
    String basePath,
    int folderNumber,
  ) {

    if (!assetKey.startsWith('$basePath/text/')) {
      return false;
    }

    // Только имя файла: «content/…/text/01 - X.md» → «01 - X.md».
    final fileName =
        assetKey.substring(assetKey.lastIndexOf('/') + 1);

    final numStr = folderNumber.toString().padLeft(2, '0');

    return fileName.startsWith('$numStr - ');
  }


  /// Полный текст достопримечательности из `text/NN - Title.md`.
  ///
  /// [folderNumber] — номер файла в папке `text/` (нумерация как
  /// на карте). Файл ищется по префиксу `NN - ` среди ассетов
  /// локации. Возвращает `null`, если файл не найден.
  static Future<String?> loadFullText(
    String basePath,
    String islandId,
    int folderNumber,
  ) async {

    try {

      final manifest = await _loadManifest();

      final fileName = manifest
          .listAssets()
          .where(
            (key) => matchesTextAsset(key, basePath, folderNumber),
          )
          .firstOrNull;

      if (fileName == null) {

        AppLogger.info(
          '[PoiTextLoader] island=$islandId '
          'folderNumber=$folderNumber файл не найден',
        );

        return null;
      }

      final raw =
          await rootBundle.loadString(fileName);

      return stripMarkdownTitle(raw);

    } catch (e) {

      AppLogger.info(
        '[PoiTextLoader] island=$islandId '
        'folderNumber=$folderNumber ошибка: $e',
      );

      return null;
    }
  }

  /// Полный текст POI СТРУКТУРОЙ блоков markdown (B3.4, 8-й
  /// проход): подзаголовки `##` — h3, списки — буллеты, инлайн
  /// `*курсив*`/`**жирный**`/ссылки — типографика. H1 выбрасывает
  /// сам парсер. Возвращает `null`, если файл не найден.
  static Future<List<MdBlock>?> loadFullBlocks(
    String basePath,
    String islandId,
    int folderNumber,
  ) async {
    try {
      final manifest = await _loadManifest();

      final fileName = manifest
          .listAssets()
          .where(
            (key) => matchesTextAsset(key, basePath, folderNumber),
          )
          .firstOrNull;

      if (fileName == null) {
        return null;
      }

      final raw = await rootBundle.loadString(fileName);

      return parseMarkdownBlocks(raw);
    } catch (e) {
      AppLogger.info(
        '[PoiTextLoader] island=$islandId '
        'folderNumber=$folderNumber blocks ошибка: $e',
      );

      return null;
    }
  }

  /// Готовит markdown-текст файла к показу в карточке POI.
  ///
  /// * Строки `# Title` (H1) выбрасываются целиком: заголовок уже
  ///   есть в карточке POI.
  /// * Подзаголовки `## `/`### ` теряют решётки — остаются строками
  ///   текста (жирную строку «Подзаголовок» показывать как текст —
  ///   нормальная типографика для читалки).
  /// * Инлайновые маркеры `**жирный**`/`__жирный__` убираются:
  ///   ExpandableText не рендерит markdown, и звёздочки показывались
  ///   пользователю как есть.
  static String stripMarkdownTitle(String raw) {

    final lines = raw.split('\n');

    final body = lines
        .where(
          (line) => !line.trim().startsWith('# '),
        )
        .map(
          (line) => line
              .replaceFirst(RegExp(r'^\s*#{2,6}\s*'), '')
              .replaceAll('**', '')
              .replaceAll('__', ''),
        )
        .join('\n');

    return body.trim();
  }
}