// П5 (29-й проход): экспорт записанного трека в GPX.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/utils/gpx_export.dart';

void main() {
  group('buildGpxTrack', () {
    test('валидный GPX с точками и временем', () {
      final gpx = buildGpxTrack(
        name: 'Мой трек',
        points: [
          UserPosition(
            latitude: 36.6,
            longitude: 29.1,
            timestamp: DateTime.utc(2026, 10, 29, 12, 0, 0),
          ),
          const UserPosition(latitude: 36.61, longitude: 29.11),
        ],
      );

      expect(gpx, contains('<?xml version="1.0" encoding="UTF-8"?>'));

      expect(gpx, contains('<gpx version="1.1" creator="Island Guide"'));

      expect(gpx, contains('<trkpt lat="36.600000" lon="29.100000">'));

      expect(gpx, contains('<time>2026-10-29T12:00:00.000Z</time>'));

      // Вторая точка без timestamp — без <time>.
      expect(gpx, contains('<trkpt lat="36.610000" lon="29.110000">'));

      expect(gpx, contains('</trkseg></trk>'));
    });

    test('имя трека экранируется', () {
      final gpx = buildGpxTrack(
        name: 'A&B <трек>',
        points: [
          const UserPosition(latitude: 1, longitude: 2),
        ],
      );

      expect(gpx, contains('<name>A&amp;B &lt;трек&gt;</name>'));

      expect(gpx, isNot(contains('<трек>')));
    });
  });
}
