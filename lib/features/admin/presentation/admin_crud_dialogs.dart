/// Диалоги CRUD админ-панели: создание/удаление локаций и точек,
/// правка метаданных POI. Все операции — одним коммитом в ветку
/// правок через [AdminContentOps]; в приложение попадают после
/// мержа в main и перевыпуска.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../poi/utils/poi_category.dart';
import '../providers/admin_providers.dart';
import '../services/admin_content_crud.dart';
import '../services/admin_content_ops.dart';

AdminContentOps _ops(WidgetRef ref) =>
    AdminContentOps(ref.read(githubContentServiceProvider));

/// Служебный диалог с busy-состоянием: [action] выполняется по «ОК»,
/// при ошибке — снекбар, при успехе — закрытие + снекбар результата.
Future<void> _runCrudAction(
  BuildContext context,
  WidgetRef ref, {
  required String busyText,
  required Future<String> Function() action,
}) async {

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Flexible(child: Text(busyText)),
        ],
      ),
    ),
  ).ignore();

  try {
    final result = await action();

    if (context.mounted) {
      Navigator.of(context).pop();

      showAppSnackBar(context, result);
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();

      showAppSnackBar(context, 'Ошибка: $e');
    }
  }
}

// --- локации ---

/// Диалог новой локации: id (slug) + название.
Future<void> showNewLocationDialog(
  BuildContext context,
  WidgetRef ref,
  String regionId,
  String regionName,
) async {
  final idController = TextEditingController();
  final nameController = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Новая локация в «$regionName»'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: idController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Id (латиница, напр. novaya-buhhta)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Создать'),
        ),
      ],
    ),
  );

  if (ok != true) {
    idController.dispose();
    nameController.dispose();
    return;
  }

  if (!context.mounted) {
    idController.dispose();
    nameController.dispose();
    return;
  }

  final locationId = idController.text.trim();
  final name = nameController.text.trim();

  idController.dispose();
  nameController.dispose();

  if (!isValidLocationId(locationId)) {
    showAppSnackBar(
      context,
      'Id локации: только a-z, 0-9 и дефисы',
    );
    return;
  }

  if (name.isEmpty) {
    showAppSnackBar(context, 'Название не задано');
    return;
  }

  await _runCrudAction(
    context,
    ref,
    busyText: 'Создаю локацию…',
    action: () async {
      await _ops(ref).createLocation(
        regionId: regionId,
        locationId: locationId,
        name: name,
      );

      return 'Локация $locationId создана в ветке правок. '
          'После мержа в main добавь ассеты пакета в pubspec.yaml '
          'и перевыпусти приложение';
    },
  );
}

/// Подтверждение удаления локации со всеми файлами.
Future<void> showDeleteLocationDialog(
  BuildContext context,
  WidgetRef ref,
  String regionId,
  String locationId,
  String locationName,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Удалить локацию «$locationName»?'),
      content: Text(
        'Будет удалён весь пакет content/$regionId/$locationId/ '
        '(тексты, аудио, фото) и запись в каталоге. Действие нельзя '
        'отменить после мержа ветки правок.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.signal,
          ),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );

  if (ok != true || !context.mounted) {
    return;
  }

  await _runCrudAction(
    context,
    ref,
    busyText: 'Удаляю локацию…',
    action: () async {
      await _ops(ref).deleteLocation(
        regionId: regionId,
        locationId: locationId,
      );

      return 'Локация $locationId удалена в ветке правок — '
          'появится в приложении после мержа и перевыпуска';
    },
  );
}

// --- точки (POI) ---

/// Общие поля формы точки: название, категория, координаты, радиус, номер.
class _PoiFormFields {

  _PoiFormFields() {
    category = kPoiCategories.keys.first;
  }

  final titleController = TextEditingController();

  final latController = TextEditingController();

  final lngController = TextEditingController();

  final radiusController = TextEditingController();

  final numberController = TextEditingController();

  String? category;

  void dispose() {
    titleController.dispose();
    latController.dispose();
    lngController.dispose();
    radiusController.dispose();
    numberController.dispose();
  }
}

Widget _poiFormBody(_PoiFormFields fields) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: fields.titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: fields.category,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Категория',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final entry in kPoiCategories.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value.label),
              ),
          ],
          onChanged: (value) {
            fields.category = value;
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: fields.latController,
                decoration: const InputDecoration(
                  labelText: 'Широта',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9.,-]'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: fields.lngController,
                decoration: const InputDecoration(
                  labelText: 'Долгота',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9.,-]'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: fields.radiusController,
                decoration: const InputDecoration(
                  labelText: 'Радиус, м (пусто — 100)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: fields.numberController,
                decoration: const InputDecoration(
                  labelText: 'Номер на маршруте (пусто — нет)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
          ],
        ),
      ],
    );

