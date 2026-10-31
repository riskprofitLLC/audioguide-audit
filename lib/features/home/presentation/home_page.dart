import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/navigation/navigation_shell.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/services/app_initializer.dart';
import '../../../core/widgets.dart';
import '../../../core/widgets/entrance.dart';
import '../../../features/content/models/region_catalog.dart';
import '../../../features/content/providers/content_providers.dart';
import '../../../features/favorites/providers/favorites_providers.dart';
import '../../../features/map/presentation/widgets/map_preview.dart';
import '../../../features/navigation/presentation/tree_navigation_button.dart';
import '../../../features/onboarding/onboarding.dart';
import '../../../features/poi/models/poi.dart';
import '../../../features/poi/presentation/widgets/poi_list_tile.dart';
import '../../../features/trails/utils/trail_gallery.dart';
import '../../../core/utils/travel_time.dart';
import '../../../features/settings/presentation/settings_sheet.dart';
import '../../../features/settings/providers/listened_providers.dart';
import '../../../features/trails/models/trail.dart';
import 'widgets/island_header.dart';
import 'widgets/continue_card.dart';
import 'widgets/island_star_filter.dart';
import 'widgets/location_progress.dart';
import 'widgets/location_switcher.dart';
import 'widgets/region_switcher.dart';
import '../models/home_model.dart';


/// Главный экран: регион, локации, достопримечательности
/// и маршруты.
///
/// Регион со своей офлайн-картой выбирается каруселью
/// [RegionSwitcher]; внутри региона карусель [LocationSwitcher]
/// переключает локации (острова и прибрежные зоны). Контент
/// локации грузится из её офлайн-пакета через провайдеры
/// `content_providers.dart`.
///
/// Списки — ленивые slivers (B15): на широком экране (≥1000 px)
/// страница двухколоночная (B4) — слева шапка региона, чипы и
/// карта, справа маршруты и места; на узком — одна колонка в
/// прежнем порядке.
///
/// Секции появляются каскадом ([Entrance]) — один раз за сессию.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  /// Счётчик пересчётов группировки главной — только для тестов
  /// (паттерн ContentTile.debugCreatedCount): тап по звезде не
  /// должен пересчитывать модель (A7, 10-й проход).
  static int debugModelComputations = 0;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

