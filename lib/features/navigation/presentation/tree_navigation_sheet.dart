import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/overlay_tracker.dart';
import '../../../app/navigation/navigation_shell.dart';
import '../../../app/theme.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../content/models/manifest.dart';
import '../../content/models/region_catalog.dart';
import '../../content/providers/content_providers.dart';
import '../../gps/providers/location_providers.dart';
import '../../gps/services/location_service.dart';
import '../../map/services/map_input_lock.dart';
import '../../poi/models/poi.dart';
import '../../poi/utils/poi_category.dart';
import '../../poi/utils/poi_sort.dart';
import '../../search/models/search_index_entry.dart';
import '../../search/providers/search_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../../trails/models/trail.dart';
import '../../trails/utils/format_distance.dart';

import '../../../core/utils/capitalize.dart';
import '../models/search_filtering.dart';


/// Цвета плашек иконок уровней дерева: единая точка вместо
/// восьми копий `Color.lerp` по файлу. Считаются ОТ ПАЛИТРЫ
/// (D3): ночная тема получает свои плашки, не бумажные.
Color _treeBoxAegean(AppPalette palette) =>
    Color.lerp(palette.sandLight, palette.info, 0.14)!;

Color _treeBoxOlive(AppPalette palette) =>
    Color.lerp(palette.sandLight, AppColors.shoal, 0.18)!;

Color _treeBoxAmber(AppPalette palette) =>
    Color.lerp(palette.sandLight, palette.accent, 0.18)!;

Color _treeBoxStone(AppPalette palette) =>
    Color.lerp(palette.sandLight, palette.onSurface, 0.16)!;


/// Фильтр результатов поиска (B6.3): Всё / Места / Маршруты /
/// Локации.
enum SearchResultFilter { all, places, trails, locations }

/// Позиция пользователя для результатов поиска (B6.2, 8-й
/// проход; A5, 11-й): последняя известная позиция из
/// [LocationService.lastKnownPosition] — синхронно и БЕЗ
/// запроса датчика. Раньше каждое открытие поиска будило GPS
/// разовым currentPosition() (до 15 с таймаута) ради подписи
/// «~2 км». Нет свежей позиции — дистанции просто не
/// показываются, датчик не трогается.
final _searchUserPositionProvider =
    Provider.autoDispose<({double latitude, double longitude})?>((ref) {
  final position = ref.watch(locationServiceProvider).lastKnownPosition;

  if (position == null) {
    return null;
  }

  return (latitude: position.latitude, longitude: position.longitude);
});

/// Открывает нижнюю панель «Навигация по проекту» с деревом
/// регионов, локаций, маршрутов и достопримечательностей.
///
/// На время показа шторки жёсты карты блокируются (на web канвас
/// maplibre получает события напрямую из DOM) — паттерн
/// `map_taps.dart`.
Future<void> showTreeNavigationSheet(
  BuildContext context, {
  bool focusSearch = false,
}) async {

  acquireMapInputLock();

  // Мини-плеер прячет пилюлю на время модальной шторки.
  modalSheetOpenCount.value++;

  try {

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AppTheme.sheetAnimationStyle,
      builder: (context) => _TreeNavigationSheet(focusSearch: focusSearch),
    );

  } finally {

    releaseMapInputLock();

    modalSheetOpenCount.value--;
  }
}


/// Нижняя панель с деревом каталога проекта.
///
/// Структура берётся из статического каталога [kRegions], названия
/// регионов и локаций — из манифестов, тяжёлый контент локации
/// (маршруты и POI) грузится лениво при раскрытии узла.
///
/// A6 (10-й проход): по умолчанию раскрыты только текущий регион
/// и текущая локация. Раньше панель разворачивала весь каталог —
/// и первое же открытие дерева на native запускало холодный
/// сидинг всех 9 пакетов (bay — 122 КБ). Остальные узлы
/// раскрываются тапом, их контент грузится лениво.
class _TreeNavigationSheet extends ConsumerStatefulWidget {

  const _TreeNavigationSheet({this.focusSearch = false});

  /// Автофокус на строке поиска при открытии
  /// (вкладка «Поиск» в навигации).
  final bool focusSearch;


  @override
  ConsumerState<_TreeNavigationSheet> createState() =>
      _TreeNavigationSheetState();
}


class _TreeNavigationSheetState extends ConsumerState<_TreeNavigationSheet> {

  /// Ключи свёрнутых узлов: строка пути `region[/location[/trail]]` /
  /// `region/location/off` / `region:<id>`.
  ///
  /// По умолчанию свёрнуто ВСЁ: ни регионы, ни локации не раскрыты
  /// (замечание владельца, 11.2026). Раскрытый узел подписывается
  /// на контентные провайдеры своей локации — полностью раскрытое
  /// дерево будило холодный сидинг всех 9 пакетов на native.
  late final Set<String> _collapsed = _defaultCollapsed();

  /// Контроллер поля поиска. Пока в поле введён текст — вместо дерева
  /// показываются плоские результаты поиска.
  final TextEditingController _searchController = TextEditingController();

  /// Дебаунс поиска (P1-4): первый введённый символ больше не
  /// запускает загрузку и сидинг всех локаций — результаты
  /// строятся через 200 мс после того, как ввод замер.
  Timer? _searchDebounce;

