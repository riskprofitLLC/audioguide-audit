part of 'map_widget.dart';


/// Дефолтная камера-фолбэк, когда у острова нет ни `mapBounds`,
/// ни `mapCenter` в манифесте (центр Гемилера).
const CameraPosition _fallbackCamera = CameraPosition(
  target: LatLng(36.5536, 29.0703),
  zoom: 12,
);


/// Зум камеры при подсветке точки (?poi=): первый показ
/// ([_MapCameraMixin._fitToData]) и SPA-переход с обычной /map
/// ([_MapCameraMixin._applyHighlightPoi]) подводят к точке
/// одинаково крупно — иначе после смены режима камера
/// оставалась на старом масштабе.
const double _highlightPoiZoom = 15;


/// Отступ от краёв при подгонке под границы острова
/// (доля размера экрана с каждой стороны).
const double _fitPaddingFraction = 0.05;


/// Отступ от краёв при подгонке под маршруты острова
/// (небольшой, чтобы остров занимал почти всю ширину
/// экрана — пользователь просил приблизить карту при первом
/// показе).
const double _dataPaddingFraction = 0.07;


/// Накладывает на целевую точку камеры [cam] поправку центра
/// из манифеста (`fitCenterAdjustment`) — сдвиг острова по
/// широте/долготе в градусах.
///
/// Применяется после расчёта подгонки, чтобы масса суши острова
/// визуально стояла по центру (если она не совпадает с центром
/// маршрутов/границ).
CameraPosition _withFitCenterAdjustment(
  CameraPosition cam,
  Manifest? manifest,
) {
  final adj = manifest?.fitCenterAdjustment;

  if (adj == null) {
    return cam;
  }

  return CameraPosition(
    target: LatLng(
      cam.target.latitude + adj.lat,
      cam.target.longitude + adj.lng,
    ),
    zoom: cam.zoom,
  );
}


