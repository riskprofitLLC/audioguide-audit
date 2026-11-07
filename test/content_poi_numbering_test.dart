// Инвариант нумерации POI (замечание владельца): id точки совпадает
// с её номером на карте. Раньше на Гемилере poi-02 показывался под
// номером 3, а poi-03 — под номером 2: путаница в оглавлении админки,
// путях файлов и подписях. Тест стережёт весь контент каталога.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Все poi.json каталога.
List<File> poiJsonFiles() {
  final files = <File>[];

  for (final region in Directory('content').listSync()) {
    if (region is! Directory) {
      continue;
    }

    for (final location in region.listSync()) {
      if (location is! Directory) {
        continue;
      }

      final poiJson = File('${location.path}/poi.json');

      if (poiJson.existsSync()) {
        files.add(poiJson);
      }
    }
  }

  return files;
}

List<Map<String, dynamic>> readPois(File file) =>
    (jsonDecode(file.readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();

void main() {
  test('id пронумерованных POI совпадает с их number во всём каталоге', () {
    final files = poiJsonFiles();

    expect(files, isNotEmpty, reason: 'каталог контента должен читаться');

    final problems = <String>[];

    for (final file in files) {
      for (final poi in readPois(file)) {
        final id = poi['id'] as String;
        final number = poi['number'] as int?;

        if (number == null) {
          continue;
        }

        final expected = 'poi-${number.toString().padLeft(2, '0')}';

        if (id != expected) {
          problems.add('${file.path}: $id должен быть $expected '
              '(number=$number, «${poi['title']}»)');
        }
      }
    }

    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('id точек уникальны, номера аудио и папок фото согласованы с id', () {
    final problems = <String>[];

    for (final file in poiJsonFiles()) {
      final seen = <String>{};

      for (final poi in readPois(file)) {
        final id = poi['id'] as String;

        if (!seen.add(id)) {
          problems.add('${file.path}: дубль id $id');
        }

        // Номер аудиофайла совпадает с номером id: каталог знает две
        // конвенции — `poi-NN.mp3` и `NN - slug.mp3`.
        final audio = poi['audio'] as String?;

        if (audio != null) {
          final base = audio.split('/').last.replaceAll('.mp3', '');
          final digits = RegExp(r'^(?:poi-)?(\d+)')
              .firstMatch(base)
              ?.group(1);

          final idNumber = int.parse(id.split('-').last);

          if (digits == null || int.parse(digits) != idNumber) {
            problems.add('${file.path}: у $id аудио $audio');
          }
        }

        // Папка фото тоже названа по id.
        for (final image in (poi['images'] as List<dynamic>? ?? const [])) {
          final path = image as String;
          final folder = path.split('/')[1];

          if (folder != id) {
            problems.add('${file.path}: у $id фото в папке $folder');
          }
        }
      }
    }

    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
