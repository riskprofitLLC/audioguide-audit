import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/notice_banner.dart';
import '../../../content/models/manifest.dart';
import '../../../content/models/region_catalog.dart';
import '../../../content/providers/content_providers.dart';
import '../../../gps/providers/location_providers.dart';
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

class DayPlanSheet extends ConsumerStatefulWidget {
  const DayPlanSheet({super.key});

  @override
  ConsumerState<DayPlanSheet> createState() => _DayPlanSheetState();
}

class _DayPlanSheetState extends ConsumerState<DayPlanSheet> {
  /// Идёт загрузка точек выбранного источника — шторка показывает
  /// спиннер вместо прыжка в пустоту.
  bool _loading = false;

  String? _sourceName;

  List<DayPlanStop>? _stops;

  /// Локации с `hikingForbidden` среди точек плана — предупреждение.
  final Set<String> _hikingForbidden = {};

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final stops = _stops;

    if (stops != null && _sourceName != null) {
      return _DayPlanView(
        stops: stops,
        sourceName: _sourceName!,
        hikingForbidden: _hikingForbidden,
        onBack: () => setState(() {
          _stops = null;
          _sourceName = null;
          _hikingForbidden.clear();
        }),
      );
    }

    return _buildSources();
  }

  Widget _buildSources() {
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
              onPressed: () => _showPlan(source),
            ),
          ),
        const SizedBox(height: AppSpace.s),
      ],
    );
  }

  Future<void> _showPlan(DayPlanSource source) async {
    setState(() => _loading = true);

    // Ключи «локация/poiId» — грузим POI по мере встречи, сохраняя
    // порядок точек как в подборке.
    final pois = <DayPlanStop>[];

    final loaded = <String, List<Poi>>{};

    final manifests = <String, Manifest>{};

    for (final key in source.keys) {
      final slash = key.indexOf('/');

      if (slash <= 0) {
        continue;
      }

      final location = key.substring(0, slash);

      final id = key.substring(slash + 1);

      // Битая/удалённая локация — пропускаем, а не роняем шторку
      // (P2 аудита): `locationAssetBase` бросает StateError.
      if (!kLocationIds.contains(location)) {
        continue;
      }

      final manifest =
          manifests[location] ??= await ref.read(
        islandManifestFamily(location).future,
      );

      final locationPois =
          loaded[location] ??= await ref.read(poisFamily(location).future);

      final poi = locationPois.where((p) => p.id == id);

      if (poi.isEmpty) {
        continue;
      }

      if (manifest.hikingForbidden) {
        _hikingForbidden.add(manifest.name);
      }

      pois.add(
        DayPlanStop(
          locationId: location,
          poi: poi.first,
          isBoat: manifest.isBoat,
          speedKmh: manifest.effectiveBoatSpeedKmh,
        ),
      );
    }

    if (!mounted) {
      return;
    }

    if (pois.isEmpty) {
      setState(() => _loading = false);

      showAppSnackBar(context, 'В подборке нет загруженных точек');

      return;
    }

    setState(() {
      _loading = false;

      _stops = pois;

      _sourceName = source.name;
    });
  }
}

class _DayPlanView extends ConsumerStatefulWidget {
  const _DayPlanView({
    required this.stops,
    required this.sourceName,
    required this.hikingForbidden,
    required this.onBack,
  });

  final List<DayPlanStop> stops;

  final String sourceName;

  final Set<String> hikingForbidden;

  final VoidCallback onBack;

  @override
  ConsumerState<_DayPlanView> createState() => _DayPlanViewState();
}

class _DayPlanViewState extends ConsumerState<_DayPlanView> {
  /// Порядок шагов: как в подборке или оптимизированный по пути.
  bool _optimized = false;

  /// Считать путь от текущей позиции пользователя («Вы здесь»).
  bool _fromMe = false;

  /// Старт дня — сейчас, округлённый до ближайших 5 минут.
  late DateTime _start = () {
    final now = DateTime.now();

    return now.add(Duration(minutes: 5 - now.minute % 5))
        .copyWith(second: 0, millisecond: 0, microsecond: 0);
  }();

