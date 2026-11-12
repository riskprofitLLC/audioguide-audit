import 'dart:convert';

import 'raster_tiles.dart';

/// Палитра слоёв офлайн-карты (D3, замечание Sonnet): светлая —
/// «бумага» Ликийского дневника, тёмная — чернильная ночь.
class MapStyleColors {
  const MapStyleColors({
    required this.water,
    required this.land,
    required this.forest,
    required this.buildings,
    required this.roadsMajor,
    required this.roadsMinor,
    required this.paths,
    required this.railway,
    required this.waterwayLines,
    required this.waterLabel,
    required this.landLabel,
    required this.placeLabel,
    required this.poiLabelColor,
    required this.poiLabelHaloColor,
    required this.trailCasingColor,
    required this.rasterOpacity,
    required this.rasterSaturation,
    required this.rasterContrast,
    this.rasterBrightnessMin = 0,
    this.rasterBrightnessMax = 1,
  });

  /// Светлая — бумага «Ликийского дневника».
  static const MapStyleColors light = MapStyleColors(
    water: '#a3c6dc',
    land: '#f2ede0',
    forest: '#dbe0c2',
    buildings: '#ded3c2',
    roadsMajor: '#e7cb87',
    roadsMinor: '#f0e5c9',
    paths: '#b3a06e',
    railway: '#a8a19a',
    waterwayLines: '#8fb9d8',
    // Подписи (D6): чернильные на бумаге, приглушённые на воде.
    waterLabel: '#41728c',
    landLabel: '#5d6e76',
    placeLabel: '#16333c',
    // Подписи POI и кант маршрута (A2): раньше были хардкодом
    // строк в map_overlays.dart и не переключались тёмной темой.
    poiLabelColor: '#16333c',
    poiLabelHaloColor: '#ffffff',
    trailCasingColor: '#ffffff',
    rasterOpacity: 0.78,
    rasterSaturation: -0.4,
    rasterContrast: -0.05,
  );

  /// Тёмная — «графит» (12.11.2026): монохромная ночь вместо
  /// насыщенной синей. Вода почти чёрная, суша — ступени серого,
  /// дороги и подписи — светлые. Единственный цвет на карте —
  /// сигнал избранного/выделения (его проверяет e2e).
  static const MapStyleColors dark = MapStyleColors(
    water: '#0c0c0e',
    land: '#1e1e21',
    forest: '#232327',
    buildings: '#2a2a2f',
    roadsMajor: '#7c7c85',
    roadsMinor: '#55555c',
    paths: '#5b5b63',
    railway: '#414147',
    waterwayLines: '#4a4a52',
    // Ночные подписи — светлые, гало — цвет подложки.
    waterLabel: '#9a9aa3',
    landLabel: '#b6b6be',
    placeLabel: '#f4f4f6',
    // Ночь: белый текст с тёмным гало (белое гало давало
    // «ореол» вокруг букв) и серый кант вместо синего.
    poiLabelColor: '#f4f4f6',
    poiLabelHaloColor: '#0b0b0c',
    trailCasingColor: '#74747d',
    // Ночной растр: светлые тайлы OSM (в светлой теме — «онлайн-
    // обогащение») в тёмной палитре забивали ночь. Гасим яркость
    // потолком (0.5) и почти снимаем насыщенность: тайлы дают
    // только текстуру, цвет задаёт палитра.
    rasterOpacity: 0.5,
    rasterSaturation: -0.85,
    rasterContrast: -0.05,
    rasterBrightnessMax: 0.5,
  );

  final String water;

  final String land;

  final String forest;

  final String buildings;

  final String roadsMajor;

  final String roadsMinor;

  final String paths;

  final String railway;

  final String waterwayLines;

  /// Подписи морей/заливов.
  final String waterLabel;

  /// Подписи лесов.
  final String landLabel;

  /// Подписи городов/мысов.
  final String placeLabel;

  /// Цвет подписей POI (A2): тёмная тема переключает его на
  /// пергаментный, иначе чернильный текст терялся на ночной карте.
  final String poiLabelColor;

  /// Гало подписей POI: днём белое, ночью — цвет подложки.
  final String poiLabelHaloColor;

  /// Кант линии маршрута: днём белый, ночью стальной.
  final String trailCasingColor;

  final double rasterOpacity;

  final double rasterSaturation;

  final double rasterContrast;

  /// Потолок/пол яркости растровой подложки (ночь: светлые
  /// тайлы OSM гасятся — иначе тёмная карта выглядит серой).
  final double rasterBrightnessMin;

  final double rasterBrightnessMax;
}

