import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../app/navigation/navigation_shell.dart';
import '../../../../app/overlay_tracker.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/geo_angles.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/chart_frame.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/glass_icon_button.dart';
import '../../../../features/poi/models/poi.dart';
import '../../../../features/poi/utils/poi_category.dart';
import '../../../../features/trails/utils/trail_gallery.dart';
import '../../../../features/trails/models/trail.dart';
import '../../../../features/trails/models/trail_point.dart';
import '../../../content/models/manifest.dart';
import '../../../content/models/region_catalog.dart';
import '../../../content/providers/content_providers.dart';
import '../../../audio/providers/auto_audio_provider.dart';
import '../../../audio/providers/audio_player_provider.dart';
import '../../../favorites/providers/favorites_providers.dart';
import '../../../settings/providers/listened_providers.dart';
import '../../../gps/models/user_position.dart';
import '../../../gps/providers/location_providers.dart';
import '../../../gps/services/location_gateway.dart';
import '../../../gps/services/location_service.dart';
import '../../../gps/services/trail_navigator.dart';
import '../../controllers/follow_camera_controller.dart' as follow_camera_controller;
import '../../controllers/gps_status_controller.dart';
import '../../controllers/user_marker_controller.dart';
import '../../providers/map_provider.dart';
import '../../services/map_feature_query.dart';
import '../../services/map_input_lock.dart';
import '../../services/map_controls_shift.dart';
import '../../services/user_marker_source.dart';
import '../../utils/keyed_future_slot.dart';
import '../../utils/poi_category_filter.dart';
import '../../utils/nearby_display.dart';
import 'map_location_status_pill.dart';
import 'nearest_poi_chip.dart';
import 'map_controls_hover_lock.dart';
import 'permission_snack_bar.dart';
import 'no_map_placeholder.dart';
import 'poi_info_sheet.dart';
import 'trail_info_sheet.dart';
import 'trail_navigation_card.dart';

part 'map_camera.dart';
part 'map_feature_data.dart';
part 'map_layers.dart';
part 'map_overlays.dart';
part 'map_state_fields.dart';
part 'map_taps.dart';
part 'map_tracking.dart';
part 'map_trail_smoothing.dart';


class MapWidget extends ConsumerStatefulWidget {

  /// Счётчик обработанных позиций — только для тестов (A6, 18-й
  /// проход): разовая позиция с кнопки GPS не должна обрабатываться
  /// дважды (поток + прямой вызов).
  @visibleForTesting
  static int debugPositionTicks = 0;

  const MapWidget({
    super.key,
    this.initialCameraPosition,
    this.islandId,
    this.highlightTrailId,
    this.highlightPoiId,
    this.preview = false,
    this.showAllRegions = false,
    this.controlsTopShift = 0,
    this.categoryFilter,
    this.bottomLeftControls,
    this.topLeftControls,
    this.onTap,
  });


  /// Фильтр категорий POI (1c, 12-й проход): `null` — все точки.
  /// Смена фильтра пересобирает источник `pois` (кластеры
  /// пересчитываются сами).
  final String? categoryFilter;

  /// Слот левого нижнего угла (B1, 16-й проход): рендерится
  /// колонкой ПОД карточкой навигации — конфликт за
  /// bottom-left исключён конструктивно. Карточка навигации и
  /// слот поднимаются над капсулой/мини-плеером одним лифтом.
  final Widget? bottomLeftControls;

  /// Слот левого ВЕРХНЕГО угла (A2, 18-й проход): содержимое
  /// MapPage (погода → баннер запрета → пилюля «Рядом»)
  /// строится В ОДНОЙ колонке с плашкой статуса геолокации и
  /// чипом ближайшей точки — пересечения исключены
  /// конструктивно, MapPage больше не угадывает высоту слотов
  /// магическим `top: 64`.
  final Widget? topLeftControls;

  /// Начальная позиция камеры.
  ///
  /// Если не задана — используется позиция по
  /// умолчанию для острова.
  final CameraPosition? initialCameraPosition;


  /// Идентификатор острова (опционально).
  ///
  /// Если не задан — используется текущий выбранный
  /// остров из провайдера.
  final String? islandId;


  /// Идентификатор маршрута, который нужно выделить на карте.
  ///
  /// Если задан — выбранный маршрут рисуется ярким цветом,
  /// а все остальные — приглушённым. Камера при этом
  /// подводится к выбранному маршруту.
  final String? highlightTrailId;