  /// Запрос, по которому построены видимые результаты (после
  /// дебаунса).
  String _debouncedQuery = '';

  /// Фильтр групп результатов (B6.3).
  SearchResultFilter _resultFilter = SearchResultFilter.all;


  String get _query => _searchController.text.trim();

  /// Начальное состояние: свёрнуты все регионы и все локации —
  /// дерево открывается полностью закрытым.
  Set<String> _defaultCollapsed() {
    final set = <String>{};

    for (final region in kRegions) {
      set.add('region:${region.id}');

      for (final locationId in region.locationIds) {
        set.add('${region.id}/$locationId');
      }
    }

    return set;
  }


  @override
  void dispose() {

    _searchDebounce?.cancel();

    _searchController.dispose();

    super.dispose();
  }


  /// Ввод в поле поиска: сразу обновляем кнопку очистки,
  /// результаты — с дебаунсом (P1-4).
  void _onSearchChanged() {

    setState(() {});

    _searchDebounce?.cancel();

    final query = _query;

    if (query.isEmpty) {

      if (_debouncedQuery.isNotEmpty) {

        setState(() {

          _debouncedQuery = '';
        });
      }

      return;
    }

    _searchDebounce = Timer(

      const Duration(milliseconds: 200),

      () {

        if (mounted) {

          setState(() {

            _debouncedQuery = _query;

            // Новый запрос — прежний фильтр групп больше не
            // осмыслен (A2, 10-й проход): раньше пустая выдача
            // выбранного фильтра замыкала пользователя без
            // чипов.
            _resultFilter = SearchResultFilter.all;
          });
        }
      },
    );
  }


  void _toggle(String key) {

    setState(() {
      if (_collapsed.contains(key)) {
        _collapsed.remove(key);
      } else {
        _collapsed.add(key);
      }
    });
  }


  /// Переход на главную с выбранной логикой контекста (регион + локация).
  void _goLocation(String regionId, String locationId) {

    final region = regionById(regionId);

    AppLogger.info(
      '[TreeNav] location -> $locationId (${region.name})',
    );

    ref.read(currentRegionIdProvider.notifier).state = regionId;
    ref.read(currentIslandIdProvider.notifier).state = locationId;

    context.pop();
    context.go('/home');
  }


  void _goTrail(String locationId, String trailId) {

    AppLogger.info(
      '[TreeNav] trail -> $trailId (island=$locationId)',
    );

    _setContext(locationId);

    context.pop();
    context.push('/trail/$trailId?island=$locationId');
  }


  void _goPoi(String locationId, String poiId) {

    AppLogger.info(
      '[TreeNav] poi -> $poiId (island=$locationId)',
    );

    _setContext(locationId);

    context.pop();
    context.push('/poi/$poiId?island=$locationId');
  }


  void _setContext(String locationId) {

    final region = regionOfLocation(locationId);

    ref.read(currentRegionIdProvider.notifier).state = region.id;
    ref.read(currentIslandIdProvider.notifier).state = locationId;
  }


