import '../models/user_position.dart';

/// Экспорт записанного трека в GPX 1.1 (29-й проход, П5).
///
/// Чистая функция: XML-строка по списку точек —
/// тестируется без платформенных каналов.

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Собирает GPX-документ с одним треком.
String buildGpxTrack({
  required String name,
  required List<UserPosition> points,
}) {
  final buffer = StringBuffer();

  buffer.write(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<gpx version="1.1" creator="Island Guide" '
    'xmlns="http://www.topografix.com/GPX/1/1">\n'
    '<trk><name>${_xmlEscape(name)}</name><trkseg>\n',
  );

  for (final point in points) {
    buffer.write(
      '<trkpt lat="${point.latitude.toStringAsFixed(6)}" '
      'lon="${point.longitude.toStringAsFixed(6)}">',
    );

    if (point.timestamp != null) {
      buffer.write(
        '<time>${point.timestamp!.toUtc().toIso8601String()}</time>',
      );
    }

    buffer.write('</trkpt>\n');
  }

  buffer.write('</trkseg></trk>\n</gpx>\n');

  return buffer.toString();
}
