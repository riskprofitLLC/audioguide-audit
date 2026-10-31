import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/models/manifest.dart';
import '../../content/models/region_catalog.dart';
import '../../content/providers/content_providers.dart';
import '../../settings/services/app_settings.dart';
import '../models/user_collection.dart';

/// Подборки пользователя (П8, 12-й проход): персист одним
/// JSON-блобом в настройках — native SQLite / web localStorage,
/// тот же механизм, что и «прослушано».
final userCollectionsProvider =
    NotifierProvider<UserCollectionsNotifier, List<UserCollection>>(
  UserCollectionsNotifier.new,
);

class UserCollectionsNotifier extends Notifier<List<UserCollection>> {
  static const _key = 'user_collections';

  @override
  List<UserCollection> build() {
    return UserCollection.decode(AppSettings().read(_key));
  }

  void _persist() {
    AppSettings().write(_key, UserCollection.encode(state));
  }

  /// Создаёт подборку с именем; пустые имена и дубликаты имён
  /// не создаются. Возвращает id новой подборки или null.
  String? create(String name) {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    final exists = state.any((c) => c.name == trimmed);

    if (exists) {
      return null;
    }

    final id = 'c${DateTime.now().microsecondsSinceEpoch}';

    state = [
      UserCollection(id: id, name: trimmed, keys: {}),
      ...state,
    ];

    _persist();

    return id;
  }

  /// Удаляет подборку пользователя.
  void remove(String id) {
    state = [
      for (final collection in state)
        if (collection.id != id) collection,
    ];

    _persist();
  }

  /// Возвращает удалённую подборку (для «Отменить» после удаления).
  void restore(UserCollection collection) {
    if (state.any((c) => c.id == collection.id)) {
      return;
    }

    state = [collection, ...state];

    _persist();
  }

  /// Переименовывает подборку; пустое имя и занятое другим
  /// именем отклоняются.
  bool rename(String id, String newName) {
    final trimmed = newName.trim();

    if (trimmed.isEmpty) {
      return false;
    }

    if (state.any((c) => c.id != id && c.name == trimmed)) {
      return false;
    }

    state = [
      for (final collection in state)
        if (collection.id == id)
          UserCollection(id: collection.id, name: trimmed, keys: collection.keys)
        else
          collection,
    ];

    _persist();

    return true;
  }

  /// Создаёт подборку с авто-именем «Подборка N» (без диалога
  /// ввода названия). Возвращает id новой подборки.
  String createDefault() {
    var i = 1;

    while (true) {
      final id = create('Подборка $i');

      if (id != null) {
        return id;
      }

      i++;
    }
  }

  /// Добавляет/убирает точку в подборке.
  void toggleItem(String collectionId, String itemKey) {
    state = [
      for (final collection in state)
        if (collection.id == collectionId)
          collection.withKeys(
            collection.keys.contains(itemKey)
                ? ({...collection.keys}..remove(itemKey))
                : {...collection.keys, itemKey},
          )
        else
          collection,
    ];

    _persist();
  }
}

/// Имена пресет-подборок, скрытых пользователем (значок на
/// карточке пресета). Пресеты живут в манифестах — «удалить» их
/// нельзя, только скрыть локально; персист — JSON-список имён в
/// настройках (как user_collections).
final hiddenPresetCollectionsProvider = NotifierProvider<
    HiddenPresetCollectionsNotifier, Set<String>>(
  HiddenPresetCollectionsNotifier.new,
);

class HiddenPresetCollectionsNotifier extends Notifier<Set<String>> {
  static const _key = 'hidden_preset_collections';

  @override
  Set<String> build() {
    final raw = AppSettings().read(_key);

    if (raw == null || raw.isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return const {};
      }

      return {
        for (final entry in decoded) if (entry is String) entry,
      };
    } catch (_) {
      return const {};
    }
  }

  void _persist() {
    AppSettings().write(_key, jsonEncode(state.toList()));
  }

  /// Скрыть пресет по имени.
  void hide(String name) {
    if (state.contains(name)) {
      return;
    }

    state = {...state, name};

    _persist();
  }

  /// Показать скрытый пресет обратно («Показать снова» из SnackBar).
  void show(String name) {
    if (!state.contains(name)) {
      return;
    }

    state = {...state}..remove(name);

    _persist();
  }
}

/// Готовые подборки из манифестов всех регионов (П8): только
/// чтение, порядок — по каталогу регионов.
final presetCollectionsProvider =
    FutureProvider<List<PresetCollection>>((ref) async {
  final presets = <PresetCollection>[];

  for (final regionId in kRegionIds) {
    final manifest = await ref.watch(regionManifestFamily(regionId).future);

    final collections = manifest.presetCollections;

    if (collections == null) {
      continue;
    }

    presets.addAll(collections);
  }

  return presets;
});