  @override
  Widget build(BuildContext context) {

    final regionsAsync = ref.watch(regionsProvider);

    final locationsAsync = ref.watch(islandsProvider);

    final currentRegionId = ref.watch(currentRegionIdProvider);

    final currentIslandId = ref.watch(currentIslandIdProvider);

    final regionManifests = regionsAsync.value ?? const <Manifest>[];

    final locationManifests = locationsAsync.value ?? const <Manifest>[];

    final query = _query;

    // Пока поле непустое — режим поиска; сами результаты
    // построены по ДЕБАУНС-запросу, старые висят, пока
    // не придут новые (P1-4).
    final showSearch = query.isNotEmpty;

    final searchPending = query != _debouncedQuery;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: BoxDecoration(
          // Скрим шторки — из темы (B5, 11-й проход).
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Для перетаскивания шторки — единая ручка каркаса
              // AppBottomSheet (B2, 10-й проход).
              const SheetGrabHandle(),

              _buildHeader(),

              const Divider(height: 1),

              Expanded(
                child: SingleChildScrollView(
                  // Низ контента — над парящей капсулой навигации:
                  // без отступа последние строки дерева прячутся
                  // за пилюлю «Главная/Карта/Избранное/Поиск».
                  // Плюс viewInsets: шторка живёт в несжимаемом
                  // теле шелла (resizeToAvoidBottomInset: false) —
                  // клавиатуру лист обязан перекрыть своим
                  // паддингом, иначе результаты поиска уезжают
                  // под неё (P0-3, 7-й проход).
                  padding: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    NavigationShell.sheetBottomInset(context) +
                        MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: showSearch
                      ? _SearchResults(
                          query: _debouncedQuery,
                          pending: searchPending,
                          filter: _resultFilter,
                          onFilterChanged: (filter) => setState(() {
                            _resultFilter = filter;
                          }),
                          onLocation: _goLocation,
                          onTrail: _goTrail,
                          onPoi: _goPoi,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Пустое состояние поиска (P1-4):
                            // последние открытые объекты над деревом.
                            _RecentItems(
                              onPoi: _goPoi,
                              onTrail: _goTrail,
                            ),
                            _buildTree(
                              loading: regionsAsync.isLoading
                                  || locationsAsync.isLoading,
                              hasError: regionsAsync.hasError
                                  || locationsAsync.hasError,
                              regionManifests: regionManifests,
                              locationManifests: locationManifests,
                              currentRegionId: currentRegionId,
                              currentIslandId: currentIslandId,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  /// Дерево каталога (показывается, когда поле поиска пустое).
  Widget _buildTree({
    required bool loading,
    required bool hasError,
    required List<Manifest> regionManifests,
    required List<Manifest> locationManifests,
    required String currentRegionId,
    required String currentIslandId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        if (loading)
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SkeletonRow(trailing: true),
              SkeletonRow(trailing: true),
              SkeletonRow(trailing: true),
              SkeletonRow(trailing: true),
            ],
          ),

        if (hasError)
          ErrorState(
            message: 'Не удалось загрузить каталог',
            compact: true,
            onRetry: () {
              ref.invalidate(regionsProvider);
              ref.invalidate(islandsProvider);
            },
          ),

        for (var i = 0; i < kRegions.length; i++) ...[

          if (i > 0) const Divider(height: 18),

          _buildRegion(
            region: kRegions[i],
            regionName:
                _manifestNameOf(regionManifests, kRegions[i].id)
                ?? kRegions[i].name,
            locationManifests: locationManifests,
            currentRegionId: currentRegionId,
            currentIslandId: currentIslandId,
          ),
        ],
      ],
    );
  }


  Widget _buildHeader() {


    final palette = AppPalette.of(context);

    final hasQuery = _searchController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 8),
      child: Row(
        children: [

          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: widget.focusSearch,
              onChanged: (_) => _onSearchChanged(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск: место, маршрут, локация…',
                hintStyle: AppText.body.copyWith(
                  color: palette.onSurfaceMuted,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: palette.onSurfaceMuted,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 38,
                  minHeight: 24,
                ),
                suffixIcon: hasQuery
                    ? IconButton(
                        tooltip: 'Очистить поиск',
                        padding: const EdgeInsets.all(6),
                        // Тап-цель 44 (B1, 10-й проход): иконка
                        // остаётся 17 — растёт зона нажатия.
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        icon: Icon(
                          LucideIcons.circleX,
                          size: 17,
                          color: palette.onSurfaceMuted,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                isDense: true,
                filled: true,
                fillColor: palette.surfaceRaised,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(
                    color: palette.sand,
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(
                    color: palette.sand,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(
                    color: palette.info,
                    width: 1.4,
                  ),
                ),
              ),
              style: AppText.body,
            ),
          ),

          const SizedBox(width: 8),

          Material(
            color: palette.surfaceRaised,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.sand, width: 0.9),
              ),
              child: IconButton(
                tooltip: 'Закрыть',
                iconSize: 18,
                padding: const EdgeInsets.all(12),
                // Тап-цель 44 (B1, 10-й проход).
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: palette.onSurface,
                  backgroundColor: palette.surfaceRaised,
                ),
                icon: const Icon(LucideIcons.x),
                onPressed: () => context.pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildRegion({
    required Region region,
    required String regionName,
    required List<Manifest> locationManifests,
    required String currentRegionId,
    required String currentIslandId,
  }) {
    final palette = AppPalette.of(context);

    final regionKey = 'region:${region.id}';

    final expanded = !_collapsed.contains(regionKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        _TreeNode(
          keyName: 'tree-region-${region.id}',
          indent: 0,
          icon: LucideIcons.mapPinned,
          iconBoxColor: _treeBoxAegean(palette),
          iconColor: palette.info,
          title: regionName,
          titleStyle: _regionStyle(Theme.of(context), palette),
          expanded: expanded,
          onTap: () => _toggle(regionKey),
          onExpand: () => _toggle(regionKey),
          trailing: _CountBadge(value: region.locationIds.length),
        ),

        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    for (final locationId in region.locationIds)
                      _buildLocation(
                        region: region,
                        locationId: locationId,
                        locationManifests: locationManifests,
                        currentRegionId: currentRegionId,
                        currentIslandId: currentIslandId,
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }


  Widget _buildLocation({
    required Region region,
    required String locationId,
    required List<Manifest> locationManifests,
    required String currentRegionId,
    required String currentIslandId,
  }) {
    final palette = AppPalette.of(context);

    final locationKey = '${region.id}/$locationId';

    final expanded = !_collapsed.contains(locationKey);

    final manifestName = _manifestNameOf(locationManifests, locationId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        _TreeNode(
          keyName: 'tree-$locationKey',
          indent: 1,
          icon: LucideIcons.anchor,
          iconBoxColor: _treeBoxAegean(palette),
          iconColor: palette.info,
          title: capitalize(manifestName ?? locationId),
          titleStyle: _locationStyle(Theme.of(context), palette),
          active: region.id == currentRegionId && locationId == currentIslandId,
          expanded: expanded,
          onTap: () => _toggle(locationKey),
          onExpand: () => _toggle(locationKey),
          onOpen: () => _goLocation(region.id, locationId),
          openTooltip: 'Открыть локацию ${capitalize(manifestName ?? locationId)}',
        ),

        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: expanded
              ? _LocationContent(
                  islandId: locationId,
                  locationKey: locationKey,
                  collapsed: _collapsed,
                  onToggle: _toggle,
                  onTrail: _goTrail,
                  onPoi: _goPoi,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }


  TextStyle _regionStyle(ThemeData theme, AppPalette palette) =>
      AppText.sectionTitle.copyWith(
        color: palette.onSurface,
      );


  TextStyle _locationStyle(ThemeData theme, AppPalette palette) =>
      AppText.body.copyWith(
        fontWeight: FontWeight.w700,
        color: palette.onSurface,
      );
}


/// Бейдж-счётчик в шапке узла дерева (сколько локаций / POI).
class _CountBadge extends StatelessWidget {

  const _CountBadge({
    required this.value,
  });


  final int value;


  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: palette.sandLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.sand, width: 0.7),
      ),
      child: Text(
        '$value',
        style: AppText.label.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: palette.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}


/// Контент локации: маршруты с их POI + группа вне-маршрутных
/// достопримечательностей — всё перечислено сразу, до самого нижнего
/// уровня (сами достопримечательности). Грузится лениво — только
/// когда локация раскрыта.
class _LocationContent extends ConsumerWidget {

  const _LocationContent({
    required this.islandId,
    required this.locationKey,
    required this.collapsed,
    required this.onToggle,
    required this.onTrail,
    required this.onPoi,
  });


  final String islandId;

  final String locationKey;

  /// Ключи свёрнутых узлов панели (маршрут / «вне маршрута»).
  final Set<String> collapsed;

  final void Function(String key) onToggle;

  final void Function(String locationId, String trailId) onTrail;

  final void Function(String locationId, String poiId) onPoi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);


    final theme = Theme.of(context);

    final trailsAsync = ref.watch(trailsFamily(islandId));

    final poisAsync = ref.watch(poisFamily(islandId));

    if (trailsAsync.isLoading || poisAsync.isLoading) {

      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonRow(trailing: true),
          SkeletonRow(trailing: true),
        ],
      );
    }

    if (trailsAsync.hasError || poisAsync.hasError) {

      return ErrorState(
        message: 'Не удалось загрузить контент локации',
        compact: true,
        onRetry: () {
          ref.invalidate(trailsFamily(islandId));
          ref.invalidate(poisFamily(islandId));
        },
      );
    }

    final trails = trailsAsync.value ?? const <Trail>[];

    final pois = poisAsync.value ?? const <Poi>[];

    final children = <Widget>[];

    for (final trail in trails) {

      final trailKey = '$locationKey/${trail.id}';

      final trailExpanded = !collapsed.contains(trailKey);

      final trailPois = sortPoisForDisplay(
        pois.where((p) => p.trailIds.contains(trail.id)),
      );

      children.add(
        _TreeNode(
          keyName: 'tree-$trailKey',
          indent: 2,
          icon: LucideIcons.route,
          iconBoxColor: _treeBoxOlive(palette),
          iconColor: AppColors.shoal,
          title: trail.name,
          titleStyle: AppText.body.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.onSurface,
          ),
          expanded: trailExpanded,
          onTap: () => onToggle(trailKey),
          onExpand: () => onToggle(trailKey),
          onOpen: () => onTrail(islandId, trail.id),
          openTooltip: 'Открыть маршрут «${trail.name}»',
          trailing: _CountBadge(value: trailPois.length),
        ),
      );

      children.add(
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: !trailExpanded
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final poi in trailPois)
                      _PoiRow(
                        islandId: islandId,
                        poi: poi,
                        indent: 3,
                        nodeKey: 'tree-$trailKey/${poi.id}',
                        onTap: onPoi,
                      ),
                  ],
                ),
        ),
      );
    }

