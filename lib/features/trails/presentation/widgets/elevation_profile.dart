import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/trail_point.dart';
import '../../utils/elevation_stats.dart';

/// Карточка «Профиль высоты» на странице маршрута (П5, 12-й
/// проход): заливка рельефа по треку, пунктирные уровни min/max,
/// маркеры «старт/финиш» и сводка подъёма/спуска.
///
/// Без высот в треке (`<ele>` отсутствует у всех точек) карточка
/// не строится — возвращается [SizedBox.shrink].
///
/// Подготовка данных (статистика + нормализованные ветки) кешируется
/// в состоянии (баг 16, замечания Sonnet): `trail.segments` отдаёт
/// новый список на каждый build, из-за чего shouldRepaint живал
/// всегда, а статистика пересчитывалась при каждой отрисовке.
class ElevationProfile extends StatefulWidget {
  const ElevationProfile({super.key, required this.segments});

  /// Ветки трека (A5): разрывы не «мостятся» — между ветками
  /// фиксированный зазор, прыжок высоты не учитывается.
  final List<List<TrailPoint>> segments;

  @override
  State<ElevationProfile> createState() => _ElevationProfileState();
}

/// Ветка профиля: точки с высотами + накопленная дистанция по
/// ним (ось X нормируется в отрисовщике).
typedef _ProfileBranch = ({List<TrailPoint> points, List<double> xs});

class _ElevationProfileState extends State<ElevationProfile> {
  late _PreparedProfile _profile;

  @override
  void initState() {
    super.initState();

    _profile = _prepare(widget.segments);
  }

  @override
  void didUpdateWidget(ElevationProfile oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Пересчёт — только при реальном изменении содержимого:
    // свежий экземпляр списка теми же точками кеши не сбрасывает.
    if (!_sameSegments(oldWidget.segments, widget.segments)) {
      _profile = _prepare(widget.segments);
    }
  }

  _PreparedProfile _prepare(List<List<TrailPoint>> segments) {
    final stats = computeElevationStatsSegments(segments);

    final branches = <_ProfileBranch>[];

    var totalDistance = 0.0;

    for (final branch in segments) {
      final points = <TrailPoint>[];

      for (final point in branch) {
        if (point.elevation != null) {
          points.add(point);
        }
      }

      if (points.length < 2) {
        continue;
      }

      final xs = <double>[0];

      for (var i = 1; i < points.length; i++) {
        final previous = points[i - 1];
        final current = points[i];

        xs.add(
          xs.last +
              _distance(
                previous.latitude,
                previous.longitude,
                current.latitude,
                current.longitude,
              ),
        );
      }

      final width = xs.last;

      if (width <= 0) {
        // Вырожденная ветка (все точки в одном месте) — пропуск,
        // ось не должна схлопываться в ноль.
        continue;
      }

      branches.add((points: points, xs: xs));

      totalDistance += width;
    }

    return _PreparedProfile(
      stats: stats,
      branches: branches,
      totalDistance: totalDistance,
    );
  }

