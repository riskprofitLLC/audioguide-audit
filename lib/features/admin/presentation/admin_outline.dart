/// Оглавление админ-панели: регионы → локации → точки
/// с поиском по всем текстам. Регионы и локации переименовываются
/// инлайн (карандаш → поле → галочка/крестик), без всплывающих окон.
/// Переименования НЕ коммитятся сразу — попадают в очередь правок
/// и уходят на GitHub только по кнопке «Сохранить» в редакторе.
/// Источник точек — лёгкий поисковый индекс (не будит сидинг).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../content/models/region_catalog.dart';
import '../../search/models/search_index_entry.dart';
import '../../search/providers/search_providers.dart';
import '../providers/admin_providers.dart';
import '../services/admin_edit_payload.dart';
import '../services/github_content_service.dart';
import 'admin_crud_dialogs.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Панель-оглавление текстов с поиском. Встраивается слева
/// от редактора (широкие экраны) или в Drawer (узкие).
class AdminOutline extends ConsumerStatefulWidget {

  const AdminOutline({
    super.key,
    required this.currentIslandId,
    required this.currentPoiId,
  });

  final String currentIslandId;

  final String currentPoiId;

  @override
  ConsumerState<AdminOutline> createState() => _AdminOutlineState();
}

class _AdminOutlineState extends ConsumerState<AdminOutline> {

  final _queryController = TextEditingController();

  String _query = '';

  // Раскрытые ветки оглавления. Состояние живёт ЗДЕСЬ, а не в
  // ExpansionTile: ListView выгружает невидимые секции, их локальное
  // состояние умирает, и ветки «сворачиваются обратно».
  final _expandedRegions = <String>{};

  final _expandedLocations = <String>{};

  @override
  void dispose() {

    _queryController.dispose();

    super.dispose();
  }

