import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/floating_pill.dart';
import '../../../../features/weather/models/weather.dart';

/// Чип погоды на карте (П7, 16-й проход): тап-цель 44, язык
/// плавающих пилюль карты (радиус pill, «стекло» + floating-тень)
/// — как NearestPoiChip. На узких экранах ветер/волна сворачиваются
/// в иконки с числом, без текстовых подписей.
class WeatherChip extends StatelessWidget {
  const WeatherChip({
    super.key,
    required this.weather,
    required this.onTap,
    this.narrow = false,
  });

  final LocationWeather weather;

  final VoidCallback onTap;

  /// Узкий экран: ветер/волна — иконки с числом, без «м/с»/«м».
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final glyph = weatherGlyph(weather.weatherCode);

    final summary = 'Погода: ${weather.temperature.round()} градусов, '
        'ветер ${weather.windSpeed.round()} метров в секунду'
        '${weather.waveHeight != null ? ', волна ${weather.waveHeight!.toStringAsFixed(1)} метра' : ''}';

    // D2: каркас — FloatingPill («стекло» + floating-тень,
    // тап-цель 44). Ведущий элемент — глиф погоды с температурой.
    return FloatingPill(
      tone: FloatingPillTone.neutral,
      onTap: onTap,
      semanticsLabel: summary,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            glyph.icon,
            size: 16,
            color: palette.info,
          ),
          const SizedBox(width: 7),
          Text(
            '${weather.temperature.round()}°',
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.info,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      gap: 10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CompactStat(
            icon: LucideIcons.wind,
            value: '${weather.windSpeed.round()}'
                '${narrow ? '' : ' м/с'}',
          ),
          if (weather.waveHeight != null) ...[
            const SizedBox(width: 8),
            _CompactStat(
              icon: LucideIcons.waves,
              value:
                  '${weather.waveHeight!.toStringAsFixed(1)}${narrow ? '' : ' м'}',
            ),
          ],
        ],
      ),
    );
  }
}

/// Иконка-статистика чипа: иконка + компактное значение.
class _CompactStat extends StatelessWidget {
  const _CompactStat({required this.icon, required this.value});

  final IconData icon;

  final String value;

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: palette.onSurfaceMuted,
        ),
        const SizedBox(width: 3),
        Text(
          value,
          style: AppText.label.copyWith(
            color: palette.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}

/// Строка прогноза на день (шторка погоды, П7/B3): компактная
/// двухстрочная вёрстка — помещается на 360 px при textScale 1.6,
/// шкала температуры мин–макс, полный Semantics на строку.
class WeatherForecastRow extends StatelessWidget {
  const WeatherForecastRow({
    super.key,
    required this.day,
    required this.isToday,
  });

  final DailyWeather day;

  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final glyph = weatherGlyph(day.weatherCode);

    final label = isToday ? 'сегодня' : _weekdayLabel(day.date);

    final condition = glyph.label +
        (day.precipitationProbability > 0
            ? ', осадки ${day.precipitationProbability}%'
            : '');

    final min = day.minTemperature;
    final max = day.maxTemperature;

    final sunriseTime = isoTimeOfDay(day.sunrise);

    final sunsetTime = isoTimeOfDay(day.sunset);

    // Колонка дня растёт с textScale: при 1.6 время восхода
    // («07:18» с иконкой) не влезает в фиксированные 84 px.
    final textScale =
        MediaQuery.textScalerOf(context).scale(12) / 12;

    final labelWidth = 84.0 * textScale.clamp(1.0, 1.6);

    final semantics = '$label: $condition, от ${min.round()} до '
        '${max.round()} градусов, ветер до '
        '${day.maxWindSpeed.round()} метров в секунду'
        '${day.maxWindGusts != null ? ', порывы до ${day.maxWindGusts!.round()}' : ''}'
        '${sunriseTime != null ? ', восход $sunriseTime' : ''}'
        '${sunsetTime != null ? ', закат $sunsetTime' : ''}';

    return Semantics(
      container: true,
      label: semantics,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  // Восход/закат дня: Wrap — при textScale кластеры
                  // переносятся строкой, а не рвут колонку.
                  if (sunriseTime != null || sunsetTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          if (sunriseTime != null)
                            _SunTime(
                              icon: LucideIcons.sunrise,
                              time: sunriseTime,
                            ),
                          if (sunsetTime != null)
                            _SunTime(
                              icon: LucideIcons.sunset,
                              time: sunsetTime,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              glyph.icon,
              size: 18,
              color: palette.info,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          condition,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.onSurfaceMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // FittedBox-время (паттерн A7/B5 9-го прохода):
                      // при textScale 1.6 на узких не переполняет.
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '+${max.round()}° / +${min.round()}°',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color:
                                    palette.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Визуальная шкала температуры (B3): тонкая
                  // полоса мин–макс в общем диапазоне прогноза.
                  _TempScaleBar(min: min, max: max),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              LucideIcons.wind,
              size: 13,
              color: palette.onSurfaceMuted,
            ),
            const SizedBox(width: 3),
            Text(
              '${day.maxWindSpeed.round()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
            // Порывы дня — рядом со средним максимумом (21-й
            // проход): именно они решают, идти ли на воду.
            if (day.maxWindGusts != null) ...[
              const SizedBox(width: 5),
              Icon(
                LucideIcons.windArrowDown,
                size: 12,
                color: palette.onSurfaceMuted,
              ),
              const SizedBox(width: 2),
              Text(
                '${day.maxWindGusts!.round()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.onSurfaceMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _weekdayLabel(String date) {
    final parsed = DateTime.tryParse(date);

    if (parsed == null) {
      return date;
    }

    const weekdays = [
      'пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс',
    ];

    // Завтра — читабельнее дня недели (прогноз короткий).
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    if (parsed.year == tomorrow.year &&
        parsed.month == tomorrow.month &&
        parsed.day == tomorrow.day) {
      return 'завтра';
    }

    return weekdays[parsed.weekday - 1];
  }
}

/// Мини-кластер времени солнца в колонке дня строки прогноза.
class _SunTime extends StatelessWidget {
  const _SunTime({required this.icon, required this.time});

  final IconData icon;

  final String time;

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: palette.onSurfaceMuted),
        const SizedBox(width: 2),
        Text(
          time,
          style: AppText.label.copyWith(
            color: palette.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}

/// Тонкая полоса температуры дня внутри общего диапазона
/// прогноза (B3): заливка от min до max, фон — sand.
class _TempScaleBar extends StatelessWidget {
  const _TempScaleBar({required this.min, required this.max});

  final double min;

  final double max;

  /// Диапазон шкалы: фикс по физике прогноза побережья.
  static const double _scaleLow = 5;
  static const double _scaleHigh = 45;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final left = ((min - _scaleLow) / (_scaleHigh - _scaleLow))
        .clamp(0.0, 1.0);

    final right = ((max - _scaleLow) / (_scaleHigh - _scaleLow))
        .clamp(0.0, 1.0);

    return SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          if (width <= 0) {
            return const SizedBox.shrink();
          }

          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.sand,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ),
              Positioned(
                left: width * left,
                width: (width * (right - left)).clamp(4.0, width),
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.info,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
