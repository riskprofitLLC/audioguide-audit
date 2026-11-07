/// Хранилище избранного на web.
///
/// SQLite на web не работает (нет dart:ffi), поэтому избранное
/// хранится в `localStorage` браузера: ключи переживают
/// перезагрузку страницы и повторный визит. Если localStorage
/// недоступен (приватный режим, отключённые cookie) — работает
/// прежний режим «только в памяти».
library;

import 'dart:convert';

import 'package:web/web.dart' as web;

const String _storageKey = 'island_guide_favorites';

final class FavoritesStore {

  FavoritesStore() {
    _loadFromLocalStorage();
  }


  final Set<String> _ids = {};


  void _loadFromLocalStorage() {

    try {

      final raw = web.window.localStorage.getItem(_storageKey);

      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);

      if (decoded is List) {
        _ids.addAll(decoded.whereType<String>());
      }

    } catch (_) {
      // Битые данные в localStorage — начинаем с пустого набора.
    }
  }


  void _persistToLocalStorage() {

    try {

      web.window.localStorage.setItem(
        _storageKey,
        jsonEncode(_ids.toList()),
      );

    } catch (_) {
      // localStorage недоступен — живём в памяти, как раньше.
    }
  }


  Future<Set<String>> loadFavoriteIds() async {
    return Set.of(_ids);
  }


  Future<void> addFavorite(
    String itemId,
  ) async {
    _ids.add(itemId);
    _persistToLocalStorage();
  }


  Future<void> addFavorites(
    Iterable<String> itemIds,
  ) async {
    _ids.addAll(itemIds);
    _persistToLocalStorage();
  }


  Future<void> removeFavorite(
    String itemId,
  ) async {
    _ids.remove(itemId);
    _persistToLocalStorage();
  }


  Future<void> removeFavorites(
    Iterable<String> itemIds,
  ) async {
    _ids.removeAll(itemIds);
    _persistToLocalStorage();
  }


  Future<void> clearAll() async {
    _ids.clear();
    _persistToLocalStorage();
  }
}
