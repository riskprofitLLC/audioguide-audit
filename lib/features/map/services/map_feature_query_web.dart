import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Запрос отрисованных фич карты в точке на web — напрямую через
/// JS-API maplibre, в обход плагина.
///
/// Зачем обход: плагинный `queryRenderedFeatures` на web не работает
/// при «грязном» стиле — `map.isStyleLoaded()` возвращает false почти
/// всё время, пока работает пульс подсвеченной точки (`?poi=`):
/// каждый `setPaintProperty` помечает источник слоя перезагрузкой
/// (`_updatedSources`), и гейт плагина отдаёт пустой список. А сам
/// maplibre на запросы фич отвечает корректно — проверка isStyleLoaded
/// нужна только плагину.
///
/// Первичный резолв тапа на web тоже мёртв: maplibre-js отдаёт
/// числовой `id` GeoJSON-фич (строковые «poi-03» превращаются в 0),
/// поэтому payload тапа бесполезен, и свойства фичи (poiId,
/// locationId, point_count) читаются только этим запросом.
///
/// Возвращает список вида `{'properties': {...}}` — как плагинный
/// метод, чтобы общий код резолва тапа не ветвился.
Future<List<Map<String, dynamic>>> queryMapFeaturesAtPoint(
  double x,
  double y,
  List<String> layerIds,
) async {
  final raw = globalContext.getProperty('__maplibreMaps'.toJS);

  if (raw == null || raw.isUndefined) {
    return const [];
  }

  final maps = raw as JSArray<JSAny>;

  // Живая карта — у скрытых (превью в соседней ветке шелла)
  // контейнер сворачивается в 0×0. Превью помечены флагом
  // `_islandGuidePreview` (tagPreviewMapInstance, Б6) — их
  // исключаем и при ненулевой ширине: превью на главой видимой,
  // и запрос тапа уходил в неё вместо полноэкранной карты (баг 15,
  // замечания Sonnet).
  JSObject? map;

  for (var i = 0; i < maps.length; i++) {
    final candidate = maps[i] as JSObject;

    final tagged = candidate.getProperty('_islandGuidePreview'.toJS);

    if (tagged != null &&
        !tagged.isUndefined &&
        tagged.dartify() == true) {
      continue;
    }

    final container =
        candidate.callMethod('getContainer'.toJS) as JSObject?;

    if (container == null) {
      continue;
    }

    final width = container.getProperty('clientWidth'.toJS);

    if (width != null && (width as JSNumber).toDartInt > 0) {
      map = candidate;

      break;
    }
  }

  if (map == null) {
    return const [];
  }

  // Точечный запрос: [[x, y], [x, y]] — как в плагине.
  final geometry = [
    [x, y],
    [x, y],
  ].jsify();

  final options = <String, Object?>{
    'layers': layerIds,
  }.jsify();

  final JSAny? result = map.callMethod<JSAny?>(
    'queryRenderedFeatures'.toJS,
    geometry,
    options,
  );

  if (result == null || result.isUndefined || result.isNull) {
    return const [];
  }

  final features = (result as JSArray<JSAny>).toDart;

  final out = <Map<String, dynamic>>[];

  for (final feature in features) {
    final jsFeature = feature as JSObject;

    final props = jsFeature.getProperty('properties'.toJS);

    if (props == null || props.isUndefined || props.isNull) {
      continue;
    }

    final dartProps = props.dartify();

    if (dartProps is Map) {
      out.add(<String, dynamic>{'properties': dartProps});
    }
  }

  return out;
}
