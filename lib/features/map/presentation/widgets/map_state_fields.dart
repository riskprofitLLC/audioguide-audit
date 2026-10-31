part of 'map_widget.dart';


/// Данные карты для показа: POI и маршруты плюс локация каждого
/// элемента (параллельные списки).
///
/// В обычном режиме все элементы принадлежат одной локации,
/// в режиме [MapWidget.showAllRegions] — разным регионам.
typedef MapDataBundle = ({
  List<Poi> pois,
  List<Trail> trails,
  List<String> poiLocations,
  List<String> trailLocations,
});


/// Максимальный возраст курса, при котором он ещё «живой» (A5,
/// 18-й проход): у стоящего стрелка не указывает по устаревшему
/// направлению последнего движения.
const Duration _courseFreshAge = Duration(seconds: 5);

/// Минимальная скорость для использования курса (м/с, A5).
const double _courseMinSpeedMps = 0.8;

/// Порог «грубой» точности автогида — тот же, что у вотчера
/// (A11, 18-й проход): при превышении дольше [_poorAccuracyDelay]
/// объясняем, почему гид молчит.
const double _poorAccuracyMeters = 100;

/// Как долго грубая точность должна тянуться для подсказки.
const Duration _poorAccuracyDelay = Duration(seconds: 20);

