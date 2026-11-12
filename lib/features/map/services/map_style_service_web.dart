import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../../core/utils/logger.dart';


/// Сервис стиля карты на web.
///
/// maplibre-gl-js воспринимает `styleString` как URL
/// стиля, а не как JSON. Поэтому упаковываем стиль в
/// blob URL, который maplibre загрузит через fetch.
///
/// Кеш по содержимому стиля: при переключении острова
/// создаётся новый blob, старый переиспользуется для
/// повторных загрузок того же стиля.

final class MapStyleService {

  MapStyleService._();

  static final MapStyleService instance =
      MapStyleService._();


  final Map<String, String> _cachedUrls = {};

  /// Ограничиваем кеш чтобы не течь при частых сменах версий.
  static const int _maxCacheSize = 10;


  String styleString(
    String styleJson,
  ) {

    final cached = _cachedUrls[styleJson];

    if (cached != null) {
      AppLogger.info('[MapStyleService] cache hit for style (${styleJson.length} chars)');
      return cached;
    }

    AppLogger.info('[MapStyleService] creating blob url (${styleJson.length} chars)');

    final blob = web.Blob(
      [styleJson.toJS].toJS,
    );

    final url = web.URL.createObjectURL(blob);

    // LRU-очистка: удаляем самый старый при переполнении.
    if (_cachedUrls.length >= _maxCacheSize) {
      final oldestKey = _cachedUrls.keys.first;
      final oldestUrl = _cachedUrls.remove(oldestKey);
      if (oldestUrl != null) {
        web.URL.revokeObjectURL(oldestUrl);
      }
    }

    _cachedUrls[styleJson] = url;

    return url;
  }

  void dispose() {
    for (final url in _cachedUrls.values) {
      web.URL.revokeObjectURL(url);
    }
    _cachedUrls.clear();
  }
}
