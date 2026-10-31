import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/utils/plural.dart';

import '../../../content/models/region_catalog.dart';
import '../../../content/providers/content_providers.dart';
import '../../../poi/utils/poi_category.dart';
import '../../models/user_collection.dart';
import '../../providers/collections_providers.dart';

/// Секция «Подборки» на странице избранного (П8, 12-й проход):
/// горизонтальный рельс готовых (из манифестов регионов) и своих
/// подборок + карточка «Создать».
class CollectionsRail extends ConsumerWidget {
  const CollectionsRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final userCollections = ref.watch(userCollectionsProvider);

    final presetsAsync = ref.watch(presetCollectionsProvider);

    // Пресеты, скрытые пользователем значком на карточке, не показываем.
    final hiddenPresets = ref.watch(hiddenPresetCollectionsProvider);

    final presets = (presetsAsync.value ?? const [])
        .where((p) => !hiddenPresets.contains(p.name))
        .toList();

    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Мои подборки',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          'Свои списки точек по смыслу. Точку добавляет кнопка '
          '«В подборку» на её странице.',
          style: theme.textTheme.bodySmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
        ),
        const SizedBox(height: AppSpace.xs),
        // D1 (замечание Sonnet): без фиксированной высоты 142 — рельс
        // растёт по контенту: при textScale 1.6 двухстрочный
        // заголовок переполнял карточку. IntrinsicHeight + stretch
        // держат карточки ряда одной высоты (по самой высокой).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final preset in presets)
                  _CollectionCard(
                    icon: LucideIcons.map,
                    title: preset.name,
                    count: preset.keys.length,
                    coverKeys: preset.keys,
                    isPreset: true,
                    onTap: () => _openCollectionSheet(
                      context,
                      title: preset.name,
                      keys: preset.keys.toList(),
                      userCollection: null,
                    ),
                    // Пресет «от авторов» тоже можно убрать с глаза —
                    // значок скрывает его локально (с отменой в плашке).
                    onHide: () => _hidePreset(context, ref, preset.name),
                  ),
                for (final collection in userCollections)
                  _CollectionCard(
                    icon: LucideIcons.listTodo,
                    title: collection.name,
                    count: collection.keys.length,
                    coverKeys: collection.keys.toList(),
                    isPreset: false,
                    onTap: () => _openCollectionSheet(
                      context,
                      title: collection.name,
                      keys: collection.keys.toList(),
                      userCollection: collection,
                    ),
                    // Явный значок удаления на карточке — без
                    // всплывающего окна, сразу + «Отменить» в плашке.
                    onDelete: () => _deleteCollection(
                      context,
                      ref,
                      collection,
                    ),
                  ),
                _CreateCollectionCard(
                  onTap: () => _createAndOpen(context, ref),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Создание подборки без всплывающего окна: сразу с авто-именем
  /// «Подборка N», шторка открывается для наполнения; имя можно
  /// поменять прямо в шторке (поле названия).
  void _createAndOpen(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(userCollectionsProvider.notifier);

    final id = notifier.createDefault();

    final created = ref
        .read(userCollectionsProvider)
        .where((c) => c.id == id)
        .firstOrNull;

    if (created != null && context.mounted) {
      _openCollectionSheet(
        context,
        title: created.name,
        keys: const [],
        userCollection: created,
      );
    }
  }

  /// Удаление СВОЕЙ подборки по значку: сразу, без подтверждающего
  /// окна — отменить можно в плашке SnackBar.
  void _deleteCollection(
    BuildContext context,
    WidgetRef ref,
    UserCollection collection,
  ) {
    final notifier = ref.read(userCollectionsProvider.notifier);

    notifier.remove(collection.id);

    showAppSnackBar(
      context,
      'Подборка удалена',
      actionLabel: 'Отменить',
      onAction: () => notifier.restore(collection),
    );
  }

  /// Сокрытие пресета «от авторов» по значку: сразу, без окна;
  /// вернуть — «Показать снова» в плашке.
  void _hidePreset(BuildContext context, WidgetRef ref, String name) {
    final notifier = ref.read(hiddenPresetCollectionsProvider.notifier);

    notifier.hide(name);

    showAppSnackBar(
      context,
      'Подборка скрыта',
      actionLabel: 'Показать снова',
      onAction: () => notifier.show(name),
    );
  }
}