/// Общее состояние карты: контроллер, загруженные данные, флаги
/// оверлеев, состояние GPS-трекинга и пульса выделенной точки.
///
/// Вынесено в отдельный mixin, чтобы остальные mixin-части
/// `_MapWidgetState` могли обращаться к полям через `on _MapStateFields`.
mixin _MapStateFields on ConsumerState<MapWidget> {

  MapLibreMapController? _controller;

  /// Готовый контроллер карты (`null` до инициализации).
  ///
  /// Единая точка доступа: в методах достаточно
  /// `final controller = _readyController; if (controller == null) return;`.
  MapLibreMapController? get _readyController => _controller;

  bool _overlaysAdded = false;

  List<Poi> _pois = const [];

  List<Trail> _trails = const [];

  /// Локация каждого элемента [_pois] (параллельный список).
  ///
  /// В обычном режиме все элементы принадлежат одной локации,
  /// в режиме [MapWidget.showAllRegions] — разным регионам.
  List<String> _poiLocations = const [];

  /// Локация каждого элемента [_trails] (параллельный список).
  List<String> _trailLocations = const [];

  /// Локация, под которую настроено ТЕКУЩЕЕ состояние карты
  /// (данные, камера, оверлеи).
  ///
  /// Обновляется синхронно при смене локации — в отличие от
  /// загруженных данных, которые появляются только по завершении
  /// загрузки. Поэтому быстрые переключения, сделанные ДО
  /// окончания первой загрузки, тоже корректно сбрасывают
  /// состояние (раньше `_islandId` в этот момент оставался пустым
  /// и сброс пропускался — карта получала камеру/данные прежней
  /// локации).
  String _configuredIslandKey = '';

  /// Манифест текущей локации (для читателей вне `build`:
  /// scale-факторы маркеров, поправки к камере).
  Manifest? _manifest;

  // Подписка создаётся в map_tracking.dart, а отменяется в dispose()
  // (map_widget.dart) — поле живёт весь жизненный цикл виджета, это
  // легитимный лайфтайм-паттерн для State.
  // ignore: cancel_subscriptions
  StreamSubscription<UserPosition>? _positionSub;

  /// Слушатель состояния СЛУЖБЫ геолокации (A7, 17-й проход):
  /// выключение в шторке телефона замечаем без ожидания resume.
  /// Отменяется в dispose() (map_widget.dart) — как и _positionSub.
  // ignore: cancel_subscriptions
  StreamSubscription<bool>? _serviceStatusSub;

  /// Состояние маркера «Вы здесь» (A1/A2, 17-й проход): последняя
  /// позиция переживает пересборку оверлеев, GeoJSON не пишется
  /// в удалённый источник.
  final UserMarkerSource _userMarker = UserMarkerSource();

  bool _trackingStarted = false;

  /// Статус геолокации для единой плашки (B3, 17-й проход).
  /// Контроллер статуса GPS-плашки (D5/R1): машина состояний
  /// вынесена из виджета в GpsStatusController (без BuildContext).
  final gpsStatus = GpsStatusController();

  /// Таймер «нет фикса дольше 15 с» — плашка «Ищем сигнал GPS…»
  /// (B3, 17-й проход); снимается первым же фиксом.
  Timer? _signalSearchTimer;

  /// Идёт поиск текущей позиции по кнопке GPS — на кнопке
  /// индикатор, повторный тап отменяет поиск (A5, 17-й проход).
  bool _locating = false;

  /// Поколение запроса _locateMe: инкремент отменяет результат
  /// устаревшего запроса (A5).
  int _locateGeneration = 0;

  /// Идёт запрос разрешения геолокации (Б11, замечание
  /// Sonnet): ensurePermission может висеть системным диалогом
  /// до 60 с — повторные тапы по кнопке GPS обязаны
  /// игнорироваться, а не открывать второй системный диалог.
  bool _permissionRequestInFlight = false;

  /// Контроллер слежения за камерой (D5/R1: чистая логика режимов
  /// «следую за мной»/«по курсу» вынесена из виджета —
  /// FollowCameraController, без BuildContext).
  final followCamera = follow_camera_controller.FollowCameraController();

  /// Курс пользователя (градусы, 0 — север): heading платформы
  /// или вычисленный по смещению между фиксами (A17).
  double? _course;

  /// Когда получен [_course] — курс «свежий» только ~5 с (A5,
  /// 18-й проход): у стоящего стрелка не должна указывать по
  /// устаревшему направлению последнего движения.
  DateTime? _courseAt;

  /// Скорость, к которой привязан [_course] (м/с): платформенная
  /// или вычисленная по смещению/времени (A7). Курс используется
  /// только при скорости выше ~0.8 м/с — ниже это шум GPS.
  double? _courseSpeedMps;

  /// Скорость последнего фикса, вычисленная по смещению/времени
  /// (A7, 18-й проход): платформа (web) часто не отдаёт speed —
  /// конус направления обязан появляться и там.
  double? _lastComputedSpeedMps;


  /// Предыдущая позиция — для расчёта курса и скорости смещением
  /// (A17/A7).
  UserPosition? _prevPosition;

  /// Последняя обработанная позиция — защита от дубля (A6, 18-й
  /// проход): разовая позиция с кнопки GPS приходит и потоком, и
  /// прямым вызовом — один и тот же объект.
  UserPosition? _lastProcessedPosition;

  /// Анимация движения маркера между фиксами (B2) — контроллеру
  /// нужен vsync, поэтому AnimationController остаётся здесь.
  AnimationController? _markerTween;

  /// Контроллер маркера «Вы здесь» (D5/R1): позиция на карте,
  /// границы твина, троттлинг записи и каскад свежести вынесены
  /// в UserMarkerController (без BuildContext).
  final userMarker = UserMarkerController();


  /// Когда впервые увидели грубый фикс (accuracy > 100 м) — плашка
  /// «Точность ±N м» после 20 с подряд (A11, 18-й проход).
  DateTime? _poorAccuracySince;

  /// Таймер отложенной проверки «грубая точность затянулась».
  Timer? _poorAccuracyTimer;

  /// Точность последнего фикса (для подписи «±N м», A11/B6).
  double? _lastAccuracyMeters;


  /// Нотификатор bearing камеры (B4): чип ближайшей точки
  /// слушает его и перерисовывает стрелку «относительно экрана»
  /// без перестройки всей карты. Обновляется из onCameraMove.
  final ValueNotifier<double> _cameraBearingNotifier =
      ValueNotifier<double>(0);

  /// Ближайшая точка и её локация (B4, 17-й проход): тап по чипу
  /// подлетает к точке и открывает её шторку.
  (Poi, String)? _nearestPoi;

  double? _nearestPoiDistance;

  /// Курс (азимут) на ближайшую точку — для стрелки на чипе
  /// (П2, 12-й проход).
  double? _nearestPoiBearing;

  /// Заголовок ближайшей точки (сравнение при смене).
  String? _nearestPoiTitle;

  /// Открыт ли сейчас информационный шит (POI/маршрут).
  ///
  /// Пока шит на экране, карта не должна реагировать на жесты:
  /// на web канвас maplibre лежит в DOM поверх Flutter-контента
  /// и перехватывает свайпы по шиту, сдвигая карту.
  bool _sheetOpen = false;

  final TrailNavigator _trailNavigator =
      TrailNavigator();

  TrailNavigationState? _navState;

  /// Слот будущего загрузки POI/маршрутов, привязанный к локации
  /// (в режиме «все регионы» — общий ключ `*`).
  ///
  /// Общий для предзагрузки стартовой камеры и оверлеев, чтобы
  /// данные не читались дважды. Ключ защищает от гонки быстрого
  /// переключения: future, созданный для прежней локации, новой
  /// локации не подсунывается.
  final KeyedFutureSlot<MapDataBundle> _dataSlot =
      KeyedFutureSlot<MapDataBundle>();

  /// Полный пакет «все регионы» после фоновой догрузки (P1-3,
  /// 6-й проход): первые маркеры рисуются по быстрому пакету
  /// текущей локации, остальные догружаются и подливаются в
  /// источники. Кешируется — повторные сборки оверлеев (сброс
  /// стиля) берут готовое.
  MapDataBundle? _allRegionsBundle;

  /// Фоновая догрузка остальных локаций уже идёт.
  bool _allRegionsMergeInFlight = false;

  /// Камера, подогнанная под маршруты острова.
  ///
  /// `null`, пока данные не загружены или их нет.
  CameraPosition? _fitCamera;

  /// Стала ли известна камера по данным (или принято
  /// решение использовать фолбэк).
  bool _fitReady = false;


  /// Для какой локации уже запрошена подгонка камеры.
  ///
  /// `_ensureFitData` вызывается из build, пока данные грузятся:
  /// без этого флага каждый rebuild запускал новый await того же
  /// future и по завершении делал свой setState с той же камерой.
  String? _fitRequestedForIsland;


  /// Зарегистрированы ли иконки POI для текущего стиля карты.
  ///
  /// Сбрасывается при смене острова (новый style -> иконки нужно
  /// перерегистрировать в [controller.addImage]).
  bool _iconsRegistered = false;

  /// Общий future регистрации иконок (разделяется между
  /// [_loadOverlays] и [_addPoisLayer], чтобы слои маркеров не
  /// добавлялись раньше готовых иконок).
  Future<void>? _iconsFuture;

  /// Категории POI, встречающиеся на текущем острове.
  ///
  /// Регистрируются только эти иконки (+ дефолтная) — на web
  /// каждый `addImage` это платформенный roundtrip, и 24 лишних
  /// вызова ощутимо задерживают появление маркеров.
  Set<String> _usedIconCategories = const {};

  /// Набор ключей избранного (`локация/poi-XX`), вшитый в текущие
  /// данные источника `pois`.
  ///
  /// При смене избранного источник пересобирается с обновлённым
  /// свойством `isFavorite` ([_applyFavoriteStates]); `null`, пока
  /// оверлеи не добавлены.
  Set<String>? _appliedFavoriteKeys;

  /// Последние применённые к источнику ключи прослушанных (1b).
  Set<String>? _appliedListenedKeys;

  /// Последняя отслеженная в `build` порция избранного
  /// (сравнение по identity — порции меняются только при
  /// реальном добавлении/удалении объектов).
  Set<String>? _lastWatchedFavoriteKeys;

  /// Последний замеченный в build набор прослушанных (1b).
  Set<String>? _lastWatchedListenedKeys;

  /// Активный фильтр категорий (1c): применяется при каждой
  /// сборке источника `pois`.
  String? _activeCategoryFilter;

  /// Последний применённый к источнику фильтр категорий (1c).
  String? _appliedCategoryFilter;


  /// Контроллер анимации пульсирующего кольца вокруг выделенного POI.
  late final AnimationController _pulseController;

  /// Идёт ли сейчас пульсация (запускается только при активном
  /// выделении POI).
  bool _pulseRunning = false;

  /// Время последнего кадра пульса (троттлинг ~80 мс, чтобы не
  /// долбить платформенный канал каждый кадр анимации).
  DateTime? _lastPulseFrame;

  /// Роут, на котором живёт карта.
  ///
  /// Карта остаётся в стеке, когда поверх пушат детали POI/маршрута
  /// (`/map?poi=…`): по нему пульс отключает отправку кадров в
  /// невидимую карту.
  ModalRoute<dynamic>? _route;


  /// Остров, который показывает карта.
  ///
  /// Явный параметр виджета имеет приоритет, иначе —
  /// текущий выбранный остров. Использует `read` чтобы
  /// не требовать `watch` вне `build`.
  String get _effectiveIslandId {

    final String resolved =
        widget.islandId ??
        ref.read(currentIslandIdProvider);

    return resolved;
  }

  /// Вариант для `build`, который подписывается на изменения острова.
  String get _effectiveIslandIdWatched {

    final String resolved =
        widget.islandId ??
        ref.watch(currentIslandIdProvider);

    return resolved;
  }

  /// Включён ли режим «все регионы» (карта показывает POI всех
  /// локаций сразу и группирует их в кластеры при отдалении).
  bool get _showAllRegions => widget.showAllRegions;

  /// Ключ загрузки данных карты.
  ///
  /// В режиме «все регионы» данные общие для всех локаций —
  /// ключ один (`*`), при смене локации загруженный пакет
  /// переиспользуется. В обычном режиме ключ — эффективная
  /// локация: смена локации отбрасывает чужой future.
  String get _effectiveIslandKey =>
      _showAllRegions ? '*' : _effectiveIslandId;

  /// Текущий набор ключей избранного (`локация/poi-XX`).
  ///
  /// Используется при сборке GeoJSON источника `pois` (свойство
  /// `isFavorite`) и при переприменении после смены избранного.
  /// Читается с `read`, т.к. вызывается вне `build`.
  Set<String> _currentFavoriteKeys() =>
      ref.read(favoritesControllerProvider);

  /// Ключи прослушанных POI — тот же формат «локация/poi-XX»
  /// (1b, 12-й проход).
  Set<String> _currentListenedKeys() => ref.read(listenedSetProvider);

  /// Масштаб полей платформенных контролов карты (компас/атрибуция):
  /// Android-плагин maplibre принимает ПИКСЕЛИ — dp-значения
  /// умножаются на плотность экрана, иначе компас на телефоне
  /// уезжал под пилюлю «К описанию» (76 px ≈ 29 dp на 420 dpi).
  /// iOS принимает пункты, web margins не поддержаны (CSS-сдвиг)
  /// — масштаб 1.
  double get _controlsPxScale {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 1;
    }

    return MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  }

  /// Ищет POI по исходному id (`poi-XX`) среди загруженных.
  ///
  /// В режиме «все регионы» — только в пределах текущей локации
  /// (id точек повторяются в каждой локации). Возвращает пару
  /// «POI, локация», либо `null`.
  (Poi, String)? _findPoiWithLocation(String? id) {

    if (id == null || id.isEmpty) {
      return null;
    }

    for (var i = 0; i < _pois.length; i++) {
      if (_pois[i].id == id &&
          (!_showAllRegions || _poiLocations[i] == _effectiveIslandId)) {
        return (_pois[i], _poiLocations[i]);
      }
    }

    return null;
  }

  /// Ищет маршрут по исходному id (`trail-XX`) среди загруженных.
  ///
  /// Возвращает пару «маршрут, локация», либо `null`.
  (Trail, String)? _findTrailWithLocation(String? id) {

    if (id == null || id.isEmpty) {
      return null;
    }

    for (var i = 0; i < _trails.length; i++) {
      if (_trails[i].id == id &&
          (!_showAllRegions || _trailLocations[i] == _effectiveIslandId)) {
        return (_trails[i], _trailLocations[i]);
      }
    }

    return null;
  }

  /// Ищет POI по составному id фичи карты (`локация/poi-XX`).
  ///
  /// В обычном режиме составной id не используется — ищется
  /// просто по исходному id.
  (Poi, String)? _resolvePoiFeature(String? featureId) {

    if (featureId == null || featureId.isEmpty) {
      return null;
    }

    if (!_showAllRegions) {
      return _findPoiWithLocation(featureId);
    }

    final slash = featureId.lastIndexOf('/');

    if (slash <= 0 || slash == featureId.length - 1) {
      return null;
    }

    final locationId = featureId.substring(0, slash);
    final poiId = featureId.substring(slash + 1);

    for (var i = 0; i < _pois.length; i++) {
      if (_poiLocations[i] == locationId && _pois[i].id == poiId) {
        return (_pois[i], locationId);
      }
    }

    return null;
  }

  /// Ищет маршрут по составному id фичи карты (`локация/trail-XX`).
  (Trail, String)? _resolveTrailFeature(String? featureId) {

    if (featureId == null || featureId.isEmpty) {
      return null;
    }

    if (!_showAllRegions) {
      return _findTrailWithLocation(featureId);
    }

    final slash = featureId.lastIndexOf('/');

    if (slash <= 0 || slash == featureId.length - 1) {
      return null;
    }

    final locationId = featureId.substring(0, slash);
    final trailId = featureId.substring(slash + 1);

    for (var i = 0; i < _trails.length; i++) {
      if (_trailLocations[i] == locationId && _trails[i].id == trailId) {
        return (_trails[i], locationId);
      }
    }

    return null;
  }
}
