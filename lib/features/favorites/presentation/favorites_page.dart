import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/navigation/navigation_shell.dart';
import '../../../app/theme.dart';
import '../../../core/widgets.dart';
import '../../../features/content/models/region_catalog.dart';
import '../../../features/content/providers/content_providers.dart';
import '../../../features/poi/models/poi.dart';
import '../../../features/favorites/controllers/favorites_controller.dart';
import '../../../features/favorites/providers/favorites_providers.dart';
import 'widgets/collections_rail.dart';
import 'widgets/day_plan_sheet.dart';
import '../../../features/settings/presentation/settings_sheet.dart';
import '../../../features/trails/models/trail.dart';
import '../../../features/trails/utils/format_distance.dart';


/// Порядок секций избранного — по каталогу (kLocationIds), а не
/// по вставке ключей в Set: раньше порядок зависел от того,
/// когда добавили первый объект локации (P0-8, 5-й проход).
List<String> sortedFavoriteLocationIds(Iterable<String> locationIds) {
  final order = {
    for (var i = 0; i < kLocationIds.length; i++) kLocationIds[i]: i,
  };

  final fallback = kLocationIds.length;

  return locationIds.toList()
    ..sort(
      (a, b) =>
          (order[a] ?? fallback).compareTo(order[b] ?? fallback),
    );
}

