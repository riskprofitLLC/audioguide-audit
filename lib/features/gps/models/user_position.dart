/// Текущая позиция пользователя, полученная с GPS.
class UserPosition {

  const UserPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.timestamp,
  });


  final double latitude;


  final double longitude;


  /// Точность определения (метры).
  final double? accuracy;


  /// Скорость движения (м/с).
  final double? speed;


  /// Курс устройства (градусы 0–360, 0 — север).
  ///
  /// На Android это bearing GPS-фикса, на web браузер отдаёт
  /// курс из Coordinates. `null` — платформа курс не измерила:
  /// потребители (стрелка направления, подсказки маршрута) могут
  /// вычислить его по смещению между двумя фиксами (A17, 17-й
  /// проход).
  final double? heading;


  final DateTime? timestamp;
}
