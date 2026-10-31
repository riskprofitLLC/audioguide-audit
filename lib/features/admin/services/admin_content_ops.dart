/// Оркестрация CRUD-операций админ-панели поверх [GitHubContentService]:
/// создание/удаление локаций и точек, правка метаданных POI.
///
/// Все изменения уходят одним коммитом в ветку правок `content-edits`
/// (GitHub — единственное хранилище, приложение на Layero не хранит).
/// В приложение правки попадают после мержа в main и перевыпуска.
///
/// Чистые преобразования — в [admin_content_crud.dart].
library;

import '../../content/models/region_catalog.dart';
import 'admin_content_crud.dart';
import 'github_content_service.dart';

/// Параметры новой точки из диалога.
class NewPoiInput {

  const NewPoiInput({
    required this.title,
    required this.latitude,
    required this.longitude,
    this.radius,
    this.category,
    this.number,
  });

  final String title;

  final double latitude;

  final double longitude;

  final double? radius;

  final String? category;

  final int? number;
}

/// Метаданные точки для диалога редактирования.
class PoiMetaInput {

  const PoiMetaInput({
    required this.title,
    required this.latitude,
    required this.longitude,
    this.radius,
    this.category,
    this.number,
  });

  final String title;

  final double latitude;

  final double longitude;

  final double? radius;

  final String? category;

  final int? number;
}

class AdminContentOps {

  AdminContentOps(this._service);

  final GitHubContentService _service;

  String _poiJsonPath(String locationId) =>
      '${locationAssetBase(locationId)}/poi.json';

  String _regionManifestPath(String regionId) =>
      'content/$regionId/manifest.json';

  Future<String> _requireFile(String path) async {
    final file = await _service.fetchFile(path);

    if (file == null) {
      throw GitHubException('Файл недоступен: $path');
    }

    return file.content;
  }

  // --- локации ---

  /// Создаёт локацию: манифест + пустые poi.json/trails.geojson +
  /// запись в манифесте региона + id в Dart-каталоге.
  Future<void> createLocation({
    required String regionId,
    required String locationId,
    required String name,
  }) async {

    if (!isValidLocationId(locationId)) {
      throw const GitHubException(
        'Id локации: только латиница, цифры и дефисы (a-z0-9-)',
      );
    }

    final regionRaw = await _requireFile(_regionManifestPath(regionId));

    final catalogRaw = await _requireFile(kRegionCatalogPath);

    final base = 'content/$regionId/$locationId';

    await _service.commitChanges(
      message: 'Админка: новая локация $locationId ($name)',
      files: [
        GhCommitFile(
          path: _regionManifestPath(regionId),
          content: addLocationToRegionManifest(regionRaw, locationId),
        ),
        GhCommitFile(
          path: kRegionCatalogPath,
          content: addLocationIdToCatalog(catalogRaw, regionId, locationId),
        ),
        GhCommitFile(
          path: '$base/manifest.json',
          content: buildLocationManifestJson(locationId, name),
        ),
        GhCommitFile(path: '$base/poi.json', content: emptyPoiJson),
        GhCommitFile(
          path: '$base/trails.geojson',
          content: emptyTrailsGeoJson(),
        ),
      ],
      deletes: const [],
    );
  }

  /// Удаляет локацию целиком: все файлы пакета + запись в манифесте
  /// региона + id из Dart-каталога.
  Future<void> deleteLocation({
    required String regionId,
    required String locationId,
  }) async {

    final prefix = 'content/$regionId/$locationId/';

    final files = await _service.listTreeFiles(prefix);

    final regionRaw = await _requireFile(_regionManifestPath(regionId));

    final catalogRaw = await _requireFile(kRegionCatalogPath);

    await _service.commitChanges(
      message: 'Админка: удалена локация $locationId',
      files: [
        GhCommitFile(
          path: _regionManifestPath(regionId),
          content: removeLocationFromRegionManifest(regionRaw, locationId),
        ),
        GhCommitFile(
          path: kRegionCatalogPath,
          content: removeLocationIdFromCatalog(catalogRaw, locationId),
        ),
      ],
      deletes: files,
    );
  }

  // --- точки (POI) ---

