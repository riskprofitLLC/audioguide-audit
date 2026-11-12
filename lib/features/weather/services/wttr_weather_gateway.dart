import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';
import 'weather_code_map.dart';
import 'weather_gateway.dart';

/// Резервный шлюз погоды: wttr.in (WorldWeatherOnline).
/// Бесплатный, без ключа и регистрации, доступен из России.
/// Даёт текущую погоду и прогноз на 3 дня; моря/волны нет —
/// морская секция шторки просто не показывается.
///
/// Включается только когда Open-Meteo не ответил (см.
/// [FallbackWeatherGateway]).
class WttrInWeatherGateway implements WeatherGateway {
  WttrInWeatherGateway({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 8);

  static const _userAgent =
      'IslandGuide/1.0 (+https://ednar.duckdns.org/audioguide)';

  @visibleForTesting
  static Uri buildUri(double latitude, double longitude) {
    return Uri.https('wttr.in', '/$latitude,$longitude', {'format': 'j1'});
  }

  @override
  Future<LocationWeather?> fetch(double latitude, double longitude) async {
    try {
      final response = await _client
          .get(
            buildUri(latitude, longitude),
            headers: {'User-Agent': _userAgent},
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final conditions = json['current_condition'] as List?;

      if (conditions == null || conditions.isEmpty) {
        return null;
      }

      final current = conditions.first as Map<String, dynamic>;

      final rawDays = json['weather'] as List? ?? const [];

      final days = <DailyWeather>[
        for (final raw in rawDays) _parseDay(raw as Map<String, dynamic>),
      ];

      return LocationWeather(
        temperature: _d(current['temp_C']) ?? 0,
        feelsLike: _d(current['FeelsLikeC']),
        humidity: _i(current['humidity']),
        precipitation: _d(current['precipMM']),
        cloudCover: _i(current['cloudcover']),
        pressureMsl: _d(current['pressure']),
        uvIndex: _d(current['uvIndex']),
        windSpeed: (_d(current['windspeedKmph']) ?? 0) / 3.6,
        windDirection: _d(current['winddirDegree']) ?? 0,
        weatherCode: wwoToWmo(_i(current['weatherCode']) ?? 113),
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

  static DailyWeather _parseDay(Map<String, dynamic> day) {
    final hourly =
        (day['hourly'] as List? ?? const []).cast<Map<String, dynamic>>();

    // Полдень (1200) — представитель дня для кода погоды и румба.
    final noon = hourly.length > 4
        ? hourly[4]
        : (hourly.isNotEmpty ? hourly.first : const <String, dynamic>{});

    final astronomy = day['astronomy'] as List? ?? const [];

    final astro = astronomy.isNotEmpty
        ? astronomy.first as Map<String, dynamic>
        : const <String, dynamic>{};

    final date = day['date'] as String? ?? '';

    return DailyWeather(
      date: date,
      maxTemperature: _d(day['maxtempC']) ?? 0,
      minTemperature: _d(day['mintempC']) ?? 0,
      precipitationProbability: hourly.isEmpty
          ? 0
          : hourly
              .map((h) => _i(h['chanceofrain']) ?? 0)
              .reduce((a, b) => a > b ? a : b),
      maxWindSpeed: hourly.isEmpty
          ? 0
          : hourly
              .map((h) => (_d(h['windspeedKmph']) ?? 0) / 3.6)
              .reduce((a, b) => a > b ? a : b),
      maxWindGusts: hourly.isEmpty
          ? null
          : hourly
              .map((h) => (_d(h['WindGustKmph']) ?? 0) / 3.6)
              .reduce((a, b) => a > b ? a : b),
      dominantWindDirection: _d(noon['winddirDegree']),
      uvIndexMax: _d(day['uvIndex']),
      precipitationSum: hourly.fold<double>(
        0,
        (sum, h) => sum + (_d(h['precipMM']) ?? 0),
      ),
      sunrise: _isoFrom12h(date, astro['sunrise'] as String?),
      sunset: _isoFrom12h(date, astro['sunset'] as String?),
      weatherCode: wwoToWmo(_i(noon['weatherCode']) ?? 113),
    );
  }

  /// «07:33 AM» + дата → «2026-11-07T07:33» (формат Open-Meteo,
  /// который ждёт [isoTimeOfDay]).
  static String? _isoFrom12h(String date, String? value) {
    if (value == null || date.isEmpty) {
      return null;
    }

    final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false)
        .firstMatch(value);

    if (match == null) {
      return null;
    }

    var hour = int.parse(match.group(1)!);

    final minute = match.group(2)!;

    final isPm = match.group(3)!.toUpperCase() == 'PM';

    if (isPm && hour != 12) {
      hour += 12;
    }

    if (!isPm && hour == 12) {
      hour = 0;
    }

    return '${date}T${hour.toString().padLeft(2, '0')}:$minute';
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
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }
}
