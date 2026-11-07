import '../../../features/content/models/region_catalog.dart';
import '../../poi/models/poi.dart';
import '../../poi/utils/poi_sort.dart';

/// Кадры галереи маршрута — фото ТОЛЬКО его точек (P1-3, 7-й
/// проход).
///
/// Раньше галерея маршрута собирала фото ВСЕХ POI локации в
/// порядке poi.json: в «галерею маршрута» попадали фото
/// внемаршрутных точек, а видео и обложка брались только из
/// точек маршрута — hero-тег обложки почти никогда не совпадал
/// с первым кадром, и полёт миниатюры отключался.
///
/// Единая точка для страницы маршрута, шторки маршрута на карте
/// (TrailInfoSheet) и обложки TrailCard на главной: все три
/// считают кадры одинаково.
List<String> trailGalleryImages(
  List<Poi> locationPois,
  String trailId,
) {
  final trailPois = sortPoisForDisplay(
    locationPois.where((p) => p.trailIds.contains(trailId)),
  );

  return [
    for (final poi in trailPois) ...poi.imagePaths,
  ];
}

/// Обложка маршрута (полный путь ассета) — первый кадр
/// [trailGalleryImages]: обложка совпадает с первым кадром
/// галереи, hero-полёт карточка → детали работает всегда,
/// когда у маршрута есть хотя бы одно фото.
String? trailCoverAssetPath(
  List<Poi> locationPois,
  String trailId,
  String locationId,
) {
  final images = trailGalleryImages(locationPois, trailId);

  if (images.isEmpty) {
    return null;
  }

  return '${locationAssetBase(locationId)}/images/${images.first}';
}
