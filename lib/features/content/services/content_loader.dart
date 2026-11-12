import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/utils/logger.dart';
import '../models/manifest.dart';


/// Загрузчик манифеста офлайн-пакета.

class ContentLoader {


  const ContentLoader();


  /// Читает и парсит манифест острова.
  ///
  /// [assetPath] — путь к манифесту в ассетах,
  /// например `content/gemiler/manifest.json`.
  ///
  /// При любой ошибке загрузки (ассет отсутствует, некорректный
  /// JSON, невалидная структура) оборачивает исходное исключение
  /// в `FormatException` с путём файла — чтобы в логах сразу было
  /// видно, какой именно манифест не загрузился.

  Future<Manifest> loadManifest(
    String assetPath,
  ) async {

    AppLogger.info('[ContentLoader] loadManifest $assetPath');

    try {

      final raw =
          await rootBundle.loadString(
        assetPath,
      );

      final json =
          jsonDecode(raw) as Map<String, dynamic>;

      final manifest = Manifest.fromJson(json);

      AppLogger.info(
        '[ContentLoader] manifest $assetPath id=${manifest.id} '
        'name=${manifest.name} map="${manifest.map}"',
      );

      return manifest;

    } catch (error) {

      throw FormatException(
        'Не удалось загрузить манифест $assetPath: $error',
      );
    }
  }
}