  (double, double)? get _startPoint {
    if (!_fromMe) {
      return null;
    }

    final position = ref.read(locationServiceProvider).lastKnownPosition;

    if (position == null) {
      return null;
    }

    return (position.latitude, position.longitude);
  }

  List<DayPlanStop> get _orderedStops {
    if (!_optimized) {
      return widget.stops;
    }

    final order = optimizeStopOrder(widget.stops, start: _startPoint);

    return [for (final index in order) widget.stops[index]];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final stops = _orderedStops;

    final plan = computeDayPlan(stops, start: _startPoint);

    // Выигрыш оптимизации — в минутах ходьбы, чтобы переключатель
    // был осмысленным, а не декоративным.
    final baseMinutes = planTravelMinutes(
      computeDayPlan(widget.stops).legs,
    );

    final saving = baseMinutes - plan.travelMinutes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.sourceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              key: const ValueKey('day-plan-back'),
              onPressed: widget.onBack,
              child: const Text('Другая подборка'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        AppCard(
          padding: const EdgeInsets.all(AppSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Всего ~${plan.totalLabel}',
                      key: const ValueKey('day-plan-total'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('day-plan-start-time'),
                    borderRadius: BorderRadius.circular(AppRadius.capsule),
                    onTap: _pickStartTime,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.s,
                        vertical: AppSpace.xs,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.clock,
                            size: 16,
                            color: palette.onSurfaceMuted,
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Text(
                            '${formatClock(_start)} → '
                            '~${formatClock(estimateFinish(_start, plan))}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'путь ${plan.legs.last.distanceLabel} · '
                'в пути ${formatMinutes(plan.travelMinutes)} · '
                'аудио ${formatMinutes(plan.audioMinutes)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Как в подборке'),
            ),
            ButtonSegment(
              value: true,
              label: Text('Оптимальный'),
            ),
          ],
          selected: {_optimized},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _optimized = selection.first),
        ),
        if (_optimized && saving > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              'Короче на ${formatMinutes(saving)} ходьбы',
              key: const ValueKey('day-plan-saving'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.info,
              ),
            ),
          ),
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            key: const ValueKey('day-plan-from-me'),
            label: const Text('Старт от меня'),
            selected: _fromMe,
            onSelected: (value) => setState(() => _fromMe = value),
          ),
        ),
        if (_fromMe && _startPoint == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              'Позиция неизвестна — путь считается от первой точки',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
          ),
        if (widget.hikingForbidden.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s),
            child: NoticeBanner(
              variant: NoticeBannerVariant.warning,
              icon: LucideIcons.alertTriangle,
              compact: true,
              title:
                  '${widget.hikingForbidden.join(', ')}: пешие маршруты запрещены',
              message:
                  'Часть точек смотрится с воды — время в пути рассчитано '
                  'для лодки.',
            ),
          ),
        const SizedBox(height: AppSpace.s),
        for (var i = 0; i < plan.legs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Row(
              key: ValueKey('day-plan-leg-$i'),
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
                      if (i > 0 || _startPoint != null)
                        if (plan.legs[i].travelMinutes > 0 ||
                            plan.legs[i].travelMeters > 0)
                          Text(
                            '${plan.legs[i].distanceLabel} · '
                            '${formatMinutes(plan.legs[i].travelMinutes)} '
                            '${plan.legs[i].isBoat ? 'на воде' : 'пешком'}',
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
        const SizedBox(height: AppSpace.s),
        FilledButton.icon(
          key: const ValueKey('day-plan-open-first'),
          icon: const Icon(LucideIcons.play),
          label: const Text('Открыть первую точку'),
          onPressed: () => _openFirst(plan.legs.first.poi, stops.first.locationId),
        ),
        const SizedBox(height: AppSpace.m),
      ],
    );
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _openFirst(Poi poi, String locationId) {
    // Шторка живёт в шелл-навигаторе, детали — root-роут над ним:
    // закрываем шторку и пушим из корневого навигатора.
    Navigator.of(context).pop();

    final routerContext = AppRouter.rootNavigatorContext;

    if (routerContext != null) {
      routerContext.push('/poi/${poi.id}?island=$locationId');
    }
  }
}
