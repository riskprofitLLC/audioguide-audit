import 'trail_point.dart';


/// Маршрут (тропа/трек).

class Trail {


  const Trail({
    required this.id,
    required this.name,
    required this.points,
    this.lines,
    this.description,
    this.distance,
    this.imagePaths = const [],
  });



  final String id;


  final String name;


  /// Все точки маршрута подряд (для навигации и границ).
  final List<TrailPoint> points;


  /// Ветки маршрута (для сети дорог с развилками): каждая ветка —
  /// отдельная непрерывная линия. Пусто, если маршрут — одна линия
  /// (в этом случае используется [points]).
  final List<List<TrailPoint>>? lines;


  final String? description;


  /// Длина маршрута в метрах (из свойств GeoJSON).
  final double? distance;


  /// Изображения маршрута (имена файлов в `images/` острова).
  final List<String> imagePaths;


  /// Ветки маршрута: если [lines] задан — он, иначе — [points]
  /// как единственная линия.
  List<List<TrailPoint>> get segments =>
      (lines != null && lines!.isNotEmpty)
          ? lines!
          : [points];



}
