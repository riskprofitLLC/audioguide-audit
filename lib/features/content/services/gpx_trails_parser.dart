import 'package:xml/xml.dart';

import '../../gps/services/location_service.dart';
import '../../trails/models/trail.dart';
import '../../trails/models/trail_point.dart';


/// Парсер маршрутов из GPX (XML).
///
/// Ожидается документ `<gpx>` с элементами `<trk>`.
/// Соглашение для id: в `<extensions><id>...</id></extensions>`,
/// название — в стандартном `<name>`, описание — в `<desc>`.
/// Длина маршрута вычисляется суммированием гаверсинусов
/// по точкам, если не задана в `<extensions><distance>`.

List<Trail> parseTrailsGpx(
  String raw,
) {

  final document = XmlDocument.parse(raw);

  final root = document.rootElement;

  final gpxChildren = root.children;

  final trails = <Trail>[];

  for (final node in gpxChildren) {

    if (node is! XmlElement) {

      continue;
    }

    if (node.name.local != 'trk') {

      continue;
    }

    final trail = _parseTrack(node);

    if (trail != null) {

      trails.add(trail);
    }
  }

  return trails;
}


Trail? _parseTrack(XmlElement trk) {

  final name =
      _firstChildText(trk, 'name') ?? '';

  final description =
      _firstChildText(trk, 'desc');

  final extensions = _firstChild(trk, 'extensions');

final id = extensions != null
        ? (_firstChildText(extensions, 'id') ?? name)
        : name;

    // Пустой id недопустим: он используется как ключ в SQLite
    // (PRIMARY KEY (island_id, id)), и одинаковые пустые id затирают
    // маршруты друг другом при сидинге.
    if (id.isEmpty) {
      throw const FormatException('Trail missing required field "id"');
    }

    final (:points, :lines) = _parseTrackPoints(trk);

    if (points.isEmpty) {

      return null;
    }

  final distance = extensions != null
      ? double.tryParse(
          _firstChildText(extensions, 'distance') ?? '',
        )
      : null;

  final images = extensions != null
      ? _parseImages(extensions)
      : const <String>[];

  return Trail(
    id: id,
    name: name,
    description: description,
    // Длина — только по самим веткам: «мост» между концом одной
    // ветки и началом другой — не путь (см. TrailNavigator).
    distance: distance ?? _computeDistance(lines),
    points: points,
    lines: lines.length > 1 ? lines : null,
    imagePaths: images,
  );
}


/// Читает список изображений из `<extensions><images>`:
/// набор дочерних элементов `<image>file.jpg</image>`.
List<String> _parseImages(XmlElement extensions) {

  final imagesNode = _firstChild(extensions, 'images');

  if (imagesNode == null) {

    return const [];
  }

  final images = <String>[];

  for (final node in imagesNode.children.whereType<XmlElement>()) {

    if (node.name.local == 'image') {

      final text = node.innerText.trim();

      if (text.isNotEmpty) {

        images.add(text);
      }
    }
  }

  return images;
}


/// Один проход по `<trkseg>/<trkpt>`: строит сразу и плоский список
/// точек маршрута, и ветки по сегментам.
///
/// Раньше это делали два независимых прохода с собственными
/// счётчиками `order` — 2× работы и риск рассинхронизации `points`
/// и `lines` при правках (это данные карты и навигации).
({
  List<TrailPoint> points,
  List<List<TrailPoint>> lines,
}) _parseTrackPoints(XmlElement trk) {

  final points = <TrailPoint>[];

  final lines = <List<TrailPoint>>[];

  var order = 0;

  for (final seg in trk.children.whereType<XmlElement>()) {

    if (seg.name.local != 'trkseg') {

      continue;
    }

    final branch = <TrailPoint>[];

    for (final pt in seg.children.whereType<XmlElement>()) {

      if (pt.name.local != 'trkpt') {

        continue;
      }

      final lat =
          double.tryParse(pt.getAttribute('lat') ?? '');

      final lon =
          double.tryParse(pt.getAttribute('lon') ?? '');

      if (lat == null || lon == null) {

        continue;
      }

      // Высота из <ele> (П5): тег не обязателен, GPX без рельефа
      // (побережье) — elevation == null, профиль не строится.
      final ele =
          double.tryParse(_firstChildText(pt, 'ele') ?? '');

      final point = TrailPoint(
        id: '$order',
        latitude: lat,
        longitude: lon,
        order: order++,
        elevation: ele,
      );

      points.add(point);

      branch.add(point);
    }

    // Пустой сегмент не даёт ветки.
    if (branch.isNotEmpty) {

      lines.add(branch);
    }
  }

  return (points: points, lines: lines);
}


/// Суммарная длина веток маршрута (метры).
///
/// Считается внутри каждой ветки отдельно: сегмент «конец ветки →
/// начало следующей» — это разрыв трека, а не пройденный путь.
double _computeDistance(List<List<TrailPoint>> lines) {

  var distance = 0.0;

  for (final branch in lines) {

    for (var i = 1; i < branch.length; i++) {

      distance += LocationService.distanceMeters(
        branch[i - 1].latitude,
        branch[i - 1].longitude,
        branch[i].latitude,
        branch[i].longitude,
      );
    }
  }

  return distance;
}


XmlElement? _firstChild(
  XmlElement element,
  String localName,
) {

  for (final child in element.children.whereType<XmlElement>()) {

    if (child.name.local == localName) {

      return child;
    }
  }

  return null;
}


String? _firstChildText(
  XmlElement element,
  String localName,
) {

  final child = _firstChild(element, localName);

  return child?.innerText.trim();
}
