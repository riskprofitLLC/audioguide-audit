
/// Точка маршрута.
library;

class TrailPoint {


  const TrailPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.order,
    this.elevation,
  });



  final String id;


  final double latitude;


  final double longitude;


  final int order;

  /// Высота точки (метры, из `<ele>` GPX; П5, 12-й проход).
  /// `null` — высот в треке нет, профиль не строится.
  final double? elevation;



  factory TrailPoint.fromJson(
    Map<String, dynamic> json,
  ) {

    final id = json['id'] as String?;
    final lat = json['latitude'] as num?;
    final lng = json['longitude'] as num?;

    if (id == null || id.isEmpty) {
      throw const FormatException('TrailPoint missing required field "id"');
    }
    if (lat == null || lng == null) {
      throw FormatException('TrailPoint "$id" missing required coordinates');
    }

    return TrailPoint(
      id: id,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      order: json['order'] as int? ?? 0,
    );
  }
}