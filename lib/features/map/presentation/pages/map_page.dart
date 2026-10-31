import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../app/theme.dart';
import '../../../../features/weather/models/weather.dart';
import '../../../../features/weather/providers/weather_providers.dart';
import '../widgets/weather_chip.dart';
import '../widgets/weather_sheet.dart';
import '../../../../app/overlay_tracker.dart';
import '../../../../app/router.dart' show AppRouter;
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/floating_pill.dart';
import '../../../../core/widgets/glass_icon_button.dart';
import '../../../../core/widgets/hiking_forbidden_notice.dart';
import '../../../../features/audio/providers/auto_audio_provider.dart';
import '../../../../features/audio/utils/auto_guide_decision.dart';
import '../../../../features/audio/providers/audio_player_provider.dart';
import '../../../../features/content/providers/content_providers.dart';
import '../../../../features/poi/utils/poi_category.dart';
import '../../../../features/poi/models/poi.dart';
import '../../../../features/settings/providers/settings_providers.dart';
import '../../../navigation/presentation/tree_navigation_button.dart';
import '../../../qr/qr_scan_page.dart';
import '../../../home/presentation/widgets/scrollable_chip_rail.dart';
import '../../../navigation/presentation/tree_navigation_sheet.dart';
import '../widgets/map_controls_hover_lock.dart';
import '../widgets/track_record_button.dart';
import '../widgets/nearby_suggest_pill.dart';
import '../../services/map_input_lock.dart';
import '../widgets/map_widget.dart';


/// Страница офлайн-карты.
///
/// Поддерживает необязательные query-параметры для
/// центрирования карты на объекте:
/// `#/map?lat=43.01&lng=131.9&zoom=14&island=gemiler`.
/// Параметр `trail` выделяет конкретный маршрут цветом
/// и подводит к нему камеру, параметр `poi` — выделяет
/// точку интереса (сигнальный маркер + ореол + пульс).
///
/// Слои плавающих контролов не перекрываются:
///   правый верх  — «дерево» (top:14, right:16) и легенда
///                  (top:70, right:16) под ним;
///   левый верх   — чип ближайшего POI (внутри MapWidget,
///                  left:12, top:12) и баннер запрета ниже него
///                  (top:64, right:132 — не заходит под правый кластер);
///   правый низ   — колонка зума/GPS (внутри MapWidget) — над
///                  парящей капсулой навигации;
///   левый низ    — карточка навигации по маршруту (внутри MapWidget).
///
/// Кнопки «домой» на карте нет: вкладка «Главная» парящей
/// капсулы всегда доступна (рекомендация второго прохода —
/// не дублировать управление).
class MapPage extends ConsumerStatefulWidget {
  const MapPage({
    super.key,
    this.lat,
    this.lng,
    this.zoom,
    this.islandId,
    this.highlightTrailId,
    this.highlightPoiId,
    this.openSearch = false,
  });

  final double? lat;
  final double? lng;
  final double? zoom;
  final String? islandId;
  final String? highlightTrailId;
  final String? highlightPoiId;

  /// Открыть страницу с уже раскрытой строкой поиска
  /// (вкладка «Поиск» в навигации).
  final bool openSearch;

  CameraPosition? get _initialCamera {
    if (lat == null || lng == null) return null;
    return CameraPosition(target: LatLng(lat!, lng!), zoom: zoom ?? 14);
  }

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  /// Шторка поиска, открытая через вкладку «Поиск» (адрес
  /// /map?search=1). Пока она открыта, уход с адреса
  /// (тап по вкладке «Карта») закрывает её (P0-1, 6-й проход).
  bool _searchSheetOpen = false;

  /// Предложение «Рядом: <точка>. Слушать?» (B5.4): появляется,
  /// когда автогид в режиме «Предлагать» и какой-то трек уже
  /// играет вручную. 10 секунд — и тихо исчезает.
  PoiEntryEvent? _suggestedEntry;

  /// Фильтр категорий POI на карте (1c, 12-й проход): `null` —
  /// «Все».
  String? _categoryFilter;

