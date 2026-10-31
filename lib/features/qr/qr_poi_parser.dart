/// Разбор QR-кода точки аудиогида в роут приложения.
///
/// Печатные QR (tool/gen_qr.py) ведут на
/// `https://audioguide.layero.app/#/poi/poi-08?island=gemiler`.
/// Сканер принимает также голые `#/poi/...` и `/poi/...` —
/// например, при сканировании чужого укороченного стикера.
library;

/// Возвращает роут вида `/poi/poi-08?island=gemiler` для `context.go`
/// или `null`, если в строке нет ссылки на точку аудиогида.
String? parsePoiRouteFromQr(String? raw) {
  if (raw == null) {
    return null;
  }

  var text = raw.trim();

  // Отрезаем всё до '#' (домен сайта прода) — дальше hash-роут.
  final hashIndex = text.indexOf('#');

  if (hashIndex >= 0) {
    text = text.substring(hashIndex + 1);
  }

  final poiIndex = text.indexOf('/poi/');

  if (poiIndex < 0) {
    return null;
  }

  var route = text.substring(poiIndex);

  // Якорь после query не нужен: '/poi/poi-08?island=gemiler#x' → без '#x'.
  final fragIndex = route.indexOf('#');

  if (fragIndex >= 0) {
    route = route.substring(0, fragIndex);
  }

  final segments = route.split('?');

  final path = segments.first;

  final id = path.substring('/poi/'.length);

  if (!RegExp(r'^poi-[\w-]+$').hasMatch(id)) {
    return null;
  }

  // Из query берём только island — остальные параметры не нужны.
  if (segments.length > 1 && segments[1].isNotEmpty) {
    final query = segments[1];

    final islandMatch = RegExp(r'(?:^|&)island=([\w-]+)').firstMatch(query);

    if (islandMatch != null) {
      return '/poi/$id?island=${islandMatch.group(1)}';
    }

    return '/poi/$id';
  }

  return '/poi/$id';
}