  /// Идентификатор точки интереса, которую нужно выделить.
  ///
  /// Если задан — выбранная точка красится сигнальным
  /// цветом с увеличенным радиусом, вокруг неё рисуется
  /// статичный ореол и анимированное пульсирующее кольцо.
  /// Камера подводится к точке (zoom 15).
  final String? highlightPoiId;


  /// Режим превью: не-интерактивная мини-карта.
  ///
  /// Используется вместо кнопки «Открыть карту» на главной
  /// и страницах деталей. Жесты карты отключены, плавающие
  /// кнопки и GPS-трекинг скрыты. Тап по карте вызывает
  /// [onTap] (например, разворот карты на весь экран).
  final bool preview;


  /// Включить режим «все регионы»: карта показывает POI и маршруты
  /// ВСЕХ локаций каталога сразу (не только текущего региона).
  ///
  /// Стартовая камера при этом подгоняется под текущую локацию
  /// (регион виден изначально), но при панорамировании появляются
  /// объекты соседних регионов.
  ///
  /// Кластеризация точек при отдалении работает на любой ПОЛНОЙ
  /// карте (в т.ч. с подсветкой `?poi=`/`?trail=`): см.
  /// [_MapOverlaysMixin._addPoisLayer]. В режиме превью флаг
  /// игнорируется — мини-карта всегда показывает только текущую
  /// локацию и без кластеров.
  final bool showAllRegions;


  /// Дополнительный отступ сверху для компаса и атрибуции OSM.
  ///
  /// На карте с подсветкой (?poi=/?trail=) в правом верхнем
  /// кластере перед «деревом» стоит пилюля «К описанию» (~115 px,
  /// top:14): компас на right:76 пересекался с ней. Сдвиг ≥
  /// высоты пилюли уводит колонку контролов ниже (P0-6, 6-й
  /// проход).
  final double controlsTopShift;


  /// Обработчик тапа по карте в режиме превью.
  final VoidCallback? onTap;


  @override
  ConsumerState<MapWidget> createState() =>
      _MapWidgetState();
}