/// Карточка подборки в рельсе.
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.coverKeys,
    required this.isPreset,
    required this.onTap,
    this.onDelete,
    this.onHide,
  });

  final IconData icon;

  final String title;

  final int count;

  /// Ключи точек подборки (для обложки B4).
  final List<String> coverKeys;

  /// Пресет региона — только чтение, с бейджем «от авторов».
  final bool isPreset;

  final VoidCallback onTap;

  /// Значок удаления в углу карточки (свои подборки).
  final VoidCallback? onDelete;

  /// Значок сокрытия в углу карточки (пресеты «от авторов»).
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final card = AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.s),
      child: SizedBox(
        width: 156,
        child: Stack(
          children: [
            Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Мини-обложка (B4): первое фото первой точки;
            // нет фото — глиф категории на бумаге. У пресетов поверх
            // обложки — бейдж «от авторов», чтобы не путать со своими.
            Stack(
              children: [
                _CollectionCover(
                  icon: icon,
                  itemKey: coverKeys.isNotEmpty ? coverKeys.first : null,
                ),
                if (isPreset)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surfaceRaised.withValues(alpha: 0.92),
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: palette.sand, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          'от авторов',
                          style: AppText.badge.copyWith(
                            color: palette.onSurfaceMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            // Подпись прижата к низу карточки — ряд одной
            // высоты (IntrinsicHeight над рельсом).
            const Spacer(),
            const SizedBox(height: AppSpace.xs),
            Text(
              '$count ${pluralRu(count, 'точка', 'точки', 'точек')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
          ],
            ),
            // Явный значок в углу карточки: отдельная tap-цель поверх
            // карточки, без всплывающих окон. Свои — удалить (trash2),
            // пресеты — скрыть (eyeOff).
            if (onDelete != null || onHide != null)
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  button: true,
                  label: onDelete != null
                      ? 'Удалить подборку «$title»'
                      : 'Скрыть подборку «$title»',
                  child: Tooltip(
                    message: onDelete != null
                        ? 'Удалить подборку'
                        : 'Скрыть подборку',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: onDelete ?? onHide,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.sand, width: 1),
                        ),
                        child: Icon(
                          onDelete != null
                              ? LucideIcons.trash2
                              : LucideIcons.eyeOff,
                          size: 16,
                          color: onDelete != null
                              ? theme.colorScheme.error
                              : palette.onSurfaceMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.xs),
      child: card,
    );
  }
}

/// Обложка карточки подборки (B4): фото первой точки, иначе
/// глиф категории на sandLight.
class _CollectionCover extends ConsumerWidget {
  const _CollectionCover({required this.icon, required this.itemKey});

  final IconData icon;

  final String? itemKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    Widget fallback = Container(
      height: 52,
      decoration: BoxDecoration(
        color: palette.sandLight,
        borderRadius: BorderRadius.circular(AppRadius.thumb),
        border: Border.all(color: palette.sand, width: 1),
      ),
      child: Icon(icon, size: 20, color: palette.info),
    );

    final key = itemKey;

    if (key == null || !key.contains('/')) {
      return fallback;
    }

    final separator = key.indexOf('/');
    final locationId = key.substring(0, separator);
    final poiId = key.substring(separator + 1);

    final poi = ref
        .watch(poisFamily(locationId))
        .value
        ?.where((p) => p.id == poiId)
        .firstOrNull;

    if (poi == null || poi.imagePaths.isEmpty) {
      // Глиф категории (B4) — POI без фото.
      final glyph = poi?.category != null
          ? poiCategoryGlyph(poi!.category!)
          : null;

      if (glyph != null) {
        fallback = Container(
          height: 52,
          decoration: BoxDecoration(
            color: palette.sandLight,
            borderRadius: BorderRadius.circular(AppRadius.thumb),
            border: Border.all(color: palette.sand, width: 1),
          ),
          child: Center(
            child: Image.asset(
              glyph,
              width: 22,
              height: 22,
              color: palette.info,
              colorBlendMode: BlendMode.srcIn,
              errorBuilder: (_, _, _) =>
                  Icon(icon, size: 20, color: palette.info),
            ),
          ),
        );
      }

      return fallback;
    }

    final asset = '${locationAssetBase(locationId)}/images/${poi.imagePaths.first}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.thumb),
      child: Image.asset(
        asset,
        height: 52,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Карточка «Создать» в конце рельса.
class _CreateCollectionCard extends StatelessWidget {
  const _CreateCollectionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.m),
      child: SizedBox(
        width: 108,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.plus,
              size: 20,
              color: palette.info,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Создать',
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шторка коллекции: список её точек (П8). Свои коллекции
/// позволяют удалять точки; пресеты — только просмотр.
Future<void> _openCollectionSheet(
  BuildContext context, {
  required String title,
  required List<String> keys,
  required UserCollection? userCollection,
}) {
  return showAppBottomSheet(
    context,
    title: title,
    maxHeightFactor: 0.85,
    builder: (sheetContext) => _CollectionSheetBody(
      initialKeys: keys,
      userCollection: userCollection,
    ),
  );
}

/// Тело шторки коллекции.
///
/// A3: СВОЯ подборка читается из провайдера по id — кнопка
/// «Убрать из подборки» обновляет список сразу, без закрытия
/// шторки. Пресет — статичен (ключи из манифеста).
class _CollectionSheetBody extends ConsumerStatefulWidget {
  const _CollectionSheetBody({
    required this.initialKeys,
    required this.userCollection,
  });

  /// Ключи на момент открытия (для пресетов — единственный
  /// источник, для своих — стартовое значение до провайдера).
  final List<String> initialKeys;

  final UserCollection? userCollection;

  @override
  ConsumerState<_CollectionSheetBody> createState() =>
      _CollectionSheetBodyState();
}

class _CollectionSheetBodyState extends ConsumerState<_CollectionSheetBody> {
  /// Последняя убранная точка — для баннера «Отменить» (SnackBar
  /// поверх модальной шторки не тапается — hit-test уходит в лист).
  String? _removedKey;

  @override
  Widget build(BuildContext context) {
    // Реактивные ключи своей коллекции (A3).
    var keys = widget.initialKeys;

    var liveCollection = widget.userCollection;

    final own = widget.userCollection;

    if (own != null) {
      liveCollection = ref
          .watch(userCollectionsProvider)
          .where((c) => c.id == own.id)
          .firstOrNull;

      keys = liveCollection?.keys.toList() ?? const [];
    }

    // Локальная копия для замыканий (Dart не сужает nullable в них).
    final ownCollection = liveCollection;

    // Точка вернулась в подборку извне — баннер отмены гасим.
    final removedKey = _removedKey;
    if (removedKey != null && keys.contains(removedKey)) {
      _removedKey = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_removedKey != null && ownCollection != null)
          _UndoBanner(
            onUndo: () {
              ref
                  .read(userCollectionsProvider.notifier)
                  .toggleItem(ownCollection.id, _removedKey!);
              setState(() => _removedKey = null);
            },
          ),
        // Своя подборка — название правится прямо здесь, без диалога.
        if (ownCollection != null)
          _CollectionNameField(collection: ownCollection),
        for (final key in keys)
          _CollectionRow(
            itemKey: key,
            userCollection: ownCollection,
            onRemoved: ownCollection == null
                ? null
                : (itemKey) {
                    ref
                        .read(userCollectionsProvider.notifier)
                        .toggleItem(ownCollection.id, itemKey);
                    setState(() => _removedKey = itemKey);
                  },
          ),
        if (keys.isEmpty)
          StatePlaceholder(
            icon: LucideIcons.listTodo,
            title: widget.userCollection != null ? 'Пока пусто' : 'Подборка пуста',
            description: 'Добавляйте точки кнопкой «В подборку» '
                'на странице достопримечательности',
            compact: true,
          ),
        // Футер СВОЕЙ подборки: переименовать/удалить. У пресетов
        // подборку менять нельзя — футера нет.
        if (ownCollection != null) ...[
          _CollectionSheetFooter(collection: ownCollection),
        ],
      ],
    );
  }
}

/// Баннер отмены удаления точки внутри шторки подборки.
class _UndoBanner extends StatelessWidget {
  const _UndoBanner({required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.sandLight,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(color: palette.sand, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s,
            vertical: 4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Убрано из подборки',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.onSurface,
                      ),
                ),
              ),
              TextButton(
                onPressed: onUndo,
                child: const Text('Отменить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Футер шторки СВОЕЙ подборки: «Удалить подборку» — сразу, без
/// подтверждающего окна (отмена — в плашке). У пресетов футера нет.
class _CollectionSheetFooter extends ConsumerWidget {
  const _CollectionSheetFooter({required this.collection});

  final UserCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.s),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              final notifier = ref.read(userCollectionsProvider.notifier);

              notifier.remove(collection.id);

              // Шторка удалённой подборки больше не нужна — закрываем.
              Navigator.of(context).pop();

              showAppSnackBar(
                context,
                'Подборка удалена',
                actionLabel: 'Отменить',
                onAction: () => notifier.restore(collection),
              );
            },
            icon: Icon(LucideIcons.trash2, size: 16, color: errorColor),
            label: Text(
              'Удалить подборку',
              style: TextStyle(color: errorColor),
            ),
          ),
        ),
      ],
    );
  }
}