    final offRoute =
        sortPoisForDisplay(pois.where((p) => p.trailIds.isEmpty));

    if (offRoute.isNotEmpty) {

      final offKey = '$locationKey/off';

      final offExpanded = !collapsed.contains(offKey);

      children.add(
        _TreeNode(
          keyName: 'tree-$offKey',
          indent: 2,
          icon: LucideIcons.mapPin,
          iconBoxColor: _treeBoxStone(palette),
          iconColor: palette.onSurface.withValues(alpha: 0.66),
          title: 'Вне маршрута',
          titleStyle: AppText.chip.copyWith(
            letterSpacing: 0.1,
            color: palette.onSurface.withValues(alpha: 0.78),
          ),
          expanded: offExpanded,
          onTap: () => onToggle(offKey),
          onExpand: () => onToggle(offKey),
          trailing: _CountBadge(value: offRoute.length),
        ),
      );

      children.add(
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: !offExpanded
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final poi in offRoute)
                      _PoiRow(
                        islandId: islandId,
                        poi: poi,
                        indent: 3,
                        nodeKey: 'tree-$offKey/${poi.id}',
                        onTap: onPoi,
                      ),
                  ],
                ),
        ),
      );
    }

    if (children.isEmpty) {

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(
          'Контент ещё не добавлен',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}


/// Строка достопримечательности (лист дерева).
class _PoiRow extends StatelessWidget {

  const _PoiRow({
    required this.islandId,
    required this.poi,
    required this.indent,
    required this.nodeKey,
    required this.onTap,
  });


  final String islandId;

  final Poi poi;

  final int indent;

  /// Ключ узла для тестов.
  final String nodeKey;

  final void Function(String locationId, String poiId) onTap;


  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);



    final label = poi.number != null
        ? '${poi.number}. ${poi.title}'
        : poi.title;

    return _TreeNode(
      keyName: nodeKey,
      indent: indent,
      icon: LucideIcons.mapPin,
      iconBoxColor: _treeBoxAmber(palette),
      iconColor: palette.accentDark,
      title: label,
      titleStyle: AppText.body.copyWith(
        fontWeight: FontWeight.w500,
        color: palette.onSurface.withValues(alpha: 0.9),
      ),
      titleMaxLines: 2,
      showExpandIcon: false,
      onTap: () => onTap(islandId, poi.id),
    );
  }
}


