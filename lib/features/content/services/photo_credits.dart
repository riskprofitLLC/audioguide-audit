import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Атрибуция одного фото из `credits.json` локации (A9, 8-й проход).
///
/// Фото из Wikimedia Commons с лицензиями CC BY / CC BY-SA требуют
/// указания автора и лицензии рядом с изображением. Данные собирает
/// `tool/collect_photo_credits.py`; для фото без найденного
/// источника записи нет — подпись не показываем, ничего не выдумываем.
@immutable
class PhotoCredit {
  const PhotoCredit({
    this.author,
    this.license,
    this.licenseUrl,
    this.title,
    this.page,
  });

  /// Автор (из extmetadata Artist, без HTML).
  final String? author;

  /// Короткое имя лицензии (CC BY-SA 4.0…).
  final String? license;

  /// URL лицензии (Creative Commons…).
  final String? licenseUrl;

  /// Имя файла на Commons (File:…).
  final String? title;

  /// Страница файла на Commons.
  final String? page;

  /// Человекочитаемая подпись для галереи:
  /// «Фото: автор · лицензия».
  String? get caption {
    final authorText = author;
    final licenseText = license;

    final parts = [
      if (authorText != null && authorText.isNotEmpty) authorText,
      if (licenseText != null && licenseText.isNotEmpty) licenseText,
    ];

    if (parts.isEmpty) {
      return null;
    }

    return 'Фото: ${parts.join(' · ')}';
  }

  factory PhotoCredit.fromJson(Map<String, dynamic> json) {
    return PhotoCredit(
      author: json['author'] as String?,
      license: json['license'] as String?,
      licenseUrl: json['licenseUrl'] as String?,
      title: json['title'] as String?,
      page: json['page'] as String?,
    );
  }
}

/// Загружает `credits.json` локации: путь фото → атрибуция.
///
/// Файл маленький (единицы КБ на локацию) и читается один раз
/// за сессию. Отсутствие файла или битый JSON — НЕ ошибка:
/// атрибуции просто нет, приложение работает как раньше.
class PhotoCreditsLoader {
  const PhotoCreditsLoader();

  Future<Map<String, PhotoCredit>> load(String islandId, String assetBase) async {
    try {
      final raw = await rootBundle.loadString('$assetBase/credits.json');

      final json = jsonDecode(raw) as Map<String, dynamic>;

      return {
        for (final entry in json.entries)
          entry.key: PhotoCredit.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      };
    } catch (_) {
      // Нет файла/данных — тихо: без атрибуции (не выдумываем).
      return const {};
    }
  }
}