/// Каскад появления секций уже играл в этой сессии.
///
/// Глобальный ValueNotifier, а не Riverpod-провайдер: флаг
/// переживает dispose страницы (ref в dispose недоступен при
/// финализации дерева), а нужен ровно один раз за сессию —
/// при первом уходе с главной.
final homeEntrancePlayed = ValueNotifier<bool>(false);

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();

    // Онбординг первого запуска (B8): один раз, постфреймом —
    // поверх уже собранной главной. Провайдер включается только
    // в main.dart (тесты без оверрайда диалога не увидят).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (ref.read(showOnboardingProvider)) {
        showFirstLaunchOnboarding(context);
      }
    });
  }

  @override
  void dispose() {
    // Первый уход с главной — каскад в этой сессии уже сыгран.
    homeEntrancePlayed.value = true;
    super.dispose();
  }

  // A7 (10-й проход): мемо-кеш группировки главной. Тяжёлая
  // часть (сортировка POI, разбивка по маршрутам) пересчитывается
  // ТОЛЬКО при смене списков точек/маршрутов; тап по звезде
  // меняет лишь избранное и переиспользует готовую модель.
  HomeModel? _homeModelCache;

  List<Poi>? _homeModelPois;

  List<Trail>? _homeModelTrails;

  HomeModel _homeModel(List<Poi> pois, List<Trail> trails) {
    final cached = _homeModelCache;

    if (cached != null &&
        identical(_homeModelPois, pois) &&
        identical(_homeModelTrails, trails)) {
      return cached;
    }

    // Группировка — чистая функция buildHomeModel (D5/R3).
    final model = buildHomeModel(pois, trails);

    _homeModelCache = model;

    _homeModelPois = pois;

    _homeModelTrails = trails;

    HomePage.debugModelComputations++;

    return model;
  }

  @override
  Widget build(BuildContext context) {
    final entrancePlayed = homeEntrancePlayed.value;

    final currentIslandId = ref.watch(currentIslandIdProvider);

    final manifestAsync = ref.watch(islandContentProvider);

    final poisAsync = ref.watch(poisProvider);

    final trailsAsync = ref.watch(trailsProvider);

    final favorites = ref.watch(favoritesControllerProvider);

    // Подписка на «прослушано» — на уровне build (A10, 9-й
    // проход): раньше watch жил в itemBuilder и дублировался на
    // каждую запись.
    final listened = ref.watch(listenedSetProvider);

    final islandId = manifestAsync.value?.id ?? currentIslandId;
    final regionAsync = ref.watch(regionContentProvider);
    final regionName = regionOfLocation(islandId).name;
    final isStub = manifestAsync.value?.stub ?? false;

    // Б15 (находка 19-го прохода): при смене локации через карту
    // манифест нового острова готов мгновенно (кеш), а
    // обёртки poisProvider/trailsProvider ещё «едут» и держат
    // previous-список СТАРОЙ локации (Riverpod:
    // copyWithPrevious). Один кадр строил тайлы «остров новый +
    // данные прежние»: битые пути фото (404), hero-теги и
    // ссылки. Списки принимаются только в состоянии AsyncData —
    // микс исключён, оверрайды тестов сохраняются.
    final pois = switch (poisAsync) {
      final AsyncData<List<Poi>> data => data.value,
      _ => const <Poi>[],
    };

    final trails = switch (trailsAsync) {
      final AsyncData<List<Trail>> data => data.value,
      _ => const <Trail>[],
    };

    // A7 (10-й проход): тяжёлая группировка (сортировка POI,
    // разбивка по маршрутам) мемоизируется по идентичности
    // списков — тап по звезде меняет только избранное и НЕ
    // пересчитывает группировку всех точек локации.
    final model = _homeModel(pois, trails);

    final islandFilterOn = ref.watch(islandStarFilterProvider).contains(islandId);
    final hikingForbidden = manifestAsync.value?.hikingForbidden == true;
    final initError = ref.watch(initErrorProvider);

    // Секция «Маршруты» будет показана — звёздочка-фильтр живёт
    // только в ней (B3); если маршрутов нет, фильтр переезжает в
    // первую доступную секцию («Вне маршрута»).
    final hasTrailSection = trailsAsync.hasValue && trails.isNotEmpty;

    // Глобальный SafeArea убран (edge-to-edge hero в деталях):
    // верхний отступ отсчитываем от статус-бара сами.
    final topInset = MediaQuery.paddingOf(context).top;

    // Двухколоночность меряется по ДОСТУПНОЙ ширине внутри
    // шелла (LayoutBuilder), а не по окну: на десктопе рельс
    // отъедает до 256 px, и при окне ~1000 px спискам
    // оставалось ~320 px (P0-1, 5-й проход).
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        final wide = available >= 1000;

        final leftColumnWidth = (available * 0.42).clamp(320.0, 420.0);

    // Шапка: регионы → титул региона → локации.
    Widget headerColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (initError != null) ...[
            _InitErrorNotice(
              error: initError,
              onRetry: () async {
                final error = await AppInitializer.retry();
                if (!context.mounted) return;
                ref.read(initErrorProvider.notifier).state = error;
              },
            ),
            const SizedBox(height: AppSpace.m),
          ],
          Entrance(
            enabled: !entrancePlayed,
            child: const RegionSwitcher(),
          ),
          const SizedBox(height: AppSpace.l),
          Entrance(
            enabled: !entrancePlayed,
            delay: const Duration(milliseconds: 60),
            child: IslandHeader(
              islandName: regionName,
              // Eyebrow — море и страна из манифеста региона.
              eyebrow:
                  'СРЕДИЗЕМНОЕ МОРЕ · ${regionAsync.value?.country ?? 'ТУРЦИЯ'}'
                      .toUpperCase(),
              version: regionAsync.value?.version,
              action: const TreeNavigationButton(floating: false),
            ),
          ),
          const SizedBox(height: AppSpace.s),

          // Честный офлайн-статус (B2.5): тихая строка, без
          // иконок-крикунов. Ассеты локальные — это правда; на
          // web первая загрузка требует сети.
          Text(
            kIsWeb
                ? 'Нужен интернет для первой загрузки'
                : 'Работает без сети · карта и аудио на устройстве',
            style: AppText.label.copyWith(
                  letterSpacing: 0.4,
                  color: AppPalette.of(context).onSurfaceMuted,
                ),
          ),
          const SizedBox(height: AppSpace.l),
          Entrance(
            enabled: !entrancePlayed,
            delay: const Duration(milliseconds: 120),
            child: const LocationSwitcher(),
          ),

          const SizedBox(height: AppSpace.xl),
        ],
      );
    }

    // Карта региона (или баннеры-заместители).
    Widget mapSection({required double mapHeight}) {
      return Entrance(
        enabled: !entrancePlayed,
        delay: const Duration(milliseconds: 180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isStub)
              const _InDevelopmentNotice()
            else ...[
              const _SectionEyebrow(text: 'КАРТА РЕГИОНА • ОФЛАЙН'),
              const SizedBox(height: AppSpace.s),
              MapPreview(
                onTap: () {
                  context.go('/map?island=$islandId');
                },
                islandId: islandId,
                height: mapHeight,
                // D6 (замечание Sonnet): тяжёлая карта главной не
                // живёт, когда пользователь ушёл на полную карту,
                // в избранное или в детали — платформенная вьюха
                // утилизируется, вместо неё бумажный плейсхолдер.
                activePaths: const {'/', '/home'},
              ),
            ],

            // «Продолжить» (B2.1) и «Прослушано» — под картой;
            // каждый блок несёт СВОЙ верхний отступ AppSpace.m,
            // поэтому скрытие любого не создаёт фантомных
            // зазоров, а ритм между блоками остаётся 16 px.
            const ContinueCard(),

            LocationProgressBar(islandId: islandId),
          ],
        ),
      );
    }

    // Slivers секций списков (маршруты + вне маршрута) — общий
    // блок для узкой и широкой раскладок.
    List<Widget> listSlivers(HomeModel model) {
      final slivers = <Widget>[];

      final orphanPois = model.orphanPois;

      // Теги Hero-миниатюр — ЧИСТЫЙ расчёт ДО построения slivers
      // (A1, 8-й проход): раньше набор заполнялся побочным эффектом
      // внутри ленивого itemBuilder «Вне маршрута» — после первой
      // прокрутки heroSeen.add возвращал false, и плитка теряла
      // тег: полёт миниатюры в детали молчал. Точка двух маршрутов
      // получает Hero в первой группе, повторные встречи — null;
      // внемаршрутным точкам тег положен всегда (основной контент
      // bay/coast/Памфилии, P2 7-го прохода).
      final heroTags = <String, String?>{};

      void assignHeroTags(List<Poi> pois) {
        for (final poi in pois) {
          heroTags[poi.id] = heroTags.containsKey(poi.id)
              ? null
              : 'poi-image-$islandId-${poi.id}';
        }
      }

      // Группировка POI по маршрутам — из мемоизованной модели
      // (A7, 10-й проход): тап по звезде не пересчитывает её.
      final trailsWithPois = model.trailsWithPois;

      // Видимые точки маршрута — фильтр избранного применяется
      // ПОВЕРХ модели, на последнем шаге (A7).
      List<Poi> visiblePoisOf(List<Poi> trailPois) {
        if (!islandFilterOn) {
          return trailPois;
        }

        return [
          for (final poi in trailPois)
            if (favorites.contains('$islandId/${poi.id}')) poi,
        ];
      }

      for (final trail in trailsWithPois) {
        assignHeroTags(visiblePoisOf(trail.allPois));
      }

      // --- Маршруты ---
      if (hikingForbidden) {
        slivers.add(
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const AppDivider(),
                const SizedBox(height: 12),
                Entrance(
                  enabled: !entrancePlayed,
                  delay: const Duration(milliseconds: 240),
                  child: HikingForbiddenNotice(
                    notice: manifestAsync.value?.trailNotice,
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (hasTrailSection) {
        slivers.add(
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const AppDivider(),
                const SizedBox(height: 12),
                Entrance(
                  enabled: !entrancePlayed,
                  delay: const Duration(milliseconds: 240),
                  child: SectionTitle(
                    title: 'Маршруты',
                    count: trails.length,
                    action: IslandStarFilter(
                      islandId: islandId,
                      filterOn: islandFilterOn,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );

        // Элементы секции: плоские ЗАПИСИ (данные), виджеты по
        // индексу собирает itemBuilder (A4, 8-й проход) — раньше
        // список держал готовые виджеты, и все 46 POI
        // Финике—Анталья строились разом при открытии; ленивым
        // оставался только layout.
        final entries = <HomeEntry>[];

        for (var t = 0; t < trailsWithPois.length; t++) {
          final entry = trailsWithPois[t];

          final visiblePois = visiblePoisOf(entry.allPois);

          if (t > 0) {
            entries.add(const GapEntry(12));
          }

          entries.add(
            TrailEntry(
              trail: entry.trail,
              allPois: entry.allPois,
              visibleCount: visiblePois.length,
              // Каскад ключей — на все точки маршрута, не только
              // видимые при звёзд-фильтре.
              cascadeKeys: [
                for (final poi in entry.allPois) '$islandId/${poi.id}',
              ],
              // Обложка — первый кадр галереи маршрута (общий
              // хелпер с деталями и шторкой, P1-3, 7-й проход):
              // при звёзд-фильтре не меняется, hero-полёт в
              // детали совпадает с первым кадром всегда.
              coverPath: trailCoverAssetPath(
                model.sortedPois,
                entry.trail.id,
                islandId,
              ),
            ),
          );

          if (visiblePois.isNotEmpty) {
            entries.add(const GapEntry(8));

            for (var i = 0; i < visiblePois.length; i++) {
              entries.add(
                PoiTileEntry(
                  poi: visiblePois[i],
                  heroTag: heroTags[visiblePois[i].id],
                  showDivider: i < visiblePois.length - 1,
                ),
              );
            }
          } else {
            entries.add(
              EmptyTrailEntry(
                message: islandFilterOn
                    ? 'В избранном нет достопримечательностей этого маршрута'
                    : 'На маршруте пока не отмечено достопримечательностей',
              ),
            );
          }
        }

        slivers.add(
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) => _buildEntry(
              entries[index],
              islandId,
              favorites,
              listened,
              isBoat: manifestAsync.value?.isBoat == true,
              // Скорость на воде — из манифеста локации (баг 16).
              boatSpeedKmh:
                  manifestAsync.value?.effectiveBoatSpeedKmh ?? 8.0,
            ),
          ),
        );
      } else if (trailsAsync.hasError) {
        slivers.add(
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const AppDivider(),
                const SizedBox(height: 12),
                ErrorState(
                  message: 'Не удалось загрузить маршруты',
                  onRetry: () => ref.invalidate(trailsProvider),
                ),
              ],
            ),
          ),
        );
      } else if (trailsAsync.isLoading) {
        // Скелетон вместо пустоты, пока грузится пакет.
        slivers.add(
          const SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 16),
                AppDivider(),
                SizedBox(height: 12),
                SkeletonCard(),
              ],
            ),
          ),
        );
      }

      // --- Загрузка POI ---
      if (poisAsync.isLoading && !trailsAsync.isLoading) {
        slivers.add(
          const SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 16),
                AppDivider(),
                SizedBox(height: 12),
                SkeletonRow(trailing: true),
                SkeletonRow(trailing: true),
                SkeletonRow(trailing: true),
                SkeletonRow(trailing: true),
              ],
            ),
          ),
        );
      }

      // --- Вне маршрута ---
      if (orphanPois.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpace.m),
                const AppDivider(),
                const SizedBox(height: AppSpace.s),
                Entrance(
                  enabled: !entrancePlayed,
                  delay: const Duration(milliseconds: 300),
                  child: SectionTitle(
                    // «Вне маршрута» — точки без привязки к трекам;
                    // прежнее «Локации» путалось с переключателем
                    // локаций выше (B2).
                    title: 'Вне маршрута',
                    count: orphanPois.length,
                    action: hasTrailSection
                        ? null
                        : IslandStarFilter(
                            islandId: islandId,
                            filterOn: islandFilterOn,
                          ),
                  ),
                ),
                const SizedBox(height: AppSpace.s),
              ],
            ),
          ),
        );

        final visibleOrphans = islandFilterOn
            ? [
                for (final poi in orphanPois)
                  if (favorites.contains('$islandId/${poi.id}')) poi,
              ]
            : orphanPois;

        // Теги внемаршрутных точек — тем же чистым расчётом.
        assignHeroTags(visibleOrphans);

        if (visibleOrphans.isEmpty) {
          slivers.add(
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'В избранном нет достопримечательностей',
                ),
              ),
            ),
          );
        } else {
          slivers.add(
            SliverList.builder(
              itemCount: visibleOrphans.length,
              itemBuilder: (context, index) => _poiTile(
                context,
                visibleOrphans[index],
                islandId,
                favorites,
                heroTag: heroTags[visibleOrphans[index].id],
                showDivider: index < visibleOrphans.length - 1,
              ),
            ),
          );
        }
      }

      // Тихая строка «Настройки» в самом низу списка: вход в
      // настройки и с главной (P0-3, 6-й проход), без
      // раздувания шапки региона.
      slivers.add(
        const SliverToBoxAdapter(child: _SettingsFooterRow()),
      );

      return slivers;
    }

    // Широкий экран (≥1000 px): слева шапка + карта (sticky —
    // не прокручивается вместе со списками), справа списки.
    if (wide) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: leftColumnWidth,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  topInset + 16,
                  16,
                  NavigationShell.contentBottomInset(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerColumn(),
                    mapSection(mapHeight: 300),
                  ],
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              color: AppPalette.of(context).sand,
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  ...listSlivers(model),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: NavigationShell.contentBottomInset(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Узкий экран: единый ленивый скролл в прежнем порядке.
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                topInset + 16,
                16,
                0,
              ),
              child: headerColumn(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: mapSection(mapHeight: 240),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              // Контент прокручивается под парящей капсулой,
              // но последний элемент должен вставать выше неё.
              NavigationShell.contentBottomInset(context),
            ),
            sliver: SliverMainAxisGroup(
              slivers: listSlivers(model),
            ),
          ),
        ],
      ),
    );
        },
    );
  }

  /// Строит виджет по записи списка главной (A4, 8-й проход):
  /// записи — чистые данные, сборка виджета происходит в
  /// itemBuilder лениво, только для вошедших во вьюпорт.
  Widget _buildEntry(
    HomeEntry entry,
    String islandId,
    Set<String> favorites,
    Set<String> listened, {
    bool isBoat = false,
    double boatSpeedKmh = 8.0,
  }) {
    switch (entry) {
      case TrailEntry():
        final trail = entry.trail;

        // Время прохождения из длины — только когда длина
        // известна. Морская локация — «на воде» по скорости
        // манифеста, а не пешеходным 4 км/ч (баг 16, замечания
        // Sonnet).
        final distance = trail.distance;

        final walkingTime = distance != null && distance > 0
            ? '≈ ${travelTimeLabel(distance, isBoat: isBoat, boatSpeedKmh: boatSpeedKmh)} ${isBoat ? 'на воде' : 'пешком'}'
            : null;

        // Прогресс маршрута (B2.3): сколько точек прослушано.
        var trailListened = 0;

        for (final poi in entry.allPois) {
          if (poi.audioPath != null &&
              listened.contains('$islandId/${poi.id}')) {
            trailListened++;
          }
        }

        final listenedLabel = trailListened > 0
            ? 'прослушано $trailListened из ${entry.allPois.length}'
            : null;

        return TrailCard(
          title: trail.name,
          distance: trail.distance,
          poiCount: entry.visibleCount,
          walkingTime: walkingTime,
          listenedLabel: listenedLabel,
          isBoat: isBoat,
          imagePath: entry.coverPath,
          isFavorite: favorites.contains('$islandId/${trail.id}'),
          heroTag: 'trail-image-$islandId-${trail.id}',
          onTap: () => context.push('/trail/${trail.id}?island=$islandId'),
          onFavoriteToggle: () => ref
              .read(favoritesControllerProvider.notifier)
              .toggle('$islandId/${trail.id}', cascadeKeys: entry.cascadeKeys),
        );

      case PoiTileEntry():
        return _poiTile(
          context,
          entry.poi,
          islandId,
          favorites,
          heroTag: entry.heroTag,
          showDivider: entry.showDivider,
        );

      case GapEntry():
        return SizedBox(height: entry.height);

      case EmptyTrailEntry():
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            entry.message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: AppPalette.of(context).onSurfaceMuted,
                ),
          ),
        );
    }
  }

  /// Строка точки интереса (единый стиль для «Маршрутов» и
  /// «Вне маршрута»). Миниатюра — общий [PoiThumbnail] (B9);
  /// тег Hero уникален в пределах страницы — дубль POI в другой
  /// группе маршрутов его уже не получит (B7). Тег приходит
  /// ИЗВНЕ чистым расчётом (A1, 8-й проход) — здесь только чтение.
  Widget _poiTile(
    BuildContext context,
    Poi poi,
    String islandId,
    Set<String> favorites, {
    required bool showDivider,
    String? heroTag,
  }) {
    final key = '$islandId/${poi.id}';

    // Вёрстка плитки — общий PoiListTile (та же плитка на странице
    // маршрута); набор избранного приходит СНАРУЖИ — главная
    // мемоизирует его и не подписывает каждую плитку на провайдер.
    return PoiListTile(
      poi: poi,
      islandId: islandId,
      showDivider: showDivider,
      heroTag: heroTag,
      isFavorite: favorites.contains(key),
      onFavoriteToggle: () =>
          ref.read(favoritesControllerProvider.notifier).toggle(key),
    );
  }

}