/// Сборка офлайн-стиля карты для PMTiles.
///
/// Стиль использует векторный источник (слой региона)
/// с архива PMTiles. На нативных платформах URL выглядит как
/// `pmtiles:///путь/к/файлу`, на web — `pmtiles://https://...`.
///
/// Палитра [colors] — светлая «бумага» или тёмная «ночь» (D3).
/// Слои снизу вверх:
///   1) фон: при наличии [basemapUrl] — ВОДА, иначе — суша
///      (совместимость без подложки);
///   2) глобальная офлайн-подложка суши z0–8 (`basemap-global`,
///      `content/basemap.pmtiles`): суша на водяном фоне —
///      контекст моря/соседей работает БЕЗ сети (A11, 9-й
///      проход);
///   3) растровая подложка OpenStreetMap как онлайн-обогащение:
///      приглушается по насыщенности, чтобы пёстрые OSM-тайлы
///      не спорили с палитрой;
///   4) векторные слои региона — свои вода/лес/дороги поверх.
///
/// Без сети вид: водяной фон + суша подложки + векторные тайлы
/// региона — офлайн-режим не ломается.
///
/// Наложения (POI и маршруты) добавляются отдельно как
/// GeoJSON-источники уже после загрузки стиля.

Map<String, dynamic> buildOfflineMapStyle({
  required String pmtilesUrl,
  String sourceId = 'gemiler',
  String sourceLayer = 'gemiler',
  String glyphsUrl = '',
  String? basemapUrl,
  MapStyleColors colors = MapStyleColors.light,
}) {
  final hasBasemap = basemapUrl != null && basemapUrl.isNotEmpty;

  return {
    'version': 8,
    if (glyphsUrl.isNotEmpty) 'glyphs': glyphsUrl,
    'sources': {
      if (hasBasemap)
        'basemap-global': {
          'type': 'vector',
          'url': basemapUrl,
          'attribution': 'Natural Earth (public domain)',
        },
      sourceId: {
        'type': 'vector',
        'url': pmtilesUrl,
        'attribution': '© OpenStreetMap contributors',
      },
      'basemap': {
        'type': 'raster',
        'tiles': [RasterTiles.urlTemplate],
        'tileSize': RasterTiles.tileSize,
        'minzoom': 0,
        'maxzoom': RasterTiles.maxZoom,
        'attribution': '© OpenStreetMap contributors',
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {
          // С подложкой фон — вода: суша рисуется поверх, море
          // остаётся «по умолчанию» (берег — правильная
          // дефолтная ошибка для морского гида).
          'background-color': hasBasemap ? colors.water : colors.land,
        },
      },
      if (hasBasemap)
        {
          'id': 'basemap-land',
          'type': 'fill',
          'source': 'basemap-global',
          'source-layer': 'basemap',
          'paint': {
            'fill-color': colors.land,
          },
        },
      {
        'id': 'basemap-raster',
        'type': 'raster',
        'source': 'basemap',
        'paint': {
          'raster-opacity': colors.rasterOpacity,
          'raster-saturation': colors.rasterSaturation,
          'raster-contrast': colors.rasterContrast,
          // Ночь: потолок яркости гасит светлые тайлы OSM, иначе
          // «ночная карта» вымывается серым (D3).
          'raster-brightness-min': colors.rasterBrightnessMin,
          'raster-brightness-max': colors.rasterBrightnessMax,
        },
      },
      {
        'id': 'water-fill',
        'type': 'fill',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'any',
          ['==', ['get', 'natural'], 'water'],
          ['==', ['get', 'waterway'], 'riverbank'],
          ['has', 'seamark:type'],
        ],
        'paint': {
          'fill-color': colors.water,
        },
      },
      {
        'id': 'forest-fill',
        'type': 'fill',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'any',
          ['==', ['get', 'natural'], 'wood'],
          ['==', ['get', 'landuse'], 'forest'],
          ['==', ['get', 'natural'], 'scrub'],
        ],
        'paint': {
          'fill-color': colors.forest,
        },
      },
      {
        'id': 'buildings-fill',
        'type': 'fill',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': ['has', 'building'],
        'paint': {
          'fill-color': colors.buildings,
          'fill-opacity': 0.92,
        },
      },
      {
        'id': 'roads-major',
        'type': 'line',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'match',
          ['get', 'highway'],
          ['trunk', 'trunk_link',
           'primary', 'primary_link',
           'secondary', 'secondary_link'],
          true,
          false,
        ],
        'paint': {
          'line-color': colors.roadsMajor,
          'line-width': [
            'interpolate', ['linear'], ['zoom'],
            8, 1.5,
            14, 6,
          ],
        },
        'layout': {
          'line-cap': 'round',
          'line-join': 'round',
        },
      },
      {
        'id': 'roads-minor',
        'type': 'line',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'match',
          ['get', 'highway'],
          ['tertiary', 'tertiary_link',
           'residential', 'unclassified',
           'living_street', 'service'],
          true,
          false,
        ],
        'paint': {
          'line-color': colors.roadsMinor,
          'line-width': [
            'interpolate', ['linear'], ['zoom'],
            8, 0.8,
            14, 4,
          ],
        },
        'layout': {
          'line-cap': 'round',
          'line-join': 'round',
        },
      },
      {
        'id': 'paths',
        'type': 'line',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'match',
          ['get', 'highway'],
          ['footway', 'path', 'steps', 'track', 'cycleway'],
          true,
          false,
        ],
        'paint': {
          'line-color': colors.paths,
          'line-width': 1.5,
          'line-dasharray': [2, 1.5],
        },
        'layout': {
          'line-cap': 'round',
          'line-join': 'round',
        },
      },
      {
        'id': 'railway',
        'type': 'line',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': ['has', 'railway'],
        'paint': {
          'line-color': colors.railway,
          'line-width': 1,
        },
      },
      {
        'id': 'waterway-lines',
        'type': 'line',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': ['has', 'waterway'],
        'paint': {
          'line-color': colors.waterwayLines,
          'line-width': 1,
        },
      },

      // ---- Топонимы из pmtiles (D6, замечание Sonnet) ----
      // Подписи морей/заливов и лесов: name сохранён у крупных
      // объектов (build_region_map.py: NAME_TAGS), карта без
      // названий выглядела пустой.
      {
        'id': 'water-names',
        'type': 'symbol',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'all',
          ['has', 'name'],
          [
            'any',
            ['==', ['get', 'natural'], 'water'],
            ['==', ['get', 'place'], 'sea'],
            ['==', ['get', 'place'], 'island'],
          ],
        ],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': const ['NotoSans'],
          'text-size': const [
            'interpolate', ['linear'], ['zoom'],
            8, 10,
            13, 13,
          ],
          'text-letter-spacing': 0.24,
          'text-max-width': 7,
          'text-transform': 'uppercase',
        },
        'paint': {
          'text-color': colors.waterLabel,
          'text-halo-color': colors.water,
          'text-halo-width': 1.4,
        },
      },
      {
        'id': 'land-names',
        'type': 'symbol',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'all',
          ['has', 'name'],
          [
            'any',
            ['==', ['get', 'natural'], 'wood'],
            ['==', ['get', 'landuse'], 'forest'],
          ],
        ],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': const ['NotoSans'],
          'text-size': const [
            'interpolate', ['linear'], ['zoom'],
            11, 10,
            14, 12,
          ],
          'text-letter-spacing': 0.08,
          'text-max-width': 7,
        },
        'paint': {
          'text-color': colors.landLabel,
          'text-halo-color': colors.land,
          'text-halo-width': 1.2,
        },
      },
      {
        'id': 'place-names',
        'type': 'symbol',
        'source': sourceId,
        'source-layer': sourceLayer,
        'filter': [
          'all',
          ['has', 'name'],
          ['has', 'place'],
        ],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': const ['NotoSans'],
          'text-size': const [
            'interpolate', ['linear'], ['zoom'],
            8, 10,
            12, 12,
            14, 14,
          ],
          'text-letter-spacing': 0.04,
          'text-max-width': 8,
        },
        'paint': {
          'text-color': colors.placeLabel,
          'text-halo-color': colors.land,
          'text-halo-width': 1.4,
        },
      },
    ],
  };
}

