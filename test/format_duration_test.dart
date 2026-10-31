// Пункт 8 замечаний Sonnet: единые форматтеры длительности и
// русской десятичной запятой.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('граница 59:59 и переход на часы', () {
      expect(
        formatDuration(
          const Duration(minutes: 59, seconds: 59),
        ),
        '59:59',
      );

      expect(
        formatDuration(
          const Duration(hours: 1, seconds: 5),
        ),
        '60:05',
      );
    });

    test('ноль и отрицательные — 00:00', () {
      expect(formatDuration(Duration.zero), '00:00');

      expect(
        formatDuration(const Duration(seconds: -3)),
        '00:00',
      );
    });

    test('formatDurationMs: null/0/обычное значение', () {
      expect(formatDurationMs(null), '00:00');

      expect(formatDurationMs(0), '00:00');

      expect(formatDurationMs(349000), '05:49');
    });

    test('formatDecimalRu: русская запятая', () {
      expect(formatDecimalRu(0.2), '0,2');

      expect(formatDecimalRu(1.25, digits: 2), '1,25');

      expect(formatDecimalRu(-0.4), '-0,4');
    });
  });
}