/// Узел дерева: строка с иконкой, названием, необязательным
/// чекером раскрытия и тапом.
class _TreeNode extends StatelessWidget {

  _TreeNode({
    this.keyName,
    required this.indent,
    required this.icon,
    required this.iconBoxColor,
    required this.iconColor,
    required this.title,
    this.titleStyle,
    this.titleMaxLines = 1,
    this.expanded = false,
    this.showExpandIcon = true,
    this.active = false,
    this.trailing,
    this.onTap,
    this.onExpand,
    this.onOpen,
    this.openTooltip,
  }) : super(
          key: keyName == null ? null : ValueKey(keyName),
        );


  /// Ключ узла для тестов (`tree-<путь>`).
  final String? keyName;

  /// Уровень вложенности: 0 — регион, 1 — локация, 2 — маршрут,
  /// 3 — достопримечательность.
  final int indent;

  final IconData icon;

  final Color iconBoxColor;

  final Color iconColor;

  final String title;

  final TextStyle? titleStyle;

  /// Длинные названия листьев (POI) переносятся на вторую
  /// строку, а не обрезаются многоточием на 360 px (A11).
  final int titleMaxLines;

  final bool expanded;

  final bool showExpandIcon;

  /// Текущий выбранный узел (подсвечивается заливкой).
  final bool active;

  final Widget? trailing;

  /// Тап по строке узла (например, переход к локации / маршруту).
  final VoidCallback? onTap;

  /// Тап по чекеру раскрытия. Если не задан — чекер повторяет [onTap].
  final VoidCallback? onExpand;

  /// Кнопка перехода к объекту узла (локация, маршрут). Показывается
  /// рядом с чекером; тап по строке при этом сворачивает/разворачивает,
  /// а не уводит из дерева.
  final VoidCallback? onOpen;

  /// Подсказка кнопки перехода (что именно откроется).
  final String? openTooltip;


  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);


    final theme = Theme.of(context);

    // Семантика узла (A6, 8-й проход): строка — КНОПКА с
    // состоянием «развёрнуто/свёрнуто» (у узлов с чекером),
    // чтобы скринридер различал тап по строке (свернуть/развернуть)
    // и отдельную стрелку перехода. Название и бейдж-счётчик
    // вливаются в узел из дочерних текстов без дублирования.
    return Semantics(
      container: true,
      button: onTap != null,
      expanded: showExpandIcon ? expanded : null,
      child: Padding(
      padding: EdgeInsets.only(left: (indent * 20).toDouble()),
      child: Material(
        color: active ? palette.sandLight : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [

                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBoxColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    title,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle ?? theme.textTheme.bodyMedium,
                  ),
                ),

                if (trailing != null) ...[

                  const SizedBox(width: 8),

                  trailing!,
                ],

                if (onOpen != null) ...[

                  const SizedBox(width: 4),

                  _OpenButton(
                    key: ValueKey('$keyName/open'),
                    onTap: onOpen!,
                    tooltip: openTooltip,
                  ),
                ],

                if (showExpandIcon) ...[

                  const SizedBox(width: 4),

                  _ExpandIcon(
                    expanded: expanded,
                    onTap: onExpand ?? onTap,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}


/// Чекер раскрытия узла: шеврон вниз/вправо.
class _ExpandIcon extends StatelessWidget {

  const _ExpandIcon({
    required this.expanded,
    this.onTap,
  });


  final bool expanded;

  final VoidCallback? onTap;


  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);


    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.block),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.block),
        onTap: onTap,
        // Тач-цель ≥ 44×44: визуальный размер иконки не растёт.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Icon(
              expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
              size: 17,
              color: palette.onSurfaceMuted,
            ),
          ),
        ),
      ),
    );
  }
}


/// Кнопка перехода к объекту узла (локация, маршрут). Тап по строке
/// сворачивает/разворачивает узел, а переход — по этой стрелке.
class _OpenButton extends StatelessWidget {

  const _OpenButton({
    super.key,
    required this.onTap,
    this.tooltip,
  });


  final VoidCallback onTap;

  final String? tooltip;


  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);


    // Собственный узел семантики с полным действием «Открыть …»
    // (A6, 8-й проход): стрелка — не безымянный квадратик,
    // а отдельная от строки кнопка перехода.
    final button = Semantics(
      container: true,
      button: true,
      label: tooltip ?? 'Открыть',
      child: Material(
        color: palette.surfaceRaised,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Тач-цель ≥ 44×44: иконка остаётся маленькой.
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                LucideIcons.arrowUpRight,
                size: 15,
                color: palette.info,
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;

    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
    );
  }
}




/// Имя объекта каталога из манифеста по его id (или null).
String? _manifestNameOf(List<Manifest> manifests, String id) {

  for (final m in manifests) {

    if (m.id == id) {

      return m.name;
    }
  }

  return null;
}


