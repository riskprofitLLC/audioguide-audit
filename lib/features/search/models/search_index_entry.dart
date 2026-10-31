import 'package:flutter/foundation.dart';

/// Тип записи поискового индекса (A10.2, 8-й проход).
enum SearchEntryKind { location, trail, poi }

/// Запись лёгкого поискового индекса локации
/// (`content/<регион>/<локация>/search_index.json`, собирает
/// `tool/build_search_index.py`).
///
/// Поиск читает эти компактные индексы вместо подписки на
/// poisFamily/trailsFamily всех локаций — на native прежняя схема
/// запускала холодный сидинг всех 9 пакетов при первом запросе.
@immutable
class SearchIndexEntry {
  const SearchIndexEntry({
    required this.kind,
    required this.locationId,
    required this.id,
    required this.title,
    required this.subtitle,
    this.number,
    this.category,
    this.lat,
    this.lng,
    this.desc,
  });

  final SearchEntryKind kind;

  /// Локация записи (файл индекса = локация).
  final String locationId;

  final String id;

  final String title;

  /// Путь «регион · локация» для строк результатов.
  final String subtitle;

  /// Номер маршрутной точки (label «N. Название»).
  final int? number;

  final String? category;

  /// Координаты (для «Рядом со мной» и дистанции, B6).
  final double? lat;

  final double? lng;

  /// Короткий фрагмент описания (совпадения «по метаданным»).
  final String? desc;

  /// Отображаемый заголовок: у маршрутных точек — с номером.
  String get displayTitle =>
      number != null ? '$number. $title' : title;

  factory SearchIndexEntry.fromJson(
    String locationId,
    Map<String, dynamic> json,
  ) {
    return SearchIndexEntry(
      kind: switch (json['kind']) {
        'location' => SearchEntryKind.location,
        'trail' => SearchEntryKind.trail,
        _ => SearchEntryKind.poi,
      },
      locationId: locationId,
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      number: (json['number'] as num?)?.toInt(),
      category: json['category'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      desc: json['desc'] as String?,
    );
  }
}
