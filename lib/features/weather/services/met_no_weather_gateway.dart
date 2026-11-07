import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';
import 'weather_code_map.dart';
import 'weather_gateway.dart';

/// Резервный шлюз погоды: MET Norway Locationforecast 2.0
/// (api.met.no). Бесплатный, без ключа, доступен из России;
/// обязателен идентифицирующий User-Agent, иначе 403.
///
/// Даёт текущую погоду и почасовой ряд (~2 суток), который
/// агрегируется в дни. Чего нет в compact-продукте — УФ,
/// порывов, восхода/заката и моря: соответствующие плитки
/// шторки просто не показываются.
class MetNoWeatherGateway implements WeatherGateway {
  MetNoWeatherGateway({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 8);

  static const _userAgent =
      'IslandGuide/1.0 (+https://audioguide.layero.app)';

  /// met.no требует координаты максимум с 4 знаками — иначе
  /// отказывает в кешировании и ругается.
  @visibleForTesting
  static Uri buildUri(double latitude, double longitude) {
    return Uri.https(
      'api.met.no',
      '/weatherapi/locationforecast/2.0/compact',
      {
        'lat': latitude.toStringAsFixed(4),
        'lon': longitude.toStringAsFixed(4),
      },
    );
  }

  @override
  Future<LocationWeather?> fetch(double latitude, double longitude) async {
    try {
      final response = await _client
          .get(buildUri(latitude, longitude), headers: {
        'User-Agent': _userAgent,
      }).timeout(_timeout);

      if (response.statusCode != 200) {
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final properties = json['properties'] as Map<String, dynamic>?;

      final series = (properties?['timeseries'] as List?)
          ?.cast<Map<String, dynamic>>();

      if (series == null || series.isEmpty) {
        return null;
      }

      final current = _instant(series.first);

      if (current == null) {
        return null;
      }

      return LocationWeather(
        temperature: _d(current['air_temperature']) ?? 0,
        humidity: _i(current['relative_humidity']),
        cloudCover: _i(current['cloud_area_fraction']),
        pressureMsl: _d(current['air_pressure_at_sea_level']),
        precipitation: _precipitation(series.first),
        windSpeed: _d(current['wind_speed']) ?? 0,
        windDirection: _d(current['wind_from_direction']) ?? 0,
        weatherCode: metNoSymbolToWmo(_symbol(series.first) ?? ''),
        daily: _daily(series),
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

  /// Агрегация почасового ряда в дни (по дате UTC-метки).
  static List<DailyWeather> _daily(List<Map<String, dynamic>> series) {
    final byDate = <String, List<Map<String, dynamic>>>{};

    for (final entry in series) {
      final time = entry['time'] as String?;

      if (time == null || time.length < 10) {
        continue;
      }

      byDate.putIfAbsent(time.substring(0, 10), () => []).add(entry);
    }

    final days = <DailyWeather>[];

    for (final date in byDate.keys) {
      final entries = byDate[date]!;

      final temperatures = entries
          .map((e) => _d(_instant(e)?['air_temperature']))
          .whereType<double>()
          .toList();

      if (temperatures.isEmpty) {
        continue;
      }

      final winds = entries
          .map((e) => _d(_instant(e)?['wind_speed']))
          .whereType<double>()
          .toList();

      // Полдень (12:00 UTC) — представитель дня; иначе середина.
      final noon = entries.firstWhere(
        (e) => (e['time'] as String).contains('T12:'),
        orElse: () => entries[entries.length ~/ 2],
      );

      days.add(DailyWeather(
        date: date,
        maxTemperature:
            temperatures.reduce((a, b) => a > b ? a : b),
        minTemperature:
            temperatures.reduce((a, b) => a < b ? a : b),
        // Compact-продукт вероятности осадков не отдаёт.
        precipitationProbability: 0,
        maxWindSpeed:
            winds.isEmpty ? 0 : winds.reduce((a, b) => a > b ? a : b),
        precipitationSum: entries.fold<double>(
          0,
          (sum, e) => sum + (_precipitation(e) ?? 0),
        ),
        weatherCode: metNoSymbolToWmo(_symbol(noon) ?? ''),
      ));
    }

    // Как у Open-Meteo (forecast_days=3): дальше ряда шторка
    // не показывает, а met.no отдаёт до 10 дней.
    return days.take(3).toList();
  }

  static Map<String, dynamic>? _instant(Map<String, dynamic> entry) {
    final data = entry['data'] as Map<String, dynamic>?;

    final instant = data?['instant'] as Map<String, dynamic>?;

    return instant?['details'] as Map<String, dynamic>?;
  }

  static String? _symbol(Map<String, dynamic> entry) {
    final data = entry['data'] as Map<String, dynamic>?;

    final next = data?['next_1_hours'] as Map<String, dynamic>?;

    final summary = next?['summary'] as Map<String, dynamic>?;

    return summary?['symbol_code'] as String?;
  }

  static double? _precipitation(Map<String, dynamic> entry) {
    final data = entry['data'] as Map<String, dynamic>?;

    final next = data?['next_1_hours'] as Map<String, dynamic>?;

    final details = next?['details'] as Map<String, dynamic>?;

    return _d(details?['precipitation_amount']);
  }

  static double? _d(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  static int? _i(dynamic value) {
    // met.no отдаёт проценты дробными — округляем.
    if (value is num) {
      return value.round();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }
}
