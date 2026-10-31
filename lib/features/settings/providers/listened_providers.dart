import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/providers/audio_player_provider.dart';
import '../../content/providers/content_providers.dart';
import '../../poi/models/poi.dart';
import '../services/app_settings.dart';

/// Множество прослушанных точек: ключи «локация/poiId» (B2.2,
/// 8-й проход).
///
/// Точка считается прослушанной, когда её трек дошёл до 80%.
/// Персист — список ключей в настройках (native SQLite, web
/// localStorage). Никакой геймификации: тонкая полоса прогресса
/// и счётчик, без бейджей.
final listenedSetProvider =
    NotifierProvider<ListenedNotifier, Set<String>>(ListenedNotifier.new);

class ListenedNotifier extends Notifier<Set<String>> {
  static const _key = 'listened_pois';

  @override
  Set<String> build() {
    final raw = AppSettings().read(_key);

    if (raw == null || raw.isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // Битая запись — начинаем с пустого множества.
    }

    return const {};
  }

  void markListened(String islandId, String poiId) {
    final key = '$islandId/$poiId';

    if (state.contains(key)) {
      return;
    }

    state = {...state, key};

    AppSettings().write(
      _key,
      jsonEncode(state.toList(growable: false)),
    );
  }
}

/// Порог прослушанности: 80% трека (B2.2).
const double _listenedThreshold = 0.8;

/// Слежение за прогрессом глобального плеера: отмечает точки
/// «прослушанными», когда их трек дошёл до 80% (B2.2).
///
/// KeepAlive-провайдер читается один раз при старте приложения
/// (`island_guide_app`) и живёт всю сессию: событие обязано
/// прийти и от автогида, и от мини-плеера, и от карточки на
/// странице точки — не только от видимого виджета плеера.
final listenedWatcherProvider = StreamProvider<void>((ref) {
  final service = ref.read(audioPlayerServiceProvider);

  final controller = StreamController<void>.broadcast();

  // Контроллер живёт всю сессию, но обязан закрываться при
  // освобождении провайдера: иначе Sink остаётся открытым.
  ref.onDispose(controller.close);

  // Длительность привязана к файлу (A6, 9-й проход): раньше
  // knownDuration мог остаться от предыдущего трека, и позиция
  // нового ложно превышала порог 80%.
  Duration? knownDuration;

  String? knownDurationFile;

  // Локации, чей пересев снимает негативный кеш ошибок (пункт 5):
  // invalidate(poisFamily) означает «данные снова доступны для
  // честной попытки» (баг 8: вторая попытка обязана сработать).
  final watchedLocations = <String>{};

  // Б12 (замечание Sonnet): сброс при смене файла — синхронно,
  // до stop/setAsset: запаздывающее событие длительности
  // старого файла не должно приписываться новому. Сам сервис
  // уже фильтрует события по ассету, здесь — второй рубеж.
  final fileSub = service.currentFileStream.listen((file) {
    if (file != knownDurationFile) {
      knownDuration = null;
      knownDurationFile = null;
    }
  });

  final durationSub = service.durationStream.listen((duration) {
    if (duration == null) {
      // Смена файла публикует null — длительность прежнего
      // файла больше не актуальна.
      knownDuration = null;
      knownDurationFile = null;
      return;
    }

    knownDuration = duration;

    knownDurationFile = service.currentFile;
  });

  final positionSub = service.positionStream.listen((position) async {
    final file = service.currentFile;

    if (file == null) {
      return;
    }

    final parts = file.split('/');

    if (parts.length >= 3) {
      final location = parts[2];

      if (!watchedLocations.contains(location)) {
        watchedLocations.add(location);

        ref.listen(poisFamily(location), (_, _) {
          // Пересев локации снимает негативный кеш её файлов:
          // недавняя ошибка не блокирует честную повторную попытку.
          _resolveErrorAt.removeWhere(
            (f, _) => f.contains('/$location/'),
          );
        });
      }
    }

    final resolved = await _resolvePlayedPoi(ref, file, loadPois: loadPoisForTest);

    if (resolved == null) {
      return;
    }

    final (_, _, audioMs) = resolved;
    // Длительность привязана к файлу: стрим, не успевший
    // обновиться для нового трека, игнорируется — фолбэк на
    // poi.json (A6).
    final duration = knownDurationFile == file
        ? knownDuration
        : audioMs != null && audioMs > 0
            ? Duration(milliseconds: audioMs)
            : null;

    if (duration == null || duration <= Duration.zero) {
      return;
    }

    if (position < duration * _listenedThreshold) {
      return;
    }

    ref
        .read(listenedSetProvider.notifier)
        .markListened(resolved.$1, resolved.$2);
  });

  controller.onCancel = () async {
    await durationSub.cancel();

    await positionSub.cancel();

    await fileSub.cancel();
  };

  return controller.stream;
});