/// Подстрока поиска: регистронезависимое вхождение (кириллица + латиница).
/// Нормализация для поиска (P1-4): регистр, ё→е. Длина строки
/// сохраняется — по свёрнутой копии можно подсветить совпадение
/// в оригинале.
// Нормализация и совпадение — в models/search_filtering.dart (D5);
// здесь forwarding, чтобы остальной файл не переписывать.
String _fold(String value) => foldSearchText(value);

String _normalizeQuery(String query) => normalizeSearchQuery(query);

/// Результаты поиска по названиям локаций, маршрутов и
/// достопримечательностей (и, с пониженным приоритетом, по
/// категориям и описаниям — P1-4). Показываются вместо дерева,
/// когда в поле поиска введён текст.
///
/// A10.2, 8-й проход: данные — ГОТОВЫЙ компактный индекс
/// (tool/build_search_index.py, searchIndexProvider), а не
/// подписка на провайдеры контента всех локаций: на native
/// прежняя схема запускала холодный сидинг всех 9 пакетов при
/// первом запросе. У каждой строки — подпись с путём «регион ·
/// локация». Результаты сгруппированы: Локации / Маршруты /
/// Места, совпадение подсвечено жирным.
class _SearchResults extends ConsumerWidget {

  const _SearchResults({
    required this.query,
    required this.pending,
    required this.filter,
    required this.onFilterChanged,
    required this.onLocation,
    required this.onTrail,
    required this.onPoi,
  });


  /// ДЕБАУНС-запрос (пустой — пока дебаунс не сработал).
  final String query;

  /// Ввод продолжается — над результатами тонкий индикатор.
  final bool pending;

  /// Фильтр групп (B6.3).
  final SearchResultFilter filter;

  final ValueChanged<SearchResultFilter> onFilterChanged;

  final void Function(String regionId, String locationId) onLocation;

  final void Function(String locationId, String trailId) onTrail;

  final void Function(String locationId, String poiId) onPoi;


  @override
  Widget build(BuildContext context, WidgetRef ref) {


    final normalized = _normalizeQuery(query);

    if (normalized.isEmpty) {
      // Дебаунс ещё держит паузу — рисуем только индикатор.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    // A10.2, 8-й проход: поиск читает ГОТОВЫЙ компактный индекс
    // (tool/build_search_index.py), а не подписывается на
    // poisFamily/trailsFamily всех локаций — на native прежняя
    // схема при первом же запросе запускала холодный сидинг
    // всех 9 пакетов.
    final indexAsync = ref.watch(searchIndexProvider);

    return indexAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (index) => _SearchResultsBody(
        index: index,
        normalized: normalized,
        pending: pending,
        query: query,
        filter: filter,
        onFilterChanged: onFilterChanged,
        onLocation: onLocation,
        onTrail: onTrail,
        onPoi: onPoi,
      ),
    );
  }
}

/// «~2,1 км» до точки (B6.2): только когда известны и позиция
/// пользователя, и координаты точки из индекса.
String? _poiDistanceLabel(
  SearchIndexEntry entry,
  ({double latitude, double longitude})? userPosition,
) {
  final position = userPosition;

  if (position == null || entry.lat == null || entry.lng == null) {
    return null;
  }

  final meters = LocationService.distanceMeters(
    position.latitude,
    position.longitude,
    entry.lat!,
    entry.lng!,
  );

  return '~${formatTrailDistance(meters)}';
}

/// Тело результатов по загруженному индексу: группы
/// Локации / Маршруты / Места, совпадение по названию —
/// в начале группы, по описанию/категории — в конце (P1-4).
class _SearchResultsBody extends ConsumerWidget {

  const _SearchResultsBody({
    required this.index,
    required this.normalized,
    required this.query,
    required this.pending,
    required this.filter,
    required this.onFilterChanged,
    required this.onLocation,
    required this.onTrail,
    required this.onPoi,
  });

  final List<SearchIndexEntry> index;

  final String normalized;

  final String query;

  final bool pending;

  final SearchResultFilter filter;

  final ValueChanged<SearchResultFilter> onFilterChanged;

  final void Function(String regionId, String locationId) onLocation;

  final void Function(String locationId, String trailId) onTrail;