  /// Лента категорий развёрнута (14-й проход: по умолчанию
  /// фильтр свёрнут в одну кнопку внизу слева).
  bool _categoryRailOpen = false;

  Timer? _suggestionTimer;

  @override
  void initState() {
    super.initState();

    // Повторный тап по уже активной вкладке «Поиск»: адрес
    // /map?search=1 может остаться при закрытой шторке (возврат
    // из деталей POI) — шелл инкрементирует счётчик, шторка
    // открывается заново.
    searchSheetRequest.addListener(_onSearchSheetRetap);

    // Deep link /map?search=1: шторка с фокусом на поиске сразу.
    if (widget.openSearch) {
      _openSearchSheet();
    }
  }

  /// Шторка прогноза погоды (П7, 21-й проход): полный срез
  /// данных Open-Meteo — контент в [WeatherSheet].
  Future<void> _showWeatherSheet(
    BuildContext context,
    LocationWeather weather,
  ) {
    acquireMapInputLock();

    return showAppBottomSheet(
      context,
      title: 'Погода на побережье',
      maxHeightFactor: 0.75,
      builder: (sheetContext) =>
          WeatherSheet(weather: weather),
    ).whenComplete(releaseMapInputLock);
  }

  /// Категории POI локации для фильтра, по русскому названию (1c).
  List<String> _sortedCategories(List<Poi> pois) {
    final categories = <String>{};

    for (final poi in pois) {
      final category = poi.category;

      if (category != null && category.isNotEmpty) {
        categories.add(category);
      }
    }

    final sorted = categories.toList()
      ..sort((a, b) => poiCategoryLabel(a).compareTo(poiCategoryLabel(b)));

    return sorted;
  }

