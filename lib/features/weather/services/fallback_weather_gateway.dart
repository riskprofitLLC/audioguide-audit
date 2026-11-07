import '../models/weather.dart';
import 'weather_gateway.dart';

/// Шлюз-цепочка: пробует источники по порядку и возвращает
/// первый непустой ответ. Open-Meteo в России работает
/// нестабильно, поэтому за ним стоят резервные бесплатные
/// источники без ключа (wttr.in, met.no).
///
/// Все источники недоступны — `null`, как и раньше: погода —
/// онлайн-обогащение, офлайн-ядро не страдает.
class FallbackWeatherGateway implements WeatherGateway {
  FallbackWeatherGateway(this._gateways);

  final List<WeatherGateway> _gateways;

  /// Порядок источников (для тестов/диагностики).
  List<WeatherGateway> get gateways => List.unmodifiable(_gateways);

  @override
  Future<LocationWeather?> fetch(double latitude, double longitude) async {
    for (final gateway in _gateways) {
      final weather = await gateway.fetch(latitude, longitude);

      if (weather != null) {
        return weather;
      }
    }

    return null;
  }
}
