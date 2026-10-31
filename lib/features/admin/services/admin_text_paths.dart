/// Резолв пути текстового файла POI в бандле.
///
/// Повторяет поиск [PoiTextLoader], но возвращает сам путь
/// ассета: редактору нужен сырой файл (с H1 и квизами), а не
/// вычищенный текст для читалки.
library;

import 'package:flutter/services.dart';

import '../../content/services/poi_text_loader.dart';

/// Путь ассета `content/<регион>/<локация>/text/NN - X.md`
/// для POI с папочным номером [folderNumber]. Null — файла нет.
Future<String?> resolveTextAssetPath(
  String basePath,
  int folderNumber,
) async {

  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

  return manifest
      .listAssets()
      .where(
        (key) => PoiTextLoader.matchesTextAsset(key, basePath, folderNumber),
      )
      .firstOrNull;
}