  /// Показывает пилюлю «Рядом: …» на 10 секунд (B5.4).
  void _showSuggestion(PoiEntryEvent entry) {
    _suggestionTimer?.cancel();

    setState(() {
      _suggestedEntry = entry;
    });

    _suggestionTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;

      setState(() {
        _suggestedEntry = null;
      });
    });
  }

  /// Тап по «Слушать?» — запуск предложенного трека.
  void _acceptSuggestion() {
    final entry = _suggestedEntry;

    if (entry == null) {
      return;
    }

    _suggestionTimer?.cancel();

    setState(() {
      _suggestedEntry = null;
    });

    playPoiAudio(
      ref,
      poi: entry.poi,
      islandId: entry.islandId,
    );
  }

  @override
  void dispose() {
    _suggestionTimer?.cancel();

    searchSheetRequest.removeListener(_onSearchSheetRetap);

    super.dispose();
  }

  void _onSearchSheetRetap() {
    if (!mounted || _searchSheetOpen) {
      return;
    }

    // Другая модальная шторка уже открыта — не наслаиваем
    // вторую поверх.
    if (modalSheetOpenCount.value > 0) {
      return;
    }

    _openSearchSheet();
  }

  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Поиск поверх ЖИВОЙ карты: /map → /map?search=1 не меняет
    // pageKey, MapPage переиспользуется — открываем шторку
    // реагируя на параметр, без пересоздания карты и камеры
    // (P0-7, 5-й проход).
    if (!oldWidget.openSearch && widget.openSearch) {
      _openSearchSheet();

      return;
    }

    // Уход с адреса /map?search=1 при открытой шторке (тап по
    // вкладке «Карта») — закрываем шторку, она больше не нужна.
    if (oldWidget.openSearch && !widget.openSearch && _searchSheetOpen) {
      Navigator.of(context).pop();
    }
  }

  /// Шторку открываем ПОСЛЕ кадра: в момент build/showModal
  // контекст навигатора ветви ещё не готов. Когда шторка,
  // открытая из вкладки «Поиск», закрывается — адрес
  // возвращается к обычному /map без search=1, иначе
  // подсвечена вкладка «Поиск», и повторный тап по ней
  // не срабатывает (P0-1, 6-й проход).
  void _openSearchSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      _searchSheetOpen = true;

      try {
        await showTreeNavigationSheet(context, focusSearch: true);
      } finally {
        _searchSheetOpen = false;
      }

      if (mounted) {
        _clearSearchFromAddress();
      }
    });
  }

  /// Убирает `search=1` из адреса /map, сохраняя остальные
  /// query-параметры (island, poi, trail, lat, lng, zoom).
  /// Не трогает адрес, если пользователь уже ушёл из карты
  /// (переход из результатов поиска — тогда наверху /poi/…).
  void _clearSearchFromAddress() {
    final uri = AppRouter.router.routerDelegate.currentConfiguration.uri;

    if (uri.path != '/map' || uri.queryParameters['search'] != '1') {
      return;
    }

    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('search');

    final target = Uri(
      path: '/map',
      queryParameters: query.isEmpty ? null : query,
    );

    context.go(target.toString());
  }

  @override
  Widget build(BuildContext context) {
    // Автозапуск голосового гида при входе в радиус POI.
    //
    // Слушатель живёт на экране карты, а не в корне приложения:
    // poiEntryProvider — autoDispose, GPS-поток и запрос разрешения
    // геолокации работают только пока открыта карта (осознанное
    // действие), и останавливаются при уходе с неё.
    // A7: смена локации — фильтр категорий прежней локации
    // не должен опустошать карту новой.
    ref.listen(currentIslandIdProvider, (previous, next) {
      if (previous != next && _categoryFilter != null) {
        setState(() {
          _categoryFilter = null;
        });
      }
    });

    ref.listen(poiEntryProvider, (previous, next) {
      final entry = next.value;

      if (entry == null) {
        return;
      }

      // Режимы автогида (B5.4 + A5): выключен — тишина; «Всегда» —
      // автозапуск; «Предлагать» — не перебивать трек, запущенный
      // вручную: пилюля на 10 секунд. Точка, которую уже слушают,
      // не предлагается (A5).
      final service = ref.read(audioPlayerServiceProvider);

      final decision = decideAutoGuide(
        mode: ref.read(autoGuideModeProvider),
        isPlaying: service.isPlaying,
        currentFile: service.currentFile,
        // Точка без аудио — предложить нечего (A5).
        suggestedFile: entry.poi.audioPath == null
            ? null
            : entry.poi.audioAssetPath(entry.islandId),
      );

      switch (decision) {
        case AutoGuideDecision.play:
          playPoiAudio(
            ref,
            poi: entry.poi,
            islandId: entry.islandId,
          );

        case AutoGuideDecision.suggest:
          _showSuggestion(entry);

        case AutoGuideDecision.ignore:
          return;
      }
    });

    final manifestAsync = ref.watch(islandContentProvider);
    final showBan = manifestAsync.value?.hikingForbidden == true;
    final trailNotice = manifestAsync.value?.trailNotice;

    // Погода текущей локации (П7, 12-й проход):
    // онлайн-обогащение — нет сети, чипа нет.
    final weather = ref.watch(locationWeatherProvider).value;

    // Категории для фильтра (1c): из POI ТЕКУЩЕЙ локации —
    // основное ядро категорий во всех регионах совпадает.
    final filterIslandId = ref.watch(currentIslandIdProvider);

    final filterPois = ref.watch(poisFamily(filterIslandId)).value;

    final hasHighlight =
        widget.highlightPoiId != null || widget.highlightTrailId != null;

    final filterItems = <ChipRailItem>[
      if (filterPois != null && filterPois.isNotEmpty) ...[
        (
          id: 'all',
          label: 'Все',
        ),
        for (final category in _sortedCategories(filterPois))
          (
            id: category,
            label: poiCategoryLabel(category),
          ),
      ],
    ];

    // A7: выбранная категория исчезла из локации (например,
    // «маяк» был на Гемилере) — тихо возвращаем «Все», иначе
    // карта пуста, а активного чипа в ленте нет.
    if (_categoryFilter != null &&
        filterItems.isNotEmpty &&
        !filterItems.any((item) => item.id == _categoryFilter)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _categoryFilter != null) {
          setState(() {
            _categoryFilter = null;
          });
        }
      });
    }

    // Узкий экран: пилюля «Рядом» разворачивается во всю ширину
    // ПОД правым верхним кластером (дерево+легенда до ~114 px) —
    // с боковым обрезом right:132 заголовку оставалось ~60 px
    // (A5, 9-й проход).
    final isNarrow = MediaQuery.sizeOf(context).width < 420;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: MapWidget(
                initialCameraPosition: widget._initialCamera,
                islandId: widget.islandId,
                highlightTrailId: widget.highlightTrailId,
                highlightPoiId: widget.highlightPoiId,
                // Пилюля «К описанию» расширяет правый верхний
                // кластер до ~187 px от правой кромки — компас
                // (right:76, top:14) пересекался с ней. Колонка
                // компас+атрибуция уходит ниже пилюли (P0-6).
                controlsTopShift:
                    widget.highlightPoiId != null ||
                            widget.highlightTrailId != null
                        ? 52
                        : 0,
                showAllRegions:
                    widget.highlightTrailId == null &&
                    widget.highlightPoiId == null &&
                    widget.lat == null &&
                    widget.lng == null,
                categoryFilter: _categoryFilter,
                // A2 (18-й проход): содержимое верхнего левого угла
                // (погода → баннер запрета → «Рядом») строится В
                // ОДНОЙ колонке MapWidget с плашкой статуса и чипом
                // ближайшей точки — пересечения исключены
                // конструктивно.
                topLeftControls:
                    weather != null || showBan || _suggestedEntry != null
                        ? Column(
                            key: const ValueKey('map-top-left-column'),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Чип погоды (П7): тап — шторка прогноза.
                              if (weather != null)
                                KeyedSubtree(
                                  key: const ValueKey('map-weather-chip'),
                                  child: WeatherChip(
                                    weather: weather,
                                    narrow: isNarrow,
                                    onTap: () =>
                                        _showWeatherSheet(context, weather),
                                  ),
                                ),

                              // Баннер запрета (Кекова).
                              if (showBan) ...[
                                if (weather != null)
                                  const SizedBox(height: 8),
                                KeyedSubtree(
                                  key: const ValueKey('map-ban-banner'),
                                  child:
                                      HikingForbiddenNotice(
                                        notice: trailNotice,
                                        compact: true,
                                        floating: true,
                                      ),
                                ),
                              ],

                              // Пилюля «Рядом: <точка>. Слушать?»
                              // (B5.4): автогид в режиме «Предлагать» не
                              // перебивает играющий вручную трек.
                              if (_suggestedEntry != null) ...[
                                if (weather != null || showBan)
                                  const SizedBox(height: 8),
                                NearbySuggestPill(
                                  key: const ValueKey('map-suggest-pill'),
                                  title: _suggestedEntry!.poi.title,
                                  narrow: isNarrow,
                                  onListen: _acceptSuggestion,
                                  onDismiss: () => setState(() {
                                    _suggestedEntry = null;
                                  }),
                                ),
                              ],
                            ],
                          )
                        : null,
                // B1: слот левого нижнего угла (фильтр категорий) —
                // MapWidget рисует его колонкой ПОД карточкой
                // навигации: конфликт за bottom-left исключён.
                bottomLeftControls:
                    // Тумблер показываем ВСЕГДА на полной карте: пока
                    // POI локации грузятся (холодный сидинг) чипов ещё
                    // нет, но кнопка фильтра должна быть на месте —
                    // иначе при входе с разных экранов она «то есть,
                    // то нет». Скрыта только при подсветке (?poi=/?trail=).
                    !hasHighlight
                        ? MapControlsHoverLock(
                            child: Row(
                              key: const ValueKey('map-category-rail'),
                              children: [
                                // Кнопка-тумблер: стеклянная, 44, с
                                // точкой-индикатором фильтра.
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Stack(
                                    children: [
                                      GlassIconButton(
                                        key: const ValueKey(
                                          'map-filter-toggle',
                                        ),
                                        tooltip: _categoryRailOpen
                                            ? 'Скрыть категории'
                                            : 'Категории точек',
                                        icon: LucideIcons.slidersHorizontal,
                                        onTap: () => setState(() {
                                          _categoryRailOpen =
                                              !_categoryRailOpen;
                                        }),
                                      ),
                                      if (_categoryFilter != null)
                                        Positioned(
                                          right: 9,
                                          top: 9,
                                          child: Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: AppColors.signal,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: AppColors.surfaceRaised,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // П5 (29-й проход): запись своего трека
                                // в GPX — рядом с фильтром категорий.
                                const SizedBox(width: 8),
                                const TrackRecordButton(),
                                // Чипы — только когда категории локации
                                // уже загружены; до этого одна кнопка.
                                if (filterItems.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                // Лента чипов: выезжает слева от
                                // кнопки; закрытая — за краем
                                // экрана и не ловит тапы.
                                // ClipRect: AnimatedSlide (Transform)
                                // НЕ клипует контент — без клипа
                                // свёрнутые чипы рендерились
                                // СЛЕВА от кнопки (артефакт).
                                Expanded(
                                  child: ClipRect(
                                    child: AnimatedSlide(
                                      offset: _categoryRailOpen
                                          ? Offset.zero
                                          : const Offset(-1, 0),
                                      duration: AppMotion.normal,
                                      curve: AppMotion.curve,
                                      child: IgnorePointer(
                                        ignoring: !_categoryRailOpen,
                                        child: ScrollableChipRail(
                                          items: filterItems,
                                          activeId: _categoryFilter ?? 'all',
                                          onSelect: (id) {
                                            setState(() {
                                              _categoryFilter =
                                                  id == 'all' ? null : id;

                                              // Выбрали — сворачиваем:
                                              // карта важнее ленты.
                                              _categoryRailOpen = false;
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                ],
                              ],
                            ),
                          )
                        : null,
              ),
            ),

            // Правый верхний кластер: «к описанию» (на карте,
            // открытой из деталей POI/маршрута) + «дерево».
            Positioned(
              top: 14,
              right: 16,
              child: MapControlsHoverLock(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Возврат к описанию: карта открыта с ?poi=/
                    // ?trail= — стек деталей сброшен, эта пилюля —
                    // единственный путь назад (A7).
                    if (widget.highlightPoiId != null ||
                        widget.highlightTrailId != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _BackToDescriptionPill(
                          onTap: () {
                            final islandId = widget.islandId ??
                                ref.read(currentIslandIdProvider);

                            if (widget.highlightPoiId != null) {
                              context.push(
                                '/poi/${widget.highlightPoiId}'
                                '?island=$islandId',
                              );
                            } else if (widget.highlightTrailId != null) {
                              context.push(
                                '/trail/${widget.highlightTrailId}'
                                '?island=$islandId',
                              );
                            }
                          },
                        ),
                      ),
                    // 29-й проход, П1: сканер QR-кодов точек —
                    // стикеры на объектах открывают страницу POI.
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GlassIconButton(
                        key: const ValueKey('qr-scan-button'),
                        icon: LucideIcons.qrCode,
                        tooltip: 'Сканировать QR точки',
                        onTap: () => showQrScanner(context),
                      ),
                    ),
                    const TreeNavigationButton(),
                  ],
                ),
              ),
            ),

            const Positioned(
              top: 70,
              right: 16,
              child: _LegendButton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка легенды карты — в правом верхнем кластере,
/// под кнопкой «дерева навигации».
class _LegendButton extends StatelessWidget {
  const _LegendButton();

  @override
  Widget build(BuildContext context) {
    return MapControlsHoverLock(
      child: GlassIconButton(
        icon: LucideIcons.layers,
        onTap: () => _showLegend(context),
        tooltip: 'Легенда',
      ),
    );
  }

  Future<void> _showLegend(BuildContext context) async {
    // Шторка блокирует жесты карты, как шторки POI/маршрута:
    // на web канвас иначе ловит панорамирование под шторкой.
    acquireMapInputLock();

    // B2 (10-й проход): каркас — единый AppBottomSheet; он сам
    // регистрирует шторку в modalSheetOpenCount (пилюля
    // мини-плеера) и рисует ручку/шапку/радиус.
    try {
      await showAppBottomSheet(
        context,
        title: 'Легенда карты',
        builder: (context) => const _LegendSheetBody(),
      );
    } finally {
      releaseMapInputLock();
    }
  }
}

/// Шторка с легендой условных знаков карты.
///
/// Ограничена по высоте (≈ 0.85 экрана) и прокручивается:
/// на маленьких экранах / в ландшафте / при крупном шрифте
/// статичная колонка раньше переполнялась и уходила под
/// жест-бар.
/// Тело шторки легенды (каркас — AppBottomSheet, B2 10-й проход).
class _LegendSheetBody extends StatelessWidget {
  const _LegendSheetBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _LegendItem(
          color: AppColors.mapPoi,
          label: 'Достопримечательность',
        ),
        const _LegendItem(
          color: AppColors.signal,
          label: 'Избранное / выделение',
        ),
        const _LegendClusterItem(label: 'Кластер точек (с числом)'),
        const _LegendItem(
          color: AppColors.mapTrail,
          label: 'Маршрут',
        ),
        const _LegendItem(
          color: AppColors.mapTrailMuted,
          label: 'Неактивный маршрут',
        ),
        // Маркер «Вы здесь» — ОБРАЗЦАМИ (D6, замечание Sonnet):
        // три состояния свежести читаются картинками, а не
        // одной строкой про цвет.
        const _LegendSampleItem(
          label: 'Вы здесь — свежий фикс (круг — точность GPS)',
          fresh: true,
        ),
        const _LegendSampleItem(
          label: 'Фикс устарел (20+ с) — точка тускнеет',
          fresh: false,
        ),
        const _LegendLostItem(
          label: 'Сигнал потерян (30+ с) — плашка на карте, '
              'точка на месте',
        ),
        const _LegendPulseItem(label: 'Выделенная точка (пульс)'),
        const _LegendItem(
          // Прослушанные маркеры приглушены (1b, 12-й проход) —
          // цвет слоя _poiListenedColor в map_layers.dart.
          color: Color(0xFFCFC7B2),
          label: 'Прослушанная точка (приглушена)',
        ),
        const SizedBox(height: AppSpace.s),
        Text('Категории точек:', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpace.s),
        // Чипы показывают те же глифы, что и маркеры — из
        // единой таблицы категорий (poi_category.dart),
        // плоские копии SDF-иконок.
        Wrap(
          spacing: AppSpace.s,
          runSpacing: AppSpace.xs,
          children: [
            for (final id in const [
              'beach',
              'lighthouse',
              'viewpoint',
              'church',
              'fort',
              'cape',
              'anchor',
              'park',
            ])
              _CategoryChip(
                label: poiCategoryLabel(id),
                asset: poiCategoryGlyph(id),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.m),
        const _LegendItem(
          color: AppColors.mapPoi,
          label: 'Прочие категории (бухта, остров, пещера, руины, город '
              'и др.) — маркер-булавка',
          glyph: 'assets/map_icons_flat/map-pin.png',
        ),
        const SizedBox(height: AppSpace.m),
        // Лицензия OSM требует видимой атрибуции (P0-3):
        // строка дублирует кнопку атрибуции карты.
        Text(
          '© участники OpenStreetMap',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.of(context).onSurfaceMuted,
          ),
        ),
        const SizedBox(height: AppSpace.m),
      ],
    );
  }
}

/// Общий каркас строки легенды: ведущая колонка 24×24 + подпись.
///
/// Единая ширина ведущей колонки — подписи всех пунктов начинаются
/// на одной вертикали (раньше точки 16px и образцы 24px давали
/// рваный левый край).
class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.leading, required this.label});

  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: leading)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.glyph,
  });

  final Color color;
  final String label;

  /// Белый глиф поверх цветного шарика (плоская копия SDF-иконки).
  final String? glyph;

  @override
  Widget build(BuildContext context) {
    return _LegendRow(
      leading: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: glyph == null
            ? null
            : Padding(
                padding: const EdgeInsets.all(2),
                child: Image.asset(glyph!),
              ),
      ),
      label: label,
    );
  }
}

