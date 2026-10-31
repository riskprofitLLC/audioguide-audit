import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';
import 'weather_gateway.dart';

/// Реальный шлюз погоды: два параллельных запроса к Open-Meteo
/// (П7, 12-й проход):
///   * forecast API — температура, ветер, код погоды + 3 дня;
///   * marine API — высота волны (только для морских точек,
///     вдали от побережья возвращает пусто — тогда волны нет).
///
/// Ключей не требует; таймаут 5 c; любая ошибка — `null`
/// (тихий офлайн-фолбэк, как растр OSM).
class OpenMeteoWeatherGateway implements WeatherGateway {
  OpenMeteoWeatherGateway({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 5);

  /// URI прогноза (A2: тестируемая сборка): единицы ветра —
  /// м/с (`wind_speed_unit=ms`), по умолчанию Open-Meteo отдаёт
  /// км/ч, а UI подписывает «м/с». 21-й проход: полный набор —
  /// порывы, влажность, давление, облачность, УФ, осадки;
  /// по дням — порывы, доминирующий румб, УФ, сумма осадков,
  /// восход/закат.
  @visibleForTesting
  static Uri buildForecastUri(double latitude, double longitude) {
    return Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'precipitation,weather_code,cloud_cover,pressure_msl,'
          'wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,'
          'sunrise,sunset,uv_index_max,precipitation_sum,'
          'precipitation_probability_max,wind_speed_10m_max,'
          'wind_gusts_10m_max,wind_direction_10m_dominant',
      'forecast_days': '3',
      'timezone': 'auto',
      'wind_speed_unit': 'ms',
    });
  }

  /// URI морской волны (A2). 21-й проход: не только высота —
  /// период/направление волны, зыбь, ветровая волна, вода.
  @visibleForTesting
  static Uri buildMarineUri(double latitude, double longitude) {
    return Uri.https('marine-api.open-meteo.com', '/v1/marine', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'wave_height,wave_direction,wave_period,wind_wave_height,'
          'swell_wave_height,swell_wave_period,swell_wave_direction,'
          'sea_surface_temperature',
      'timezone': 'auto',
      'wind_speed_unit': 'ms',
    });
  }

  @override
  Future<LocationWeather?> fetch(double latitude, double longitude) async {
    final forecastUri = buildForecastUri(latitude, longitude);

    final marineUri = buildMarineUri(latitude, longitude);

    try {
      final results = await Future.wait([
        _client.get(forecastUri).timeout(_timeout),
        _client
            .get(marineUri)
            .timeout(_timeout)
            // Marine-сетка покрывает не всякую точку: 400/404 или
            // пустой current — просто «без волны», не ошибка.
            .catchError((_) => http.Response('', 400)),
      ]);

      final forecastResponse = results[0];
      final marineResponse = results[1];

      if (forecastResponse.statusCode != 200) {
        return null;
      }

      final forecast =
          jsonDecode(forecastResponse.body) as Map<String, dynamic>;

      final current = forecast['current'] as Map<String, dynamic>;

      final daily = forecast['daily'] as Map<String, dynamic>;

      final dailyCount = (daily['time'] as List).length;

      final days = <DailyWeather>[
        for (var i = 0; i < dailyCount; i++)
          DailyWeather(
            date: (daily['time'] as List)[i] as String,
            maxTemperature:
                _num(daily['temperature_2m_max'], i)?.toDouble() ?? 0,
            minTemperature:
                _num(daily['temperature_2m_min'], i)?.toDouble() ?? 0,
            precipitationProbability:
                _num(daily['precipitation_probability_max'], i)?.toInt() ?? 0,
            maxWindSpeed:
                _num(daily['wind_speed_10m_max'], i)?.toDouble() ?? 0,
            maxWindGusts:
                _num(daily['wind_gusts_10m_max'], i)?.toDouble(),
            dominantWindDirection:
                _num(daily['wind_direction_10m_dominant'], i)?.toDouble(),
            uvIndexMax: _num(daily['uv_index_max'], i)?.toDouble(),
            precipitationSum:
                _num(daily['precipitation_sum'], i)?.toDouble(),
            sunrise: _str(daily['sunrise'], i),
            sunset: _str(daily['sunset'], i),
            weatherCode: _num(daily['weather_code'], i)?.toInt() ?? 0,
          ),
      ];

      double? waveHeight;

      double? waveDirection;

      double? wavePeriod;

      double? windWaveHeight;

      double? swellWaveHeight;

      double? swellWavePeriod;

      double? swellWaveDirection;

      double? seaSurfaceTemperature;

      if (marineResponse.statusCode == 200) {
        try {
          final marine =
              jsonDecode(marineResponse.body) as Map<String, dynamic>;

          final marineCurrent = marine['current'] as Map<String, dynamic>?;

          waveHeight = _num(marineCurrent?['wave_height'], 0)?.toDouble();

          waveDirection =
              _num(marineCurrent?['wave_direction'], 0)?.toDouble();

          wavePeriod = _num(marineCurrent?['wave_period'], 0)?.toDouble();

          windWaveHeight =
              _num(marineCurrent?['wind_wave_height'], 0)?.toDouble();

          swellWaveHeight =
              _num(marineCurrent?['swell_wave_height'], 0)?.toDouble();

          swellWavePeriod =
              _num(marineCurrent?['swell_wave_period'], 0)?.toDouble();

          swellWaveDirection =
              _num(marineCurrent?['swell_wave_direction'], 0)?.toDouble();

          seaSurfaceTemperature = _num(
              marineCurrent?['sea_surface_temperature'], 0)
            ?.toDouble();
        } catch (_) {
          // Кривой ответ marine — не теряем погоду из-за волны.
        }
      }

      return LocationWeather(
        temperature: _num(current['temperature_2m'], 0)?.toDouble() ?? 0,
        feelsLike:
            _num(current['apparent_temperature'], 0)?.toDouble(),
        humidity: _num(current['relative_humidity_2m'], 0)?.toInt(),
        precipitation: _num(current['precipitation'], 0)?.toDouble(),
        cloudCover: _num(current['cloud_cover'], 0)?.toInt(),
        pressureMsl: _num(current['pressure_msl'], 0)?.toDouble(),
        uvIndex: _num(current['uv_index'], 0)?.toDouble(),
        windSpeed: _num(current['wind_speed_10m'], 0)?.toDouble() ?? 0,
        windDirection:
            _num(current['wind_direction_10m'], 0)?.toDouble() ?? 0,
        windGusts: _num(current['wind_gusts_10m'], 0)?.toDouble(),
        weatherCode: _num(current['weather_code'], 0)?.toInt() ?? 0,
        waveHeight: waveHeight,
        waveDirection: waveDirection,
        wavePeriod: wavePeriod,
        windWaveHeight: windWaveHeight,
        swellWaveHeight: swellWaveHeight,
        swellWavePeriod: swellWavePeriod,
        swellWaveDirection: swellWaveDirection,
        seaSurfaceTemperature: seaSurfaceTemperature,
        daily: days,
      );
    } catch (_) {
      // Сеть/таймаут/парсинг — тихо без погоды.
      return null;
    }
  }

  /// Закрытие http-клиента (dispose провайдера).
  void close() {
    _client.close();
  }

  static num? _num(dynamic value, int index) {
    if (value is List) {
      if (index >= value.length) {
        return null;
      }

      return value[index] as num?;
    }

    return value as num?;
  }

  /// Строка из daily-массива (восход/закат), иначе null.
  static String? _str(dynamic value, int index) {
    if (value is List) {
      if (index >= value.length) {
        return null;
      }

      return value[index] as String?;
    }

    return value as String?;
  }
}
