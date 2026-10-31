part of 'map_widget.dart';


/// Геометрия маршрута: LineString для одной линии, MultiLineString —
/// для сети веток. Каждая ветка сглаживается Catmull-Rom отдельно,
/// чтобы между ветками не появлялись ложные соединяющие кривые.
Map<String, dynamic> _trailGeometry(
  Trail trail,
) {

  final segments = trail.segments
      .map(_smoothTrailCoordinates)
      .toList();

  if (segments.length == 1) {

    return {
      'type': 'LineString',
      'coordinates': segments.first,
    };
  }

  return {
    'type': 'MultiLineString',
    'coordinates': segments,
  };
}


/// Сглаживает ломаную маршрута так, чтобы она выглядела гладкой
/// кривой, а не «нарисованной ребёнком» ломаной.
///
/// Алгоритм выбирается по плотности точек трека:
///
/// * **Плотный трек** (средний шаг < 40 м, напр. Гемилер — дороги
///   OSM с шумом: микро-зигзаги в несколько метров и градусов):
///   кривая Catmull-Rom проходит ЧЕРЕЗ каждую шумную вершину,
///   и линия «дёргается» из множества мелких отрезков. Поэтому
///   применяется стандартный картографический пайплайн:
///   1. [simplifyTrailPoints] — Douglas-Peucker с порогом 2 м
///      убирает шум, сохраняя форму маршрута;
///   2. [_chaikinSmooth] — итеративное срезание углов (Chaikin):
///      шумные вершины НЕ сохраняются, итоговая кривая плавная.
///
/// * **Разряженный трек** (средний шаг >= 40 м —
///   OSRM-маршруты с шагом ~150 м, шума нет): Chaikin срезал бы
///   реальные повороты (до 26 м отклонения), поэтому используется
///   Catmull-Rom — плавная кривая, проходящая через вершины.
List<List<double>> _smoothTrailCoordinates(
  List<TrailPoint> points,
) {

  if (points.length < 3) {

    return points
        .map((p) => [p.longitude, p.latitude])
        .toList();
  }

  final dense = _isDenseTrail(points);

  if (!dense) {

    return _catmullRomSmooth(points, 6);
  }

  final simplified = simplifyTrailPoints(points, toleranceMeters: 2.0);

  if (simplified.length < 3) {

    return simplified
        .map((p) => [p.longitude, p.latitude])
        .toList();
  }

  return _chaikinSmooth(simplified, 3);
}


/// Средний шаг точек трека в метрах.
double _trailStepMeters(List<TrailPoint> points) {

  var total = 0.0;

  for (var i = 0; i < points.length - 1; i++) {

    total += LocationService.distanceMeters(
      points[i].latitude,
      points[i].longitude,
      points[i + 1].latitude,
      points[i + 1].longitude,
    );
  }

  return total / (points.length - 1);
}


/// Плотный трек (точки ближе ~40 м) — считаем, что это дороги OSM
/// с шумом, где нужны упрощение + Chaikin.
bool _isDenseTrail(List<TrailPoint> points) {

  return _trailStepMeters(points) < 40.0;
}


/// Сглаживание ломаной кривой Catmull-Rom для разряженных треков.
///
/// На каждый отрезок добавляется [subdivisions] промежуточных
/// точек. Кривая проходит через каждую исходную вершину (в
/// разряженных треках шума нет), углы скругляются.
List<List<double>> _catmullRomSmooth(
  List<TrailPoint> points,
  int subdivisions,
) {

  final result = <List<double>>[
    [points.first.longitude, points.first.latitude],
  ];

  for (var i = 0; i < points.length - 1; i++) {

    final p0 = points[(i - 1).clamp(0, points.length - 1)];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[(i + 2).clamp(0, points.length - 1)];

    for (var s = 1; s <= subdivisions; s++) {

      final t = s / subdivisions;

      final lon = _catmullRom(p0.longitude, p1.longitude,
          p2.longitude, p3.longitude, t);

      final lat = _catmullRom(p0.latitude, p1.latitude,
          p2.latitude, p3.latitude, t);

      result.add([lon, lat]);
    }
  }

  return result;
}