/// Кластер точек: образец повторяет слой карты — синий круг с белым
/// кольцом и числом внутри (раньше был обычный шарик и терялся
/// среди синих пунктов легенды).
class _LegendClusterItem extends StatelessWidget {
  const _LegendClusterItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _LegendRow(
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.mapPoi,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accentOn, width: 2),
        ),
        child: Center(
          child: Text(
            '3',
            style: AppText.meta.copyWith(color: AppColors.accentOn),
          ),
        ),
      ),
      label: label,
    );
  }
}

/// Выделенная точка: образец с «пульсом» — сигнальный шарик и
/// расходящееся кольцо (отличим от простого «Избранное/выделение»).
class _LegendPulseItem extends StatelessWidget {
  const _LegendPulseItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _LegendRow(
      leading: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.signal.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppColors.signal,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
      label: label,
    );
  }
}

/// Пункт легенды с ОБРАЗЦОМ маркера «Вы здесь» (D6): точка с
/// белым кольцом и кругом точности — как слои user-position-*;
/// тусклый вариант показывает состояние «фикс устарел».
class _LegendSampleItem extends StatelessWidget {
  const _LegendSampleItem({
    required this.label,
    required this.fresh,
  });

  final String label;

  /// Свежий (яркий) или устаревший (тусклый) фикс.
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final dotColor = AppColors.mapUser.withValues(alpha: fresh ? 1 : 0.45);

