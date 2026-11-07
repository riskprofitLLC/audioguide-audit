import '../../../core/utils/logger.dart';


/// Сервис глифов (шрифта) для текстовых подписей на web.
///
/// Ассеты на web отдаются сервером по адресу
/// `assets/fonts/...`, поэтому возвращаем абсолютный шаблон URL
/// вида `https://host/assets/fonts/{fontstack}/{range}.pbf`.
///
/// Абсолютный URL обязателен: стиль упакован в blob URL, и
/// относительные пути maplibre не смог бы разрешить.
final class MapGlyphsService {

  MapGlyphsService._();

  static final MapGlyphsService instance =
      MapGlyphsService._();


  String glyphsUrl() {

    final base = Uri.base.resolve('assets/fonts/');

    final url = '$base{fontstack}/{range}.pbf';

    AppLogger.info('[MapGlyphsService] glyphs url=$url');

    return url;
  }
}
