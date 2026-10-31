part of 'map_widget.dart';


/// Цвет маршрута по умолчанию (когда ни один не выделен).
///
/// Глубокая бирюза бренда (AppColors.mapTrail = #19617B) с
/// белым кейсингом — цвет прокладки читается как элемент
/// морской карты и не выбивается из палитры (маджента
/// #C43A8C конфликтовала с бирюзово-терракотовой темой).
const String _trailDefaultColor = '#19617B';

/// Цвет выделенного маршрута.
const String _trailHighlightColor = '#19617B';

/// Цвет остальных маршрутов, когда один выделен
/// (AppColors.mapTrailMuted = #7BA7BB).
const String _trailMutedColor = '#7BA7BB';

/// Палитра цветов маршрутов, когда ни один не выделен.
///
/// Все маршруты — бирюзовые (единый стиль).
const List<String> _trailPalette = [
  '#19617B',
];


/// Цвет точки интереса по умолчанию — морской синий шарик
/// (бывший чернильный #10222E выглядел чёрным).
const String _poiDefaultColor = '#1668A8';

/// Цвет выделенной точки интереса — сигнальный
/// (AppColors.signal — красно-оранжевый «сигнал» карт).
const String _poiHighlightColor = '#E85D3F';

/// Цвет шарика POI, добавленного в избранное (сигнальный,
/// как звезда избранного в интерфейсе — AppColors.signal).
const String _poiFavoriteColor = '#E85D3F';

/// Цвет ободка POI, добавленного в избранное
/// (AppColors.signalDark — глубокий терракотовый).
const String _poiFavoriteRingColor = '#C44A30';

/// Цвет шарика прослушанного POI (1b, 12-й проход): выцветший
/// пергамент — «точка пройдена», не спорит с фоном воды и суши.
const String _poiListenedColor = '#CFC7B2';

/// Прозрачность иконки прослушанного POI.
const double _poiListenedIconOpacity = 0.55;


/// Выражение цвета шарика POI (1b, 12-й проход): избранное
/// главнее прослушанного (сигнальная звезда не гаснет), дальше —
/// приглушение прослушанных, затем категория/выделение.
///
/// Чистая функция — покрыта тестом (map_layers_test).
dynamic buildPoiBallColorExpression(dynamic categoryColor) {
  return [
    'case',
    ['get', 'isFavorite'],
    _poiFavoriteColor,
    ['get', 'isListened'],
    _poiListenedColor,
    categoryColor,
  ];
}


/// Выражение прозрачности иконки POI: прослушанные — приглушены
/// (1b). Чистая функция — покрыта тестом.
dynamic buildPoiIconOpacityExpression() {
  return [
    'case',
    ['get', 'isListened'],
    _poiListenedIconOpacity,
    1.0,
  ];
}


/// Размер иконки POI, выделенного через [MapWidget.highlightPoiId].
const double _poiHighlightIconSize = 0.12;

/// Размер обычной иконки POI.
const double _poiDefaultIconSize = 0.1;

/// Радиус цветного шарика-подложки выделенного POI.
const double _poiHighlightBallRadius = 19;

/// Радиус цветного шарика-подложки обычного POI.
const double _poiDefaultBallRadius = 16;


/// Категория POI -> имя файла SDF-иконки в `assets/map_icons/` —
/// берётся из ЕДИНОЙ таблицы категорий (poi_category.dart):
/// карта, легенда и hero-плейсхолдер берают иконки из одного
/// источника и не расходятся (P0-8, 5-й проход).
final Map<String, String> _poiIconAssets = {
  for (final entry in kPoiCategories.entries)
    if (entry.value.mapIcon != null) entry.key: entry.value.mapIcon!,
};

/// Имя иконки-фолбэка для POI без категории.
const String _poiDefaultIconName = 'poi-default';


/// Строит match-выражение style-spec для иконки POI по категории.
///
/// [usedCategories] — категории, реально встречающиеся на карте
/// (регистрируются и матчатся только они: на web каждый addImage —
/// платформенный roundtrip, лишние иконки задерживают маркеры),
/// [iconAssets] — карта «категория → файл иконки»,
/// [defaultIcon] — имя иконки-фолбэка для точек без категории.
///
/// Если НИ одна из [usedCategories] не входит в [iconAssets],
/// match-пары не образуются, и выражение выродилось бы в
/// невалидное `['match', input, default]` — maplibre не принимает
/// match без пар, слой иконок падал бы целиком. В этом случае
/// возвращается просто имя иконки-фолбэка.
dynamic buildPoiIconImageExpression(
  Set<String> usedCategories,
  Map<String, String> iconAssets, {
  String defaultIcon = _poiDefaultIconName,
}) {

  final args = <dynamic>[
    'match',
    ['get', 'category'],
  ];

  iconAssets.forEach((category, fileName) {

    if (!usedCategories.contains(category)) {
      return;
    }

    args.add(category);

    args.add('poi-$category');
  });

  // Ни одной пары «категория → иконка» — вырожденный match
  // невалиден, отдаём фолбэк напрямую.
  if (args.length == 2) {

    return defaultIcon;
  }

  args.add(defaultIcon);

  return args;
}