class _MapWidgetState extends ConsumerState<MapWidget>
    with TickerProviderStateMixin,
        WidgetsBindingObserver,
        _MapStateFields,
        _MapLayersMixin,
        _MapCameraMixin,
        _MapTrackingMixin,
        _MapOverlaysMixin,
        _MapTapsMixin {

  /// Распознаватели жестов для превью: вертикальный драг отдаётся
  /// родительскому скроллу (ListView), чтобы список можно было
  /// листать над мини-картой на нативе (platform view иначе
  /// съедала бы все касания).
  static final Set<Factory<OneSequenceGestureRecognizer>>
      _previewGestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(
      () => VerticalDragGestureRecognizer(),
    ),
  };

  @override
  void initState() {

    super.initState();

    // Колбэки каскада свежести маркера (D5: логика в UserMarkerController).
    userMarker.onStale = _onMarkerStale;

    userMarker.onSignalLost = _onSignalLost;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _pulseController.addListener(_onPulseTick);

    // Интерполяция маркера «Вы здесь» между фиксами (B2, 18-й
    // проход): едет ~700 мс вместо прыжка.
    _markerTween = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _markerTween!.addListener(_onMarkerTweenTick);

    _syncIslandFromWidget();

    // Начальное состояние карты настраивается под текущую
    // эффективную локацию: первый didUpdateWidget с ней же не
    // должен пересбрасывать состояние (и перезагружать данные).
    _configuredIslandKey = _effectiveIslandKey;

    _activeCategoryFilter = widget.categoryFilter;

    // Перепроверка GPS при возврате в приложение (15-й проход).
    WidgetsBinding.instance.addObserver(this);

    // Заранее читаем байты всех SDF-иконок в кеш — до того, как
    // карта построит стиль. На web это сетевые GET-запросы к
    // ассетам; выполнив их в initState, к моменту onStyleLoaded
    // останется только регистрация иконок (addImage), а не
    // загрузка байтов. Маркеры появляются вместе с картой.
    _preloadIconBytes();

    // Проверка разрешения геолокации при открытии (18-й проход):
    // раньше ждала постройки карты (_addUserPositionLayer) — плашка
    // «Включить геолокацию» появлялась с задержкой, а при сбое
    // стиля не появлялась вовсе. Мягкая проверка (без диалога).
    if (!widget.preview) {
      _startTracking();
    }
  }


  @override
  void didChangeDependencies() {

    super.didChangeDependencies();

    // Верхний сдвиг контролов на web — CSS-переменной (натив
    // берёт тот же shift прямо в margins выше).
    applyMapControlsTopShift(widget.controlsTopShift.toDouble());


    // Роут нужен пульсу (_onPulseTick): карта остаётся в стеке
    // под деталями POI, и слать кадры в невидимую карту не нужно.
    _route = ModalRoute.of(context);
  }


  /// Приводит глобальный «текущий остров» в соответствие
  /// с явным параметром виджета (URL `?island=`), чтобы
  /// контентные провайдеры и авто-аудио не расходились
  /// с тем, что показывает карта.
  void _syncIslandFromWidget() {

    final explicit = widget.islandId;

    if (explicit == null) {
      return;
    }

    // URL `?island=` — внешний вход: неизвестный id не должен
    // попадать в глобальные провайдеры. Иначе манифест локации не
    // находится, а regionOfLocation у HomePage кидает StateError
    // прямо в build — серый экран в release.
    if (!kLocationIds.contains(explicit)) {

      AppLogger.warning(
        '[MapWidget] unknown island "$explicit" from URL, ignored',
      );

      return;
    }

    final provider = ref.read(currentIslandIdProvider);

    if (provider == explicit) {
      return;
    }

    AppLogger.info(
      '[MapWidget] sync island provider $provider -> $explicit',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (!mounted) {
        return;
      }

      ref.read(currentIslandIdProvider.notifier).state = explicit;

      // Регион меняем атомарно с локацией: шапка/карта/баннер
      // главной — региональные, и при контенте новой локации
      // не должны показывать прошлый регион.
      ref.read(currentRegionIdProvider.notifier).state =
          regionOfLocation(explicit).id;
    });
  }


  @override
  void didUpdateWidget(MapWidget oldWidget) {

    super.didUpdateWidget(oldWidget);

    if (oldWidget.islandId != widget.islandId) {

    _syncIslandFromWidget();
    }

    _resetOverlaysIfIslandChanged(
      widget.islandId ?? ref.read(currentIslandIdProvider),
    );

    // Смена режима «все регионы» ↔ одна локация (SPA-переход
    // /map ↔ /map?poi= — страница карты не пересоздаётся): данные
    // источника `pois` и id фич меняются, оверлеи пересобираем.
    // Без пересборки карта застревала в прежнем режиме: кластеры
    // и объекты соседних регионов не появлялись на обычной /map
    // после ухода с подсвеченной (и наоборот).
    if (oldWidget.showAllRegions != widget.showAllRegions) {

      _resetOverlaysForModeChange();
    }

    if (oldWidget.controlsTopShift != widget.controlsTopShift) {
      applyMapControlsTopShift(widget.controlsTopShift.toDouble());
    }

    // Смена фильтра категорий (1c): источник `pois`
    // пересобирается на месте (после кадра — как избранное).
    if (oldWidget.categoryFilter != widget.categoryFilter) {

      _activeCategoryFilter = widget.categoryFilter;

      // _appliedCategoryFilter НЕ сбрасываем: мемоизация
      // _applyFavoriteStates сравнивает применённый фильтр с
      // активным — именно это фиксирует смену «монастырь» → null
      // («Все»). Преждевременный null делал сравнение ложным
      // no-op, и точки/подписи не возвращались.

      WidgetsBinding.instance.addPostFrameCallback((_) {

        if (mounted) {

          _applyFavoriteStates();
        }
      });
    }

    // Сменился выделенный маршрут (например, при SPA-переходе
    // с другого маршрута) — перекрашиваем слой и подводим камеру.
    if (oldWidget.highlightTrailId != widget.highlightTrailId) {

      _applyHighlightTrail();
    }

    // Сменилась выделенная точка интереса — перекрашиваем маркер,
    // обновляем ореол/пульс и подводим камеру.
    if (oldWidget.highlightPoiId != widget.highlightPoiId) {

      _applyHighlightPoi();
    }
  }


  /// Если локация, которую показывает карта, сменилась —
  /// сбрасывает состояние оверлеев, чтобы они перезагрузились
  /// для новой локации при следующем style.load.
  ///
  /// Сравнивает с [_configuredIslandKey] — локацией, под которую
  /// состояние НАСТРОЕНО сейчас, — а не с уже загруженными
  /// данными (`_islandId` раньше заполнялся только после
  /// загрузки, и быстрая смена локации в этот момент
  /// пропускала сброс: новая локация получала камеру и данные
  /// прежней).
  void _resetOverlaysIfIslandChanged(
    String islandId,
  ) {

    if (islandId == _configuredIslandKey) {
      return;
    }

    AppLogger.info(
      '[MapWidget] island change $_configuredIslandKey -> $islandId, '
      'resetting overlays',
    );

    _overlaysAdded = false;

    _pois = const [];

    _trails = const [];

    _poiLocations = const [];

    _trailLocations = const [];

    // В режиме «все регионы» пакет данных общий для всех локаций
    // (грузить все девять заново ради смены локации не нужно) —
    // сбрасываем только камеру и состояние оверлеев.
    if (!_showAllRegions) {

      _dataSlot.reset();
    }

    _iconsRegistered = false;

    _iconsFuture = null;

    _usedIconCategories = const {};

    _fitCamera = null;

    _fitReady = false;

    _fitRequestedForIsland = null;

    _appliedFavoriteKeys = null;

    _navState = null;

    _nearestPoiTitle = null;

    _nearestPoiDistance = null;

    _trackingStarted = false;

    // A2 (17-й проход): источник user-position сейчас будет
    // пересоздан — маркер «не готов» до нового _addUserPositionLayer.
    _userMarker.onLayerRemoved();

    _setPulse(false);

    _lastPulseFrame = null;

    _configuredIslandKey = islandId;
  }


  /// Сброс состояния при смене режима показа
  /// (одна локация ↔ «все регионы») и пересборка оверлеев.
  ///
  /// SPA-переход /map ↔ /map?poi= не пересоздаёт страницу карты
  /// (pageKey один), а смена режима меняет данные источника `pois`
  /// и id фич (namespaced), поэтому слои пересобираются целиком.
  /// Fit-поля камеры НЕ трогаем: build с готовым fit не должен
  /// подменять живую карту лоадером (иначе платформенный вид
  /// пересоздастся), камеру подводит подсветка (animateCamera).
  void _resetOverlaysForModeChange() {

    AppLogger.info(
      '[MapWidget] showAllRegions ${!_showAllRegions} -> '
      '$_showAllRegions, rebuilding overlays',
    );

    _overlaysAdded = false;

    _pois = const [];

    _trails = const [];

    _poiLocations = const [];

    _trailLocations = const [];

    // Слот загрузки привязан к режиму (ключ `*` ↔ локация) —
    // future прежнего режима новой карте не годится.
    _dataSlot.reset();

    // Кеш пакета «все регионы» не соответствует режиму.
    _allRegionsBundle = null;

    _iconsRegistered = false;

    _iconsFuture = null;

    _usedIconCategories = const {};

    _appliedFavoriteKeys = null;

    // A2 (17-й проход): маркер пользователя пересоздаётся вместе
    // с оверлеями — до нового добавления писать в источник нельзя.
    _userMarker.onLayerRemoved();

    // Пульс подсветки тикает в слой «poi-highlight-pulse», который
    // сейчас удаляется: без остановки тик бил в несуществующий
    // слой (unhandled PlatformException LAYER_NOT_FOUND).
    // Пересборка сама включит пульс заново, если подсветка задана
    // (_applyHighlightPoi в конце _loadOverlays).
    _setPulse(false);

    final controller = _controller;

    // Карта ещё не построена — оверлеи соберутся в новом режиме
    // при style.load (поля выше уже сброшены).
    if (controller == null) {
      return;
    }

    unawaited(_rebuildOverlays());
  }


  /// Полная пересборка оверлеев на живой карте: старые
  /// источники/слои удаляются, новые добавляются в новом режиме.
  Future<void> _rebuildOverlays() async {

    await _removeExistingOverlays();

    if (!mounted) {
      return;
    }

    await _maybeAddOverlays();
  }


  /// Тестовый шов (A2, 18-й проход): оверлеи карты в widget-тестах
  /// не строятся (нет платформенной карты), `_pois` остаются
  /// пустыми — layout-тесты верхнего слота кладут точки напрямую,
  /// чтобы чип ближайшей точки построился.
  @visibleForTesting
  void debugSetMapDataForTests(List<Poi> pois, List<String> locations) {

    _pois = pois;

    _poiLocations = locations;
  }

  @override
  Widget build(BuildContext context) {

    final islandId = _effectiveIslandIdWatched;

    // Смена локации через провайдер — реакция на событие, а не
    // побочный эффект в build: раньше reset выполнялся на каждом
    // перестроении (мутация полей состояния прямо во время build).
    // Смена widget.islandId покрывается didUpdateWidget выше.
    ref.listen<String>(currentIslandIdProvider, (previous, next) {

      // Явный остров виджета в приоритете: пока он задан, провайдер
      // на эффективный id не влияет.
      if (widget.islandId != null) {
        return;
      }

      _resetOverlaysIfIslandChanged(next);
    });

    // Воздействие избранного на маркеры: при смене набора источник
    // `pois` пересобирается (сигнальная заливка/ободок избранных POI).
    // Сравнение по identity не даёт планировать no-op после каждого
    // перестроения виджета.
    final favorites = ref.watch(favoritesControllerProvider);

    // «Прослушанные» маркеры — тот же механизм (1b, 12-й проход):
    // источник пересобирается, когда трек доходит до 80%.
    final listened = ref.watch(listenedSetProvider);

    if (!identical(favorites, _lastWatchedFavoriteKeys) ||
        !identical(listened, _lastWatchedListenedKeys)) {

      _lastWatchedFavoriteKeys = favorites;

      _lastWatchedListenedKeys = listened;

      WidgetsBinding.instance.addPostFrameCallback((_) {

        if (mounted) {

          _applyFavoriteStates();
        }
      });
    }

    final manifest =
        ref.watch(islandManifestFamily(islandId));

    // Кэшируем последний известный манифест: методы вне `build`
    // (scale-факторы в `map_layers.dart`) читают поля без `watch`.
    _manifest = manifest.value ?? _manifest;

    final styleAsync =
        ref.watch(mapStyleFamily(islandId));

    return LayoutBuilder(
      builder: (context, constraints) {

        final size = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        // Максимальная ширина карточки навигации: она не должна
        // доходить до кнопок справа (Домой, зум, геолокация).
        // Нижний предел 240 — физический минимум карточки (фикс.
        // элементы: иконка, статус, азимут), чтобы она не переливалась.
        final navCardMaxWidth = (constraints.maxWidth - 80.0)
            .clamp(240.0, 360.0)
            .toDouble();

        return styleAsync.when(

      loading: () => _loadingPlaceholder(),

      error: (error, stack) => Center(
        child: ErrorState(
          message: 'Не удалось загрузить карту',
          description: 'Что-то пошло не так при сборке стиля',
          onRetry: () =>
              ref.invalidate(mapStyleFamily(islandId)),
        ),
      ),

      data: (style) {

        if (style == null) {

          return const NoMapPlaceholder();
        }

        final explicit = widget.initialCameraPosition;

        // Если явной камеры нет — дожидаемся данных острова,
        // чтобы подогнать камеру под маршруты (с запасом).
        if (explicit == null && !_fitReady) {

          _ensureFitData(islandId, manifest.value, size);

          return _loadingPlaceholder();
        }

        return Stack(
          children: [

            // Пока открыт шит, карта не принимает жесты: на web
            // канвас maplibre ловит указатель поверх Flutter-контента
            // и свайпы по шиту сдвигали бы карту.
            IgnorePointer(
              ignoring: _sheetOpen,

              child: MapLibreMap(

              styleString: style,

              // Атрибуция OSM и компас — колонкой в верхней правой
              // части СЛЕВА от кластера «дерево»+«легенда»
              // (right:16): в левом нижнем углу атрибуцию закрывала
              // парящая капсула навигации (лицензия OSM требует
              // ВИДИМОЙ атрибуции), а компас в левом верхнем углу
              // пересекался с чипом ближайшего POI и баннером
              // запрета (P0-3, 5-й проход). На web плагин не
              // поддерживает margins контролов — колонку сдвигает
              // CSS-правило в web/index.html.
              attributionButtonPosition: widget.preview
                  ? AttributionButtonPosition.bottomLeft
                  : AttributionButtonPosition.topRight,
              attributionButtonMargins: widget.preview
                  ? const Point(6, 4)
                  : Point(
                      76 * _controlsPxScale,
                      (60 + widget.controlsTopShift) * _controlsPxScale,
                    ),

              // Компас — в той же колонке, над атрибуцией: вращение
              // и сброс на север. В превью карта не вращается —
              // компас не нужен.
              compassEnabled: !widget.preview,
              compassViewPosition: CompassViewPosition.topRight,
              compassViewMargins: Point(
                76 * _controlsPxScale,
                (14 + widget.controlsTopShift) * _controlsPxScale,
              ),

              annotationOrder: const [],
              annotationConsumeTapEvents: const [
                AnnotationType.circle,
              ],

              initialCameraPosition:
                  explicit ??
                  _fitCamera ??
                  _startCamera(manifest.value, size),

              rotateGesturesEnabled: !widget.preview,
              scrollGesturesEnabled: !widget.preview,
              zoomGesturesEnabled: !widget.preview,
              tiltGesturesEnabled: !widget.preview,
              // B2 (17-й проход): отслеживание камеры нужно режиму
              // слежения «следую за мной» — панорамирование
              // пользователем отличаем от собственного moveCamera
              // по цели камеры.
              trackCameraPosition: !widget.preview,
              onCameraMove: widget.preview ? null : _onCameraMove,
              // ВАЖНО: dragEnabled=TRUE даёт в плагине addGeoJsonSource
              // withSynchronousUpdate(true), из-за чего на Android баг
              // maplibre-native#4326: иконки, зарегистрированные через
              // addImage(), молча отбрасываются при зуме (texture atlas
              // переиспользует слот без перезаливки GPU-пикселей) —
              // белые значки внутри шариков пропадают. Фикс из
              // flutter-maplibre-gl#866: dragEnabled=false (перетаскивание
              // symbol-аннотаций не используется — annotationOrder: []).
              dragEnabled: false,
              featureTapsTriggersMapClick: widget.preview,
              gestureRecognizers: widget.preview
                  ? _previewGestureRecognizers
                  : null,

              // В режиме превью любой клик по карте (в том числе
              // по POI/маршруту) разворачивает её на весь экран.
              onMapClick: widget.preview
                  ? (_, _) {
                      widget.onTap?.call();
                    }
                  : null,

              onMapCreated:
                  (MapLibreMapController controller) {

                _controller = controller;

                if (!widget.preview) {
                  controller.onFeatureTapped.add(
                    _handleFeatureTap,
                  );
                } else {
                  // Б6 (замечание Sonnet): помечаем ЭТУ карту как
                  // превью — глушение pointer-events теперь
                  // работает только по пометке, а не «по последней
                  // созданной» (которой при позднем style.load
                  // могла оказаться полноэкранная карта).
                  tagPreviewMapInstance();

                  // Канвас превью не-интерактивен (тап ловит
                  // Flutter-распознаватель в map_preview.dart), поэтому
                  // убираем его из DOM hit-test: во встроенных браузерах
                  // (Orca) перехваченный канвасом клик у правого/нижнего
                  // края уезжал по координатам — видимые кнопки и область
                  // нажатия не совпадали.
                  disablePreviewCanvasPointerEvents();
                }
              },

              onStyleLoadedCallback:
                  _maybeAddOverlays,
            ),
            ),

            if (!widget.preview)
              AnimatedBuilder(
                // Мини-плеер внизу карты: контролы поднимаются над
                // пилюлей, чтобы не перекрываться (A2c).
                animation: Listenable.merge(
                  [miniPlayerVisible, modalSheetOpenCount],
                ),
                builder: (context, _) {
                  final lifted = miniPlayerVisible.value &&
                      modalSheetOpenCount.value == 0;

                  return AnimatedPositioned(
                    // Единый блок контролов над парящей капсулой
                    // навигации (учёт её высоты — не магические
                    // числа); над мини-плеером — с запасом.
                    right: 16,
                    bottom: NavigationShell.capsuleExtent +
                        12 +
                        (lifted ? 66 : 0),
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    child: PointerInterceptor(
                      child: MapControlsHoverLock(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [

                            // Кнопка GPS — четыре состояния (B2/B3,
                            // 18-й проход): «определить» (locateFixed)
                            // → «ищу» (индикатор, повторный тап — отмена)
                            // → «следую за мной» (заливка depth) →
                            // «по курсу» (повёрнутая карта, тап —
                            // возврат к северу). B6: затянувшаяся грубая
                            // точность — подпись «±N м» прямо в кнопке.
                            GlassIconButton(
                              tooltip: followCamera.courseUp
                                  ? 'Карта повёрнута по курсу '
                                        '(нажмите — возврат к северу)'
                                  : followCamera.following
                                      ? (_lastAccuracyMeters != null &&
                                              _lastAccuracyMeters! >
                                                  _poorAccuracyMeters
                                          ? 'Слежение за местоположением '
                                                '(точность ±${_lastAccuracyMeters!.round()} м)'
                                          : 'Слежение за местоположением '
                                                '(нажмите — поворот по курсу)')
                                      : _locating
                                          ? 'Идёт поиск позиции '
                                                '(нажмите — отменить)'
                                          : 'Моё местоположение',
                              icon: followCamera.following
                                  ? LucideIcons.navigation2
                                  : LucideIcons.locateFixed,
                              active: followCamera.following,
                              onTap: () {
                                if (followCamera.courseUp) {
                                  _exitCourseUp();
                                } else if (followCamera.following) {
                                  _enterCourseUp();
                                } else {
                                  _locateMe();
                                }
                              },
                              loading: _locating,
                            ),

                            const SizedBox(height: 10),

                            // Компактная вертикальная пилюля «+ / −»
                            // вместо двух тяжёлых 56-px FAB'ов.
                            Container(
                              decoration: BoxDecoration(
                                color: AppPalette.of(context)
                                    .surfaceRaised
                                    .withValues(alpha: 0.94),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.tile),
                                border: Border.all(
                                    color: AppPalette.of(context).sand,
                                    width: 1),
                                boxShadow: AppShadows.floating(
                                    AppPalette.of(context).onSurface),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Приблизить',
                                    onPressed: _zoomIn,
                                    icon: const Icon(
                                      LucideIcons.plus,
                                      size: 20,
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(44, 44),
                                      padding: EdgeInsets.zero,
                                      foregroundColor:
                                          AppPalette.of(context).onSurface,
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: AppPalette.of(context)
                                        .sand
                                        .withValues(alpha: 0.7),
                                    indent: 10,
                                    endIndent: 10,
                                  ),
                                  IconButton(
                                    tooltip: 'Отдалить',
                                    onPressed: _zoomOut,
                                    icon: const Icon(
                                      LucideIcons.minus,
                                      size: 20,
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(44, 44),
                                      padding: EdgeInsets.zero,
                                      foregroundColor:
                                          AppPalette.of(context).onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // ЕДИНЫЙ верхний левый слот (A2, 18-й проход): плашка
            // статуса геолокации → чип ближайшей точки → слот
            // MapPage (погода/баннер/«Рядом») — одна колонка,
            // пересечения исключены конструктивно (раньше плашка и
            // чип висели в одном left:12/top:12). Появление плашки —
            // мягкий фейд (B5; Reduce Motion — мгновенно).
            if (!widget.preview)
              Positioned(
                key: const ValueKey('map-top-left-slot'),
                left: 12,
                top: 12,
                right: 76,
                child: MapControlsHoverLock(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Плашка статуса геолокации (B3/B5).
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.fast,
                        switchInCurve: AppMotion.curve,
                        switchOutCurve: AppMotion.curve,
                        child: gpsStatus.status == MapLocationStatus.none
                            ? const SizedBox.shrink()
                            : MapLocationStatusPill(
                                key: const ValueKey(
                                  'map-location-status-pill',
                                ),
                                status: gpsStatus.status,
                                accuracyMeters: _lastAccuracyMeters,
                                onTap: _onStatusPillTap,
                              ),
                      ),

                      // Чип ближайшей точки: подписан на поворот камеры —
                      // стрелка всегда «относительно экрана» (B4), без
                      // перестройки всей карты.
                      if (_nearestPoiDistance != null) ...[
                        if (gpsStatus.status != MapLocationStatus.none)
                          const SizedBox(height: 8),
                        ValueListenableBuilder<double>(
                          valueListenable: _cameraBearingNotifier,
                          builder: (context, mapBearing, _) =>
                              NearestPoiChip(
                            title: _nearestPoiTitle ?? '',
                            distance: _nearestPoiDistance ?? 0,
                            bearing: _nearestPoiBearing,
                            mapBearing: mapBearing,
                            onTap: _onNearestPoiTap,
                          ),
                        ),
                      ],

                      // Слот MapPage: погода → баннер запрета →
                      // «Рядом» (A2).
                      if (widget.topLeftControls != null) ...[
                        if (gpsStatus.status != MapLocationStatus.none ||
                            _nearestPoiDistance != null)
                          const SizedBox(height: 8),
                        widget.topLeftControls!,
                      ],
                    ],
                  ),
                ),
              ),


            // ЕДИНАЯ КОЛОНКА левого нижнего угла (B1): карточка
            // навигации по маршруту -> слот фильтра категорий
            // (передан с MapPage). Один lift над капсулой и
            // мини-плеером — конфликт за bottom-left исключён.
            if (!widget.preview && (_navState != null || widget.bottomLeftControls != null))
              AnimatedBuilder(
                // Колонка уходит выше мини-плеера целиком.
                animation: Listenable.merge(
                  [miniPlayerVisible, modalSheetOpenCount],
                ),
                builder: (context, _) {
                  final lifted = miniPlayerVisible.value &&
                      modalSheetOpenCount.value == 0;

                  return AnimatedPositioned(
                    left: 12,
                    right: 76,
                    // Над парящей капсулой навигации + воздух;
                    // с мини-плеером — выше пилюли.
                    bottom: NavigationShell.capsuleExtent +
                        12 +
                        (lifted ? 66 : 0),
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    child: MapControlsHoverLock(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_navState != null)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: navCardMaxWidth,
                              ),
                              child: TrailNavigationCard(
                                state: _navState!,
                              ),
                            ),
                          if (_navState != null &&
                              widget.bottomLeftControls != null)
                            const SizedBox(height: 8),
                          if (widget.bottomLeftControls != null)
                            widget.bottomLeftControls!,
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },

        );
      },
    );
  }


  /// Плейсхолдер загрузки карты.
  ///
  /// В обычном режиме — крутящийся спиннер. В режиме превью —
  /// статичная заглушка без анимации: спиннер не даёт
  /// `pumpAndSettle` в виджет-тестах завершиться, а на реальном
  /// устройстве стиль и тайлы грузятся за доли секунды.
  Widget _loadingPlaceholder() {

    if (!widget.preview) {

      return const Center(
        child: CircularProgressIndicator(),
      );
    }


    // Б10: превью-заглушка — «бумажный лист» с градусными тиками
    // и компасом вместо статичного текста: размеры будущего
    // блока совпадают, вёрстка не прыгает при загрузке стиля.
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.mapPlaceholder),
        const Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: ChartTicksPainter()),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.compass,
                size: 34,
                color: AppColors.depth.withValues(alpha: 0.32),
              ),
              const SizedBox(height: 8),
              Text(
                'Загружаем карту…',
                style: AppText.caption.copyWith(
                  letterSpacing: 0.8,
                  color:
                      AppPalette.of(context).onSurface
                          .withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  /// Возврат в приложение: разрешение могли выдать в
  /// настройках телефона мимо приложения — перепроверяем
  /// (15-й проход).
  ///
  /// A1/A12 (18-й проход): политика фона — приложение свёрнуто
  /// (paused/hidden) — платформенная подписка GPS ОТМЕНЯЕТСЯ
  /// (нативный опрос не жжёт батарею и не копит буфер
  /// устаревших фиксов; прежний pause() буферизовал события).
  /// `inactive` НЕ останавливает трекинг: так ведёт себя
  /// системный диалог разрешений и шторка уведомлений — рвать
  /// GPS из-за них нельзя. При возврате — свежая подписка и
  /// перепроверка прав. Политику держит MapWidget, а не сервис:
  /// между вкладками шелла карта живёт в стеке, и автогид
  /// осознанно продолжает работать (см. AGENTS.md).
  /// Аудиогид не затрагивается: плеер живёт отдельно от потока
  /// позиций (iOS фонит его без GPS-потока).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {

    if (widget.preview) {
      return;
    }

    final location = ref.read(locationServiceProvider);

    switch (state) {

      case AppLifecycleState.resumed:

        location.resumePlatformStream();

        _recheckPermissionOnResume();

      // Системные диалоги (запрос разрешения, шторка) — трекинг
      // НЕ рвём (A1: короткий inactive не должен глушить GPS).
      case AppLifecycleState.inactive:
        break;

      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:

        location.pausePlatformStream();

      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {

    WidgetsBinding.instance.removeObserver(this);

    AppLogger.info('[MapWidget] dispose');

    _positionSub?.cancel();

    _serviceStatusSub?.cancel();

    _signalSearchTimer?.cancel();

    // B1/A11 (18-й проход): побочные таймеры трекинга.
    userMarker.dispose();

    _poorAccuracyTimer?.cancel();

    _markerTween?.dispose();

    _cameraBearingNotifier.dispose();

    _pulseController.dispose();

    super.dispose();
  }
}



/// Адаптер контроллера карты к [UserMarkerSink] (A1/A2, 17-й
/// проход): узкий интерфейс, который подменяется фейком в
/// тестах маркера.
class _MapLibreUserMarkerSink implements UserMarkerSink {

  _MapLibreUserMarkerSink(this._controller);

  final MapLibreMapController _controller;

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, Object?> data,
  ) {
    return _controller.setGeoJsonSource(sourceId, data);
  }
}
