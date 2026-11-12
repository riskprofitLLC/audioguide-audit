// Тесты логики пропуска перезаписи локальных копий ассетов карты
// (pmtiles/глифы) на нативных платформах.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/services/map_tile_service_io.dart';

void main() {
  group('needsAssetRewrite', () {
    test('файла нет — перезаписываем', () {
      expect(
        needsAssetRewrite(
          fileExists: false,
          fileSize: 0,
          assetSize: 100,
        ),
        isTrue,
      );
    });

    test('размер не совпал (ассет обновился) — перезаписываем', () {
      expect(
        needsAssetRewrite(
          fileExists: true,
          fileSize: 90,
          assetSize: 100,
        ),
        isTrue,
      );
    });

    test('размер совпал — копия актуальна, запись пропускается', () {
      expect(
        needsAssetRewrite(
          fileExists: true,
          fileSize: 100,
          assetSize: 100,
        ),
        isFalse,
      );
    });
  });

  group('поведение копии на диске (без path_provider, напрямую)', () {
    test('повторная запись не нужна, если длина файла равна длине ассета',
        () async {
      final tmp = await Directory.systemTemp
          .createTemp('island_guide_asset_cache');

      addTearDown(() {
        tmp.deleteSync(recursive: true);
      });

      final file = File('${tmp.path}/content_caria_map.pmtiles');

      // «Первый запуск»: файла нет — пишем.
      const assetSize = 2048;

      var exists = await file.exists();

      expect(
        needsAssetRewrite(
          fileExists: exists,
          fileSize: exists ? await file.length() : 0,
          assetSize: assetSize,
        ),
        isTrue,
      );

      await file.writeAsBytes(List.filled(assetSize, 1), flush: true);

      // «Второй запуск»: файл той же длины — запись пропускается
      // (раньше мегабайты pmtiles перезаписывались при каждом
      // старте приложения).
      exists = await file.exists();

      expect(
        needsAssetRewrite(
          fileExists: exists,
          fileSize: await file.length(),
          assetSize: assetSize,
        ),
        isFalse,
      );

      // Ассет «обновился» в новой сборке — длина изменилась,
      // копия перезаписывается.
      const newAssetSize = 4096;

      expect(
        needsAssetRewrite(
          fileExists: exists,
          fileSize: await file.length(),
          assetSize: newAssetSize,
        ),
        isTrue,
      );
    });
  });
}