  /// Создаёт точку: запись в poi.json + стартовый текстовый файл.
  /// Возвращает созданный id (`poi-NN`).
  Future<String> createPoi({
    required String locationId,
    required NewPoiInput input,
  }) async {

    final path = _poiJsonPath(locationId);

    final raw = await _requireFile(path);

    final id = poiIdForNumber(nextPoiIdNumber(raw));

    final poi = buildNewPoi(
      id: id,
      title: input.title,
      latitude: input.latitude,
      longitude: input.longitude,
      radius: input.radius,
      category: input.category,
      number: input.number,
    );

    // Маршрутная точка (есть номер) — текст в way, иначе в no-way.
    final onTrail = input.number != null;

    // Папочный номер новой точки в конце списка.
    final folderNumber = input.number ?? nextFolderNumberForNewPoi(raw);

    final base = locationAssetBase(locationId);

    final textPath =
        '$base/text/${onTrail ? 'way' : 'no-way'}/${poiTextFileName(folderNumber, input.title)}';

    await _service.commitChanges(
      message: 'Админка: новая точка $id (${input.title})',
      files: [
        GhCommitFile(path: path, content: addPoiToJson(raw, poi)),
        GhCommitFile(
          path: textPath,
          content: newPoiTextContent(input.title),
        ),
      ],
      deletes: const [],
    );

    return id;
  }

  /// Метаданные точки для диалога редактирования.
  Future<PoiMetaInput> loadPoiMeta({
    required String locationId,
    required String poiId,
  }) async {

    final raw = await _requireFile(_poiJsonPath(locationId));

    final record = poiRecordFromJson(raw, poiId);

    if (record == null) {
      throw GitHubException('Точка $poiId не найдена в poi.json');
    }

    return PoiMetaInput(
      title: record['title'] as String? ?? poiId,
      latitude: (record['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (record['longitude'] as num?)?.toDouble() ?? 0,
      radius: (record['radius'] as num?)?.toDouble(),
      category: record['category'] as String?,
      number: (record['number'] as num?)?.toInt(),
    );
  }

  /// Обновляет метаданные точки. При смене названия переименовывает
  /// и текстовый файл (`NN - …md`).
  Future<void> updatePoiMeta({
    required String locationId,
    required String poiId,
    required PoiMetaInput input,
  }) async {

    final path = _poiJsonPath(locationId);

    final raw = await _requireFile(path);

    final record = poiRecordFromJson(raw, poiId);

    if (record == null) {
      throw GitHubException('Точка $poiId не найдена в poi.json');
    }

    final fields = <String, Object?>{
      'title': input.title,
      'latitude': input.latitude,
      'longitude': input.longitude,
      'radius': input.radius,
      'category': input.category,
      'number': input.number,
    };

    final files = <GhCommitFile>[
      GhCommitFile(path: path, content: updatePoiJsonFields(raw, poiId, fields)),
    ];

    final deletes = <String>[];

    // Переименование текстового файла при смене названия.
    final oldTitle = record['title'] as String?;

    if (oldTitle != null && oldTitle != input.title) {
      final folderNumber = folderNumberOfPoi(raw, poiId);

      if (folderNumber > 0) {
        final trails = (record['trails'] as List<Object?>? ?? const [])
            .map((e) => '$e')
            .toList();

        final base = locationAssetBase(locationId);

        final subdir = poiTextSubdir(trails);

        final oldPath =
            '$base/text/$subdir/${poiTextFileName(folderNumber, oldTitle)}';

        final newPath =
            '$base/text/$subdir/${poiTextFileName(folderNumber, input.title)}';

        deletes.add(oldPath);

        files.add(
          GhCommitFile(path: newPath, content: newPoiTextContent(input.title)),
        );
      }
    }

    await _service.commitChanges(
      message: 'Админка: правка метаданных $poiId',
      files: files,
      deletes: deletes,
    );
  }

  /// Удаляет точку: запись из poi.json + её файлы (текст по папочному
  /// номеру, аудио/фото по id в пути).
  Future<void> deletePoi({
    required String locationId,
    required String poiId,
  }) async {

    final path = _poiJsonPath(locationId);

    final raw = await _requireFile(path);

    final folderNumber = folderNumberOfPoi(raw, poiId);

    final prefix = '${locationAssetBase(locationId)}/';

    final allFiles = await _service.listTreeFiles(prefix);

    final numPrefix = folderNumber > 0
        ? '${folderNumber.toString().padLeft(2, '0')} - '
        : null;

    bool isPoiFile(String file) {
      if (!file.startsWith(prefix)) {
        return false;
      }

      if (file.contains('/$poiId/') || file.contains('/$poiId.')) {
        return true;
      }

      // Текстовый файл — по имени «NN - …» (имена текстов не содержат id).
      if (numPrefix != null &&
          file.contains('/text/') &&
          file.substring(file.lastIndexOf('/') + 1).startsWith(numPrefix)) {
        return true;
      }

      return false;
    }

    final deletes = allFiles.where(isPoiFile).toList();

    await _service.commitChanges(
      message: 'Админка: удалена точка $poiId',
      files: [
        GhCommitFile(path: path, content: removePoiFromJson(raw, poiId)),
      ],
      deletes: deletes,
    );
  }
}
