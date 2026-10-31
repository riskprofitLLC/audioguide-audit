// Тесты санитайзера параметра ?island= из глубоких ссылок.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/models/region_catalog.dart';

void main() {
  group('sanitizeIslandParam', () {
    test('известная локация проходит как есть', () {
      expect(sanitizeIslandParam('gemiler'), 'gemiler');
      expect(sanitizeIslandParam('demre-finike'), 'demre-finike');
    });

    test('null остаётся null (параметра нет)', () {
      expect(sanitizeIslandParam(null), isNull);
    });

    test('неизвестная локация (удалённая из каталога) → null', () {
      // «karacaoren» удалён из kLocationIds: старая ссылка
      // /poi/poi-01?island=karacaoren не должна ронять страницу
      // StateError'ом из regionOfLocation.
      expect(sanitizeIslandParam('karacaoren'), isNull);
      expect(sanitizeIslandParam('no-such-island'), isNull);
      expect(sanitizeIslandParam(''), isNull);
    });

    test('регистр важен: «Gemiler» — не валидный id', () {
      expect(sanitizeIslandParam('Gemiler'), isNull);
    });
  });

  group('kLocationIds согласован с kRegions', () {
    test('каждая локация каталога входит в kLocationIds', () {
      for (final region in kRegions) {
        for (final locationId in region.locationIds) {
          expect(kLocationIds, contains(locationId),
              reason: 'локация $locationId региона ${region.id} '
                  'отсутствует в kLocationIds');
        }
      }
    });

    test('kLocationIds не содержит локаций вне регионов', () {
      final regionLocations = {
        for (final region in kRegions) ...region.locationIds,
      };

      for (final locationId in kLocationIds) {
        expect(regionLocations, contains(locationId),
            reason: 'локация $locationId есть в kLocationIds, '
                'но не принадлежит ни одному региону');
      }
    });
  });
}
