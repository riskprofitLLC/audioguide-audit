/// Погода локации (П7, 12-й проход): текущая — температура,
/// ветер, волна; прогноз — по дням. Открытые данные
/// Open-Meteo (forecast + marine), онлайн-обогащение: без сети
/// тихо отсутствует, офлайн-ядро приложения не страдает.
///
/// 21-й проход: полный срез данных сервиса — порывы, влажность,
/// давление, облачность, УФ, осадки; море — период/направление
/// волны, зыбь, температура воды.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LocationWeather {
  const LocationWeather({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    required this.weatherCode,
    this.waveHeight,
    this.feelsLike,
    this.humidity,
    this.precipitation,
    this.cloudCover,
    this.pressureMsl,
    this.uvIndex,
    this.windGusts,
    this.waveDirection,
    this.wavePeriod,
    this.windWaveHeight,
    this.swellWaveHeight,
    this.swellWavePeriod,
    this.swellWaveDirection,
    this.seaSurfaceTemperature,
    required this.daily,
  });

  /// Температура сейчас, °C.
  final double temperature;

  /// Ощущаемая температура, °C (apparent_temperature).
  final double? feelsLike;

  /// Влажность сейчас, %.
  final int? humidity;

  /// Осадки сейчас, мм.
  final double? precipitation;

  /// Облачность сейчас, %.
  final int? cloudCover;

  /// Давление на уровне моря, гПа.
  final double? pressureMsl;

  /// УФ-индекс сейчас (0–11+).
  final double? uvIndex;

  /// Скорость ветра сейчас, м/с.
  final double windSpeed;

  /// Направление ветра сейчас, метеорологические градусы
  /// (0 — север).
  final double windDirection;

  /// Порывы ветра сейчас, м/с.
  final double? windGusts;

  /// WMO-код погоды (0 — ясно, 61 — дождь и т.д.).
  final int weatherCode;

  /// Высота волны сейчас, метры (`null` — точка далеко от моря,
  /// marine-сетка Open-Meteo не покрывает).
  final double? waveHeight;

  /// Направление волны, метеорологические градусы (откуда идёт).
  final double? waveDirection;

  /// Период волны, секунды.
  final double? wavePeriod;

  /// Высота ветровой волны, метры.
  final double? windWaveHeight;

  /// Высота зыби, метры.
  final double? swellWaveHeight;

  /// Период зыби, секунды.
  final double? swellWavePeriod;

  /// Направление зыби, метеорологические градусы.
  final double? swellWaveDirection;

  /// Температура поверхности моря, °C.
  final double? seaSurfaceTemperature;

  /// Прогноз по дням (включая сегодня).
  final List<DailyWeather> daily;
}

class DailyWeather {
  const DailyWeather({
    required this.date,
    required this.maxTemperature,
    required this.minTemperature,
    required this.precipitationProbability,
    required this.maxWindSpeed,
    required this.weatherCode,
    this.maxWindGusts,
    this.dominantWindDirection,
    this.uvIndexMax,
    this.precipitationSum,
    this.sunrise,
    this.sunset,
  });

  /// День («2026-10-20»).
  final String date;

  final double maxTemperature;

  final double minTemperature;

  /// Максимальная вероятность осадков за день, %.
  final int precipitationProbability;

  final double maxWindSpeed;

  /// Порывы ветра, максимум за день, м/с.
  final double? maxWindGusts;

  /// Доминирующее направление ветра за день, градусы.
  final double? dominantWindDirection;

  /// Максимум УФ-индекса за день.
  final double? uvIndexMax;

  /// Сумма осадков за день, мм.
  final double? precipitationSum;

  /// Восход («2026-10-24T07:19», локальное время).
  final String? sunrise;

  /// Закат, аналогично восходу.
  final String? sunset;

  final int weatherCode;
}

/// Глиф и подпись по WMO-коду погоды (Open-Meteo).
({IconData icon, String label}) weatherGlyph(int code) {
  if (code == 0) {
    return (icon: LucideIcons.sun, label: 'ясно');
  }

  if (code == 1) {
    return (icon: LucideIcons.cloudSun, label: 'малооблачно');
  }

  if (code == 2) {
    return (icon: LucideIcons.cloud, label: 'облачно');
  }

  if (code == 3) {
    return (icon: LucideIcons.cloudy, label: 'пасмурно');
  }

  if (code >= 45 && code <= 48) {
    return (icon: LucideIcons.cloudFog, label: 'туман');
  }

  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return (icon: LucideIcons.cloudRain, label: 'дождь');
  }

  if (code >= 71 && code <= 77) {
    return (icon: LucideIcons.cloudSnow, label: 'снег');
  }

  if (code >= 95) {
    return (icon: LucideIcons.cloudLightning, label: 'гроза');
  }

  return (icon: LucideIcons.cloud, label: 'переменная облачность');
}

/// Румб ветра по метеорологическим градусам («западный» —
/// направление, ОТКУДА дует).
String windDirectionLabel(double degrees) {
  const names = [
    'северный',
    'северо-восточный',
    'восточный',
    'юго-восточный',
    'южный',
    'юго-западный',
    'западный',
    'северо-западный',
  ];

  final index = (((degrees + 22.5) % 360) / 45).floor();

  return names[index];
}

/// Короткий румб («СЗ», «Ю») — направление волны/зыби в плитках.
String compassPointLabel(double degrees) {
  const names = ['С', 'СВ', 'В', 'ЮВ', 'Ю', 'ЮЗ', 'З', 'СЗ'];

  final index = (((degrees + 22.5) % 360) / 45).floor();

  return names[index];
}

/// Слова про силу УФ-индекса (шкала ВОЗ).
String uvIndexLabel(double uv) {
  if (uv < 3) {
    return 'низкий';
  }

  if (uv < 6) {
    return 'умеренный';
  }

  if (uv < 8) {
    return 'высокий';
  }

  if (uv < 11) {
    return 'очень высокий';
  }

  return 'экстремальный';
}

/// Время из ISO-строки Open-Meteo («2026-10-24T07:19» → «07:19»);
/// не парсится — null.
String? isoTimeOfDay(String? iso) {
  if (iso == null) {
    return null;
  }

  final match = RegExp(r'T(\d{2}:\d{2})').firstMatch(iso);

  return match?.group(1);
}
