import 'dart:math' as math;

import '../models/trail_point.dart';

/// Сводка рельефа маршрута (П5, 12-й проход).
class ElevationStats {
  const ElevationStats({
    required this.minElevation,
    required this.maxElevation,
    required this.ascent,
    required this.descent,
    this.startElevation,
    this.finishElevation,
  });

  /// Минимальная высота трека (метры).
  final double minElevation;

  /// Максимальная высота трека (метры).
  final double maxElevation;

  /// Суммарный подъём (метры) — только восходящие участки.
  final double ascent;

  /// Суммарный спуск (метры) — только нисходящие участки.
  final double descent;

  /// Высота первой точки профиля (D1: метка «Старт»).
  final double? startElevation;

  /// Высота последней точки профиля (D1: метка «Финиш»).
  final double? finishElevation;

  /// Есть ли данные (минимум 2 точки с высотой).
  bool get isEmpty =>
      minElevation.isNaN || maxElevation.isNaN || ascent.isNaN;

  /// Парный геттер для читаемых условий.
  bool get isNotEmpty => !isEmpty;
}

/// Статистика высот по точкам трека (П5).
///
/// Простой случай — сеть из одной ветки; для сети веток см.
/// [computeElevationStatsSegments] (A5: прыжок между ветками —
/// не подъём и не спуск).
ElevationStats computeElevationStats(
  List<TrailPoint> points, {
  double noiseThreshold = 2,
}) {
  return computeElevationStatsSegments(
    [points],
    noiseThreshold: noiseThreshold,
  );
}

/// Статистика высот по ВЕТКАМ трека (A5): подъём/спуск считается
/// внутри каждой ветки, разрывы между ветками в профиль не
/// идут — иначе «мост» между берегами набирал сотни метров.
ElevationStats computeElevationStatsSegments(
  List<List<TrailPoint>> branches, {
  double noiseThreshold = 2,
}) {
  var hasData = false;

  var min = double.infinity;
  var max = double.negativeInfinity;

  var ascent = 0.0;
  var descent = 0.0;

  double? start;

  double? finish;

  for (final branch in branches) {
    final elevations = [
      for (final point in branch)
        if (point.elevation != null) point.elevation!,
    ];

    if (elevations.length < 2) {
      continue;
    }

    hasData = true;

    // Метки старта/финиша (D1): первая/последняя вершины всего
    // профиля — независимо от веток.
    start ??= elevations.first;

    finish = elevations.last;

    // Первая точка ветки задаёт старт min/max (A5): цикл ниже
    // обновляет их со второй точки — без посева первая терялась.
    min = math.min(min, elevations.first);
    max = math.max(max, elevations.first);

    var pending = 0.0;

    for (var i = 1; i < elevations.length; i++) {
      final delta = elevations[i] - elevations[i - 1];

      min = math.min(min, elevations[i]);
      max = math.max(max, elevations[i]);

      // Плоский шаг — накопление не трогаем: раньше delta == 0
      // попадал в «смену направления» и обнулял pending,
      // теряя набор высоты (Б3, замечание Sonnet).
      if (delta == 0) {
        continue;
      }

      if (delta.sign == pending.sign || pending == 0) {
        pending += delta;

        if (pending.abs() >= noiseThreshold) {
          if (pending > 0) {
            ascent += pending;
          } else {
            descent += pending.abs();
          }

          pending = 0;
        }
      } else {
        // Смена направления: накопленный шум стирается, копим заново.
        pending = delta;
      }
    }

    // Хвостовой перепад ветки, пробивший порог.
    if (pending.abs() >= noiseThreshold) {
      if (pending > 0) {
        ascent += pending;
      } else {
        descent += pending.abs();
      }
    }
  }

  if (!hasData) {
    return const ElevationStats(
      minElevation: double.nan,
      maxElevation: double.nan,
      ascent: double.nan,
      descent: double.nan,
    );
  }

  return ElevationStats(
    minElevation: min,
    maxElevation: max,
    ascent: ascent,
    descent: descent,
    startElevation: start,
    finishElevation: finish,
  );
}

/// Метка сложности маршрута по суммарному подъёму (П5).
///
/// Кило-подъём — граница «прогулочной» и «требующей подготовки»
/// тропы; у морских локаций подъём маленький — почти всегда
/// «лёгкий».
String elevationDifficultyLabel(ElevationStats stats) {
  if (stats.isEmpty || stats.ascent < 150) {
    return 'лёгкий';
  }

  if (stats.ascent < 400) {
    return 'средний';
  }

  return 'требует подготовки';
}