  /// Сравнение веток ПО СОДЕРЖИМОМУ (баг 16): identity всегда
  /// ложно для `trail.segments` без lines.
  static bool _sameSegments(
    List<List<TrailPoint>> a,
    List<List<TrailPoint>> b,
  ) {
    if (identical(a, b)) {
      return true;
    }

    if (a.length != b.length) {
      return false;
    }

    for (var i = 0; i < a.length; i++) {
      final branchA = a[i];
      final branchB = b[i];

      if (branchA.length != branchB.length) {
        return false;
      }

      for (var j = 0; j < branchA.length; j++) {
        final pa = branchA[j];
        final pb = branchB[j];

        if (pa.latitude != pb.latitude ||
            pa.longitude != pb.longitude ||
            pa.elevation != pb.elevation) {
          return false;
        }
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    final stats = _profile.stats;

    if (stats.isEmpty) {
      return const SizedBox.shrink();
    }

    // B5: доступность — полный смысл карточки одним узлом.
    final summary =
        'Профиль высоты: от ${stats.minElevation.round()} до '
        '${stats.maxElevation.round()} метров, '
        'подъём ${stats.ascent.round()} метров, '
        'спуск ${stats.descent.round()} метров, '
        'маршрут ${elevationDifficultyLabel(stats)}';

    return Semantics(
      label: summary,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.mountain,
                  size: 16,
                  color: palette.info,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Профиль высоты',
                    style: AppText.chip.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                ),
                // Метка сложности — по суммарному подъёму.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.sandLight,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: palette.sand, width: 1),
                  ),
                  child: Text(
                    elevationDifficultyLabel(stats),
                    // Токен D4.
                    style: AppText.badge.copyWith(
                      color: palette.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            SizedBox(
              height: 96,
              width: double.infinity,
              child: CustomPaint(
                painter: _ElevationPainter(
                  profile: _profile,
                  // Цвета — роли палитры (D3): карточка живёт в
                  // ночной теме без хардкода.
                  fill: palette.sandLight,
                  line: palette.info,
                  dash: palette.sand,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            // Метки старта/финиша — строкой ПОД графиком (D1):
            // TextPainter внутри канваса не знал про textScale и
            // рисовался поверх заливки.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Старт · ${stats.startElevation?.round() ?? '—'} м',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Токен D4.
                    style: AppText.meta
                        .copyWith(color: palette.onSurfaceMuted),
                  ),
                ),
                const SizedBox(width: AppSpace.s),
                Expanded(
                  child: Text(
                    'Финиш · ${stats.finishElevation?.round() ?? '—'} м',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    // Токен D4.
                    style: AppText.meta
                        .copyWith(color: palette.onSurfaceMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${stats.minElevation.round()}–${stats.maxElevation.round()} м · '
              'подъём +${stats.ascent.round()} м · '
              'спуск −${stats.descent.round()} м',
              // Токен D4.
              style: AppText.meta.copyWith(color: palette.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// Гаверсинус (метры) — без зависимости от сервисов.
  static double _distance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;

    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double degrees) => degrees * math.pi / 180;
}

/// Подготовленный профиль: статистика один раз, нормализованные
/// ветки — painter не пересчитывает данные на каждом кадре.
class _PreparedProfile {
  const _PreparedProfile({
    required this.stats,
    required this.branches,
    required this.totalDistance,
  });

  final ElevationStats stats;

  final List<_ProfileBranch> branches;

  final double totalDistance;
}

/// Отрисовка профиля: ось X — накопленная дистанция по треку,
/// ось Y — высота (нормированная на min/max с воздухом 10%).
///
/// Все тяжёлые расчёты (статистика, ветки, дистанции) сделаны
/// один раз в состоянии виджета; painter только рисует.
class _ElevationPainter extends CustomPainter {
  const _ElevationPainter({
    required this.profile,
    required this.fill,
    required this.line,
    required this.dash,
  });

  final _PreparedProfile profile;

  /// Цвет заливки рельефа.
  final Color fill;

  /// Цвет линии профиля.
  final Color line;

  /// Цвет пунктирных уровней min/max.
  final Color dash;

  /// Фиксированный зазор между ветками на оси X (A5): разрыв
  /// трека НЕ «мостится» дистанцией — визуальная пауза.
  static const double _branchGap = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final stats = profile.stats;

    if (stats.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    final branches = profile.branches;

    final totalDistance = profile.totalDistance;

    if (branches.isEmpty || totalDistance <= 0) {
      return;
    }

    // Ширина оси X: дистанции веток + зазоры между ними.
    final gaps = (branches.length - 1) * _branchGap;

    final axisWidth = size.width - gaps;

    final minEle = stats.minElevation;
    final maxEle = stats.maxElevation;

    // Воздух сверху/снизу, чтобы линия не липла к кромкам.
    final padding = (maxEle - minEle).clamp(1.0, double.infinity) * 0.12;

    final low = minEle - padding;
    final high = maxEle + padding;

    double y(double elevation) =>
        size.height * (1 - (elevation - low) / (high - low));

    var xOffset = 0.0;

    final fillPaint = Paint()..color = fill;

    final linePaint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final branch in branches) {
      double x(int i) =>
          xOffset + axisWidth * (branch.xs[i] / totalDistance);

      final linePath = Path()
        ..moveTo(x(0), y(branch.points.first.elevation!));

      for (var i = 1; i < branch.points.length; i++) {
        linePath.lineTo(x(i), y(branch.points[i].elevation!));
      }

      // Заливка — до низа карточки, мягким песочным тоном.
      final fillPath = Path.from(linePath)
        ..lineTo(x(branch.xs.length - 1), size.height)
        ..lineTo(x(0), size.height)
        ..close();

      canvas.drawPath(fillPath, fillPaint);

      canvas.drawPath(linePath, linePaint);

      xOffset +=
          axisWidth * (branch.xs.last / totalDistance) + _branchGap;
    }

    // Пунктирные уровни min/max (D1): границы рельефа читаются
    // без подписей поверх заливки.
    _drawDashedLine(
      canvas,
      Offset(0, y(maxEle)),
      Offset(size.width, y(maxEle)),
    );

    _drawDashedLine(
      canvas,
      Offset(0, y(minEle)),
      Offset(size.width, y(minEle)),
    );

    // Маркеры «старт/финиш» (D1): точки на первой и последней
    // вершине первой/последней ветки.
    final firstBranch = branches.first;

    final lastBranch = branches.last;

    final markerPaint = Paint()..color = line;

    final markerBorderPaint = Paint()..color = fill;

    final startPoint = Offset(
      0,
      y(firstBranch.points.first.elevation!),
    );

    final finishPoint = Offset(
      size.width,
      y(lastBranch.points.last.elevation!),
    );

    _drawMarker(canvas, startPoint, markerPaint, markerBorderPaint);

    _drawMarker(canvas, finishPoint, markerPaint, markerBorderPaint);
  }

  /// Кружок-маркер на профиле: заливка линии + ободок фона.
  void _drawMarker(
    Canvas canvas,
    Offset center,
    Paint markerPaint,
    Paint borderPaint,
  ) {
    canvas.drawCircle(center, 4, borderPaint);

    canvas.drawCircle(center, 2.5, markerPaint);
  }

  /// Пунктирная горизонталь уровней min/max.
  void _drawDashedLine(Canvas canvas, Offset from, Offset to) {
    if ((from.dy - to.dy).abs() < 0.5) {
      // Вырожденный профиль (ровный трек) — уровни совпадают,
      // пунктир ляжет прямо на линию: не рисуем.
      return;
    }

    const dashWidth = 4.0;

    const gapWidth = 4.0;

    final paint = Paint()
      ..color = dash.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    var x = from.dx;

    while (x < to.dx) {
      final end = math.min(x + dashWidth, to.dx);

      canvas.drawLine(Offset(x, from.dy), Offset(end, to.dy), paint);

      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) =>
      // Профиль — ИММУТАБЕЛЬНЫЙ объект из кеша состояния: тот же
      // экземпляр ⇒ тот же рисунок (баг 16: раньше identity
      // свежего `trail.segments` давал ложное true на каждый build).
      !identical(oldDelegate.profile, profile) ||
          oldDelegate.fill != fill ||
          oldDelegate.line != line ||
          oldDelegate.dash != dash;
}