/// Значение кривой Catmull-Rom в точке [t] (0..1) для четырёх
/// контрольных точек [p0]..[p3] (сегмент между [p1] и [p2]).
double _catmullRom(
  double p0,
  double p1,
  double p2,
  double p3,
  double t,
) {

  final t2 = t * t;

  final t3 = t2 * t;

  return 0.5 * (
    (2 * p1) +
    (-p0 + p2) * t +
    (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
    (-p0 + 3 * p1 - 3 * p2 + p3) * t3
  );
}


/// Упрощение ломаной Douglas-Peucker в локальной равнопромежуточной
/// проекции (метры). Точки, отклоняющиеся от текущего упрощения
/// меньше [toleranceMeters], отбрасываются.
///
/// Реализация ИТЕРАТИВНАЯ (явный стек диапазонов): рекурсивная
/// на патологических треках имела глубину ~ числа точек и рисковала
/// `StackOverflowError` на длинных треках.
List<TrailPoint> simplifyTrailPoints(
  List<TrailPoint> points, {
  required double toleranceMeters,
}) {

  if (points.length < 3) {

    return points;
  }

  final refLat = (points.first.latitude +
      points.last.latitude) / 2.0;

  final cosLat = cos(refLat * pi / 180.0);

  double toX(double lon) => lon * 111320.0 * cosLat;

  double toY(double lat) => lat * 110540.0;

  double distToSegment(
    TrailPoint p,
    TrailPoint a,
    TrailPoint b,
  ) {

    final px = toX(p.longitude);
    final py = toY(p.latitude);
    final ax = toX(a.longitude);
    final ay = toY(a.latitude);
    final bx = toX(b.longitude);
    final by = toY(b.latitude);

    final dx = bx - ax;
    final dy = by - ay;

    if (dx == 0 && dy == 0) {

      return sqrt(
        (px - ax) * (px - ax) + (py - ay) * (py - ay),
      );
    }

    final t = ((px - ax) * dx + (py - ay) * dy) /
        (dx * dx + dy * dy).clamp(1e-12, double.infinity);

    final c = t.clamp(0.0, 1.0);

    final cx = ax + c * dx;
    final cy = ay + c * dy;

    return sqrt(
      (px - cx) * (px - cx) + (py - cy) * (py - cy),
    );
  }

  // Точки, оставленные упрощением (первая и последняя — всегда).
  final keep = List<bool>.filled(points.length, false);

  keep[0] = true;

  keep[points.length - 1] = true;

  // Стек диапазонов вместо рекурсии: (start, end) — сегменты,
  // которые ещё нужно проверить. Рекурсивная версия на
  // патологических треках имела глубину ~ числа точек.
  final stack = <(int, int)>[(0, points.length - 1)];

  while (stack.isNotEmpty) {

    final (start, end) = stack.removeLast();

    if (end - start < 2) {

      continue;
    }

    var maxDist = 0.0;

    var index = start;

    for (var i = start + 1; i < end; i++) {

      final d = distToSegment(
        points[i],
        points[start],
        points[end],
      );

      if (d > maxDist) {

        maxDist = d;

        index = i;
      }
    }

    if (maxDist > toleranceMeters) {

      keep[index] = true;

      stack.add((start, index));

      stack.add((index, end));
    }
  }

  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}


/// Срезание углов по алгоритму Chaikin: каждая итерация заменяет
/// вершину [p] двумя точками на 25% и 75% каждого прилегающего
/// ребра. Кривая сходится к плавной линии и не проходит через
/// исходные (шумные) вершины.
List<List<double>> _chaikinSmooth(
  List<TrailPoint> points,
  int iterations,
) {

  var pts = points
      .map((p) => [p.longitude, p.latitude])
      .toList();

  for (var it = 0; it < iterations; it++) {

    if (pts.length < 3) {

      break;
    }

    final out = <List<double>>[pts.first];

    for (var i = 0; i < pts.length - 1; i++) {

      final p = pts[i];
      final q = pts[i + 1];

      out.add([
        p[0] + 0.25 * (q[0] - p[0]),
        p[1] + 0.25 * (q[1] - p[1]),
      ]);
      out.add([
        p[0] + 0.75 * (q[0] - p[0]),
        p[1] + 0.75 * (q[1] - p[1]),
      ]);
    }

    out.add(pts.last);
    pts = out;
  }

  return pts;
}
