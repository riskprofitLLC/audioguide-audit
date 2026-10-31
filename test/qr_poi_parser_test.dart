// П1 (29-й проход): разбор QR-кода точки в роут приложения.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/qr/qr_poi_parser.dart';

void main() {
  group('parsePoiRouteFromQr', () {
    test('полный URL прода с hash-роутом', () {
      expect(
        parsePoiRouteFromQr(
          'https://audioguide.layero.app/#/poi/poi-08?island=gemiler',
        ),
        '/poi/poi-08?island=gemiler',
      );
    });

    test('голый hash-роут и путь без домена', () {
      expect(
        parsePoiRouteFromQr('#/poi/poi-01?island=bay'),
        '/poi/poi-01?island=bay',
      );

      expect(parsePoiRouteFromQr('/poi/poi-12'), '/poi/poi-12');
    });

    test('без island — роут без query', () {
      expect(
        parsePoiRouteFromQr(
          'https://audioguide.layero.app/#/poi/poi-03',
        ),
        '/poi/poi-03',
      );
    });

    test('пробелы и фрагмент после query обрезаются', () {
      expect(
        parsePoiRouteFromQr(
          '  https://audioguide.layero.app/#/poi/poi-08?island=gemiler#top ',
        ),
        '/poi/poi-08?island=gemiler',
      );
    });

    test('чужой QR — null', () {
      expect(parsePoiRouteFromQr('https://example.com/page'), isNull);

      expect(parsePoiRouteFromQr(null), isNull);

      expect(
        parsePoiRouteFromQr('https://audioguide.layero.app/#/map'),
        isNull,
      );

      // id точки обязан быть вида poi-…
      expect(
        parsePoiRouteFromQr('#/poi/../admin'),
        isNull,
      );
    });
  });
}
