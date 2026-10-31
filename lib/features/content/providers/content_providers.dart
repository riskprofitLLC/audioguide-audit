import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/data/map_data_repository.dart';
import '../../poi/models/poi.dart';
import '../../poi/utils/poi_sort.dart';
import '../../trails/models/trail.dart';
import '../models/manifest.dart';
import '../models/region_catalog.dart';
import '../services/content_loader.dart';
import '../services/markdown_blocks.dart';
import '../services/photo_credits.dart';


/// Текущий выбранный регион.
///
/// Меняется в переключателе регионов на главном экране. При смене
/// региона текущая локация выставляется на первую локацию региона.
final currentRegionIdProvider =
    StateProvider<String>((ref) {
  return kRegionIds.first;
});


/// Текущая выбранная локация (офлайн-пакет).
///
/// Острова (Гемилер, Караджаорен, Кекова) и прибрежные зоны (bay) —
/// все они теперь локации внутри регионов. Меняется переключателем
/// локаций на главном экране или переключателем регионов (тогда —
/// на первую локацию региона). Все контентные провайдеры следят
/// за этим состоянием.
final currentIslandIdProvider =
    StateProvider<String>((ref) {
  return kLocationIds.first;
});


/// Список доступных локаций (id пакетов).
///
/// Мёртвый islandIdsProvider удалён (Q1): нигде не читался,
/// все потребители берут kLocationIds напрямую.


/// Провайдер текущего региона (объект каталога).
final currentRegionProvider =
    Provider<Region>((ref) {
  return regionById(ref.watch(currentRegionIdProvider));
});


/// id локаций текущего региона (в порядке каталога).
final currentRegionLocationIdsProvider =
    Provider<List<String>>((ref) {
  return ref.watch(currentRegionProvider).locationIds;
});


/// Манифесты всех регионов.
final regionsProvider =
    FutureProvider<List<Manifest>>((ref) async {

  const loader = ContentLoader();

  return Future.wait(
    kRegionIds.map(
      (id) => loader.loadManifest(
        '${regionAssetBase(id)}/manifest.json',
      ),
    ),
  );
});


/// Манифест конкретного региона.
final regionManifestFamily =
    FutureProvider.family<Manifest, String>((
      ref,
      regionId,
    ) async {

  return const ContentLoader().loadManifest(
    '${regionAssetBase(regionId)}/manifest.json',
  );
});


/// Манифест текущего региона.
final regionContentProvider =
    FutureProvider<Manifest>((ref) async {

  final regionId = ref.watch(currentRegionIdProvider);

  return ref.watch(regionManifestFamily(regionId).future);
});


/// Манифесты локаций текущего региона (в порядке каталога).
final regionLocationsProvider =
    FutureProvider<List<Manifest>>((ref) async {

  const loader = ContentLoader();

  final ids = ref.watch(currentRegionLocationIdsProvider);

  return Future.wait(
    ids.map(
      (id) => loader.loadManifest(
        '${locationAssetBase(id)}/manifest.json',
      ),
    ),
  );
});


/// Манифесты всех доступных локаций.
///
/// Используется в переключателе локаций на главном экране
/// (название + версия каждого пакета).
final islandsProvider =
    FutureProvider<List<Manifest>>((ref) async {

  const loader = ContentLoader();

  final manifests = await Future.wait(
    kLocationIds.map(
      (id) => loader.loadManifest(
        '${locationAssetBase(id)}/manifest.json',
      ),
    ),
  );

  return manifests;
});


/// Манифест конкретной локации (острова).
final islandManifestFamily =
    FutureProvider.family<Manifest, String>((
      ref,
      islandId,
    ) async {

  return const ContentLoader().loadManifest(
    '${locationAssetBase(islandId)}/manifest.json',
  );
});


/// Манифест текущей локации.
///
/// Локация выбирается по [currentIslandIdProvider].
final islandContentProvider =
    FutureProvider<Manifest>((ref) async {

  final islandId =
      ref.watch(currentIslandIdProvider);

  return ref.watch(
    islandManifestFamily(islandId).future,
  );
});




/// Репозиторий данных конкретной локации.
final mapDataRepositoryFamily =
    Provider.family<MapDataRepository, String>((
      ref,
      islandId,
    ) {
  return MapDataRepository(
    islandId: islandId,
  );
});




/// Список точек интереса конкретной локации.
final poisFamily =
    FutureProvider.family<List<Poi>, String>((
      ref,
      islandId,
    ) async {
  return ref
      .watch(mapDataRepositoryFamily(islandId))
      .loadPois();
});


/// Список точек интереса текущей локации.
final poisProvider =
    FutureProvider<List<Poi>>((ref) async {

  final islandId =
      ref.watch(currentIslandIdProvider);

  return ref.watch(poisFamily(islandId).future);
});


/// Список маршрутов конкретной локации.
final trailsFamily =
    FutureProvider.family<List<Trail>, String>((
      ref,
      islandId,
    ) async {
  return ref
      .watch(mapDataRepositoryFamily(islandId))
      .loadTrails();
});


/// Список маршрутов текущей локации.
final trailsProvider =
    FutureProvider<List<Trail>>((ref) async {

  final islandId =
      ref.watch(currentIslandIdProvider);

  return ref.watch(trailsFamily(islandId).future);
});


/// Полный текст достопримечательности из `text/NN - Title.md`.
///
/// Загружает длинное описание POI из отдельного markdown-файла
/// в пакете локации. В `poi.json` хранится только короткое
/// описание (первые абзацы), а здесь — весь текст целиком.
/// Возвращает `null`, если файла нет.
final poiFullTextProvider =
    FutureProvider.family<String?, ({String islandId, String poiId})>((
      ref,
      args,
    ) async {

  final pois =
      await ref.watch(poisFamily(args.islandId).future);

  final folderNumber =
      folderNumberFor(args.poiId, pois);

  if (folderNumber == 0) {
    return null;
  }

  return ref
      .watch(mapDataRepositoryFamily(args.islandId))
      .loadPoiFullText(folderNumber);
});


/// Полный текст POI СТРУКТУРОЙ блоков (B3.4, 8-й проход):
/// подзаголовки, списки, инлайновая типографика.
final poiFullBlocksProvider =
    FutureProvider.family<List<MdBlock>?, ({String islandId, String poiId})>((
      ref,
      args,
    ) async {

  final pois =
      await ref.watch(poisFamily(args.islandId).future);

  final folderNumber =
      folderNumberFor(args.poiId, pois);

  if (folderNumber == 0) {
    return null;
  }

  return ref
      .watch(mapDataRepositoryFamily(args.islandId))
      .loadPoiFullBlocks(folderNumber);
});

/// Атрибуция фото локации (credits.json, A9 8-й проход).
///
/// Кеш на сессию: файлы крошечные, читаются один раз. Отсутствие
/// файла — пустая карта (подписи просто не показываются).
final photoCreditsFamily =
    FutureProvider.family<Map<String, PhotoCredit>, String>((
      ref,
      islandId,
    ) async {
  return const PhotoCreditsLoader().load(
    islandId,
    locationAssetBase(islandId),
  );
});
