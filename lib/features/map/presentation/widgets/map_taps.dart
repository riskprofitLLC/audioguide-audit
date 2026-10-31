part of 'map_widget.dart';


/// Останавливать ли плеер после закрытия шторки POI (A4, 10-й
/// проход).
///
/// Раньше закрытие шторки глушило ЛЮБОЙ играющий трек: автогид
/// или вручную запущенный рассказ другой точки умирал от того,
/// что пользователь просто заглянул в карточку и закрыл её.
/// Аудиогид — фон путешествия: остановка — только явная.
/// Глушим трек ТОЛЬКО если играет файл именно этой точки.
bool shouldStopAfterPoiSheetClose(
  String? currentFile,
  Poi poi,
  String locationId,
) {
  if (currentFile == null || poi.audioPath == null) {
    return false;
  }

  return currentFile == poi.audioAssetPath(locationId);
}


/// Обработка тапов по фичам карты (POI и маршруты) и показ
/// соответствующих нижних шитов.
///
/// Вынесены из `_MapWidgetState` в отдельный файл, чтобы уменьшить
/// размер основного файла карты.
mixin _MapTapsMixin on _MapOverlaysMixin {

  /// Тап по чипу ближайшей точки (B4, 17-й проход): подлетаем
  /// к точке и открываем её шторку.
  Future<void> _onNearestPoiTap() async {

    final nearest = _nearestPoi;

    if (nearest == null) {
      return;
    }

    // Ручной полёт к точке — слежение больше не нужно.
    _setFollowing(false);

    final controller = _controller;

    if (controller != null) {

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(nearest.$1.latitude, nearest.$1.longitude),
          15,
        ),
      );
    }

    if (!mounted) {
      return;
    }

    await _showPoiInfo(nearest.$1, locationId: nearest.$2);
  }

  /// Обработчик тапа по фиче (POI или маршрут).
  ///
  /// На web maplibre не сохраняет топ-левел id фичи (строковые id
  /// GeoJSON превращаются в 0), поэтому полезную нагрузку берём
  /// из properties через запрос фич в точке.
  void _handleFeatureTap(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {

    AppLogger.info(
      '[MapWidget] featureTap point=(${point.x},${point.y}) '
      'lat=${coordinates.latitude} lng=${coordinates.longitude} '
      'id=$id layer=$layerId',
    );

    _findTappedItem(point, id, layerId);
  }


  Future<void> _findTappedItem(
    Point<double> point,
    String payloadId,
    String layerId,
  ) async {

    AppLogger.info(
      '[MapWidget] _findTappedItem layer=$layerId payloadId=$payloadId '
      'pois=${_pois.length} trails=${_trails.length}',
    );

    // Тап по кластеру: приближаем карту в точке тапа — группа
    // распадается на отдельные объекты. Кластеры живут на любой
    // полной карте (и в однолокационном режиме с подсветкой ?poi=).
    if (layerId == 'pois-clusters' || layerId == 'pois-cluster-count') {

      final controller = _controller;

      if (controller != null) {

        AppLogger.info(
          '[MapWidget] cluster tap → zoomBy(+2) at '
          '(${point.x},${point.y})',
        );

        await controller.animateCamera(
          CameraUpdate.zoomBy(2, Offset(point.x, point.y)),
        );
      }

      return;
    }

    if (layerId == 'poi-balls' ||
        layerId == 'poi-icons' ||
        layerId == 'poi-labels') {

      final found = _resolvePoiFeature(payloadId);

      if (found != null) {

        // Открытие шторки — fire-and-forget из обработчика тапа.
        unawaited(_showPoiInfo(found.$1, locationId: found.$2));

        return;
      }
    }

    if (layerId == 'trail-lines') {

      final found = _resolveTrailFeature(payloadId);

      if (found != null) {

        unawaited(_showTrailInfo(found.$1, locationId: found.$2));

        return;
      }
    }

    final controller = _controller;

    if (controller == null) {

      return;
    }

    final hitTestTrails =
        _showAllRegions || (_manifest?.trailHitTest ?? true);

    final layerIds = [
      // Кластерные слои на любой полной карте — с них начинается
      // поиск фич в точке тапа.
      if (!widget.preview) ...[
        'pois-clusters',
        'pois-cluster-count',
      ],
      'poi-balls',
      'poi-icons',
      'poi-labels',
      // Hit-test линий маршрутов выносится в флаг манифеста
      // trailHitTest (P2): раньше хардкод id «gemiler».
      if (hitTestTrails) 'trail-lines',
    ];

    // На web плагинный запрос фич мёртв при работающем пульсе
    // подсветки: его гейт isStyleLoaded почти всегда закрыт (каждый
    // paint-сет пульса помечает источник перезагрузкой). Запрашиваем
    // напрямую через JS-API — см. map_feature_query_web.dart.
    final features = kIsWeb
        ? await queryMapFeaturesAtPoint(point.x, point.y, layerIds)
        : await controller.queryRenderedFeatures(
            point,
            layerIds,
            null,
          );

    AppLogger.info(
      '[MapWidget] queryRenderedFeatures at ($point) -> ${features.length} features',
    );

    if (features.isEmpty || !mounted) {

      return;
    }

    final properties = (features.first as Map)['properties'] as Map?;

    // Тап пришёлся по кластеру: вместо шторки приближаем карту,
    // чтобы группа распалась на точки.
    if (properties?['point_count'] != null) {

      await controller.animateCamera(
        CameraUpdate.zoomBy(2, Offset(point.x, point.y)),
      );

      return;
    }

    // В обычном режиме свойства хранят id в поле `id`, в режиме
    // «все регионы» — исходный id в `poiId`/`trailId` и локацию
    // в `locationId`.
    final poiId = properties?['poiId'] ?? properties?['id'];

    if (poiId != null) {

      final locationId = properties?['locationId'] as String? ?? '';

      final found = _showAllRegions
          ? _findPoiFeatureByLocation(poiId.toString(), locationId)
          : _findPoiWithLocation(poiId.toString());

      if (found != null) {

        // Открытие шторки — fire-and-forget из обработчика тапа.
        unawaited(_showPoiInfo(found.$1, locationId: found.$2));

        return;
      }
    }

    final trailId = properties?['trailId'] ?? properties?['id'];

    if (trailId != null) {

      final locationId = properties?['locationId'] as String? ?? '';

      final found = _showAllRegions
          ? _findTrailFeatureByLocation(trailId.toString(), locationId)
          : _findTrailWithLocation(trailId.toString());

      if (found != null) {

        unawaited(_showTrailInfo(found.$1, locationId: found.$2));

        return;
      }
    }
  }


  /// Ищет POI по исходному id в конкретной локации
  /// (для резолва через properties из queryRenderedFeatures).
  (Poi, String)? _findPoiFeatureByLocation(
    String poiId,
    String locationId,
  ) {

    for (var i = 0; i < _pois.length; i++) {

      if (_pois[i].id == poiId && _poiLocations[i] == locationId) {

        return (_pois[i], locationId);
      }
    }

    return null;
  }


  /// Ищет маршрут по исходному id в конкретной локации.
  (Trail, String)? _findTrailFeatureByLocation(
    String trailId,
    String locationId,
  ) {

    for (var i = 0; i < _trails.length; i++) {

      if (_trails[i].id == trailId && _trailLocations[i] == locationId) {

        return (_trails[i], locationId);
      }
    }

    return null;
  }


  Future<void> _showPoiInfo(
    Poi poi, {
    required String locationId,
  }) async {

    // Защита от наслоения шторок: на web канвас maplibre получает
    // тапы даже поверх открытого шита, и без этой проверки тап по
    // фотографии в галерее снова открывал бы шит того же/другого POI.
    if (_sheetOpen) {

      AppLogger.info(
        '[MapWidget] skip PoiInfoSheet ${poi.id} — шит уже открыт',
      );

      return;
    }

    AppLogger.info('[MapWidget] show PoiInfoSheet ${poi.id} ${poi.title}');

    _sheetOpen = true;

    acquireMapInputLock();

    // Пилюля мини-плеера не должна висеть поверх шторки.
    // Синхронный throw (контекст без Navigator) не должен
    // оставлять счётчик поднятым — как в showAppBottomSheet
    // (баг 16, замечания Sonnet).
    modalSheetOpenCount.value++;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        sheetAnimationStyle: AppTheme.sheetAnimationStyle,
        // Лист «со стопами» (1d, 12-й проход): старт на прежних
        // 70% (верх карты виден, как раньше), вверх — до 95% для
        // длинных описаний; резкий утяг вниз (ниже 0.45) —
        // закрывает шторку, как прежний «жест вниз».
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.7],
          builder: (context, scrollController) => PoiInfoSheet(
            poi: poi,
            islandId: locationId,
            scrollController: scrollController,
          ),
        ),
      );

    } finally {

      _sheetOpen = false;

      releaseMapInputLock();

      modalSheetOpenCount.value--;
    }

    // Закрытие шторки глушит только трек ЭТОЙ точки (A4, 10-й
    // проход): звучащий автогид/фоновый рассказ другой точки —
    // фон путешествия, его закрытие карточки не касается.
    if (!mounted) {
      return;
    }

    final service = ref.read(audioPlayerServiceProvider);

    if (shouldStopAfterPoiSheetClose(
      service.currentFile,
      poi,
      locationId,
    )) {
      await service.stop();
    }
  }


  Future<void> _showTrailInfo(
    Trail trail, {
    required String locationId,
  }) async {

    if (_sheetOpen) {

      AppLogger.info(
        '[MapWidget] skip TrailInfoSheet ${trail.id} — шит уже открыт',
      );

      return;
    }

    AppLogger.info('[MapWidget] show TrailInfoSheet ${trail.id} ${trail.name}');

    _sheetOpen = true;

    acquireMapInputLock();

    // Пилюля мини-плеера не должна висеть поверх шторки.
    // Счётчик защищён try/catch: синхронный throw showModalBottomSheet
    // (контекст без Navigator) не оставляет счётчик поднятым (баг 16,
    // замечания Sonnet — как в showAppBottomSheet).
    modalSheetOpenCount.value++;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        sheetAnimationStyle: AppTheme.sheetAnimationStyle,
        // Лист «со стопами» — как шторка POI (1d, 12-й проход):
        // резкий утяг вниз закрывает, как прежний «жест вниз».
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.7],
          builder: (context, scrollController) => TrailInfoSheet(
            trail: trail,
            islandId: locationId,
            scrollController: scrollController,
            // A8: тип перемещения — из манифеста ЛОКАЦИИ тапа, а не
            // текущей (в «всех регионах» бейдж брал чужую локацию).
            isBoat: ref
                    .read(islandManifestFamily(locationId))
                    .value
                    ?.isBoat ??
                false,
            // Кадры — только фото ТОЧЕК МАРШРУТА (P1-3, 7-й проход):
            // общий хелпер с галереей страницы маршрута; в режиме
            // «все регионы» сначала фильтруем POI по локации.
            imagePaths: trailGalleryImages(
              [
                for (var i = 0; i < _pois.length; i++)
                  if (_poiLocations[i] == locationId) _pois[i],
              ],
              trail.id,
            ),
            // Точки маршрута: счётчик и каскад ключей избранного
            // для звезды в шторке (P1-3).
            poiCount: [
              for (var i = 0; i < _pois.length; i++)
                if (_poiLocations[i] == locationId &&
                    _pois[i].trailIds.contains(trail.id))
                  _pois[i],
            ].length,
            cascadeKeys: [
              for (var i = 0; i < _pois.length; i++)
                if (_poiLocations[i] == locationId &&
                    _pois[i].trailIds.contains(trail.id))
                  '$locationId/${_pois[i].id}',
            ],
          ),
        ),
      );
    } finally {
      // Прежний код снимал счётчик в whenComplete: синхронный
      // throw showModalBottomSheet (контекст без Navigator)
      // обходил его — счётчик оставался поднятым навсегда, и
      // мини-плеер прятался до конца сессии.
      _sheetOpen = false;

      releaseMapInputLock();

      modalSheetOpenCount.value--;
    }
  }
}
