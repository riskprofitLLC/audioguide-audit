import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../content/models/manifest.dart';
import '../../../content/providers/content_providers.dart';
import '../../../poi/models/poi.dart';
import '../../models/user_collection.dart';
import '../../providers/collections_providers.dart';
import '../../providers/favorites_providers.dart';
import '../../utils/day_plan.dart';

/// Источник плана дня: избранное, готовая подборка («от авторов»)
/// или своя подборка.
class DayPlanSource {
  const DayPlanSource({
    required this.id,
    required this.name,
    required this.keys,
  });

  /// Идентификатор для ключей виджетов: уникален — у готовой и
  /// своей подборки могут совпасть названия.
  final String id;

  /// Подпись в списке выбора.
  final String name;

  /// Ключи точек «локация/poi-XX» в порядке подборки.
  final Set<String> keys;
}

/// Собирает источники плана дня: избранное, готовые подборки
/// (скрытые пользователем не показываем) и свои подборки.
///
/// Чистая функция — покрывается тестом без виджетов.
List<DayPlanSource> buildDayPlanSources({
  required Set<String> favorites,
  required Iterable<PresetCollection> presets,
  required Set<String> hiddenPresets,
  required Iterable<UserCollection> collections,
}) {
  return [
    if (favorites.isNotEmpty)
      DayPlanSource(id: 'favorites', name: 'Избранное', keys: favorites),
    for (final preset in presets)
      if (preset.keys.isNotEmpty && !hiddenPresets.contains(preset.name))
        DayPlanSource(
          id: 'preset-${preset.name}',
          name: preset.name,
          keys: preset.keys.toSet(),
        ),
    for (final collection in collections)
      if (collection.keys.isNotEmpty)
        DayPlanSource(
          id: 'collection-${collection.id}',
          name: collection.name,
          keys: collection.keys,
        ),
  ];
}

/// Шторка «План дня» (29-й проход, П9): выбираете подборку или
/// избранное — получаете порядок точек, пешее время между ними
/// (4 км/ч) и суммарное время с аудиогидами.
Future<void> showDayPlanSheet(BuildContext context) async {
  await showAppBottomSheet(
    context,
    title: 'План дня',
    builder: (context) => const DayPlanSheet(),
  );
}

class DayPlanSheet extends ConsumerWidget {

  const DayPlanSheet({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    // Источники плана: «Избранное», готовые подборки («от авторов»,
    // ровно те, что видны в рельсе) и свои подборки. Готовые
    // раньше не предлагались — при видимой подборке «Гемилер:
    // главные точки» шторка утверждала, что подборок нет.
    final sources = buildDayPlanSources(
      favorites: ref.watch(favoritesControllerProvider),
      presets: ref.watch(presetCollectionsProvider).value ?? const [],
      hiddenPresets: ref.watch(hiddenPresetCollectionsProvider),
      collections: ref.watch(userCollectionsProvider),
    );

    if (sources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Text(
          'Добавьте точки в избранное или в подборку — и здесь появится план дня с оценкой времени.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.onSurfaceMuted,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Из какой подборки собрать день?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: AppSpace.s),
        for (final source in sources)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: OutlinedButton.icon(
              key: ValueKey('day-plan-source-${source.id}'),
              icon: const Icon(LucideIcons.route),
              label: Text(
                '${source.name} (${source.keys.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => _showPlan(context, ref, source.name, source.keys),
            ),
          ),
        const SizedBox(height: AppSpace.s),
      ],
    );
  }


  Future<void> _showPlan(
    BuildContext context,
    WidgetRef ref,
    String sourceName,
    Set<String> keys,
  ) async {
    // Ключи «локация/poiId» — группируем по локациям и грузим POI.
    final byLocation = <String, List<String>>{};

    for (final key in keys) {
      final slash = key.indexOf('/');

      if (slash <= 0) {
        continue;
      }

      byLocation
          .putIfAbsent(key.substring(0, slash), () => [])
          .add(key.substring(slash + 1));
    }

    final pois = <Poi>[];

    for (final entry in byLocation.entries) {
      final locationPois = await ref.read(poisFamily(entry.key).future);

      for (final id in entry.value) {
        final poi = locationPois.where((p) => p.id == id);

        if (poi.isNotEmpty) {
          pois.add(poi.first);
        }
      }
    }

    if (pois.isEmpty) {
      if (context.mounted) {
        showAppSnackBar(context, 'В подборке нет загруженных точек');
      }

      return;
    }

    final plan = computeDayPlan(pois);

    if (!context.mounted) {
      return;
    }

    await showAppBottomSheet(
      context,
      title: 'План: $sourceName',
      builder: (context) => _DayPlanView(plan: plan),
    );
  }
}


class _DayPlanView extends StatelessWidget {

  const _DayPlanView({required this.plan});


  final DayPlan plan;


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < plan.legs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${i + 1}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.info,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.legs[i].poi.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (i > 0 && plan.legs[i].walkMinutes > 0)
                        Text(
                          'пешком ${formatMinutes(plan.legs[i].walkMinutes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.onSurfaceMuted,
                          ),
                        ),
                      if (plan.legs[i].audioMinutes > 0)
                        Text(
                          'аудио ${formatMinutes(plan.legs[i].audioMinutes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.onSurfaceMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const Divider(),
        Text(
          'Всего: ~${plan.totalLabel} '
          '(пешком ${formatMinutes(plan.walkMinutes)} + аудио ${formatMinutes(plan.audioMinutes)})',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpace.m),
      ],
    );
  }
}