    final ringColor = palette.surfaceRaised;

    return _LegendRow(
      // Круг точности + точка с белым кольцом — миниатюра
      // слоёв карты.
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.mapUser.withValues(
            alpha: fresh ? 0.22 : 0.1,
          ),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: ringColor,
                width: 2,
              ),
            ),
          ),
        ),
      ),
      label: label,
    );
  }
}

/// Пункт легенды «сигнал потерян» (D6): образец — приглушённая
/// точка со значком потери.
class _LegendLostItem extends StatelessWidget {
  const _LegendLostItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _LegendRow(
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.mapUser.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            LucideIcons.wifiOff,
            size: 13,
            color: palette.onSurfaceMuted,
          ),
        ),
      ),
      label: label,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.asset});

  final String label;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      // Тёмный шарик с белым глифом — как маркер на карте.
      avatar: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: AppColors.mapPoi,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Image.asset(asset),
        ),
      ),
      backgroundColor: AppPalette.of(context).sandLight,
      side: BorderSide(
          color: AppPalette.of(context).sand, width: 1),
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

/// Компактная пилюля «← К описанию» в правом верхнем кластере
/// карты: возврат на страницу POI/маршрута, с которой карта
/// была открыта (A7).
class _BackToDescriptionPill extends StatelessWidget {
  const _BackToDescriptionPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // D2: каркас — единый FloatingPill с заливкой бирюзы
    // (кнопка-акцент возврата на страницу описания).
    return PointerInterceptor(
      child: FloatingPill(
        tone: FloatingPillTone.info,
        background: palette.info,
        onTap: onTap,
        semanticsLabel: 'К описанию',
        tooltip: 'К описанию',
        padding: const EdgeInsets.symmetric(horizontal: 13),
        leading: Icon(
          LucideIcons.chevronLeft,
          size: 15,
          color: palette.accentOn,
        ),
        gap: 3,
        child: Text(
          'К описанию',
          style: AppText.caption.copyWith(
            color: palette.accentOn,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// Плавающий баннер запрета пеших маршрутов на карте: компактный
