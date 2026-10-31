part of 'map_widget.dart';


/// Методы добавления оверлеев карты: маркеры POI (шарики, иконки,
/// подписи), линии маршрутов, маркер позиции пользователя и слои
/// выделения точки интереса (ореол + пульс).
///
/// Также отвечает за регистрацию SDF-иконок категорий в стиле
/// карты и за предзагрузку их байтов. Вынесены из `_MapWidgetState`
/// в отдельный файл, чтобы уменьшить размер основного файла карты.
mixin _MapOverlaysMixin on _MapTrackingMixin {

  /// Читает байты всех SDF-иконок категорий POI в [_iconDataCache].
  ///
  /// Выполняется fire-and-forget в [initState]; [_registerPoiIcons]
  /// берёт готовые байты из кеша и регистрирует их в стиле.
  Future<void> _preloadIconBytes() async {
    final entries = [
      for (final entry in _poiIconAssets.entries) entry.value,
      'map-pin.png',
      // Конус курса маркера «Вы здесь» (B1/B3, 18-й проход).
      'user-heading-cone.png',
    ];

    await Future.wait(
      entries.map((file) async {
        if (_iconDataCache.containsKey(file)) {
          return;
        }

        try {
          final data = await rootBundle.load(
            'assets/map_icons/$file',
          );

          _iconDataCache[file] = data;
        } catch (e) {
          AppLogger.warning(
            '[MapWidget] не удалось предзагрузить иконку '
            '$file: $e',
          );
        }
      }),
    );
  }


  Future<void> _maybeAddOverlays() async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    // Канвас появляется только после загрузки стиля. Превью не-
    // интерактивен (тап ловит Flutter-распознаватель в
    // map_preview.dart), поэтому убираем канвас из DOM hit-test:
    // во встроенных браузерах (Orca) перехваченный канвасом клик
    // у правого/нижнего края уезжал по координатам — видимые кнопки
    // и область нажатия не совпадали. Повторные вызовы идемпотентны.
    if (widget.preview) {
      disablePreviewCanvasPointerEvents();
    }

    AppLogger.info(
      '[MapWidget] _maybeAddOverlays: '
      'overlaysAdded=$_overlaysAdded',
    );

    // Если оверлеи уже добавлены, но слои пропали из стиля
    // (maplibre перезагрузил стиль — SPA-переход, ресайз,
    // повторный style.load), пересоздаём их заново. Иначе карта
    // останется без маркеров и маршрутов навсегда.
    if (_overlaysAdded) {

      final ids = await controller.getLayerIds();

      if (ids.contains('poi-balls')) {
        return;
      }

      AppLogger.warning(
        '[MapWidget] слои оверлеев пропали из стиля '
        '(${ids.length} слоёв) — пересоздаём',
      );

      _overlaysAdded = false;

      // Стиль перезагрузился — иконки нужно зарегистрировать
      // заново для нового стиля. Иначе _registerPoiIcons()
      // короткозамкнётся на _iconsRegistered == true и маркеры
      // останутся без иконок.
      _iconsRegistered = false;

      _iconsFuture = null;

      _usedIconCategories = const {};

      // Мог уцелеть не весь набор (частичный сбой прошлой попытки):
      // чистим остатки, чтобы повторное добавление не упёрлось
      // в «already exists».
      await _removeExistingOverlays();
    }

    _overlaysAdded = true;

    try {

      // Регистрируем иконки сразу, параллельно с загрузкой данных:
      // категории уже известны после _ensureFitData, иконки
      // появляются вместе с картой, а не после данных. Если данные
      // ещё не загружены (например, явная камера из deep-link),
      // категории неизвестны — тогда иконки регистрирует
      // _loadOverlays после загрузки данных.
      if (_usedIconCategories.isNotEmpty) {
        // Регистрация иконок fire-and-forget: результат (загрузка байтов
        // в стиль) не нужен здесь — `_loadOverlays` дождётся его сам.
        unawaited(_registerPoiIcons());
      }

      await _loadOverlays();

      // Канвас появляется только после первой отрисовки стиля.
      // Здесь он точно существует — ещё раз убираем контейнер/канвас
      // превью из DOM hit-test (идемпотентно).
      if (widget.preview) {
        disablePreviewCanvasPointerEvents();
      }
    } catch (error, stack) {

      AppLogger.warning(
        '[MapWidget] _loadOverlays failed: $error\n$stack',
      );

      // Частично добавленные источники/слои чистим сразу: повтор
      // addSource/addLayer на уже существующие падал бы «already
      // exists» и оверлеи не восстановились бы уже никогда.
      await _removeExistingOverlays();

      // Сбрасываем флаг, чтобы следующий onStyleLoaded/повторный
      // вызов попробовал добавить оверлеи снова.
      _overlaysAdded = false;
    }
  }


  /// Слои оверлеев карты (для чистки остатков перед повторным
  /// добавлением — см. [_removeExistingOverlays]).
  static const List<String> _overlayLayerIds = [
    'trail-casing',
    'trail-lines',
    'pois-clusters',
    'pois-cluster-count',
    'poi-balls',
    'poi-favorite-ring',
    'poi-icons',
    'poi-labels',
    'poi-highlight-halo',
    'poi-highlight-pulse',
    'user-position-accuracy',
    'user-position-dot',
    'user-position-heading',
  ];

  /// Источники оверлеев карты.
  static const List<String> _overlaySourceIds = [
    'pois',
    'trails',
    'poi-highlight',
    'user-position',
  ];


  /// Удаляет источники и слои оверлеев, оставшиеся в стиле.
  ///
  /// Повторное добавление после сбоя посреди `_loadOverlays`
  /// (addSource прошёл, addCircleLayer упал) иначе натыкается на
  /// «already exists» и не может восстановиться. Ошибки чистки
  /// (контроллер уже уничтожается и т.п.) не важны — сам вызов
  /// идёт из обработчика другой ошибки.
  Future<void> _removeExistingOverlays() async {

    // A2 (17-й проход): источник сейчас исчезнет — маркер
    // пользователя снова «не готов»: позиции, пришедшие во
    // время пересборки, больше не пишутся в несуществующий
    // источник (unhandled PlatformException).
    _userMarker.onLayerRemoved();

    final controller = _controller;

    if (controller == null) {
      return;
    }

    try {

      final layerIds = await controller.getLayerIds();

      for (final id in _overlayLayerIds) {

        if (layerIds.contains(id)) {

          await controller.removeLayer(id);
        }
      }

      final sourceIds = await controller.getSourceIds();

      for (final id in _overlaySourceIds) {

        if (sourceIds.contains(id)) {

          await controller.removeSource(id);
        }
      }
    } catch (cleanupError) {

      AppLogger.warning(
        '[MapWidget] overlay cleanup failed: $cleanupError',
      );
    }
  }


  Future<void> _loadOverlays() async {

    final islandId = _effectiveIslandId;

    AppLogger.info(
      '[MapWidget] _loadOverlays start islandId=$islandId',
    );

    final future = _ensureDataFuture();

    final (:pois, :trails, :poiLocations, :trailLocations) = await future;

    AppLogger.infoFn(
      () => '[MapWidget] _loadOverlays loaded islandId=$islandId '
          'pois=${pois.length} trails=${trails.length} '
          'showAllRegions=$_showAllRegions '
          'trailNames=${trails.map((t) => t.name).toList()}',
    );

    if (!mounted || _effectiveIslandId != islandId) {
      return;
    }

    // Регистрируем только иконки категорий, которые реально
    // встречаются на карте (+ дефолтную). В режиме «все регионы»
    // берём категории всех загруженных POI. На web каждый
    // addImage — платформенный roundtrip, лишние вызовы
    // задерживают появление маркеров.
    _usedIconCategories = {
      for (final poi in pois)
        if (poi.category != null && poi.category!.isNotEmpty)
          poi.category!,
    };

    final iconsFuture = _registerPoiIcons();

    await iconsFuture;

    if (!mounted || _effectiveIslandId != islandId) {
      return;
    }

    _pois = pois;

    _trails = trails;

    _poiLocations = poiLocations;

    _trailLocations = trailLocations;

    await _addPoisLayer(pois, poiLocations);

    // Источник `pois` уже собран с актуальными ключами избранного
    // и прослушанных (в _addPoisLayer), поэтому отмечаем их как
    // применённые, чтобы следующий запрос на пересборку был no-op.
    _appliedFavoriteKeys = _currentFavoriteKeys();

    _appliedListenedKeys = _currentListenedKeys();

    _appliedCategoryFilter = _activeCategoryFilter;

    await _addTrailsLayer(trails, trailLocations);

    if (!widget.preview) {
      await _addUserPositionLayer();
    }

    await _addPoiHighlightLayer();

    await _applyHighlightPoi();

    if (kDebugMode) {
      try {
        final ids = await _controller?.getLayerIds() ?? const [];
        final sources = await _controller?.getSourceIds() ?? const [];
        AppLogger.info('[MapWidget] DEBUG layers=${ids.length} $ids');
        AppLogger.info('[MapWidget] DEBUG sources=$sources');
        final visible = await _controller?.getVisibleRegion();
        AppLogger.info('[MapWidget] DEBUG visible=$visible');
      } catch (e) {
        AppLogger.info('[MapWidget] DEBUG error $e');
      }
    }

    AppLogger.info(
      '[MapWidget] _loadOverlays done for $islandId',
    );

    // Первые маркеры уже на карте: в режиме «все регионы»
    // догружаем остальные локации фоном и подливаем их в
    // источники (P1-3, 6-й проход).
    if (_showAllRegions) {
      unawaited(_mergeAllRegions());
    }
  }

  /// Фоновая догрузка остальных локаций каталога в режиме «все
  /// регионы» (P1-3, 6-й проход).
  ///
  /// Первые маркеры рисуются по быстрому пакету текущей локации
  /// (см. [_ensureDataFuture]); полный пакет (9 локаций, сидинг
  /// + парсинг poi.json до 122 КБ) грузится здесь и подливается
  /// в ИМЕЮЩИЕСЯ источники `pois`/`trails` через setGeoJsonSource
  /// — кластеры пересчитываются, слои не пересоздаются.
  /// Идемпотентен; завершившаяся догрузка кешируется в
  /// [_allRegionsBundle].
  Future<void> _mergeAllRegions() async {
    if (_allRegionsBundle != null || _allRegionsMergeInFlight) {
      return;
    }

    _allRegionsMergeInFlight = true;

    try {
      final bundle = await _loadAllPoisAndTrails();

      if (!mounted || !_showAllRegions) {
        return;
      }

      _allRegionsBundle = bundle;

      final controller = _controller;

      if (controller == null || !_overlaysAdded) {
        return;
      }

      // Иконки новых категорий: регистратор короткозамкнут
      // флагом _iconsRegistered — сбрасываем и перерегистрируем
      // (добавление существующего имени ловится внутри).
      final mergedCategories = {
        for (final poi in bundle.pois)
          if (poi.category != null && poi.category!.isNotEmpty)
            poi.category!,
      };

      if (!mergedCategories.every(_usedIconCategories.contains)) {
        _usedIconCategories = mergedCategories;

        _iconsRegistered = false;

        _iconsFuture = null;

        await _registerPoiIcons();
      }

      if (!mounted) {
        return;
      }

      _pois = bundle.pois;

      _trails = bundle.trails;

      _poiLocations = bundle.poiLocations;

      _trailLocations = bundle.trailLocations;

      final keys = _currentFavoriteKeys();

      final listenedKeys = _currentListenedKeys();

      // Фильтр категорий (1c) действует и в режиме «все регионы».
      final filtered = filterPoisByCategory(
        bundle.pois,
        bundle.poiLocations,
        _activeCategoryFilter,
      );

      await controller.setGeoJsonSource(
        'pois',
        _poiFeatureCollection(
          filtered.pois,
          filtered.locations,
          namespaced: true,
          favoriteKeys: keys,
          listenedKeys: listenedKeys,
        ),
      );

      await controller.setGeoJsonSource(
        'trails',
        _trailFeatureCollection(
          bundle.trails,
          bundle.trailLocations,
          namespaced: true,
        ),
      );

      _appliedFavoriteKeys = keys;

      _appliedListenedKeys = listenedKeys;

      _appliedCategoryFilter = _activeCategoryFilter;

      AppLogger.infoFn(
        () => '[MapWidget] _mergeAllRegions done: '
            'pois=${bundle.pois.length} trails=${bundle.trails.length}',
      );
    } catch (error, stack) {
      AppLogger.warning(
        '[MapWidget] _mergeAllRegions failed: $error\n$stack',
      );
    } finally {
      _allRegionsMergeInFlight = false;
    }
  }


  /// Маркер «Вы здесь» (B1, 17-й проход): классический синий
  /// «гугл-точки» — роль [AppColors.mapUser]. От маркеров POI
  /// (#1668A8, шарик с иконкой) отличается конструкцией: белое
  /// кольцо, круг точности и стрелка курса при движении.
  static const String _mapUserColor = '#2563EB';

  /// Белое кольцо вокруг точки пользователя (B1).
  static const String _mapUserRingColor = '#ffffff';

  /// Коэффициент пересчёта метров точности в пиксели для зума z:
  /// px = accuracy · 256·2^z / (40075016.686·cos(φ)) (cos — радианы).
  ///
  /// MapLibre разрешает [`zoom`] ТОЛЬКО как вход top-level
  /// interpolate/step — выражение с `^`/`zoom` внутри отвергается
  /// при addLayer (проверено на web-сборке, B7 17-го прохода).
  /// Поэтому кривая 2^z задана стопами по ЦЕЛЫМ зумам 12–22
  /// (линейная интерполяция между соседними даёт ≤6% ошибки —
  /// глазом незаметно); ниже z12 всегда работает пол 16 px.
  static List<Object> _accuracyRadiusExpression() {

    // px = acc * K(z) / cos(φ), K(z) = 256·2^z.
    Object radiusAtZoom(int z) {

      final k = 256.0 * pow(2.0, z).toDouble();

      return [
        'max',
        16,
        [
          '/',
          ['*', ['get', 'accuracy'], k],
          [
            '*',
            40075016.686,
            [
              'cos',
              ['*', ['get', 'lat'], ['/', ['pi'], 180]],
            ],
          ],
        ],
      ];
    }

    return [
      'interpolate',
      ['linear'],
      ['zoom'],
      for (var z = 12; z <= 22; z++) ...[z, radiusAtZoom(z)],
    ];
  }

  /// Добавляет на карту маркер текущей позиции пользователя.
  ///
  /// Слои снизу вверх (B1, 17-й проход; 18-й — свежесть/конус/
  /// окантовка):
  /// - `user-position-accuracy` — полупрозрачный круг точности
  ///   с белой окантовкой (B6), только у СВЕЖЕГО фикса с accuracy
  ///   (радиус в метрах → пиксели zoom-выражением, MapLibre
  ///   считает тригонометрию в РАДИАНАХ, минимум 16 px);
  /// - `user-position-dot` — залитая точка с белым кольцом 3 px;
  ///   у давнего фикса приглушена (свойство `fresh`, B1);
  /// - `user-position-heading` — конус направления ПОД точкой
  ///   (виден только при движении и свежем курсе, B3). belowLayerId
  ///   обязан ссылаться на УЖЕ добавленный слой — точка строится
  ///   первой (иначе maplibre роняет стиль «before non-existing
  ///   layer» — поймано веб-пробой).
  ///
  /// A1: сразу после добавления восстанавливает последнюю
  /// позицию (свою или сервиса) — при `distanceFilter: 10`
  /// стоящий пользователь не получил бы маркер до сдвига.
  /// B1 (18-й): живых фиксов не было — показываем последний фикс
  /// ПЛАТФОРМЫ приглушённым маркером (датчик ОС хранит его без
  /// активной подписки; web — не хранит).
  Future<void> _addUserPositionLayer() async {

    final controller = _controller;

    if (controller == null) {
      return;
    }

    await controller.addGeoJsonSource(
      UserMarkerSource.sourceId,
      UserMarkerSource.featureCollection(null),
    );

    // Круг точности: только у СВЕЖЕГО фикса с известной accuracy
    // (A7: null-ключи больше не пишутся — фильтр надёжен на web).
    // B6: белая окантовка — радиус читается и на воде, и на суше.
    await controller.addCircleLayer(
      UserMarkerSource.sourceId,
      'user-position-accuracy',
      CircleLayerProperties(
        circleColor: _mapUserColor,
        circleOpacity: 0.14,
        circleRadius: _accuracyRadiusExpression(),
        circleStrokeColor: _mapUserRingColor,
        circleStrokeWidth: 1.5,
        circleStrokeOpacity: 0.55,
      ),
      filter: [
        'all',
        ['has', 'accuracy'],
        ['==', ['get', 'fresh'], true],
      ],
    );

    // Точка: у давнего фикса — приглушённая (B1), круг точности
    // на ней уже скрыт фильтром свежести.
    await controller.addCircleLayer(
      UserMarkerSource.sourceId,
      'user-position-dot',
      const CircleLayerProperties(
        circleColor: _mapUserColor,
        circleRadius: 7,
        circleOpacity: [
          'case',
          ['==', ['get', 'fresh'], true],
          1.0,
          0.45,
        ],
        circleStrokeColor: _mapUserRingColor,
        // Белое кольцо 3 px (B1) — отделяет точку от фона карты
        // и от маркеров ПОИ.
        circleStrokeWidth: 3,
      ),
    );

    // Конус направления при движении (B3, 18-й проход):
    // полупрозрачный сектор ПОД точкой, поворачивается свойством
    // heading; виден только у свежего фикса при движении быстрее
    // ~1 м/с. НЕ SDF — цвет фиксированный (белый кант + морской
    // синий в PNG).
    try {

      final bytes = _iconDataCache['user-heading-cone.png'] ??
          await rootBundle.load(
            'assets/map_icons/user-heading-cone.png',
          );

      _iconDataCache['user-heading-cone.png'] = bytes;

      await controller.addImage(
        'user-heading-cone',
        bytes.buffer.asUint8List(),
        false,
      );

    } catch (error) {

      AppLogger.warning(
        '[MapWidget] не удалось зарегистрировать конус курса: $error',
      );
    }

    await controller.addSymbolLayer(
      UserMarkerSource.sourceId,
      'user-position-heading',
      const SymbolLayerProperties(
        iconImage: 'user-heading-cone',
        iconRotate: ['get', 'heading'],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconSize: 1.35,
      ),
      // A7: фильтр требует СУЩЕСТВОВАНИЕ ключей — null-свойства
      // больше не пишутся, сравнения с null не выполняются вовсе.
      filter: [
        'all',
        ['==', ['get', 'fresh'], true],
        ['has', 'heading'],
        ['has', 'speed'],
        ['>', ['get', 'speed'], 1.0],
      ],
      belowLayerId: 'user-position-dot',
    );

    _userMarker.onLayerAdded();

    // A1: пересборка оверлеев не должна прятать стоящего
    // пользователя — восстанавливаем последнюю позицию сразу,
    // без ожидания GPS-тика.
    final location = ref.read(locationServiceProvider);

    var fallback = location.lastKnownPosition;

    var fallbackFresh = true;

    // B1: живых фиксов не было — давний фикс датчика ОС, он
    // рисуется приглушённым (первый настоящий приедет сам).
    if (fallback == null && !kIsWeb) {

      fallback = await location.platformLastKnownPosition();

      fallbackFresh = false;
    }

    await _userMarker.restoreInto(
      _MapLibreUserMarkerSink(controller),
      fallback: fallback,
      fallbackFresh: fallbackFresh,
    );
  }

  Future<void> _addPoisLayer(
    List<Poi> pois,
    List<String> poiLocations,
  ) async {

    final controller = _controller;

    if (controller == null) {
      return;
    }

    final filtered = filterPoisByCategory(
      pois,
      poiLocations,
      _activeCategoryFilter,
    );

    final featureCollection = _poiFeatureCollection(
      filtered.pois,
      filtered.locations,
      namespaced: _showAllRegions,
      favoriteKeys: _currentFavoriteKeys(),
      listenedKeys: _currentListenedKeys(),
    );

    // Кластеризация нужна на любой ПОЛНОЙ карте (в т.ч. с подсветкой
    // ?poi=/?trail=): при отдалении близкие точки группируются в
    // кластеры с числом, тап по кластеру приближает карту — группа
    // распадается. Только превью без кластеров: мини-карта маленькая,
    // кластер (радиус 50 px) съел бы все точки острова целиком.
    final useClusters = !widget.preview;

    if (useClusters) {

      // Источник создаём через addSource с кластеризацией: maplibre
      // сам группирует близкие точки в кластеры (свойства
      // `point_count`) при отдалении и распаковывает их при
      // приближении.
      await controller.addSource(
        'pois',
        GeojsonSourceProperties(
          data: featureCollection,
          cluster: true,
          // Радиус поиска соседей в пикселях.
          clusterRadius: 50,
          // Выше этого zoom кластеры не создаются — точки рисуются
          // по одной (на уровне отдельного региона/острова).
          clusterMaxZoom: 14,
        ),
      );

    } else {

      await controller.addGeoJsonSource(
        'pois',
        featureCollection,
      );
    }

    await controller.addGeoJsonSource(
      'poi-highlight',
      _highlightPoiFeatureCollection(null),
    );

    await _registerPoiIcons();

    // Кластерные кружки с количеством объектов — на любой полной
    // карте (создавались только в режиме «все регионы» — на карте с
    // подсветкой ?poi= группировки не было). Кластеры и единичные
    // POI взаимоисключаются по фильтрам `has point_count`.
    if (useClusters) {

      await controller.addCircleLayer(
        'pois',
        'pois-clusters',
        _poiClusterLayerProperties(),
        filter: ['has', 'point_count'],
      );

      await controller.addSymbolLayer(
        'pois',
        'pois-cluster-count',
        _poiClusterCountProperties(),
        filter: ['has', 'point_count'],
      );
    }

    // Фильтр «не кластер» применяется только к кластеризованному
    // источнику: на превью у точки нет `point_count`, и фильтр
    // не нужен (по лишней надёжности — maplibre допускает).
    final unclusteredFilter = ['!', ['has', 'point_count']];

    // Цветной шарик-подложка под иконкой.
    await controller.addCircleLayer(
      'pois',
      'poi-balls',
      _poiBallLayerProperties(),
      filter: useClusters ? unclusteredFilter : null,
    );

    // Золотой ободок вокруг избранных POI — поверх шарика, под
    // иконкой. Слой привязан к тому же источнику `pois`, поэтому
    // ободки прячутся вместе с точками, собранными в кластер
    // (фильтр «не кластер").
    await controller.addCircleLayer(
      'pois',
      'poi-favorite-ring',
      _poiFavoriteRingLayerProperties(),
      filter: useClusters
          ? [
              'all',
              unclusteredFilter,
              ['==', ['get', 'isFavorite'], true],
            ]
          : ['==', ['get', 'isFavorite'], true],
    );

    await controller.addSymbolLayer(
      'pois',
      'poi-icons',
      _poiIconLayerProperties(),
      filter: useClusters ? unclusteredFilter : null,
    );

    // Подписи достопримечательностей над маркерами.
    //
    // Появляются с zoom 10, чтобы были видны сразу при открытии
    // карты острова (стартовая камера ~zoom 10-11). В режиме
    // превью подписи не рисуются — мини-карта слишком маленькая.
    if (!widget.preview) {

      await controller.addSymbolLayer(
        'pois',
        'poi-labels',
        SymbolLayerProperties(
          // Подпись точки: «1. Вход — продажа билетов возле моря».
          // Строка собирается в `_poiFeatureCollection` (поле `label`):
          // номер подставляется, только если он задан (для точек
          // острова Гемилер нумерация явная из poi.json, для остальных
          // островов — порядок следования; точки без номера — просто
          // название без префикса).
          textField: [Expressions.get, 'label'],
          textFont: ['NotoSans'],
          // Подписи масштабируются вместе с картой: при отдалении
          // текст уменьшается, при приближении — заметно растёт
          // (в 2 раза от zoom 9 до zoom 21, как и иконки).
          textSize: _poiLabelTextSize(),
          textMaxWidth: 10,
          textLineHeight: 1.15,
          // Подписи «подвижные»: движок сам выбирает, с какой стороны
          // точки поставить текст (top/bottom/left/right/углы), чтобы
          // не наезжать на соседние подписи. textAnchor/textOffset в
          // этом режиме игнорируются — вместо них радиальный отступ.
          textVariableAnchor: const [
            'top',
            'bottom',
            'left',
            'right',
            'top-left',
            'top-right',
            'bottom-left',
            'bottom-right',
          ],
          textRadialOffset: 1.0,
          textColor: '#16333C',
          // Тонкая белая обводка для читаемости поверх карты, без
          // размытия: широкий halo (width 2.0 + blur 1.2) выглядел
          // как белый растушёванный фон и «съедал» чёткость букв.
          textHaloColor: '#ffffff',
          textHaloWidth: 1.0,
          textHaloBlur: 0.0,
          // Подписи НЕ должны накладываться друг на друга: движок
          // разрешает коллизии, раздвигая подписи по свободным
          // сторонам (textVariableAnchor выше). Если подпись некуда
          // поставить без наложения — она прячется, а не пишется
          // поверх другой (раньше textAllowOverlap: true давал
          // нечитаемую кашу на тесных точках Гемилера 6-8).
          textAllowOverlap: false,
        ),
        minzoom: 10,
        filter: [
          'all',
          ['has', 'title'],
          ['!', ['has', 'point_count']],
        ],
      );
    }

    // Статичный ореол вокруг выделенной точки — под маркером.
    await controller.addCircleLayer(
      'poi-highlight',
      'poi-highlight-halo',
      const CircleLayerProperties(
        circleColor: _poiHighlightColor,
        circleRadius: 22,
        circleOpacity: 0.2,
      ),
      belowLayerId: 'poi-icons',
    );
  }


