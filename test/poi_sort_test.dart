// Нумерация и порядок показа точек (PoiSort).
//
// Функции — общий примитив отображения И нумерации файлов
// `text/NN - …` (повторяет folder_numbers из tool/sync_texts.py):
// расхождение номера на карте и номера папки ломает поиск
// текста/аудио (тихо, без ошибки), поэтому инвариант покрыт тестом.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/poi/models/poi.dart';
import 'package:island_guide/features/poi/utils/poi_sort.dart';

Poi poi(String id, {int? number}) => Poi(
      id: id,
      title: id,
      latitude: 36.0,
      longitude: 29.0,
      description: '',
      number: number,
    );

void main() {
  group('partitionPoisForDisplay', () {
    test('нумерованные — по возрастанию номера, безномерные — в порядке '
        'исходного списка', () {
      final partition = partitionPoisForDisplay([
        poi('poi-03', number: 3),
        poi('off-1'),
        poi('poi-01', number: 1),
        poi('off-2'),
        poi('poi-02', number: 2),
      ]);

      expect(partition.numbered.map((p) => p.id).toList(),
          ['poi-01', 'poi-02', 'poi-03']);

      expect(partition.unnumbered.map((p) => p.id).toList(),
          ['off-1', 'off-2']);

      expect(partition.maxNumber, 3);
    });

    test('без пронумерованных точек maxNumber = 0', () {
      final partition = partitionPoisForDisplay([poi('off-1'), poi('off-2')]);

      expect(partition.maxNumber, 0);

      expect(partition.numbered, isEmpty);
    });

    test('пустой список', () {
      final partition = partitionPoisForDisplay(const <Poi>[]);

      expect(partition.numbered, isEmpty);

      expect(partition.unnumbered, isEmpty);

      expect(partition.maxNumber, 0);
    });
  });

  test('sortPoisForDisplay: сначала маршрутные, затем внемаршрутные', () {
    final sorted = sortPoisForDisplay([
      poi('off-1'),
      poi('poi-02', number: 2),
      poi('off-2'),
      poi('poi-01', number: 1),
    ]);

    expect(sorted.map((p) => p.id).toList(),
        ['poi-01', 'poi-02', 'off-1', 'off-2']);
  });

  group('folderNumberFor', () {
    test('пронумерованная точка отдаёт свой номер', () {
      final pois = [poi('poi-01', number: 1), poi('off-1')];

      expect(folderNumberFor('poi-01', pois), 1);
    });

    test('внемаршрутные продолжают нумерацию от максимума в порядке '
        'poi.json (как folder_numbers в sync_texts.py)', () {
      final pois = [
        poi('poi-01', number: 1),
        poi('poi-02', number: 2),
        poi('off-a'),
        poi('off-b'),
      ];

      expect(folderNumberFor('off-a', pois), 3);

      expect(folderNumberFor('off-b', pois), 4);
    });

    test('id и номер расходятся — отдаётся НОМЕР, а не позиция (инвариант '
        'папочного номера)', () {
      // Гемилер до перенумерации: poi-02 стоял под №3.
      final pois = [
        poi('poi-01', number: 1),
        poi('poi-02', number: 3),
        poi('poi-03', number: 2),
      ];

      expect(folderNumberFor('poi-02', pois), 3);
    });

    test('неизвестный id — 0', () {
      expect(folderNumberFor('нет-такой', [poi('poi-01', number: 1)]), 0);
    });

    test('только внемаршрутные: нумерация с 1', () {
      expect(folderNumberFor('off-a', [poi('off-a'), poi('off-b')]), 1);

      expect(folderNumberFor('off-b', [poi('off-a'), poi('off-b')]), 2);
    });
  });
}