  final void Function(String locationId, String poiId) onPoi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);


    // Позиция пользователя — последняя известная (A5): есть —
    // показываем дистанции, нет — просто без них.
    final userPosition = ref.watch(_searchUserPositionProvider);

    final groups = groupSearchEntries(index, normalized);

    final locationRows = <Widget>[];

    final trailRows = <Widget>[];

    final trailRowsByDescription = <Widget>[];

    Widget trailRow(SearchIndexEntry entry) {
      return _SearchResultRow(
        key: ValueKey('search-trail-${entry.locationId}-${entry.id}'),
        icon: LucideIcons.route,
        iconBoxColor: _treeBoxOlive(palette),
        iconColor: AppColors.shoal,
        title: entry.title,
        subtitle: entry.subtitle,
        matchQuery: normalized,
        onTap: () => onTrail(entry.locationId, entry.id),
      );
    }

    for (final entry in groups.locations) {
      locationRows.add(
        _SearchResultRow(
          key: ValueKey('search-location-${entry.id}'),
          icon: LucideIcons.anchor,
          iconBoxColor: _treeBoxAegean(palette),
          iconColor: palette.info,
          title: entry.title,
          subtitle: entry.subtitle,
          matchQuery: normalized,
          onTap: () => onLocation(
            regionOfLocation(entry.id).id,
            entry.id,
          ),
        ),
      );
    }

    for (final entry in groups.trails) {
      trailRows.add(trailRow(entry));
    }

    for (final entry in groups.trailsByDescription) {
      trailRowsByDescription.add(trailRow(entry));
    }

    final poiTitleMatches = groups.poiByTitle;

    final poiMetadataMatches = groups.poiByMetadata;

    // «Рядом» (1a): с позицией внутри каждой подгруппы ближайшие
    // совпадения — сверху; без позиции порядок прежний (по индексу).
    sortEntriesByDistance(
      poiTitleMatches,
      userLat: userPosition?.latitude,
      userLng: userPosition?.longitude,
    );

    sortEntriesByDistance(
      poiMetadataMatches,
      userLat: userPosition?.latitude,
      userLng: userPosition?.longitude,
    );

    Widget poiRow(SearchIndexEntry entry) {
      return _SearchResultRow(
        key: ValueKey('search-poi-${entry.locationId}-${entry.id}'),
        icon: LucideIcons.mapPin,
        iconBoxColor: _treeBoxAmber(palette),
        iconColor: palette.accentDark,
        title: entry.displayTitle,
        subtitle: entry.subtitle,
        matchQuery: normalized,
        categoryGlyph: poiCategoryGlyph(entry.category),
        distanceLabel: _poiDistanceLabel(entry, userPosition),
        onTap: () => onPoi(entry.locationId, entry.id),
      );
    }

    final poiRows = [
      for (final entry in poiTitleMatches) poiRow(entry),
    ];

    final poiRowsByMetadata = [
      for (final entry in poiMetadataMatches) poiRow(entry),
    ];

    final trailGroup = [...trailRows, ...trailRowsByDescription];

    final poiGroup = [...poiRows, ...poiRowsByMetadata];

    // Есть ли совпадения хотя бы в одном виде (БЕЗ фильтра).
    final foundNothing = locationRows.isEmpty &&
        trailGroup.isEmpty &&
        poiGroup.isEmpty;

    if (foundNothing) {
      // Единый стиль пустых состояний (B8, 9-й проход).
      return StatePlaceholder(
        icon: LucideIcons.searchX,
        title: 'Ничего не найдено',
        description: 'По запросу «${query.trim()}» совпадений нет',
        compact: true,
      );
    }

    // Фильтр прячет целые группы, но чипы остаются на экране:
    // из «пустого» фильтра можно выйти одним тапом (A2).
    final showLocations =
        filter == SearchResultFilter.all ||
            filter == SearchResultFilter.locations;

    final showTrails =
        filter == SearchResultFilter.all ||
            filter == SearchResultFilter.trails;

    final showPois =
        filter == SearchResultFilter.all ||
            filter == SearchResultFilter.places;

    final visibleLocations = showLocations ? locationRows : const <Widget>[];

    final visibleTrails = showTrails ? trailGroup : const <Widget>[];

    final visiblePois = showPois ? poiGroup : const <Widget>[];

    final filteredEmpty = visibleLocations.isEmpty &&
        visibleTrails.isEmpty &&
        visiblePois.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        // Фильтры результатов (B6.3): Всё / Места / Маршруты /
        // Локации. Показываются всегда, когда по запросу есть
        // совпадения хотя бы в одном виде — фильтр не прячет
        // само наличие (A2, 10-й проход).
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (value, label) in [
                  (SearchResultFilter.all, 'Всё'),
                  (SearchResultFilter.places, 'Места'),
                  (SearchResultFilter.trails, 'Маршруты'),
                  (SearchResultFilter.locations, 'Локации'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ResultFilterChip(
                      key: ValueKey('search-filter-${value.name}'),
                      label: label,
                      selected: filter == value,
                      onTap: () => onFilterChanged(value),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Ввод ещё идёт (дебаунс) — тонкая линия над результатами.
        if (pending)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          ),

        // В выбранном разделе совпадений нет — компактная
        // заглушка вместо полного «Ничего не найдено» (A2).
        if (filteredEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'В этом разделе совпадений нет',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
          )
        else ...[
          if (visibleLocations.isNotEmpty) ...[
            const _SearchGroupHeader('Локации'),
            ...visibleLocations,
          ],

          if (visibleTrails.isNotEmpty) ...[
            const _SearchGroupHeader('Маршруты'),
            ...visibleTrails,
          ],

          if (visiblePois.isNotEmpty) ...[
            const _SearchGroupHeader('Места'),
            ...visiblePois,
          ],
        ],
      ],
    );
  }
}

/// Чип фильтра результатов (B6.3): кнопка с состоянием выбора.
///
/// B1 (10-й проход): зона нажатия — 44 по высоте, визуальная
/// пилюля внутри — 36 (Center + ConstrainedBox), иконка/текст
/// не растут.
class _ResultFilterChip extends StatelessWidget {
  const _ResultFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;

  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);


    return Semantics(
      button: true,
      selected: selected,
      label: 'Фильтр: $label',
      child: SizedBox(
        height: 44,
        child: Center(
          child: Material(
            color: selected ? palette.info : palette.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: onTap,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: selected ? palette.info : palette.sand,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: selected ? AppColors.accentOn : palette.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Заголовок группы результатов: Локации / Маршруты / Места.
class _SearchGroupHeader extends StatelessWidget {
  const _SearchGroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: AppText.label.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: palette.onSurfaceMuted,
        ),
      ),
    );
  }
}