  // Нормализация запроса: регистр и ё→е.
  String _fold(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е');

  bool _matches(SearchIndexEntry entry, String query) {

    final q = _fold(query);

    if (q.isEmpty) {
      return true;
    }

    return _fold(entry.title).contains(q) ||
        _fold(entry.subtitle).contains(q) ||
        (entry.desc != null && _fold(entry.desc!).contains(q));
  }

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    final indexAsync = ref.watch(searchIndexProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _queryController,
            onChanged: (value) => setState(() {
              _query = value;
            }),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(LucideIcons.search),
              hintText: 'Поиск по всем текстам',
              border: OutlineInputBorder(),
            ),
          ),
        ),

        Expanded(
          child: indexAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Center(
              child: Text('Индекс не загрузился: $e'),
            ),
            data: (entries) {

              // Только точки — редактируются именно тексты POI.
              final pois = entries
                  .where((e) => e.kind == SearchEntryKind.poi)
                  .where((e) => _matches(e, _query))
                  .toList();

              if (pois.isEmpty) {
                return Center(
                  child: Text(
                    'Ничего не найдено',
                    style: AppText.body.copyWith(
                      color: palette.onSurfaceMuted,
                    ),
                  ),
                );
              }

              // Два уровня: регионы → локации (порядок каталога).
              final byRegion = <Region, List<SearchIndexEntry>>{};

              for (final entry in pois) {
                byRegion
                    .putIfAbsent(regionOfLocation(entry.locationId), () => [])
                    .add(entry);
              }

              return ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  for (final regionGroup in byRegion.entries)
                    _RegionSection(
                      region: regionGroup.key,
                      entries: regionGroup.value,
                      currentLocationId: widget.currentIslandId,
                      currentPoiId: widget.currentPoiId,
                      // Ветка текущей точки раскрыта сразу, иначе —
                      // то, что пользователь раскрывал сам.
                      regionExpanded:
                          _expandedRegions.contains(regionGroup.key.id) ||
                              regionGroup.value.any(
                                (e) => e.locationId == widget.currentIslandId,
                              ),
                      onRegionExpansionChanged: (expanded) {
                        // setState нужен: пересоздаваемые секции читают
                        // значения из свежих виджетов, а не из мутации.
                        setState(() {
                          if (expanded) {
                            _expandedRegions.add(regionGroup.key.id);
                          } else {
                            _expandedRegions.remove(regionGroup.key.id);
                          }
                        });
                      },
                      isLocationExpanded: (locationId, isCurrent) =>
                          _expandedLocations.contains(locationId) || isCurrent,
                      onLocationExpansionChanged: (locationId, expanded) {
                        setState(() {
                          if (expanded) {
                            _expandedLocations.add(locationId);
                          } else {
                            _expandedLocations.remove(locationId);
                          }
                        });
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Верхний уровень оглавления: регион с инлайн-переименованием
/// и кнопкой создания локации.
class _RegionSection extends ConsumerWidget {

  const _RegionSection({
    required this.region,
    required this.entries,
    required this.currentLocationId,
    required this.currentPoiId,
    required this.regionExpanded,
    required this.onRegionExpansionChanged,
    required this.isLocationExpanded,
    required this.onLocationExpansionChanged,
  });

  final Region region;

  final List<SearchIndexEntry> entries;

  final String currentLocationId;

  final String currentPoiId;

  // Состояние раскрытия хранится в родителе: ListView выгружает
  // невидимые секции, и локальное состояние ExpansionTile умирает —
  // без этого ветки «сворачиваются обратно» при прокрутке.
  final bool regionExpanded;

  final ValueChanged<bool> onRegionExpansionChanged;

  final bool Function(String locationId, bool isCurrent) isLocationExpanded;

  final void Function(String locationId, bool expanded)
      onLocationExpansionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    // Группировка точек по локации внутри региона.
    final locationGroups = <String, List<SearchIndexEntry>>{};

    for (final entry in entries) {
      locationGroups
          .putIfAbsent(entry.locationId, () => [])
          .add(entry);
    }

    // Порядок POI в оглавлении — как в приложении: по номеру
    // маршрута, затем без номера. Индекс хранит порядок poi.json,
    // а он может расходиться с номерами (было: poi-02 с number=3
    // шёл перед poi-03 с number=2 на Гемилере).
    for (final group in locationGroups.values) {
      group.sort((a, b) {
        if (a.kind == SearchEntryKind.poi && b.kind == SearchEntryKind.poi) {
          return (a.number ?? 1 << 30).compareTo(b.number ?? 1 << 30);
        }

        return 0;
      });
    }

    // Имя региона: до разделителя подзаголовка индекса.
    final regionName = entries.first.subtitle.split('·').first.trim();

    return ExpansionTile(
      dense: true,
      // Ветка текущей точки раскрыта сразу — регион и локация.
      initiallyExpanded: regionExpanded,
      onExpansionChanged: onRegionExpansionChanged,
      title: Row(
        children: [
          Expanded(
            child: _RenameInline(
              title: regionName,
              manifestPath: 'content/${region.id}/manifest.json',
              commitMessage:
                  'Правка названия региона ${region.id} из админ-панели',
            ),
          ),
          IconButton(
            tooltip: 'Добавить локацию',
            icon: const Icon(LucideIcons.plus, size: 18),
            onPressed: () => showNewLocationDialog(
              context,
              ref,
              region.id,
              regionName,
            ),
          ),
        ],
      ),
      children: [
        for (final group in locationGroups.entries)
          _OutlineSection(
            key: ValueKey('outline-loc-${group.key}'),
            header: group.value.first.subtitle.split('·').last.trim(),
            locationId: group.key,
            manifestPath:
                '${locationAssetBase(group.key)}/manifest.json',
            commitMessage:
                'Правка названия локации ${group.key} из админ-панели',
            entries: group.value,
            currentLocationId: currentLocationId,
            currentPoiId: currentPoiId,
            initiallyExpanded:
                isLocationExpanded(group.key, group.key == currentLocationId),
            onExpansionChanged: (expanded) =>
                onLocationExpansionChanged(group.key, expanded),
          ),
      ],
    );
  }
}

class _OutlineSection extends ConsumerStatefulWidget {

  const _OutlineSection({
    super.key,
    required this.header,
    required this.locationId,
    required this.manifestPath,
    required this.commitMessage,
    required this.entries,
    required this.currentLocationId,
    required this.currentPoiId,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
  });

  final String header;

  final String locationId;

  final String manifestPath;

  final String commitMessage;

  final List<SearchIndexEntry> entries;

  final String currentLocationId;

  final String currentPoiId;

  // Раскрытие — из родительского состояния (см. _AdminOutlineState):
  // локальное состояние ExpansionTile умирает при выгрузке секции
  // из ListView, и ветка сворачивалась бы обратно.
  final bool initiallyExpanded;

  final ValueChanged<bool> onExpansionChanged;

  @override
  ConsumerState<_OutlineSection> createState() => _OutlineSectionState();
}

class _OutlineSectionState extends ConsumerState<_OutlineSection> {

  final _renameController = TextEditingController();

  bool _editingName = false;

  bool _savingName = false;

  String? _manifestRaw;

  @override
  void dispose() {

    _renameController.dispose();

    super.dispose();
  }

  Future<void> _startEditing() async {

    // Текущее имя — из манифеста на GitHub.
    final service = ref.read(githubContentServiceProvider);

    String? manifestRaw;

    try {
      manifestRaw = (await service.fetchFile(widget.manifestPath))?.content;
    } catch (_) {
      // нет сети — редактируем от заголовка индекса
    }

    if (!mounted) {
      return;
    }

    _manifestRaw = manifestRaw;

    _renameController.text = _manifestRaw != null
        ? (manifestName(_manifestRaw!) ?? widget.header)
        : widget.header;

    setState(() {
      _editingName = true;
    });
  }

  Future<void> _saveName() async {

    final newName = _renameController.text.trim();

    if (newName.isEmpty) {
      return;
    }

    setState(() {
      _savingName = true;
    });

    final service = ref.read(githubContentServiceProvider);

    try {

      // Манифест мог не прочитаться при входе в правку — читаем сейчас.
      final raw = _manifestRaw ??
          (await service.fetchFile(widget.manifestPath))?.content;

      if (raw == null) {
        throw const GitHubException('Манифест недоступен');
      }

      // Не коммитим — правка уходит в очередь и публикуется кнопкой
      // «Сохранить» в редакторе (единая точка сохранения).
      ref.read(pendingRenamesProvider.notifier).put(
            widget.manifestPath,
            updateManifestName(raw, newName),
          );

      if (mounted) {
        showAppSnackBar(
          context,
          'Название поставлено в очередь — сохрани кнопкой «Сохранить»',
        );
      }
    } catch (e) {

      if (mounted) {
        showAppSnackBar(context, 'Не удалось подготовить правку: $e');
      }
    }

    if (mounted) {
      setState(() {
        _editingName = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return ExpansionTile(
      dense: true,
      // Локация текущей точки раскрыта сразу; далее — состояние из
      // родителя (переживает выгрузку секции из ListView).
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      title: _editingName
          ? Row(
              children: [

                Expanded(
                  child: TextField(
                    controller: _renameController,
                    autofocus: true,
                    style: AppText.body,
                    onSubmitted: (_) => _saveName(),
                  ),
                ),

                if (_savingName)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    tooltip: 'В очередь на сохранение',
                    icon: const Icon(LucideIcons.check, size: 20),
                    onPressed: _saveName,
                  ),

                  IconButton(
                    tooltip: 'Отмена',
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => setState(() {
                      _editingName = false;
                    }),
                  ),
                ],
              ],
            )
          : Row(
              children: [

                Expanded(
                  child: Text(
                    widget.header,
                    style: AppText.body,
                    maxLines: 2,
                  ),
                ),

                // Переименовать — инлайн, без диалога.
                IconButton(
                  tooltip: 'Переименовать',
                  icon: const Icon(LucideIcons.pencil, size: 18),
                  onPressed: () => _startEditing(),
                ),

                IconButton(
                  tooltip: 'Добавить точку',
                  icon: const Icon(LucideIcons.plus, size: 18),
                  onPressed: () => showNewPoiDialog(
                    context,
                    ref,
                    widget.locationId,
                    widget.header,
                  ),
                ),

                IconButton(
                  tooltip: 'Удалить локацию',
                  icon: const Icon(
                    LucideIcons.trash2,
                    size: 18,
                    color: AppColors.signal,
                  ),
                  onPressed: () => showDeleteLocationDialog(
                    context,
                    ref,
                    regionOfLocation(widget.locationId).id,
                    widget.locationId,
                    widget.header,
                  ),
                ),
              ],
            ),
      children: [
        for (final entry in widget.entries)
          _OutlinePoiTile(
            entry: entry,
            selected: entry.id == widget.currentPoiId &&
                entry.locationId == widget.currentLocationId,
          ),
      ],
    );
  }
}

/// Строка точки оглавления: тап — переход в редактор; справа —
/// правка метаданных и удаление точки. Выделенная строка после кадра
/// подводится в видимую область (список длинный, текущая точка может
/// быть за вьюпортом).
class _OutlinePoiTile extends ConsumerWidget {

  const _OutlinePoiTile({required this.entry, required this.selected});

  final SearchIndexEntry entry;

  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final palette = AppPalette.of(context);

    final tile = ListTile(
      dense: true,
      selected: selected,
      contentPadding: const EdgeInsets.only(left: 24, right: 4),
      title: Text(
        entry.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: selected
            ? AppText.body.copyWith(fontWeight: FontWeight.w800)
            : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Свойства точки',
            icon: const Icon(LucideIcons.settings2, size: 16),
            onPressed: () => showEditPoiMetaDialog(
              context,
              ref,
              entry.locationId,
              entry.id,
            ),
          ),
          IconButton(
            tooltip: 'Удалить точку',
            icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.signal),
            onPressed: () => showDeletePoiDialog(
              context,
              ref,
              entry.locationId,
              entry.id,
              entry.displayTitle,
            ),
          ),
        ],
      ),
      onTap: () {
        GoRouter.of(context).go(
          '/admin/poi/${entry.id}?island=${entry.locationId}',
        );
      },
    );

    if (!selected) {
      return tile;
    }

    // Редактируемая точка — заметная плашка: заливка бирюзой
    // + рамка + полоса слева (selected-цвет ListTile на бумажном
    // фоне почти не виден — заголовок «терялся» в списке).
    return _EnsureVisibleAfterExpand(
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 8, top: 2, bottom: 2),
        child: Row(
          children: [

            // Полоса-маркер слева от строки.
            Container(
              width: 3,
              height: 28,
              decoration: BoxDecoration(
                color: palette.info,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),

            Expanded(
              child: Material(
                key: const ValueKey('outline-current-poi'),
                color: palette.info.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  side: BorderSide(
                    color: palette.info.withValues(alpha: 0.45),
                  ),
                ),
                child: tile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// После раскрытия дерева (анимация ExpansionTile ~200 мс)
/// подводит ребёнка в видимую область скролла.
class _EnsureVisibleAfterExpand extends StatefulWidget {

  const _EnsureVisibleAfterExpand({required this.child});

  final Widget child;

  @override
  State<_EnsureVisibleAfterExpand> createState() =>
      _EnsureVisibleAfterExpandState();
}

class _EnsureVisibleAfterExpandState extends State<_EnsureVisibleAfterExpand> {

  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();

    // Ждём конец анимации раскрытия, затем скроллим.
    _revealTimer = Timer(const Duration(milliseconds: 350), _reveal);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();

    super.dispose();
  }

  void _reveal() {
    if (mounted) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        alignment: 0.3,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Инлайн-переименование (регионы): карандаш → поле → галочка/крестик.
/// Правка ставится в очередь [pendingRenamesProvider], коммит —
/// только по кнопке «Сохранить».
class _RenameInline extends ConsumerStatefulWidget {

  const _RenameInline({
    required this.title,
    required this.manifestPath,
    required this.commitMessage,
  });

  final String title;

  final String manifestPath;

  final String commitMessage;

  @override
  ConsumerState<_RenameInline> createState() => _RenameInlineState();
}

class _RenameInlineState extends ConsumerState<_RenameInline> {

  final _controller = TextEditingController();

  bool _editing = false;

  bool _saving = false;

  String? _manifestRaw;

  @override
  void dispose() {

    _controller.dispose();

    super.dispose();
  }

  Future<void> _startEditing() async {

    final service = ref.read(githubContentServiceProvider);

    String? manifestRaw;

    try {
      manifestRaw = (await service.fetchFile(widget.manifestPath))?.content;
    } catch (_) {
      // нет сети — редактируем от заголовка
    }

    if (!mounted) {
      return;
    }

    _manifestRaw = manifestRaw;

    _controller.text = _manifestRaw != null
        ? (manifestName(_manifestRaw!) ?? widget.title)
        : widget.title;

    setState(() {
      _editing = true;
    });
  }

  Future<void> _save() async {

    final newName = _controller.text.trim();

    if (newName.isEmpty) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final service = ref.read(githubContentServiceProvider);

    try {

      final raw = _manifestRaw ??
          (await service.fetchFile(widget.manifestPath))?.content;

      if (raw == null) {
        throw const GitHubException('Манифест недоступен');
      }

      ref.read(pendingRenamesProvider.notifier).put(
            widget.manifestPath,
            updateManifestName(raw, newName),
          );

      if (mounted) {
        showAppSnackBar(
          context,
          'Название поставлено в очередь — сохрани кнопкой «Сохранить»',
        );
      }
    } catch (e) {

      if (mounted) {
        showAppSnackBar(context, 'Не удалось поставить правку: $e');
      }
    }

    if (mounted) {
      setState(() {
        _editing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_editing) {
      return Row(
        children: [

          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: AppText.body,
              onSubmitted: (_) => _save(),
            ),
          ),

          if (_saving)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'В очередь на сохранение',
              icon: const Icon(LucideIcons.check, size: 20),
              onPressed: _save,
            ),

            IconButton(
              tooltip: 'Отмена',
              icon: const Icon(LucideIcons.x, size: 20),
              onPressed: () => setState(() {
                _editing = false;
              }),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [

        Expanded(
          child: Text(
            widget.title,
            style: AppText.body,
            maxLines: 2,
          ),
        ),

        IconButton(
          tooltip: 'Переименовать',
          icon: const Icon(LucideIcons.pencil, size: 18),
          onPressed: _startEditing,
        ),
      ],
    );
  }
}