/// Кеш байтов SDF-иконок между открытиями карты.
///
/// Иконки одинаковы для всех островов, поэтому PNG читаются
/// с диска/из сети только один раз за сессию.
/// Очищается при `MapWidget.dispose` если нужно.
final Map<String, ByteData> _iconDataCache = {};


/// Методы построения свойств слоёв карты: маркеры POI (шарики,
/// иконки, подписи), линии маршрутов и их casing-подложка.
///
/// Вынесены из `_MapWidgetState` в отдельный файл, чтобы уменьшить
/// размер основного файла карты.
mixin _MapLayersMixin on _MapStateFields {

  /// Цвет иконки POI.
  ///
  /// Если задан [MapWidget.highlightPoiId] — выбранная точка
  /// красится ярким цветом, остальные — стандартным.
  dynamic _poiIconColor() {

    final highlightId = widget.highlightPoiId;

    if (highlightId == null || highlightId.isEmpty) {

      return _poiDefaultColor;
    }

    return [
      'match',
      ['get', 'poiId'],
      highlightId,
      _poiHighlightColor,
      _poiDefaultColor,
    ];
  }


  /// Имя иконки POI по категории.
  ///
  /// match-выражение строит [buildPoiIconImageExpression] —
  /// чистая функция отдельно от виджета, покрыта тестом
  /// (`test/map_layers_test.dart`).
  dynamic _poiIconImage() {

    return buildPoiIconImageExpression(
      _usedIconCategories,
      _poiIconAssets,
    );
  }


  /// Множитель размера маркеров для текущего острова.
  ///
  /// Например, на Гемилере остров маленький и стартовая камера
  /// приближена (zoom ~16), из-за чего маркеры выглядят крупнее,
  /// чем на других островах. Компенсируем это уменьшением базового
  /// размера. Значение берётся из манифеста локации
  /// (`poiScaleFactor`), а не хардкодится по id.
  double get _poiScaleFactor =>
      _manifest?.poiScaleFactor ?? 1.0;

  /// Множитель размера подписей POI.
  ///
  /// Отдельный от маркеров: текст не уменьшается так сильно, как
  /// маркеры (например, на Гемилере), иначе подписи становятся
  /// мелкими и размытыми (SDF-глифы при 7-8px сливаются).
  /// Задаётся в манифесте (`poiLabelScaleFactor`).
  double get _poiLabelScaleFactor =>
      _manifest?.poiLabelScaleFactor ?? 1.0;

  /// Интерполяция размера подписей POI по зуму карты.
  ///
  /// Подписи масштабируются вместе с маркерами: на удалении
  /// уменьшаются, при приближении растут (до 21px на zoom 18).
  /// Для островов с [get _poiScaleFactor] < 1 подписи тоже
  /// уменьшаются пропорционально.
  List<Object?> _poiLabelTextSize() {

    final factor = _poiLabelScaleFactor;

    return [
      'interpolate',
      ['linear'],
      ['zoom'],
      9,
      9 * factor,
      12,
      12 * factor,
      15,
      15 * factor,
      18,
      21 * factor,
      21,
      18 * factor,
    ];
  }

  /// Размер иконки POI (выделенная — крупнее).
  ///
  /// Интерполируется по zoom: при отдалении карты иконки
  /// уменьшаются, при приближении — растут.
  ///
  /// ВАЖНО: maplibre допускает только ОДНУ zoom-интерполяцию на
  /// выражение и она должна быть на верхнем уровне. Поэтому
  /// `interpolate` оборачивает `match`, а не наоборот.
  dynamic _poiIconSize() {

    final factor = _poiScaleFactor;

    return _zoomScaled(
      _poiDefaultIconSize * factor,
      highlightValue: _poiHighlightIconSize * factor,
    );
  }

  /// Радиус шарика-подложки POI (выделенный — крупнее).
  ///
  /// Интерполируется по zoom вместе с иконкой.
  dynamic _poiBallRadius() {

    final factor = _poiScaleFactor;

    return _zoomScaled(
      _poiDefaultBallRadius * factor,
      highlightValue: _poiHighlightBallRadius * factor,
    );
  }

  /// Интерполяция размера/радиуса по зуму карты.
  ///
  /// При отдалении карты значки уменьшаются, при приближении —
  /// заметно растут (в 2 раза от zoom 9 до zoom 21). Если задан
  /// выделенный POI — внутри подставляется match по id.
  dynamic _zoomScaled(
    double base, {
    double? highlightValue,
  }) {

    final highlightId = widget.highlightPoiId;

    final dynamic atZoom =
        (highlightValue != null && highlightId != null && highlightId.isNotEmpty)
            ? [
                'match',
                ['get', 'poiId'],
                highlightId,
                highlightValue,
                base,
              ]
            : base;

    return [
      'interpolate',
      ['linear'],
      ['zoom'],
      9,
      ['*', atZoom, 0.25],
      12,
      ['*', atZoom, 0.7],
      15,
      atZoom,
      18,
      ['*', atZoom, 1.4],
      21,
      ['*', atZoom, 3.0],
    ];
  }


  /// Полный набор свойств слоя иконок POI.
  ///
  /// Используется и при создании слоя, и при перекраске выделения
  /// через [setLayerProperties]. ВАЖНО: контроллер сериализует
  /// свойства с `skipNulls: false`, а плагин web для каждого поля
  /// сначала пробует setPaintProperty, при падении — setLayoutProperty.
  /// Если оставить какое-то поле null (как было при передаче
  /// частичного `SymbolLayerProperties(iconColor, iconSize)`), плагин
  /// вызовет `setLayoutProperty('icon-image', null)` и maplibre
  /// СБРОСИТ иконку в дефолт. Поэтому всегда передаём полный набор.
  SymbolLayerProperties _poiIconLayerProperties() {

    return SymbolLayerProperties(
      iconImage: _poiIconImage(),
      iconSize: _poiIconSize(),
      iconColor: '#ffffff',
      iconHaloColor: '#ffffff',
      iconHaloWidth: 0.0,
      iconHaloBlur: 0.0,
      iconAllowOverlap: true,
      iconAnchor: 'center',
      // Прослушанные точки — приглушенная иконка (1b).
      iconOpacity: buildPoiIconOpacityExpression(),
    );
  }


  /// Цвет шарика-подложки POI.
  ///
  /// Избранные точки (свойство `isFavorite`) рисуются сигнальным оранжевым
  /// цветом звезды избранного, остальные — стандартным или
  /// выделенным через [MapWidget.highlightPoiId].
  dynamic _poiBallColor() {
    return buildPoiBallColorExpression(_poiIconColor());
  }

  /// Цвет обводки шарика POI: у избранных — глубокий терракот
  /// (сигнальная кайма, как у залитой звезды избранного),
  /// у остальных — белая.
  dynamic _poiBallStrokeColor() {

    return [
      'case',
      ['get', 'isFavorite'],
      _poiFavoriteRingColor,
      '#ffffff',
    ];
  }

  /// Полный набор свойств слоя цветных шариков-подложек POI.
  ///
  /// Шарик — заливка цветом категории (выделенная — сигнальная,
  /// избранная — сигнальная) с белой/терракотовой обводкой. Иконка
  /// (белый силуэт) рисуется поверх в центре шарика, поэтому
  /// сам маркер читается как «цветной кружок с белой пиктограммой»
  /// и не теряется на карте любого фона.
  CircleLayerProperties _poiBallLayerProperties() {

    return CircleLayerProperties(
      circleColor: _poiBallColor(),
      circleRadius: _poiBallRadius(),
      circleStrokeColor: _poiBallStrokeColor(),
      circleStrokeWidth: 2.0,
      circleOpacity: 1.0,
    );
  }

  /// Радиус сигнального ободка избранного POI.
  ///
  /// Чуть больше шарика-подложки, чтобы ободок читался как кайма
  /// вокруг маркера. Скалится по зуму вместе с шариком, чтобы
  /// зазор оставался постоянным на любом масштабе.
  dynamic _poiFavoriteRingRadius() {

    final factor = _poiScaleFactor;

    return _zoomScaled(
      (_poiDefaultBallRadius + 5) * factor,
      highlightValue: (_poiHighlightBallRadius + 5) * factor,
    );
  }

  /// Полный набор свойств слоя сигнального ободка избранных POI.
  ///
  /// Прозрачный круг с терракотовой обводкой, рисуется ПОВЕРХ шарика
  /// (но под иконкой), чтобы не перекрывать белую пиктограмму.
  CircleLayerProperties _poiFavoriteRingLayerProperties() {

    return CircleLayerProperties(
      circleColor: '#00000000',
      circleRadius: _poiFavoriteRingRadius(),
      circleStrokeColor: _poiFavoriteRingColor,
      circleStrokeWidth: 2.0,
      circleOpacity: 1.0,
    );
  }


  /// Полный набор свойств слоя `trail-lines`.
  ///
  /// Нужен и при СОЗДАНИИ слоя (map_overlays), и при перекраске
  /// подсветки (map_camera): `setLayerProperties` у maplibre_gl
  /// стирает непереданные свойства (lineCap/lineJoin → null),
  /// поэтому набор обязан быть полным в обоих местах. Раньше
  /// два списка были скопированы — правка одного расходилась с другим.
  LineLayerProperties _trailLineLayerProperties() {

    return LineLayerProperties(
      lineColor: _trailLineColor(),
      lineWidth: _trailLineWidth(),
      lineOpacity: 0.95,
      lineCap: 'round',
      lineJoin: 'round',
    );
  }

  /// Цвет линии маршрутов на карте.
  ///
  /// Если задан [MapWidget.highlightTrailId] — выбранный
  /// маршрут красится ярким цветом, а все остальные —
  /// приглушённым. Иначе каждый маршрут получает свой цвет
  /// из [_trailPalette], чтобы накладывающиеся маршруты
  /// оставались различимыми.
  dynamic _trailLineColor() {
    final highlightId = widget.highlightTrailId;

    if (highlightId != null && highlightId.isNotEmpty) {

      return [
        'match',
        ['get', 'trailId'],
        highlightId,
        _trailHighlightColor,
        _trailMutedColor,
      ];
    }

    if (_trails.isEmpty) {

      return _trailDefaultColor;
    }

    // В режиме «все регионы» исходные id маршрутов повторяются в
    // разных локациях (например `trail-01` в gemiler и antalya),
    // поэтому ветви match-выражения делаем уникальными
    // (`локация/маршрут`) и читаем их из составного `id` фичи.
    // В обычном режиме ветви — исходные id из `trailId`.
    final getKey = _showAllRegions ? 'id' : 'trailId';

    // Индекс локации берем из параллельного списка по i — indexOf
    // внутри цикла давал O(n²) на каждое построение выражения.
    String keyAt(int i) => _showAllRegions
        ? '${_trailLocations[i]}/${_trails[i].id}'
        : _trails[i].id;

    final args = <dynamic>[
      'match',
      ['get', getKey],
    ];

    for (var i = 0; i < _trails.length; i++) {

      args.add(keyAt(i));
      args.add(_trailPalette[i % _trailPalette.length]);
    }

    args.add(_trailDefaultColor);

    return args;
  }


  /// Толщина линии маршрута, zoom-зависимая (как у дорог в стиле):
  /// на отдалении линии тонкие, при приближении — толще.
  dynamic _trailLineWidth() {

    return [
      'interpolate', ['linear'], ['zoom'],
      10, 0.75,
      14, 1.5,
      18, 2.5,
    ];
  }


  /// Толщина белой подложки (casing) под линией маршрута.
  dynamic _trailCasingWidth() {

    return [
      'interpolate', ['linear'], ['zoom'],
      10, 2.0,
      14, 3.5,
      18, 5.0,
    ];
  }


  // ------------------------------------------------------------------
  //  Кластеризация (только в режиме «все регионы»)
  // ------------------------------------------------------------------

  /// Радиус кластерного кружка — 3 шага по числу объектов
  /// (B4.4, 8-й проход): ≤10 — маленький, ≤50 — средний, дальше —
  /// крупный (см. _poiClusterLayerProperties). При zoom ≥
  /// clusterMaxZoom кластеры уже не видны, интерполяция не нужна.

  /// Цвет кластерного кружка — тот же морской синий, что и шарики
  /// POI; кластер от точки отличает белая обводка и число внутри.
  static const String _clusterCircleColor = '#1668A8';

  /// Свойства слоя кластерных кружков: размер по числу точек
  /// (3 шага, B4.4).
  CircleLayerProperties _poiClusterLayerProperties() {
    return const CircleLayerProperties(
      circleColor: _clusterCircleColor,
      circleRadius: [
        'step', ['get', 'point_count'],
        16,
        11, 20,
        51, 26,
      ],
      circleStrokeColor: '#ffffff',
      circleStrokeWidth: 2.0,
      circleOpacity: 1.0,
    );
  }

  /// Свойства слоя текста с числом объектов в кластере:
  /// 12 px bold (B4.4).
  SymbolLayerProperties _poiClusterCountProperties() {
    return const SymbolLayerProperties(
      textField: ['get', 'point_count_abbreviated'],
      textFont: ['NotoSans'],
      textSize: 12,
      textColor: '#ffffff',
      textAnchor: 'center',
      textAllowOverlap: true,
      iconAllowOverlap: true,
      iconAnchor: 'center',
    );
  }
}
