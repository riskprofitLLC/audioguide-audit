/// Сервис доступа к архивам PMTiles на web.
///
/// Ассеты на web отдаются сервером по адресу
/// `assets/<path>`, а протокол `pmtiles://` регистрируется
/// в `web/index.html` через библиотеку pmtiles. Возвращаем
/// абсолютный URL вида `pmtiles://https://host/assets/...`.
library;

import '../../../core/utils/logger.dart';

final class MapTileService {

  MapTileService._();

  static final MapTileService instance =
      MapTileService._();


  final Map<String, String> _cachedUrls = {};


  Future<String> pmtilesUrl(
    String assetPath,
  ) async {

    final cached = _cachedUrls[assetPath];

    if (cached != null) {
      AppLogger.info('[MapTileService] cache hit $assetPath');
      return cached;
    }

    final uri = Uri.base.resolve(
      'assets/$assetPath',
    );

    final url = 'pmtiles://$uri';

    _cachedUrls[assetPath] = url;

    AppLogger.info('[MapTileService] new url for $assetPath -> $url');

    return url;
  }
}