/// «Недавние» (P1-4): последние открытые точки и маршруты над
/// деревом каталога, пока поле поиска пустое. Скрыт, когда
/// список пуст.
///
/// A10.2, 8-й проход: названия — из поискового индекса, без
/// подписки на контентные провайдеры локаций.
class _RecentItems extends ConsumerWidget {
  const _RecentItems({
    required this.onPoi,
    required this.onTrail,
  });

  final void Function(String locationId, String poiId) onPoi;

  final void Function(String locationId, String trailId) onTrail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final recents = ref.watch(recentItemsProvider);

    if (recents.isEmpty) {
      return const SizedBox.shrink();
    }

    final index = ref.watch(searchIndexProvider).value;

    if (index == null) {
      return const SizedBox.shrink();
    }

    final rows = <Widget>[];

    for (final item in recents) {
      final parts = item.split(':');

      if (parts.length != 3) continue;

      final type = parts[0];

      final locationId = parts[1];

      final id = parts[2];

      final SearchIndexEntry? entry;
      switch (type) {
        case 'poi':
          entry = index
              .where((e) =>
                  e.kind == SearchEntryKind.poi &&
                  e.locationId == locationId &&
                  e.id == id)
              .firstOrNull;
        case 'trail':
          entry = index
              .where((e) =>
                  e.kind == SearchEntryKind.trail &&
                  e.locationId == locationId &&
                  e.id == id)
              .firstOrNull;
        default:
          entry = null;
      }

      if (entry == null) continue;

      rows.add(
        _SearchResultRow(
          key: ValueKey('recent-${entry.kind.name}-$locationId-$id'),
          icon: entry.kind == SearchEntryKind.trail
              ? LucideIcons.route
              : LucideIcons.mapPin,
          iconBoxColor: entry.kind == SearchEntryKind.trail
              ? _treeBoxOlive(palette)
              : _treeBoxAmber(palette),
          iconColor: entry.kind == SearchEntryKind.trail
              ? AppColors.shoal
              : palette.accentDark,
          title: entry.displayTitle,
          subtitle: entry.subtitle,
          onTap: () => entry!.kind == SearchEntryKind.trail
              ? onTrail(locationId, id)
              : onPoi(locationId, id),
        ),
      );
    }

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SearchGroupHeader('Недавние'),
        ...rows,
        const Divider(height: 18),
      ],
    );
  }
}

/// Строка результата поиска: название + подпись с путём к объекту.
/// Совпадение с запросом подсвечено жирным (P1-4).
class _SearchResultRow extends StatelessWidget {

  const _SearchResultRow({
    super.key,
    required this.icon,
    required this.iconBoxColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.matchQuery,
    this.categoryGlyph,
    this.distanceLabel,
  });


  final IconData icon;

  /// Глиф категории POI (B6.2): точнее генерической булавки.
  final String? categoryGlyph;

  /// Дистанция до точки («~2,1 км», B6.2), если позиция известна.
  final String? distanceLabel;

  final Color iconBoxColor;

  final Color iconColor;

  final String title;

  final String subtitle;

  final VoidCallback onTap;

  /// Нормализованный запрос — подсветка совпадения в названии
  /// (пустой/`null` — без подсветки).
  final String? matchQuery;


  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);



    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      // Результат поиска — кнопка с полным названием и путём
      // (A6): не безымянный InkWell.
      child: Semantics(
        container: true,
        button: true,
        child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [

                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBoxColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  // Иконка результата: у POI — глиф категории
                  // (B6.2), у прочих — переданная иконка.
                  child: categoryGlyph != null
                      ? Image.asset(
                          categoryGlyph!,
                          width: 15,
                          height: 15,
                          color: iconColor,
                          colorBlendMode: BlendMode.srcIn,
                          errorBuilder: (_, _, _) =>
                              Icon(icon, size: 15, color: iconColor),
                        )
                      : Icon(icon, size: 15, color: iconColor),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text.rich(
                        _highlightSpans(
                          context,
                          title,
                          matchQuery,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.onSurface.withValues(alpha: 0.9),
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        distanceLabel == null
                            ? subtitle
                            : '$subtitle · $distanceLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: palette.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Подсветка совпадения в названии (P1-4): сегмент до/после —
/// обычным стилем строки, совпадение — жирным (w900).
TextSpan _highlightSpans(
  BuildContext context,
  String title,
  String? matchQuery,
) {
  final query = matchQuery ?? '';

  if (query.isEmpty) {
    return TextSpan(text: title);
  }

  final folded = _fold(title);

  // ё→е не меняет длину, но на всякий случай свёрнутая копия
  // обязана совпадать по длине — иначе подсветка невозможна.
  if (folded.length != title.length) {
    return TextSpan(text: title);
  }

  final start = folded.indexOf(query);

  if (start < 0) {
    return TextSpan(text: title);
  }

  return TextSpan(
    children: [
      TextSpan(text: title.substring(0, start)),
      TextSpan(
        text: title.substring(start, start + query.length),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      TextSpan(text: title.substring(start + query.length)),
    ],
  );
}