/// Путь аудио → (локация, poiId, audioMs). Кеш на сессию: путь стабилен.
final Map<String, (String, String, int?)?> _playedPoiCache = {};

/// Негативный кеш ошибок (пункт 5 замечаний Sonnet): _resolvePlayedPoi
/// зовётся на каждый тик позиции (~5/с), при падающей загрузке локации
/// это бесконечные повторные сидинги. Ошибка локации запоминается
/// с TTL — повторные обращения в окно не дёргают провайдер.
final Map<String, DateTime> _resolveErrorAt = {};

/// In-flight резолвы по файлу: тики позиции приходят чаще, чем
/// завершается загрузка — дедупикация, чтобы не плодить параллельные
/// запросы одного файла.
final Map<String, Future<(String, String, int?)?>> _resolveInFlight = {};

/// Окно негативного кеша после ошибки загрузки.
const _resolveErrorTtl = Duration(seconds: 8);

/// Подмена загрузки списка POI (только тесты): глобальные карты
/// и сидинг не задействуются.
@visibleForTesting
Future<List<Poi>> Function(String location)? loadPoisForTest;

/// Публичный вход для тестов: резолв пути аудио с той же кеш-
/// логикой, что и в watcher'е (пункт 5 замечаний Sonnet).
@visibleForTesting
Future<(String, String, int?)?> resolvePlayedPoiForTests(
  String locationId,
  String file,
) async =>
    _resolvePlayedPoiInternal(
      file,
      loadPois: loadPoisForTest ??
          (throw StateError('loadPoisForTest не задан')),
    );

/// Сброс кеша (только тесты): между прогонами глобальная карта
/// не должна протекать из теста в тест.
@visibleForTesting
void debugResetPlayedPoiCache() {
  _playedPoiCache.clear();
  _resolveErrorAt.clear();
  _resolveInFlight.clear();
}

Future<(String, String, int?)?> _resolvePlayedPoi(
  Ref ref,
  String file, {
  Future<List<Poi>> Function(String location)? loadPois,
}) =>
    _resolvePlayedPoiInternal(
      file,
      loadPois: loadPois ??
          (location) => ref.read(poisFamily(location).future),
    );

Future<(String, String, int?)?> _resolvePlayedPoiInternal(
  String file, {
  required Future<List<Poi>> Function(String location) loadPois,
}) async {
  if (_playedPoiCache.containsKey(file)) {
    return _playedPoiCache[file];
  }

  // Негативный кеш: недавняя ошибка — не ретраим каждый тик.
  final erroredAt = _resolveErrorAt[file];

  if (erroredAt != null &&
      DateTime.now().difference(erroredAt) < _resolveErrorTtl) {
    return null;
  }

  final inFlight = _resolveInFlight[file];

  if (inFlight != null) {
    return inFlight;
  }

  final future = _resolvePlayedPoiUncached(file, loadPois: loadPois);

  _resolveInFlight[file] = future;

  try {
    return await future;
  } finally {
    // remove отдаёт Future — значение намеренно игнорируется.
    _resolveInFlight.remove(file)?.ignore();
  }
}

Future<(String, String, int?)?> _resolvePlayedPoiUncached(
  String file, {
  required Future<List<Poi>> Function(String location) loadPois,
}) async {

  final parts = file.split('/');

  // content/<регион>/<локация>/audio/<audioPath…>
  if (parts.length < 5 || parts[0] != 'content' || parts[3] != 'audio') {
    return _playedPoiCache[file] = null;
  }

  final location = parts[2];

  // Баг 8 (замечания Sonnet): ошибка/отсутствие данных локации —
  // НЕ «точка не найдена». null кешировался ДО конца сессии, и
  // точка больше не отмечалась прослушанной. Кешируем только
  // успешный резолв (в т.ч. честное «нет такой точки в
  // ЗАГРУЖЕННОМ списке»).
  final List<Poi> pois;

  try {
    pois = await loadPois(location);
  } catch (_) {
    // Пункт 5: запоминаем момент ошибки — в окно TTL тики позиции
    // не перезапускают загрузку (дедуп in-flight выше).
    _resolveErrorAt[file] = DateTime.now();

    return null;
  }

  for (final poi in pois) {
    if (poi.audioPath != null &&
        poi.audioAssetPath(location) == file) {
      return _playedPoiCache[file] = (location, poi.id, poi.audioMs);
    }
  }

  return _playedPoiCache[file] = null;
}