/// Регистрирует SDF-иконки категорий POI в стиле карты.
  ///
  /// Иконки — белые силуэты из `assets/map_icons/` (Font Awesome);
  /// при рендере перекрашиваются через `iconColor` и получают
  /// белую обводку через `iconHaloColor`. SDF-режим позволяет
  /// перекрашивать иконку без генерации набора цветных PNG.
  ///
  /// Повторные вызовы (из [_loadOverlays] и [_addPoisLayer]) ждут
  /// один и тот же future, поэтому слои `poi-balls`/`poi-icons`
  /// добавляются только после реальной регистрации всех иконок —
  /// маркеры появляются сразу с картой, без «всплывания».
  Future<void> _registerPoiIcons() {
    if (_iconsRegistered) {
      return Future.value();
    }

    return _iconsFuture ??= _registerPoiIconsOnce();
  }

  Future<void> _registerPoiIconsOnce() async {
    final controller = _controller;

    if (controller == null) {
      // Контроллер ещё не создан — не помечаем иконки
      // зарегистрированными и не кешируем no-op future:
      // позже, когда карта появится, [_registerPoiIcons]
      // вызовется снова и зарегистрирует их.
      _iconsFuture = null;

      return;
    }

    final entries = [
      for (final entry in _poiIconAssets.entries)
        if (_usedIconCategories.contains(entry.key))
          (name: 'poi-${entry.key}', file: entry.value),
      (name: _poiDefaultIconName, file: 'map-pin.png'),
    ];

    // Читаем ВСЕ файлы иконок параллельно, из кеша, если уже читали.
    final loaded = await Future.wait(
      entries.map((entry) async {
        try {
          final data = _iconDataCache[entry.file] ??
              await rootBundle.load('assets/map_icons/${entry.file}');

          _iconDataCache[entry.file] = data;

          return (
            name: entry.name,
            bytes: data.buffer.asUint8List(),
          );
        } catch (e) {
          AppLogger.warning(
            '[MapWidget] не удалось загрузить иконку '
            '${entry.name}: $e',
          );

          return null;
        }
      }),
    );

    // Регистрируем все иконки в стиле параллельно.
    await Future.wait(
      loaded.whereType<({String name, Uint8List bytes})>()
          .map((result) async {
        try {
          await controller.addImage(
            result.name,
            result.bytes,
            true,
          );
        } catch (e) {
          AppLogger.warning(
            '[MapWidget] не удалось зарегистрировать '
            'иконку ${result.name}: $e',
          );
        }
      }),
    );

    _iconsRegistered = true;
  }


  /// Добавляет пульсирующее кольцо вокруг выделенной точки.
  ///
  /// Слой-кольцо (прозрачная заливка, только обводка) добавляется
  /// ПОСЛЕ маркеров и маршрутов, поэтому рисуется поверх них, но
  /// не перекрывает сам маркер. Анимация — в [_onPulseTick].
  Future<void> _addPoiHighlightLayer() async {

    final controller = _controller;

    if (controller == null) {
      return;
    }

    await controller.addCircleLayer(
      'poi-highlight',
      'poi-highlight-pulse',
      const CircleLayerProperties(
        circleColor: '#00000000',
        circleRadius: 14,
        circleOpacity: 0.6,
        circleStrokeColor: _poiHighlightColor,
        circleStrokeWidth: 3,
      ),
    );
  }


  /// Переприменяет избранное к источнику `pois`.
  ///
  /// Пересобирает GeoJSON источник с обновлённым свойством
  /// `isFavorite`, из-за чего сигнальная заливка/ободок избранных
  /// POI появляются/пропадают на уже построенной карте (в том
  /// числе при переключении звезды в информационном шите).
  ///
  /// Вызывается после смены [favoritesControllerProvider]. Сравнение
  /// с [_appliedFavoriteKeys] делает метод дешёвым no-op, когда
  /// избранное не менялось (например, при перестройках виджета).
  Future<void> _applyFavoriteStates() async {

    final controller = _readyController;

    if (controller == null || !_overlaysAdded || _pois.isEmpty) {
      return;
    }

    final keys = _currentFavoriteKeys();

    final listenedKeys = _currentListenedKeys();

    // Мемоизация по ОБЕИМ наборам: пересборка — только когда
    // изменился хотя бы один (1b: прослушанные вместе с избранными).
    final favoritesSame = keys.length == (_appliedFavoriteKeys?.length ?? -1) &&
        keys.containsAll(_appliedFavoriteKeys ?? const {});
    final listenedSame =
        listenedKeys.length == (_appliedListenedKeys?.length ?? -1) &&
            listenedKeys.containsAll(_appliedListenedKeys ?? const {});
    final filterSame = _appliedCategoryFilter == _activeCategoryFilter;

    if (favoritesSame && listenedSame && filterSame) {
      return;
    }

    AppLogger.info(
      '[MapWidget] _applyFavoriteStates: '
      'favoritesChanged=${keys.length} listenedChanged=${listenedKeys.length}',
    );

    // Фильтр категорий (1c): применяется при каждой сборке
    // источника; мемоизация учитывает его тоже.
    final filtered = filterPoisByCategory(
      _pois,
      _poiLocations,
      _activeCategoryFilter,
    );

    final featureCollection = _poiFeatureCollection(
      filtered.pois,
      filtered.locations,
      namespaced: _showAllRegions,
      favoriteKeys: keys,
      listenedKeys: listenedKeys,
    );

    await controller.setGeoJsonSource('pois', featureCollection);

    _appliedFavoriteKeys = keys;

    _appliedListenedKeys = listenedKeys;

    _appliedCategoryFilter = _activeCategoryFilter;
  }


  Future<void> _addTrailsLayer(
    List<Trail> trails,
    List<String> trailLocations,
  ) async {

    final controller = _controller;

    if (controller == null) {
      return;
    }

    await controller.addGeoJsonSource(
      'trails',
      _trailFeatureCollection(
        trails,
        trailLocations,
        namespaced: _showAllRegions,
      ),
    );

    // Белая подложка (casing) под линиями маршрутов: делает
    // линии визуально плавнее и читаемее на фоне карты.
    //
    // Маршруты добавляются ПОД слоями POI (poi-balls): линии
    // должны быть под маркерами и их подписями, а не поверх них.
    await controller.addLineLayer(
      'trails',
      'trail-lines',
      _trailLineLayerProperties(),
      belowLayerId: 'poi-balls',
    );

    await controller.addLineLayer(
      'trails',
      'trail-casing',
      LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: _trailCasingWidth(),
        lineOpacity: 0.85,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'trail-lines',
    );
  }
}
