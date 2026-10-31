import 'dart:convert';

/// Пользовательская подборка (П8, 12-й проход): имя + ключи
/// «локация/poiId». Хранится в настройках одним JSON-блобом
/// (как «прослушано») — native SQLite / web localStorage.
class UserCollection {
  const UserCollection({
    required this.id,
    required this.name,
    required this.keys,
  });

  /// Стабильный идентификатор (метка времени создания).
  final String id;

  final String name;

  /// Ключи точек — тот же формат, что и в избранном.
  final Set<String> keys;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'keys': keys.toList(growable: false),
      };

  static UserCollection fromJson(Map<String, dynamic> json) => UserCollection(
        id: json['id'] as String,
        name: json['name'] as String,
        keys: {
          for (final key in (json['keys'] as List).whereType<String>()) key,
        },
      );

  UserCollection withKeys(Set<String> keys) =>
      UserCollection(id: id, name: name, keys: keys);

  static String encode(List<UserCollection> collections) =>
      jsonEncode([for (final collection in collections) collection.toJson()]);

  static List<UserCollection> decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return const [];
      }

      return [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>)
            UserCollection.fromJson(entry),
      ];
    } catch (_) {
      // Битая запись — начинаем с пустого набора.
      return const [];
    }
  }
}