/// Страница избранного — показывает избранные POI и маршруты.
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final favorites = ref.watch(favoritesControllerProvider);

    // Ключи удалённых локаций (напр., «karacaoren») не должны ронять
    // страницу: их нельзя сопоставить ни с манифестом, ни с регионoм.
    // Обычно они чистятся ещё при загрузке (FavoritesController.load),
    // здесь — защитная чистка на случай, если состояние поменяли
    // извне (тесты, синхронизация).
    final (:byLocation, :staleKeys) = groupFavoriteKeys(favorites);

    if (staleKeys.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(favoritesControllerProvider.notifier)
            .removeAll(staleKeys);
      });
    }

    if (byLocation.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Избранное'),
          centerTitle: true,
          // Настройки доступны и в ПУСТОМ избранном (P0-3, 6-й
          // проход): раньше иконка была только в непустом
          // состоянии — автогид нельзя было выключить, не
          // добавив что-нибудь в избранное.
          actions: [
            // П9 (29-й проход): план дня из подборок/избранного.
            IconButton(
              key: const ValueKey('day-plan-button'),
              icon: const Icon(LucideIcons.calendarDays),
              tooltip: 'План дня',
              onPressed: () => showDayPlanSheet(context),
            ),
            IconButton(
              icon: const Icon(LucideIcons.settings2),
              tooltip: 'Настройки',
              onPressed: () => showSettingsSheet(context),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Подборки доступны и без избранного (П8,
                    // 12-й проход).
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: CollectionsRail(),
                    ),
                    SizedBox(height: AppSpace.m),
                    AppCard(
                  child: Stack(
                    children: [

                      // Градусные тики по кромке листа.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: ChartTicksPainter(),
                          ),
                        ),
                      ),

                      // Единый стиль пустых состояний (B8, 9-й
                      // проход): глиф в круге, Prata-заголовок,
                      // пояснение onSurfaceMuted, действия.
                      Padding(
                        padding: EdgeInsets.fromLTRB(32, 40, 32, 44),
                        child: StatePlaceholder(
                          icon: LucideIcons.star,
                          title: 'Пока ничего не добавлено',
                          description:
                              'Нажмите на звездочку на карточке POI '
                              'или маршрута, чтобы добавить в избранное',
                          // Действия из пустого состояния (B11):
                          // сразу к карте, где выбирают точки, или к
                          // маршрутам на главной.
                          actions: [
                            _GoRouteButton(
                              label: 'Перейти к карте',
                              path: '/map',
                              filled: true,
                            ),
                            _GoRouteButton(
                              label: 'К маршрутам',
                              path: '/home',
                            ),
                          ],
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Избранное'),
        centerTitle: true,
        actions: [
          // П9 (29-й проход): план дня из подборок/избранного.
          IconButton(
            key: const ValueKey('day-plan-button'),
            icon: const Icon(LucideIcons.calendarDays),
            tooltip: 'План дня',
            onPressed: () => showDayPlanSheet(context),
          ),
          // Настройки (P1-7): автогид, очистка избранного и
          // «О приложении» — здесь, в шторке.
          IconButton(
            icon: const Icon(LucideIcons.settings2),
            tooltip: 'Настройки',
            onPressed: () => showSettingsSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          // Контент уходит под парящую капсулу, но конец списка —
          // выше неё.
          NavigationShell.contentBottomInset(context),
        ),
        children: [
          ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Подборки (П8): пресеты регионов + свои списки.
                const CollectionsRail(),
                const SizedBox(height: AppSpace.l),
                // Явная секция «Избранное» с пояснением, чем оно
                // отличается от подборок над ним.
                const SectionTitle(title: 'Избранное'),
                const SizedBox(height: 2),
                Text(
                  'Всё, что вы отметили звёздочкой на карточках. '
                  'Убрать — звёздочка в строке ниже.',
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.of(context).onSurfaceMuted,
                      ),
                ),
                const SizedBox(height: AppSpace.m),
                for (final islandId in sortedFavoriteLocationIds(
                  byLocation.keys,
                )) ...[
                  _IslandFavoritesSection(
                    islandId: islandId,
                    itemIds: byLocation[islandId]!,
                  ),
                  const SizedBox(height: AppSpace.l),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _IslandFavoritesSection extends ConsumerWidget {
  const _IslandFavoritesSection({
    required this.islandId,
    required this.itemIds,
  });

  final String islandId;

  /// id избранных объектов локации (POI и маршруты вместе —
  /// тип определяется по загруженным данным).
  final List<String> itemIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final region = regionOfLocation(islandId);

    // Имя локации — из манифеста (как в приложении), а не сырой id.
    final manifestAsync = ref.watch(islandManifestFamily(islandId));

    final poisAsync = ref.watch(poisFamily(islandId));
    final trailsAsync = ref.watch(trailsFamily(islandId));

    // Секция с устаревшими ключами (id объектов больше нет в
    // контенте) не должна рисовать заголовок-одиночку: пустые
    // секции скрываем целиком (P0-8, 5-й проход). Пока данные
    // грузятся — скелетон, как раньше.
    if (poisAsync.hasValue && trailsAsync.hasValue) {
      final allPois = poisAsync.value ?? const <Poi>[];
      final allTrails = trailsAsync.value ?? const <Trail>[];

      final hasPois = allPois.any((p) => itemIds.contains(p.id));
      final hasTrails = allTrails.any((t) => itemIds.contains(t.id));

      if (!hasPois && !hasTrails) {
        return const SizedBox.shrink();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppPalette.of(context).onSurface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(LucideIcons.compass, size: 18, color: AppColors.accentOn),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    region.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.of(context)
                          .onSurface
                          .withValues(alpha: 0.72),
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    manifestAsync.value?.name ?? islandId,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.m),
        poisAsync.when(
          data: (allPois) {
            // Тип объекта определяется по данным локации: id избранного
            // либо находится среди POI, либо нет. Счётчик в заголовке —
            // ровно число показанных строк (раньше туда попадал
            // общий счётчик избранного локации: и «маршруты», и «POI»
            // показывали одно и то же число).
            final favPois = allPois
                .where((p) => itemIds.contains(p.id))
                .toList();

            if (favPois.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(title: 'Достопримечательности', count: favPois.length),
                const SizedBox(height: AppSpace.xs),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: favPois.length,
                  itemBuilder: (context, index) {
                    final poi = favPois[index];
                    return ContentTile(
                      title: poi.title,
                      subtitle: poi.description,
                      compact: true,
                      leading: _buildPoiLeading(context, poi),
                      // Hero-тег ветки избранного уникален относительно
                      // главной (P1-4, 6-й проход): обе страницы живут
                      // в стеке веток шелла и строили ОДИНАКОВЫЕ теги —
                      // push деталей падал «multiple heroes share the
                      // same tag». Полёт подхватывается через ?hero=fav.
                      heroTag: 'fav-poi-image-$islandId-${poi.id}',
                      // Звезда прямо в списке: снимаем избранное
                      // без захода на страницу (P1-5).
                      isFavorite: itemIds.contains(poi.id),
                      onFavoriteToggle: () => _removeFavorite(
                        context,
                        ref,
                        '$islandId/${poi.id}',
                      ),
                      onTap: () => context.push(
                        '/poi/${poi.id}?island=$islandId&hero=fav',
                      ),
                      semanticLabel: poi.title,
                    );
                  },
                ),
              ],
            );
          },
          loading: () => const Column(
            children: [
              SkeletonRow(trailing: true),
              SkeletonRow(trailing: true),
              SkeletonRow(trailing: true),
            ],
          ),
          error: (e, _) => ErrorState(
            message: 'Не удалось загрузить достопримечательности',
            compact: true,
            onRetry: () => ref.invalidate(poisFamily(islandId)),
          ),
        ),
        trailsAsync.when(
          data: (allTrails) {
            final favTrails = allTrails
                .where((t) => itemIds.contains(t.id))
                .toList();

            if (favTrails.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (poisAsync.hasValue) const SizedBox(height: AppSpace.l),
                SectionTitle(title: 'Маршруты', count: favTrails.length),
                const SizedBox(height: AppSpace.xs),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: favTrails.length,
                  itemBuilder: (context, index) {
                    final trail = favTrails[index];
                    return ContentTile(
                      title: trail.name,
                      subtitle: formatTrailDistance(trail.distance),
                      leading: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.depth,
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                        child: const Icon(
                          LucideIcons.footprints,
                          size: 24,
                          color: AppColors.accentOn,
                        ),
                      ),
                      // Звезда прямо в списке (P1-5): каскад ключей
                      // как на странице маршрута.
                      isFavorite: itemIds.contains(trail.id),
                      onFavoriteToggle: () => _removeFavorite(
                        context,
                        ref,
                        '$islandId/${trail.id}',
                        cascadeKeys: [
                          for (final poi in (poisAsync.value ?? const <Poi>[]))
                            if (poi.trailIds.contains(trail.id))
                              '$islandId/${poi.id}',
                        ],
                      ),
                      onTap: () => context.push('/trail/${trail.id}?island=$islandId'),
                      semanticLabel: trail.name,
                    );
                  },
                ),
              ],
            );
          },
          loading: () => const Column(
            children: [
              SkeletonRow(trailing: true),
              SkeletonRow(trailing: true),
            ],
          ),
          error: (e, _) => ErrorState(
            message: 'Не удалось загрузить маршруты',
            compact: true,
            onRetry: () => ref.invalidate(trailsFamily(islandId)),
          ),
        ),
      ],
    );
  }

  /// Снимает избранное и предлагает «Отменить» (P1-5): удаление
  /// из списка одним тапом не должно быть необратимым.
  void _removeFavorite(
    BuildContext context,
    WidgetRef ref,
    String key, {
    Iterable<String>? cascadeKeys,
  }) {
    final favorites = ref.read(favoritesControllerProvider.notifier);

    favorites.toggle(key, cascadeKeys: cascadeKeys);

    showAppSnackBar(
      context,
      'Удалено из избранного',
      actionLabel: 'Отменить',
      onAction: () {
        favorites.toggle(key, cascadeKeys: cascadeKeys);
      },
    );
  }

  Widget _buildPoiLeading(BuildContext context, Poi poi) {
    final imagePath = poi.imagePaths.isEmpty
        ? null
        : '${locationAssetBase(islandId)}/images/${poi.imagePaths.first}';

    // Единая миниатюра с бейджем номера (B9).
    return PoiThumbnail(
      imagePath: imagePath,
      number: poi.number,
      size: 56,
    );
  }
}

/// Кнопка-переход пустого состояния (B8): const-дружелюбная —
/// StatePlaceholder принимает действия в const-контексте.
class _GoRouteButton extends StatelessWidget {
  const _GoRouteButton({
    required this.label,
    required this.path,
    this.filled = false,
  });

  final String label;

  final String path;

  final bool filled;

  @override
  Widget build(BuildContext context) {
    void onPressed() => context.go(path);

    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        child: Text(label),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