/// Поле названия своей подборки прямо в шторке — переименование
/// без отдельного диалогового окна.
class _CollectionNameField extends ConsumerStatefulWidget {
  const _CollectionNameField({required this.collection});

  final UserCollection collection;

  @override
  ConsumerState<_CollectionNameField> createState() =>
      _CollectionNameFieldState();
}

class _CollectionNameFieldState extends ConsumerState<_CollectionNameField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.collection.name);

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  void _apply() {
    final name = _controller.text.trim();

    if (name.isNotEmpty) {
      ref.read(userCollectionsProvider.notifier).rename(
            widget.collection.id,
            name,
          );
    } else {
      // Пустое имя не принимаем — возвращаем прежнее.
      _controller.text = widget.collection.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: TextField(
        controller: _controller,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Название подборки',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _apply(),
        onEditingComplete: _apply,
      ),
    );
  }
}

/// Строка точки в коллекции.
class _CollectionRow extends ConsumerWidget {
  const _CollectionRow({
    required this.itemKey,
    required this.userCollection,
    this.onRemoved,
  });

  final String itemKey;

  final UserCollection? userCollection;

  /// Уведомление об удалении точки (шторка показывает баннер отмены).
  final void Function(String itemKey)? onRemoved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    // Ключ без '/' (битые данные) не должен ронять шторку (A3).
    final separator = itemKey.indexOf('/');

