import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/logger.dart';


/// Сервис глифов (шрифта) для текстовых подписей на нативных
/// платформах.
///
  /// Копирует `fonts/NotoSans/*.pbf` из ассетов в каталог
  /// приложения и возвращает шаблон URL вида
  /// `file:///абс/путь/{fontstack}/{range}.pbf` — maplibre-native
  /// подставляет сюда имя шрифта и диапазон кодовых точек и грузит
  /// глифы из локального файла (полный офлайн-режим).
  ///
  /// Список диапазонов вынесен в отдельный файл, чтобы сервисы
  /// io/web могли переиспользовать одни и те же имена файлов.

final class MapGlyphsService {

  MapGlyphsService._();

  static final MapGlyphsService instance =
      MapGlyphsService._();


  /// Диапазоны глифов, которые нужно скопировать в приложение.
  ///
  /// Покрывают: базовую латиницу и пунктуацию, кириллицу (включая
  /// ё/Ё), общие знаки препинания (—) и буквоподобные символы (№).
  static const List<String> kGlyphRanges = [
    '0-255',
    '256-511',
    '1024-1279',
    '1280-1535',
    '2048-2303',
    '8192-8447',
    '8448-8703',
  ];

  Future<String?>? _cachedUrl;


  Future<String?> glyphsUrl() async {

    final cached = _cachedUrl;

    if (cached != null) {
      return cached;
    }

    final future = _prepare();

    // Кешируем только успешный результат: временный сбой I/O
    // (заполненный диск, ошибка записи) не должен навсегда
    // отключать подписи на карте до перезапуска приложения.
    _cachedUrl = future;

    // Сброс кеша при неудаче — fire-and-forget, результат уже отдан.
    unawaited(future.then(
      (url) {
        if (url == null) {
          _cachedUrl = null;
        }
      },
      onError: (_) {
        _cachedUrl = null;
      },
    ));

    return future;
  }


  Future<String?> _prepare() async {

    try {

      // Support-каталог: файлы приложения, не попадающие в бэкапы
      // iOS (в Documents они засоряли iCloud-бэкап).
      final appDir =
          await getApplicationSupportDirectory();

      // Каталог, в который maplibre подставляет имя шрифта вместо
      // `{fontstack}` — здесь лежат подкаталоги вида NotoSans/0-255.pbf.
      final fontsDir = Directory(
        p.join(appDir.path, 'island_guide', 'fonts'),
      );

      final fontDir = Directory(
        p.join(fontsDir.path, 'NotoSans'),
      );

      await fontDir.create(recursive: true);

      for (final range in kGlyphRanges) {

        final assetPath =
            'fonts/NotoSans/$range.pbf';

        final bytes = await rootBundle.load(assetPath);

        final file = File(p.join(fontDir.path, '$range.pbf'));

        // Перезапись только при изменении: раньше все 7 файлов
        // переписывались при каждом запуске приложения.
        final exists = await file.exists();

        if (!exists ||
            await file.length() != bytes.lengthInBytes) {

          await file.writeAsBytes(
            bytes.buffer.asUint8List(
              bytes.offsetInBytes,
              bytes.lengthInBytes,
            ),
            flush: true,
          );
        }
      }

      // Шаблон должен вести в каталог ФОНТОВ, а не в сам шрифт:
      // maplibre подставляет имя стекка вместо `{fontstack}`.
      // Иначе путь удваивается — .../NotoSans/NotoSans/0-255.pbf,
      // и подписи на нативе не отображаются.
      final url = 'file://${p.join(fontsDir.path, '{fontstack}')}/{range}.pbf';

      AppLogger.info('[MapGlyphsService] glyphs url=$url');

      return url;
    } catch (error) {

      AppLogger.warning('[MapGlyphsService] failed to prepare glyphs: $error');

      return null;
    }
  }
}