/// Парсит поля формы; null + снекбар при ошибке ввода.
NewPoiInput? _parsePoiForm(
  BuildContext context,
  _PoiFormFields fields,
) {
  final title = fields.titleController.text.trim();

  if (title.isEmpty) {
    showAppSnackBar(context, 'Название не задано');
    return null;
  }

  double parseCoord(String raw, String label) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));

    if (value == null) {
      throw FormatException('$label: не число «$raw»');
    }

    return value;
  }

  try {
    final lat = parseCoord(fields.latController.text, 'Широта');
    final lng = parseCoord(fields.lngController.text, 'Долгота');

    final radiusRaw = fields.radiusController.text.trim();
    final numberRaw = fields.numberController.text.trim();

    return NewPoiInput(
      title: title,
      latitude: lat,
      longitude: lng,
      radius: radiusRaw.isEmpty ? null : double.tryParse(radiusRaw),
      category: fields.category,
      number: numberRaw.isEmpty ? null : int.tryParse(numberRaw),
    );
  } on FormatException catch (e) {
    showAppSnackBar(context, e.message);
    return null;
  }
}

/// Диалог новой точки в локации.
Future<void> showNewPoiDialog(
  BuildContext context,
  WidgetRef ref,
  String locationId,
  String locationName,
) async {
  final fields = _PoiFormFields();

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Новая точка в «$locationName»'),
      content: SingleChildScrollView(child: _poiFormBody(fields)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Создать'),
        ),
      ],
    ),
  );

  if (ok != true) {
    fields.dispose();
    return;
  }

  if (!context.mounted) {
    fields.dispose();
    return;
  }

  final input = _parsePoiForm(context, fields);

  fields.dispose();

  if (input == null) {
    return;
  }

  await _runCrudAction(
    context,
    ref,
    busyText: 'Создаю точку…',
    action: () async {
      final id = await _ops(ref).createPoi(
        locationId: locationId,
        input: input,
      );

      return 'Точка $id создана в ветке правок — после мержа '
          'заполни текст и фото, переозвучь аудио';
    },
  );
}

/// Диалог правки метаданных точки (из оглавления или шапки редактора).
Future<void> showEditPoiMetaDialog(
  BuildContext context,
  WidgetRef ref,
  String locationId,
  String poiId,
) async {
  final ops = _ops(ref);

  PoiMetaInput meta;

  try {
    meta = await ops.loadPoiMeta(locationId: locationId, poiId: poiId);
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, 'Не удалось загрузить метаданные: $e');
    }
    return;
  }

  if (!context.mounted) {
    return;
  }

  final fields = _PoiFormFields();

  fields.titleController.text = meta.title;
  fields.latController.text = meta.latitude.toString();
  fields.lngController.text = meta.longitude.toString();
  fields.radiusController.text = meta.radius?.toString() ?? '';
  fields.numberController.text = meta.number?.toString() ?? '';
  fields.category = meta.category != null && kPoiCategories.containsKey(meta.category)
      ? meta.category
      : kPoiCategories.keys.first;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Свойства точки $poiId'),
      content: SingleChildScrollView(child: _poiFormBody(fields)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );

  if (ok != true) {
    fields.dispose();
    return;
  }

  if (!context.mounted) {
    fields.dispose();
    return;
  }

  final parsed = _parsePoiForm(context, fields);

  fields.dispose();

  if (parsed == null) {
    return;
  }

  await _runCrudAction(
    context,
    ref,
    busyText: 'Сохраняю свойства…',
    action: () async {
      await ops.updatePoiMeta(
        locationId: locationId,
        poiId: poiId,
        input: PoiMetaInput(
          title: parsed.title,
          latitude: parsed.latitude,
          longitude: parsed.longitude,
          radius: parsed.radius,
          category: parsed.category,
          number: parsed.number,
        ),
      );

      return 'Метаданные $poiId обновлены в ветке правок';
    },
  );
}

/// Подтверждение удаления точки (текст, аудио, фото тоже удаляются).
Future<void> showDeletePoiDialog(
  BuildContext context,
  WidgetRef ref,
  String locationId,
  String poiId,
  String title,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Удалить точку «$title»?'),
      content: const Text(
        'Точка исчезнет из poi.json, вместе с ней — текст, аудио '
        'и фото. Действие нельзя отменить после мержа ветки правок.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.signal,
          ),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );

  if (ok != true || !context.mounted) {
    return;
  }

  await _runCrudAction(
    context,
    ref,
    busyText: 'Удаляю точку…',
    action: () async {
      await _ops(ref).deletePoi(locationId: locationId, poiId: poiId);

      return 'Точка $poiId удалена в ветке правок';
    },
  );
}