    if (separator <= 0 || separator == itemKey.length - 1) {
      return const SizedBox.shrink();
    }

    final locationId = itemKey.substring(0, separator);
    final poiId = itemKey.substring(separator + 1);

    final poi = ref
        .watch(poisFamily(locationId))
        .value
        ?.where((p) => p.id == poiId)
        .firstOrNull;

    final title = poi?.title ?? 'Точка недоступна';

    final locationName = ref
            .watch(islandsProvider)
            .value
            ?.where((m) => m.id == locationId)
            .firstOrNull
            ?.name ??
        locationId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              onTap: poi == null
                  ? null
                  : () => context.push('/poi/$poiId?island=$locationId'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      locationName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Свою коллекцию можно чистить построчно (П8); удаление
          // обратимое — шторка покажет баннер «Отменить» (SnackBar
          // поверх модальной шторки не тапается).
          if (userCollection != null && onRemoved != null)
            IconButton(
              tooltip: 'Убрать из подборки',
              icon: const Icon(LucideIcons.minus, size: 18),
              onPressed: () => onRemoved!(itemKey),
            ),
        ],
      ),
    );
  }
}

/// Шторка «В подборку» на странице POI (П8, 12-й проход): свои
/// коллекции с членством этой точки + создание новой.
Future<void> showCollectionPicker(
  BuildContext context, {
  required String itemKey,
}) {
  return showAppBottomSheet(
    context,
    title: 'В подборку',
    maxHeightFactor: 0.7,
    builder: (sheetContext) => _CollectionPickerBody(itemKey: itemKey),
  );
}

class _CollectionPickerBody extends ConsumerWidget {
  const _CollectionPickerBody({required this.itemKey});

  final String itemKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final collections = ref.watch(userCollectionsProvider);

    final notifier = ref.read(userCollectionsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final collection in collections)
          _PickerRow(
            name: collection.name,
            checked: collection.keys.contains(itemKey),
            onTap: () => notifier.toggleItem(collection.id, itemKey),
          ),
        if (collections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Text(
              'Своих подборок ещё нет — создайте первую',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
          ),
        const SizedBox(height: AppSpace.xs),
        OutlinedButton.icon(
          // Без диалогового окна: сразу подборка с авто-именем
          // «Подборка N», точка в неё добавляется; имя меняется
          // в шторке подборки.
          onPressed: () {
            final id = notifier.createDefault();

            notifier.toggleItem(id, itemKey);
          },
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Новая подборка'),
        ),
      ],
    );
  }
}


/// Строка коллекции в пикере «В подборку» (П8): галочка-кружок
/// и имя; состояние читается иконкой (ListTile с фоном шторки
/// ронял debug-ассерт про невидимые чернила).
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.name,
    required this.checked,
    required this.onTap,
  });

  final String name;

  final bool checked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 10,
        ),
        child: Row(
          children: [
            Icon(
              checked ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 20,
              color: checked
                  ? theme.colorScheme.primary
                  : palette.onSurfaceMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: checked ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Открывает шторку СВОЕЙ подборки по id (A3: публичный вход —
/// рельс и тесты идут через него; ключи внутри шторки читаются
/// из провайдера реактивно).
Future<void> openCollectionSheetById(
  BuildContext context, {
  required String id,
}) {
  final container = ProviderScope.containerOf(context);

  final collection = container
      .read(userCollectionsProvider)
      .where((c) => c.id == id)
      .first;

  return _openCollectionSheet(
    context,
    title: collection.name,
    keys: collection.keys.toList(),
    userCollection: collection,
  );
}
