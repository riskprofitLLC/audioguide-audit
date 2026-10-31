/// Каталог регионов и локаций.
///
/// Приложение устроено в два уровня:
///   1. Регион — географическая область (залив, архипелаг),
///      со своей офлайн-картой и списком локаций.
///   2. Локация — офлайн-пакет `content/<регион>/<локация>/`
///      со своим манифестом, POI, маршрутами, аудио и фото.
///
/// Файловая структура повторяет вложенность приложения:
/// `content/<region_id>/<location_id>/…`. Список статический,
/// потому что ассеты собираются в приложение на этапе сборки.
///
/// Чтобы добавить регион:
/// 1. Создать `content/<region_id>/` (региональный манифест, карта);
/// 2. Прописать ассеты в `pubspec.yaml`;
/// 3. Добавить регион в [kRegions] со списком [Region.locationIds].
///
/// Чтобы добавить локацию:
/// 1. Создать пакет `content/<region_id>/<location_id>/`;
/// 2. Прописать ассеты пакета в `pubspec.yaml`;
/// 3. Добавить id в [Region.locationIds] нужного региона.
library;

class Region {

  const Region({
    required this.id,
    required this.name,
    required this.locationIds,
  });


  final String id;


  final String name;


  /// id локаций региона в порядке показа.
  final List<String> locationIds;
}


const List<Region> kRegions = [
  Region(
    id: 'fethiye',
    name: 'Залив Фетхие',
    locationIds: ['bay', 'gemiler'],
  ),
  Region(
    id: 'lykia',
    name: 'Ликия',
    locationIds: [
      'coast',
      'kekova',
    ],
  ),
  Region(
    id: 'caria',
    name: 'Кария',
    locationIds: [
      'dalaman',
      'marmaris',
    ],
  ),
  Region(
    id: 'pamphylia',
    name: 'Памфилия',
    locationIds: [
      'demre-finike',
      'finike-antalya',
      'antalya',
    ],
  ),
  Region(
    id: 'kilikia',
    name: 'Киликия',
    locationIds: [
      'antalya-gazipasha',
      'gazipasha-tashuju',
    ],
  ),
  Region(
    id: 'sevastopol',
    name: 'Севастополь',
    locationIds: ['sevastopol'],
  ),
];


/// Все id регионов — выведены из [kRegions].
List<String> get kRegionIds => [for (final region in kRegions) region.id];


/// Все локации (пакеты контента) всех регионов — выведены из
/// [kRegions], чтобы не дублировать источник истины.
List<String> get kLocationIds => [
      for (final region in kRegions) ...region.locationIds,
    ];


Region regionById(String regionId) {
  return kRegions.firstWhere((r) => r.id == regionId);
}


Region regionOfLocation(String locationId) {
  return kRegions.firstWhere(
    (r) => r.locationIds.contains(locationId),
  );
}


/// Параметр `?island=` из глубокой ссылки (`/poi/:id`, `/trail/:id`).
///
/// Неизвестный id (локация удалена из каталога, напр. «karacaoren»
/// из старой ссылки) не должен попадать в контентные провайдеры:
/// `regionOfLocation` бросает StateError, и страница падает серым
/// экраном. Неизвестное значение отбрасывается (→ `null`), страница
/// берёт текущую локацию — как в `MapWidget._syncIslandFromWidget`.
String? sanitizeIslandParam(String? raw) {
  if (raw == null) {
    return null;
  }

  if (!kLocationIds.contains(raw)) {
    return null;
  }

  return raw;
}


/// Пакет локации: `content/<region_id>/<location_id>`.
String locationAssetBase(String locationId) {
  final region = regionOfLocation(locationId);
  return 'content/${region.id}/$locationId';
}


/// Пакет региона: `content/<region_id>`.
String regionAssetBase(String regionId) {
  return 'content/$regionId';
}