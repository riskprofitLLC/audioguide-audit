/// Сервис стиля карты на нативных платформах.
///
/// maplibre-native принимает стиль как JSON-строку
/// (setStyleJson), поэтому возвращаем её как есть.
library;

final class MapStyleService {

  MapStyleService._();

  static final MapStyleService instance =
      MapStyleService._();


  String styleString(
    String styleJson,
  ) {

    return styleJson;
  }
}