/// Методы расчёта и подгонки камеры карты, а также выделения
/// маршрута/точки интереса (перекраска слоёв + анимация камеры
/// + пульсирующее кольцо вокруг выделенной точки).
///
/// Вынесены из `_MapWidgetState` в отдельный файл, чтобы уменьшить
/// размер основного файла карты.
mixin _MapCameraMixin on _MapLayersMixin {

  /// Стартовая камера: подгонка под границы острова из манифеста
  /// (`mapBounds`), иначе — центр острова (`mapCenter`, zoom 13),
  /// иначе — общий фолбэк.
  CameraPosition _startCamera(Manifest? manifest, Size size) {

    final bounds = manifest?.mapBounds;

    if (bounds != null) {

      var zoom = _fitZoom(bounds, size);
      // Поправка к зуму из манифеста: например, Кекова — слегка
      // уменьшаем масштаб при первом открытии.
      final adjust =
          manifest?.fitZoomAdjustment ?? 0.0;
      if (adjust != 0.0) {
        zoom = (zoom + adjust).clamp(2.0, 17.0);
      }
      return _withFitCenterAdjustment(
        CameraPosition(
          target: LatLng(
            (bounds.south + bounds.north) / 2,
            (bounds.west + bounds.east) / 2,
          ),
          zoom: zoom,
        ),
        manifest,
      );
    }

    return _islandCamera(manifest) ?? _fallbackCamera;
  }


  /// Начальная камера для острова: из `mapCenter` манифеста,
  /// иначе — общий фолбэк.
  static CameraPosition? _islandCamera(
    Manifest? manifest,
  ) {

    final center = manifest?.mapCenter;

    if (center == null) {
      return _fallbackCamera;
    }

    return CameraPosition(
      target: LatLng(center.lat, center.lng),
      zoom: 13,
    );
  }


  /// Zoom, при котором прямоугольник [bounds] целиком помещается
  /// в область [size] с отступом `paddingFraction` от краёв.
  ///
  /// Расчёт в веб-меркаторных координатах maplibre: мир на zoom 0 —
  /// квадрат 512×512 условных единиц (в отличие от классических
  /// 256×256 Google Maps).
  static double _fitZoom(
    MapBounds bounds,
    Size size, {
    double paddingFraction = _fitPaddingFraction,
  }) {

    const worldWidth = 512.0;

    double mercY(double lat) {
      final rad = lat * pi / 180;
      return (1 - log(tan(rad) + 1 / cos(rad)) / pi) / 2;
    }

    final xWest = (bounds.west + 180) / 360;
    final xEast = (bounds.east + 180) / 360;
    final ySouth = mercY(bounds.south);
    final yNorth = mercY(bounds.north);

    final dx = (xEast - xWest).abs();
    final dy = (yNorth - ySouth).abs();

    if (dx == 0 && dy == 0) {
      return 13;
    }

    final availW = size.width * (1 - 2 * paddingFraction);
    final availH = size.height * (1 - 2 * paddingFraction);

    final zoomW = log(availW / (dx * worldWidth)) / ln2;
    final zoomH = log(availH / (dy * worldWidth)) / ln2;

    return min(zoomW, zoomH).clamp(2.0, 17.0);
  }


  /// Прямоугольник, покрывающий все точки маршрутов острова.
  ///
  /// Если маршрутов нет — прямоугольник по достопримечательностям.
  /// Если данных нет вовсе — `null`.
  static MapBounds? _dataBounds(
    List<Trail> trails,
    List<Poi> pois,
  ) {

    double? west, south, east, north;

    void include(double lat, double lng) {
      if (south == null || lat < south!) {
        south = lat;
      }
      if (north == null || lat > north!) {
        north = lat;
      }
      if (west == null || lng < west!) {
        west = lng;
      }
      if (east == null || lng > east!) {
        east = lng;
      }
    }

    for (final trail in trails) {
      for (final point in trail.points) {
        include(point.latitude, point.longitude);
      }
    }

    if (trails.isEmpty) {
      for (final poi in pois) {
        include(poi.latitude, poi.longitude);
      }
    }

    if (west == null) {
      return null;
    }

    return MapBounds(
      west: west!,
      south: south!,
      east: east!,
      north: north!,
    );
  }


  /// Камера, подогнанная под маршруты острова (с запасом),
  /// либо камера по границам острова, если данных нет.
  CameraPosition? _fitToData(
    Manifest? manifest,
    List<Trail> trails,
    List<Poi> pois,
    Size size,
  ) {

    // Если задан выделенный маршрут — подгоняем камеру
    // именно под него, чтобы он целиком попадал в кадр.
    var fitTrails = trails;

    final highlightId = widget.highlightTrailId;

    if (highlightId != null && highlightId.isNotEmpty) {

      final selected = trails
          .where((trail) => trail.id == highlightId)
          .toList();

      if (selected.isNotEmpty) {

        fitTrails = selected;
      }
    }

    // Если задана выделенная точка интереса — центрируем камеру
    // на ней (zoom 15), как при «Показать на карте» с детали POI.
    final highlightPoiId = widget.highlightPoiId;

    if ((highlightId == null || highlightId.isEmpty) &&
        highlightPoiId != null &&
        highlightPoiId.isNotEmpty) {

      for (final poi in pois) {

        if (poi.id == highlightPoiId) {

          return CameraPosition(
            target: LatLng(poi.latitude, poi.longitude),
            zoom: _highlightPoiZoom,
          );
        }
      }
    }

    final bounds = _dataBounds(fitTrails, pois);

    if (bounds == null) {
      return _startCamera(manifest, size);
    }

    // Границы острова (суша) из манифеста приоритетнее маршрутов:
    // маршруты могут покрывать не весь остров, и подгонка только
    // по ним «уводит» остров от центра (напр. Гемилер). Берём
    // объединение — и маршруты, и суша целиком попадают в кадр.
    // При выделении конкретного маршрута объединение не делаем —
    // камера должна показывать именно его.
    final fitBounds =
        (highlightId == null || highlightId.isEmpty)
        ? _unionBounds(bounds, manifest?.islandBounds)
        : bounds;

    var zoom = _fitZoom(
      fitBounds,
      size,
      paddingFraction: _dataPaddingFraction,
    );
    // Поправка к зуму из манифеста (например, Кекова — отодвинуть,
    // чтобы остров целиком вошёл в кадр).
    final adjust =
        manifest?.fitZoomAdjustment ?? 0.0;
    if (adjust != 0.0) {
      zoom = (zoom + adjust).clamp(2.0, 17.0);
    }
    return _withFitCenterAdjustment(
      CameraPosition(
        target: LatLng(
          (fitBounds.south + fitBounds.north) / 2,
          (fitBounds.west + fitBounds.east) / 2,
        ),
        zoom: zoom,
      ),
      manifest,
    );
  }


  /// Объединение двух прямоугольников границ.
  ///
  /// Если [other] равен `null` — возвращает [a] как есть.
  static MapBounds _unionBounds(
    MapBounds a,
    MapBounds? other,
  ) {
    if (other == null) {
      return a;
    }

    return MapBounds(
      west: min(a.west, other.west),
      south: min(a.south, other.south),
      east: max(a.east, other.east),
      north: max(a.north, other.north),
    );
  }


  /// Загружает POI и маршруты острова из репозитория.
  Future<MapDataBundle> _loadPoisAndTrails(String islandId) async {

    final dataRepository =
        ref.read(mapDataRepositoryFamily(islandId));

    final pois = await dataRepository.loadPois();

    final trails = await dataRepository.loadTrails();

    return (
      pois: pois,
      trails: trails,
      poiLocations: List.filled(pois.length, islandId),
      trailLocations: List.filled(trails.length, islandId),
    );
  }


  /// Загружает POI и маршруты ВСЕХ локаций каталога.
  ///
  /// Используется в режиме [MapWidget.showAllRegions]: карта
  /// показывает объекты всех регионов сразу, группируя
  /// близкие в кластеры при отдалении.
  Future<MapDataBundle> _loadAllPoisAndTrails() async {

    // Ошибка одной локации не должна прятать объекты остальных
    // девяти: раньше Future.wait ронял всю загрузку целиком, и
    // карта «все регионы» оставалась пустой из-за одного битого
    // ассета.
    final results =
        await Future.wait<({
          String locationId,
          List<Poi> pois,
          List<Trail> trails,
        })>(
      kLocationIds.map((locationId) async {
        try {
          final repo = ref.read(
            mapDataRepositoryFamily(locationId),
          );
          final pois = await repo.loadPois();
          final trails = await repo.loadTrails();
          return (
            locationId: locationId,
            pois: pois,
            trails: trails,
          );
        } catch (error, stack) {

          AppLogger.warning(
            '[MapWidget] failed to load $locationId: $error\n$stack',
          );

          return (
            locationId: locationId,
            pois: const <Poi>[],
            trails: const <Trail>[],
          );
        }
      }),
    );

    return (
      pois: [for (final r in results) ...r.pois],
      trails: [for (final r in results) ...r.trails],
      poiLocations: [
        for (final r in results)
          for (final _ in r.pois) r.locationId,
      ],
      trailLocations: [
        for (final r in results)
          for (final _ in r.trails) r.locationId,
      ],
    );
  }


  /// Возвращает общий future загрузки данных, создавая его
  /// при первом обращении.
  ///
  /// В режиме «все регионы» первому обращению отдаётся БЫСТРЫЙ
  /// пакет текущей локации: первые маркеры появляются сразу, а
  /// остальные локации догружаются фоном ([_mergeAllRegions]) и
  /// подливаются в источники — раньше все 9 локаций ждались до
  /// первого маркера (P1-3, 6-й проход).
  Future<MapDataBundle> _ensureDataFuture() {

    return _dataSlot.obtain(
      _effectiveIslandKey,

      () async {
        if (_showAllRegions) {
          return _allRegionsBundle ??
              await _loadPoisAndTrails(_effectiveIslandId);
        }

        return _loadPoisAndTrails(_effectiveIslandId);
      },
    );
  }


  /// Предзагружает данные острова и вычисляет камеру,
  /// подогнанную под маршруты, чтобы маршруты при открытии
  /// карты целиком попадали в кадр с запасом.
  Future<void> _ensureFitData(
    String islandId,
    Manifest? manifest,
    Size size,
  ) async {

    // Пока данные этой локации грузятся, повторные вызовы из build
    // (до `_fitReady`) не порождают новых подписок на тот же future.
    if (_fitRequestedForIsland == islandId) {
      return;
    }

    _fitRequestedForIsland = islandId;

    // Подгонке камеры в режиме «все регионы» нужны только объекты
    // ТЕКУЩЕЙ локации: общий слот держит быстрый пакет первой
    // локации (P1-3) — при переключении локации до конца фоновой
    // догрузки фильтр по нему был бы пуст. Читаем локацию
    // напрямую (репозиторий кешируется провайдером).
    final future = _showAllRegions
        ? _loadPoisAndTrails(islandId)
        : _ensureDataFuture();

    try {

      final (:pois, :trails, :poiLocations, :trailLocations) =
          await future;

      if (!mounted || _effectiveIslandId != islandId) {
        return;
      }

      // Категории, встречающиеся на карте, известны ещё до
      // создания карты — сохраняем их заранее, чтобы регистрация
      // иконок в [_maybeAddOverlays] не ждала повторной загрузки
      // данных и шла параллельно с рендером карты. В режиме
      // «все регионы» — по всем загруженным POI сразу.
      _usedIconCategories = {
        for (final poi in pois)
          if (poi.category != null && poi.category!.isNotEmpty)
            poi.category!,
      };

      // Стартовая камера в режиме «все регионы» подгоняется под
      // ТЕКУЩУЮ локацию (как и раньше): объекты других регионов
      // появляются при панорамировании карты.
      final cameraPois = _showAllRegions
          ? _filterByLocation(pois, poiLocations, islandId)
          : pois;
      final cameraTrails = _showAllRegions
          ? _filterByLocation(trails, trailLocations, islandId)
          : trails;

      final camera = _fitToData(
        manifest,
        cameraTrails,
        cameraPois,
        size,
      );

      setState(() {

        _fitCamera = camera;

        _fitReady = true;
      });
    } catch (error) {

      AppLogger.warning(
        '[MapWidget] _ensureFitData failed: $error',
      );

      if (mounted) {

        setState(() {

          _fitCamera = null;

          _fitReady = true;
        });
      }
    }
  }


  /// Оставляет только элементы [items] текущей локации [locationId]
  /// (по параллельному списку [locations]).
  List<T> _filterByLocation<T>(
    List<T> items,
    List<String> locations,
    String locationId,
  ) {

    final result = <T>[];

    for (var i = 0; i < items.length; i++) {

      if (locations[i] == locationId) {
        result.add(items[i]);
      }
    }

    return result;
  }


  /// Применяет выделение маршрута: перекрашивает слой `trail-lines`
  /// и подводит камеру к выбранному маршруту.
  ///
  /// Вызывается при смене [MapWidget.highlightTrailId] на уже
  /// созданной карте. Для первого открытия камера подгоняется
  /// в [_fitToData], а слой рисуется сразу с нужным цветом.
  Future<void> _applyHighlightTrail() async {

    final controller = _readyController;

    if (controller == null || !_overlaysAdded) {

      return;
    }

    await controller.setLayerProperties(
      'trail-lines',
      _trailLineLayerProperties(),
    );

    final highlightId = widget.highlightTrailId;

    if (highlightId == null || highlightId.isEmpty) {

      return;
    }

    final selected =
        _trails.where((trail) => trail.id == highlightId).toList();

    if (selected.isEmpty) {

      return;
    }

    final bounds = _dataBounds(selected, const []);

    if (bounds == null) {

      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(bounds.south, bounds.west),
          northeast: LatLng(bounds.north, bounds.east),
        ),
        left: 48,
        top: 48,
        right: 48,
        bottom: 48,
      ),
    );
  }


  /// Применяет выделение точки интереса: перекрашивает маркеры,
  /// наполняет ореол/пульс координатами выбранной точки и подводит
  /// к ней камеру.
  ///
  /// Вызывается при смене [MapWidget.highlightPoiId] на уже
  /// созданной карте и сразу после добавления оверлеев. Для
  /// первого открытия камера подводится в [_fitToData], а маркеры
  /// рисуются сразу с нужным цветом.
  Future<void> _applyHighlightPoi() async {

    final controller = _readyController;

    if (controller == null || !_overlaysAdded) {

      return;
    }

    final highlightId = widget.highlightPoiId;

    final poi = _findPoi(highlightId);

    await controller.setLayerProperties(
      'poi-balls',
      _poiBallLayerProperties(),
    );

    await controller.setLayerProperties(
      'poi-icons',
      _poiIconLayerProperties(),
    );

    await controller.setGeoJsonSource(
      'poi-highlight',
      _highlightPoiFeatureCollection(poi),
    );

    _setPulse(poi != null);

    if (poi == null) {

      return;
    }

    // SPA-переход с обычной /map на /map?poi= не пересоздаёт
    // карту: подводим и центр, и зум — иначе камера оставалась
    // на масштабе прежнего режима.
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(poi.latitude, poi.longitude),
        _highlightPoiZoom,
      ),
    );
  }


  /// Ищет POI по id среди загруженных точек.
  Poi? _findPoi(String? id) {

    return _findPoiWithLocation(id)?.$1;
  }


  /// Включает/выключает пульсацию кольца вокруг выделенного POI.
  void _setPulse(bool running) {

    if (running == _pulseRunning) {

      return;
    }

    if (running &&
        MediaQuery.maybeDisableAnimationsOf(context) == true) {

      // Доступность (B12): Reduce Motion — без живого пульса,
      // но кольцо остаётся статичным: выделение читается и без
      // анимации.
      _pulseRunning = true;

      _pulseController.stop();

      _lastPulseFrame = null;

      if (_route?.isCurrent != false) {
        _controller?.setLayerProperties(
          'poi-highlight-pulse',
          const CircleLayerProperties(
            circleColor: '#00000000',
            circleRadius: 26,
            circleOpacity: 0.32,
            circleStrokeColor: _poiHighlightColor,
            circleStrokeWidth: 3,
          ),
        );
      }

      return;
    }

    _pulseRunning = running;

    if (running) {

      _lastPulseFrame = null;

      _pulseController.repeat();
    } else {

      _pulseController.stop();
    }
  }


  /// Один тик пульса: обновляет радиус и прозрачность кольца.
  ///
  /// Троттлинг ~80 мс, чтобы не слать setCircleLayerProperties
  /// каждый кадр анимации (это платформенный канал, дорого).
  void _onPulseTick() {

    if (!_pulseRunning || !_overlaysAdded) {

      // Слой «poi-highlight-pulse» есть только при готовых
      // оверлеях: во время пересборки (смена режима показа)
      // тик молча пропускаем.
      return;
    }

    // Поверх карты пушнуты детали POI/маршрута: карта не видна,
    // кадры пульса в платформенный канал не отправляем — анимация
    // контроллера продолжает идти, при возврате кольцо живое.
    if (_route?.isCurrent == false) {

      return;
    }

    final now = DateTime.now();

    final last = _lastPulseFrame;

    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 80)) {

      return;
    }

    _lastPulseFrame = now;

    final t = _pulseController.value;

    final radius = 14 + 22 * t;

    final opacity = 0.6 * (1 - t);

    _controller?.setLayerProperties(
      'poi-highlight-pulse',
      CircleLayerProperties(
        circleColor: '#00000000',
        circleRadius: radius,
        circleOpacity: opacity,
        circleStrokeColor: _poiHighlightColor,
        circleStrokeWidth: 3,
      ),
    );
  }
}
