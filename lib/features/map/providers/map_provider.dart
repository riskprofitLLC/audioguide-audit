import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/utils/logger.dart';
import '../../content/models/region_catalog.dart';
import '../../content/providers/content_providers.dart';
import '../config/offline_map_style.dart';
import '../../settings/providers/settings_providers.dart';


/// Реактивная яркость ПЛАТФОРМЫ (D3): ThemeMode.system должен
/// замечать смену светлой/тёмной темы телефона без перезапуска.
///
/// Observer — МИКСИН (`with`), а не `implements` (баг 1, замечания
/// Sonnet): закрытие методов через noSuchMethod возвращало null
/// из `didPopRoute`/`didRequestAppExit` — при системном «Назад»
/// это TypeError. Миксин даёт штатные дефолты коллбэков.
class _PlatformBrightnessNotifier extends ValueNotifier<Brightness>
    with WidgetsBindingObserver {
  _PlatformBrightnessNotifier() : super(_current) {
    WidgetsBinding.instance.addObserver(this);
  }

  static Brightness get _current =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void didChangePlatformBrightness() {
    value = _current;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }
}

/// Палитра слоёв офлайн-карты по настройке темы (D3): тёмная —
/// для «Тёмной» и «Системной» (когда система тёмная), светлая —
/// во всех остальных случаях.
final mapStyleColorsProvider = Provider<MapStyleColors>((ref) {
  final mode = ref.watch(themeModeProvider);

  switch (mode) {
    case ThemeMode.dark:
      return MapStyleColors.dark;

    case ThemeMode.light:
      return MapStyleColors.light;

    case ThemeMode.system:
      // ChangeNotifierProvider: зависимые провайдеры перестраиваются
      // на каждый notify — палитра карты следует за темой телефона.
      final notifier = ref.watch(_platformBrightnessProvider);

      return notifier.value == Brightness.dark
          ? MapStyleColors.dark
          : MapStyleColors.light;
  }
});

final _platformBrightnessProvider =
    ChangeNotifierProvider<_PlatformBrightnessNotifier>((ref) {
  return _PlatformBrightnessNotifier();
});

/// Офлайн-стиль карты конкретного РЕГИОНА.
///
/// Карта одна на регион: стиль строится из регионального манифеста
/// (`content/<region_id>/manifest.json` + его `map.pmtiles`) плюс
/// глобальная офлайн-подложка суши `content/basemap.pmtiles` (A11,
/// 9-й проход): водяной фон + бумажная суша вокруг региона работают
/// без сети; растр OSM — только онлайн-обогащение.
final regionMapStyleFamily =
    FutureProvider.family<String?, String>((
      ref,
      regionId,
    ) async {

  // Пункт 6 (замечания Sonnet): все ref.watch — ДО первого await,
  // дальше только готовые значения. Реактивность палитры карты
  // (смена темы) и сервисов держится именно на этом watch.
  final manifestFut = ref.watch(regionManifestFamily(regionId).future);

  final mapStyleColors = ref.watch(mapStyleColorsProvider);

  final mapStyleService = ref.watch(mapStyleServiceProvider);

  final mapGlyphsService = ref.watch(mapGlyphsServiceProvider);

  final mapTileService = ref.watch(mapTileServiceProvider);

  final manifest =
      await manifestFut;

  AppLogger.info(
    '[regionMapStyleFamily] region=$regionId map="${manifest.map}" '
    'sourceLayer=${manifest.effectiveSourceLayer}',
  );

  // Глобальная подложка — общий ассет; недоступность (старый
  // бандл/тест) не ломает карту: стиль деградирует до бумаги.
  final basemapUrl = await _resolveBasemapUrl(ref);

  if (manifest.map.isEmpty) {
    AppLogger.info('[regionMapStyleFamily] $regionId has no map -> raster fallback');
    final glyphsUrl = await mapGlyphsService.glyphsUrl();
    final styleJson = jsonEncode(
      buildRasterOnlyMapStyle(
        glyphsUrl: glyphsUrl ?? '',
        basemapUrl: basemapUrl,
        colors: mapStyleColors,
      ),
    );
    final style = mapStyleService.styleString(styleJson);
    AppLogger.info('[regionMapStyleFamily] $regionId raster style ready (${style.length} chars)');
    return style;
  }

  final assetPath =
      '${regionAssetBase(regionId)}/${manifest.map}';

  final pmtilesUrl =
      await mapTileService.pmtilesUrl(
        assetPath,
      );

  AppLogger.info('[regionMapStyleFamily] $regionId pmtilesUrl=$pmtilesUrl');

  final glyphsUrl = await mapGlyphsService.glyphsUrl();

  final styleJson = jsonEncode(
    buildOfflineMapStyle(
      pmtilesUrl: pmtilesUrl,
      sourceId: manifest.id,
      sourceLayer: manifest.effectiveSourceLayer,
      glyphsUrl: glyphsUrl ?? '',
      basemapUrl: basemapUrl,
      colors: mapStyleColors,
    ),
  );

  final style = mapStyleService.styleString(
    styleJson,
  );

  AppLogger.info(
    '[regionMapStyleFamily] $regionId style ready (${style.length} chars)',
  );

  return style;
});


/// Офлайн-стиль карты конкретной локации (острова).
///
/// Стиль всегда региональный: карта одна на регион, локация лишь
/// выбирает, какая территория «активна». Оставлен как обёртка над
/// [regionMapStyleFamily], чтобы не менять вызовы в карте.
final mapStyleFamily =
    FutureProvider.family<String?, String>((
      ref,
      islandId,
    ) async {

  final region = regionOfLocation(islandId);

  return ref.watch(regionMapStyleFamily(region.id).future);
});

/// URL подложки: общий ассет, резолвится сервисом карты.
///
/// Ошибка (нет ассета в старом бандле, сбой ФС на native) не
/// должна ронять карту — null, и стиль рисует бумагу как раньше.
Future<String?> _resolveBasemapUrl(Ref ref) async {
  try {
    return await ref
        .watch(mapTileServiceProvider)
        .pmtilesUrl('content/basemap.pmtiles');
  } catch (error) {
    AppLogger.error(
      '[regionMapStyleFamily] basemap недоступен',
      error: error,
    );
    return null;
  }
}
