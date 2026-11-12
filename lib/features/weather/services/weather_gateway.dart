import '../models/weather.dart';

/// Источник погоды (П7, 12-й проход): платформенный шлюз.
///
/// Реализация — [OpenMeteoWeatherGateway]; тесты подменяют
/// фейком. `null` — сети нет или API недоступно: погода —
/// онлайн-обогащение, офлайн-ядро приложения от неё не зависит.
abstract class WeatherGateway {
  Future<LocationWeather?> fetch(double latitude, double longitude);
}
