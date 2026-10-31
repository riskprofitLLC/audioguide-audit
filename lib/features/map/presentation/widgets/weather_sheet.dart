import 'package:flutter/material.dart';
import '../../../../core/utils/format.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../features/weather/models/weather.dart';
import 'weather_chip.dart';

/// Тело шторки «Погода на побережье» (21-й проход): полный
/// срез данных Open-Meteo — «сейчас» (порывы, влажность,
/// давление, облачность, УФ, осадки), море (волна с периодом
/// и направлением, зыбь, температура воды) и прогноз на 3 дня.
///
/// Каркас (ручка/шапка/скролл) — `showAppBottomSheet`, этот
/// виджет — только контент.
class WeatherSheet extends StatelessWidget {
  const WeatherSheet({super.key, required this.weather});

  final LocationWeather weather;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final glyph = weatherGlyph(weather.weatherCode);

    // Подзаголовок «ощущается · влажность» — из того, что есть.
    final nowParts = <String>[
      if (weather.feelsLike != null)
        'ощущается ${weather.feelsLike!.round()}°',
      if (weather.humidity != null) 'влажность ${weather.humidity}%',
    ];

    final airTiles = _airTiles(weather);

    final marineTiles = _marineTiles(weather);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(glyph.icon, size: 24, color: palette.info),
            const SizedBox(width: 10),
            Text(
              '${weather.temperature.round()}° · ${glyph.label}',
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (nowParts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            nowParts.join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.onSurfaceMuted),
          ),
        ],
        if (airTiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          _StatGrid(tiles: airTiles),
        ],
        if (marineTiles.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'МОРЕ',
            style: AppText.eyebrowMuted.copyWith(color: palette.onSurfaceMuted),
          ),
          const SizedBox(height: 8),
          _StatGrid(tiles: marineTiles),
        ],
        const SizedBox(height: 6),
        for (var i = 0; i < weather.daily.length; i++)
          WeatherForecastRow(
            day: weather.daily[i],
            isToday: i == 0,
          ),
        const SizedBox(height: 8),
        Text(
          'Данные — Open-Meteo, нужны интернет; без сети прогноз '
          'не показывается.',
          style: AppText.label.copyWith(
            color: palette.onSurfaceMuted,
          ),
        ),
      ],
    );
  }

  /// Плитки «сейчас»: ветер, порывы, облачность, давление, УФ,
  /// осадки. Отсутствующие в ответе — тихо пропускаются.
  static List<_StatTile> _airTiles(LocationWeather weather) {
    return [
      _StatTile(
        icon: LucideIcons.wind,
        label: 'Ветер',
        value: '${weather.windSpeed.round()} м/с · '
            '${compassPointLabel(weather.windDirection)}',
      ),
      if (weather.windGusts != null)
        _StatTile(
          icon: LucideIcons.windArrowDown,
          label: 'Порывы',
          value: '${weather.windGusts!.round()} м/с',
        ),
      if (weather.cloudCover != null)
        _StatTile(
          icon: LucideIcons.cloud,
          label: 'Облачность',
          value: '${weather.cloudCover}%',
        ),
      if (weather.pressureMsl != null)
        _StatTile(
          icon: LucideIcons.gauge,
          label: 'Давление',
          value: '${weather.pressureMsl!.round()} гПа',
        ),
      if (weather.uvIndex != null)
        _StatTile(
          icon: LucideIcons.sun,
          label: 'УФ-индекс',
          value: '${formatDecimalRu(weather.uvIndex!)} · '
              '${uvIndexLabel(weather.uvIndex!)}',
        ),
      if (weather.precipitation != null)
        _StatTile(
          icon: LucideIcons.umbrella,
          label: 'Осадки',
          value: '${formatDecimalRu(weather.precipitation!)} мм',
        ),
    ];
  }

  /// Плитки моря: волна (высота · откуда), период, зыбь,
  /// ветровая волна, температура воды.
  static List<_StatTile> _marineTiles(LocationWeather weather) {
    return [
      if (weather.waveHeight != null)
        _StatTile(
          icon: LucideIcons.waves,
          label: 'Волна',
          value: '${formatDecimalRu(weather.waveHeight!)} м'
              '${weather.waveDirection != null ? ' · ${compassPointLabel(weather.waveDirection!)}' : ''}',
        ),
      if (weather.wavePeriod != null)
        _StatTile(
          icon: LucideIcons.timer,
          label: 'Период волны',
          value: '${formatDecimalRu(weather.wavePeriod!)} с',
        ),
      if (weather.swellWaveHeight != null)
        _StatTile(
          icon: LucideIcons.waves,
          label: 'Зыбь',
          value: '${formatDecimalRu(weather.swellWaveHeight!)} м'
              '${weather.swellWavePeriod != null ? ' · ${formatDecimalRu(weather.swellWavePeriod!)} с' : ''}'
              '${weather.swellWaveDirection != null ? ' · ${compassPointLabel(weather.swellWaveDirection!)}' : ''}',
        ),
      // Нулевая ветровая волна — шум, показываем только заметную.
      if (weather.windWaveHeight != null && weather.windWaveHeight! > 0.05)
        _StatTile(
          icon: LucideIcons.wind,
          label: 'Ветровая волна',
          value: '${formatDecimalRu(weather.windWaveHeight!)} м',
        ),
      if (weather.seaSurfaceTemperature != null)
        _StatTile(
          icon: LucideIcons.thermometerSun,
          label: 'Вода',
          value: '${formatDecimalRu(weather.seaSurfaceTemperature!)}°',
        ),
    ];
  }
}

/// Сетка плиток статистики: 2 колонки на телефоне, 3 — от 520 px
/// (tile-подобные плашки sand, как шкала температуры прогноза).
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;

        final columns = constraints.maxWidth >= 520 ? 3 : 2;

        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

/// Плитка «подпись + значение»: иконка, приглушённая подпись,
/// весомое значение. MergeSemantics — одна смысловая точка.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;

  final String label;

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: palette.sand,
          borderRadius:
              const BorderRadius.all(Radius.circular(AppRadius.tile)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 14, color: palette.info),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // onSurface@0.8, а не muted: 11 px на sand —
                    // мелкий текст, muted даёт всего 3.84:1.
                    style: AppText.label.copyWith(
                      color: palette.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
