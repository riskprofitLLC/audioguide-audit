/// Запрос отрисованных фич карты в точке — платформенная заглушка.
///
/// На нативных платформах тапы резолвятся через плагинный
/// `queryRenderedFeatures`: там строковые id фич GeoJSON
/// пробрасываются корректно, и метод не имеет гейта
/// «стиль не загружен». Web-реализация нужна только на web.
Future<List<Map<String, dynamic>>> queryMapFeaturesAtPoint(
  double x,
  double y,
  List<String> layerIds,
) async {
  return const [];
}
