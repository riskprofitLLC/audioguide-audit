import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/widgets.dart';
import '../../content/models/manifest.dart';
import '../../content/models/region_catalog.dart';
import '../../content/providers/content_providers.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../../../core/utils/plural.dart';
import '../providers/settings_providers.dart';

/// Открывает шторку настроек (P1-7).
///
/// B2 (10-й проход): каркас — единый AppBottomSheet (ручка,
/// шапка с заголовком, радиус, регистрация в modalSheetOpenCount
/// — пилюля мини-плеера, живущая НАД Navigator'ом, не висит
/// поверх нижних карточек шторки).
Future<void> showSettingsSheet(BuildContext context) {
  return showAppBottomSheet(
    context,
    title: 'Настройки',
    builder: (context) => const SettingsSheet(),
  );
}

/// Тело шторки настроек: автогид, избранное, «О приложении»
/// (каркас — AppBottomSheet).
///
/// Открывается из вкладки «Избранное» (иконка в AppBar) и со
/// строки «Настройки» внизу главной.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final autoGuide = ref.watch(autoGuideModeProvider);

    final themeMode = ref.watch(themeModeProvider);

    // Каркас (ручка/шапка/скролл с нижним отступом над капсулой)
    // — единый AppBottomSheet; здесь только контент.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Автогид (P1-6/B5.4): режимы «Всегда / Предлагать /
        // Выключен». По умолчанию «Предлагать» — не
        // перебивает начатый вручную трек, а предлагает.
                AppCard(
                  padding: const EdgeInsets.all(AppSpace.m),
                  // MergeSemantics НЕ нужен: каждая строка режима —
                  // свой узел Semantics (container) с состоянием
                  // выбора; общий merge убивал бы их различие.
                  child: Semantics(
                    container: true,
                    label: 'Автогид. Запускать аудиогид при входе '
                        'в радиус достопримечательности',
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ExcludeSemantics(
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: palette.sandLight,
                                    borderRadius: BorderRadius.circular(AppRadius.chip),
                                  ),
                                  child: Icon(
                                    LucideIcons.audioLines,
                                    size: 16,
                                    color: palette.info,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  'Автогид',
                                  style: AppText.chip.copyWith(
                                    color: palette.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Что делать при входе в радиус точки: '
                            '«Предлагать» не перебивает начатый вручную '
                            'рассказ, а тихо предлагает соседний',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                              color: palette.onSurfaceMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          for (final (mode, label, hint) in [
                            (
                              AutoGuideMode.always,
                              'Всегда',
                              'запускать рассказ сразу',
                            ),
                            (
                              AutoGuideMode.suggest,
                              'Предлагать',
                              'не перебивать играющий трек',
                            ),
                            (
                              AutoGuideMode.off,
                              'Выключен',
                              'не запускать ничего',
                            ),
                          ])
                            RadioRowTile(
                              semanticLabel: 'Автогид: $label',
                              label: label,
                              hint: hint,
                              selected: autoGuide == mode,
                              onSelect: () => ref
                                  .read(autoGuideModeProvider.notifier)
                                  .setMode(mode),
                            ),
                        ],
                      ),
                  ),
                ),
                const SizedBox(height: AppSpace.m),

                // Тема оформления (D3, замечание Sonnet):
                // светлая / системная / тёмная. Ночная тема
                // включается ТОЛЬКО этим переключателем —
                // автоматически приложение не темнеет.
                AppCard(
                  padding: const EdgeInsets.all(AppSpace.m),
                  child: Semantics(
                    container: true,
                    label: 'Тема оформления приложения',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ExcludeSemantics(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: palette.sandLight,
                                  borderRadius: BorderRadius.circular(AppRadius.chip),
                                ),
                                child: Icon(
                                  LucideIcons.moon,
                                  size: 16,
                                  color: palette.info,
                                ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                'Тема',
                                style: AppText.chip.copyWith(
                                  color: palette.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '«Системная» повторяет настройку телефона; '
                          '«Тёмная» — чернильная ночная тема карт и '
                          'текстов',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                            color: palette.onSurfaceMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        for (final (mode, label, hint) in [
                          (
                            ThemeMode.light,
                            'Светлая',
                            'бумага «Ликийского дневника»',
                          ),
                          (
                            ThemeMode.system,
                            'Системная',
                            'как в настройках телефона',
                          ),
                          (
                            ThemeMode.dark,
                            'Тёмная',
                            'чернильная ночная тема',
                          ),
                        ])
                          RadioRowTile(
                            semanticLabel: 'Тема: $label',
                            label: label,
                            hint: hint,
                            selected: themeMode == mode,
                            onSelect: () => ref
                                .read(themeModeProvider.notifier)
                                .setMode(mode),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.m),

                // Избранное (переехало из AppBar: P1-7).
                AppCard(
                  padding: const EdgeInsets.all(AppSpace.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Избранное',
                        style: AppText.chip.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      OutlinedButton.icon(
                        onPressed: () => _confirmClear(context, ref),
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        label: const Text('Очистить избранное'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.m),

                // Недавние объекты поиска (P2, 6-й проход).
                AppCard(
                  padding: const EdgeInsets.all(AppSpace.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Недавние',
                        style: AppText.chip.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Список последних открытых точек и маршрутов '
                        'в шторке поиска',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: palette.onSurface.withValues(alpha: 0.68),
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(recentItemsProvider.notifier)
                            .clear(),
                        icon: const Icon(LucideIcons.history, size: 16),
                        label: const Text('Очистить недавние'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.m),

                // Источники фото (A9, 8-й проход): атрибуция
                // Wikimedia Commons — краткое изложение по
                // локациям, полные подписи — у каждого фото в
                // полноэкранной галерее.
                const _PhotoCreditsCard(),
                const SizedBox(height: AppSpace.m),

                // О приложении и лицензии данных (P1-7).
                AppCard(
                  padding: const EdgeInsets.all(AppSpace.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'О приложении',
                        style: AppText.chip.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Island Guide — офлайн-гид по островам '
                        'и побережьям Турции.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                          color: palette.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Данные карты © участники OpenStreetMap '
                        '(лицензия ODbL).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                          color: palette.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Фотографии — Wikimedia Commons, по лицензиям '
                        'авторов. Озвучка — синтез речи ru-RU. '
                        'Прогноз погоды — Open-Meteo (CC BY 4.0), '
                        'нужен интернет.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                          color: palette.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.m),
              ],
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Очистить избранное?'),
        content:
            const Text('Все избранные точки и маршруты будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(favoritesControllerProvider.notifier).clearAll();

              Navigator.of(dialogContext).pop();

              // Обычный Navigator.pop, а не go_router: шторка лежит
              // в ближайшем навигаторе (в приложении — шелл-ветка),
              // его и закрываем без привязки к роутеру.
              Navigator.of(context).pop();
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }
}

/// Раздел «Источники фото» (A9, 8-й проход): атрибуция фото из
/// Wikimedia Commons по локациям. Полная подпись каждого фото —
/// в полноэкранной галерее; здесь — сводка по авторам.
class _PhotoCreditsCard extends ConsumerWidget {
  const _PhotoCreditsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final locationManifests =
        ref.watch(islandsProvider).value ?? const <Manifest>[];

    // Сводка: локация → «автор · лицензия» → число фото.
    final sections = <({String location, Map<String, int> credits})>[];

    for (final id in kLocationIds) {
      final credits = ref.watch(photoCreditsFamily(id)).value;

      if (credits == null || credits.isEmpty) {
        continue;
      }

      final byAuthor = <String, int>{};

      for (final credit in credits.values) {
        final key = credit.caption ?? 'Wikimedia Commons';

        byAuthor[key] = (byAuthor[key] ?? 0) + 1;
      }

      final name = locationManifests
          .where((m) => m.id == id)
          .firstOrNull
          ?.name;

      sections.add((
        location: name ?? id,
        credits: byAuthor,
      ));
    }

    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Источники фото',
            style: AppText.chip.copyWith(
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Фотографии — Wikimedia Commons, по лицензиям авторов',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.4,
              color: palette.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: AppSpace.s),
          for (final section in sections) ...[
            Text(
              section.location,
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: palette.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 4),
            for (final entry in section.credits.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${entry.key} — ${entry.value} '
                  '${pluralRu(entry.value, 'фото', 'фото', 'фото')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: palette.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ),
    );
  }
}