/// Стиль без векторных тайлов региона — только глобальная
/// подложка + OSM растр (для регионов без `map.pmtiles`,
/// метки всё равно отрисуются).
Map<String, dynamic> buildRasterOnlyMapStyle({
  String glyphsUrl = '',
  String? basemapUrl,
  MapStyleColors colors = MapStyleColors.light,
}) {
  final hasBasemap = basemapUrl != null && basemapUrl.isNotEmpty;

  return {
    'version': 8,
    if (glyphsUrl.isNotEmpty) 'glyphs': glyphsUrl,
    'sources': {
      if (hasBasemap)
        'basemap-global': {
          'type': 'vector',
          'url': basemapUrl,
          'attribution': 'Natural Earth (public domain)',
        },
      'basemap': {
        'type': 'raster',
        'tiles': [RasterTiles.urlTemplate],
        'tileSize': RasterTiles.tileSize,
        'minzoom': 0,
        'maxzoom': RasterTiles.maxZoom,
        'attribution': '© OpenStreetMap contributors',
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {
          'background-color': hasBasemap ? colors.water : colors.land,
        },
      },
      if (hasBasemap)
        {
          'id': 'basemap-land',
          'type': 'fill',
          'source': 'basemap-global',
          'source-layer': 'basemap',
          'paint': {
            'fill-color': colors.land,
          },
        },
      {
        'id': 'basemap-raster',
        'type': 'raster',
        'source': 'basemap',
        'paint': {
          'raster-opacity': colors.rasterOpacity,
          'raster-saturation': colors.rasterSaturation,
          'raster-contrast': colors.rasterContrast,
          // Ночь: потолок яркости гасит светлые тайлы OSM (D3).
          'raster-brightness-min': colors.rasterBrightnessMin,
          'raster-brightness-max': colors.rasterBrightnessMax,
        },
      },
    ],
  };
}

/// Сериализация стиля в JSON-строку для виджета карты.
String encodeOfflineMapStyle({
  required String pmtilesUrl,
  String sourceId = 'gemiler',
  String sourceLayer = 'gemiler',
  String glyphsUrl = '',
  String? basemapUrl,
  MapStyleColors colors = MapStyleColors.light,
}) {
  return jsonEncode(
    buildOfflineMapStyle(
      pmtilesUrl: pmtilesUrl,
      sourceId: sourceId,
      sourceLayer: sourceLayer,
      glyphsUrl: glyphsUrl,
      basemapUrl: basemapUrl,
      colors: colors,
    ),
  );
}