/// Eyebrow-подпись секции: сигнальный ромб + трекинг-строка.
class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {

    return Row(
      children: [
        Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.brandAccent,
              borderRadius: BorderRadius.circular(AppRadius.hairline),
            ),
          ),
        ),
        const SizedBox(width: 9),
        // Гибкий текст: трекинг-CAPS на textScale 1.6 не
        // переполняет узкую колонку, а обрезается (P1-5).
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color:
                  AppPalette.of(context).onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }
}

/// Баннер «ошибка инициализации» на главном экране.
///
/// Каркас — единый [NoticeBanner] (B2, 11-й проход); здесь —
/// только специфичный футер: сворачиваемая техническая деталь
/// и кнопка повтора. Человеческий текст без технических
/// деталей (принцип ErrorState, P0-5 5-го прохода): сырой
/// '$error' пугал и ничего не объяснял.
class _InitErrorNotice extends StatefulWidget {
  const _InitErrorNotice({
    required this.error,
    required this.onRetry,
  });

  final Object error;

  final VoidCallback onRetry;

  @override
  State<_InitErrorNotice> createState() => _InitErrorNoticeState();
}

class _InitErrorNoticeState extends State<_InitErrorNotice> {
  bool _detailsVisible = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NoticeBanner(
      variant: NoticeBannerVariant.error,
      icon: LucideIcons.alertTriangle,
      title: 'Ошибка инициализации',
      message: 'Не удалось открыть базу данных контента. '
          'Проверьте свободное место и перезапустите приложение.',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Техническая деталь — сворачиваемая строка.
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => setState(() => _detailsVisible = !_detailsVisible),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _detailsVisible
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 14,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Подробнее',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_detailsVisible)
            Text(
              '${widget.error}',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                fontFamily: 'monospace',
                color: theme.colorScheme.onErrorContainer
                    .withValues(alpha: 0.85),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton(
            onPressed: widget.onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

/// Заглушка для острова, материал которого ещё в разработке:
/// каркас — единый NoticeBanner (B2, 11-й проход).
class _InDevelopmentNotice extends StatelessWidget {
  const _InDevelopmentNotice();

  @override
  Widget build(BuildContext context) {
    return const NoticeBanner(
      variant: NoticeBannerVariant.info,
      icon: LucideIcons.construction,
      title: 'В разработке',
      message: 'Остров находится в разработке, будем признательны '
          'за помощь в поиске фото / видео материалов',
    );
  }
}

/// Тихая строка «Настройки» в самом низу списка главной
/// (P0-3, 6-й проход): настройки доступны и без захода в
/// «Избранное», шапку региона не раздуваем.
class _SettingsFooterRow extends StatelessWidget {
  const _SettingsFooterRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpace.m),
        child: TextButton.icon(
          onPressed: () => showSettingsSheet(context),
          icon: const Icon(LucideIcons.settings2, size: 16),
          label: const Text('Настройки'),
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.of(context)
                .onSurface
                .withValues(alpha: 0.72),
            textStyle: theme.textTheme.labelMedium,
          ),
        ),
      ),
    );
  }
}
