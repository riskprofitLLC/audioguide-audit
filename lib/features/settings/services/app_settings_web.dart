import 'dart:convert';

import 'package:web/web.dart' as web;

/// Хранилище настроек (web): `localStorage` — ключи переживают
/// перезагрузку страницы. Если хранилище недоступно (приватный
/// режим), настройки живут только в памяти сессии.
const String _storageKey = 'island_guide_settings';

final class AppSettings {
  Map<String, String>? _cache;

  Map<String, String> _load() {
    final cached = _cache;

    if (cached != null) {
      return cached;
    }

    try {
      final raw = web.window.localStorage.getItem(_storageKey);

      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);

        if (decoded is Map) {
          return _cache = {
            for (final entry in decoded.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
          };
        }
      }
    } catch (_) {
      // Битые данные — начинаем с пустого набора.
    }

    return _cache = <String, String>{};
  }

  String? read(String key) {
    return _load()[key];
  }

  void write(String key, String value) {
    final map = _load();

    map[key] = value;

    _persist(map);
  }

  /// Удаляет ключ (миграции настроек).
  void remove(String key) {
    final map = _load();

    if (map.remove(key) == null) {
      return;
    }

    _persist(map);
  }

  void _persist(Map<String, String> map) {
    try {
      web.window.localStorage.setItem(
        _storageKey,
        jsonEncode(map),
      );
    } catch (_) {
      // localStorage недоступен — настройки только в памяти.
    }
  }
}
