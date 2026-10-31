import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/chart_frame.dart';
import 'map_widget.dart';

/// Мини-превью карты острова вместо кнопки «Открыть карту».
///
/// Показывает не-интерактивную живую карту (те же офлайн-тайлы,
/// POI и маршруты, что и на полной карте, с подсветкой
/// [MapWidget.highlightPoiId]/[MapWidget.highlightTrailId]).
/// Карта вставлена в рамку морской карты [ChartFrame] — белый
/// воротник с градусными тиками по кромке. Тап по превью
/// вызывает [onTap] — как правило, разворот карты на весь
/// экран (`/map?island=...`).
///
/// D6 (замечание Sonnet): [activePaths] — пути роутера, при
/// которых превью ЖИВЁТ. Карта — тяжёлая платформенная вьюха
/// (GL-контекст, кеш тайлов); когда вкладка не видна (пользователь
/// ушёл на полную карту или в детали), превью подменяется
/// «бумажным» плейсхолдером и вьюха утилизируется — одновременно
/// живёт максимум одна-две карты вместо трёх. `null` — живёт
/// всегда (превью на страницах деталей: их дерево и так живёт
/// только пока открыта страница).
class MapPreview extends StatefulWidget {
  const MapPreview({
    super.key,
    required this.onTap,
    this.islandId,
    this.highlightPoiId,
    this.highlightTrailId,
    this.height = 160,
    this.activePaths,
  });

  /// Обработчик тапа по превью (разворот карты).
  final VoidCallback onTap;

  /// Остров, карту которого показываем. Если не задан —
  /// текущий выбранный остров.
  final String? islandId;

  /// Выделенная точка интереса (сигнальный маркер, камера на точке).
  final String? highlightPoiId;

  /// Выделенный маршрут (приглушённые линии, камера под маршрут).
  final String? highlightTrailId;

  /// Высота превью (включая воротник рамки).
  final double height;

  /// Пути роутера, при которых карта жива (D6). Сравнение — по
  /// префиксу: '/poi' покрывает все `/poi/:id`.
  final Set<String>? activePaths;

  @override
  State<MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<MapPreview> {
  bool _active = true;

  @override
  void initState() {
    super.initState();

    if (widget.activePaths != null) {
      _active = _isActive();

      AppRouter.router.routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    if (widget.activePaths != null) {
      AppRouter.router.routerDelegate.removeListener(_onRouteChanged);
    }

    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;

    final active = _isActive();

    if (active != _active) {
      setState(() {
        _active = active;
      });
    }
  }

  bool _isActive() {
    final paths = widget.activePaths;

    if (paths == null) {
      return true;
    }

    final uri = AppRouter.router.routerDelegate.currentConfiguration.uri;

    final path = uri.path;

    for (final prefix in paths) {
      if (path == prefix || path.startsWith('$prefix/')) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final body = _active
        ? MapWidget(
            islandId: widget.islandId,
            highlightPoiId: widget.highlightPoiId,
            highlightTrailId: widget.highlightTrailId,
            preview: true,
            onTap: widget.onTap,
          )
        // D6: вкладка не видна — карта не живёт, показываем
        // «бумажный» лист рамки (как загрузка превью).
        : _PaperPlaceholder(palette: palette);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ChartFrame(
          height: widget.height,
          child: SizedBox(
            height: widget.height - ChartFrame.defaultCollar * 2,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(child: body),

                // Прозрачный «ловец» тапов поверх карты. На web канвас
                // maplibre — платформенный вид: его flt-platform-view
                // перехватывает DOM-события до Flutter-хиттеста, поэтому
                // внешний GestureDetector тапы по карте не получает.
                // Слой, нарисованный ПОЗЖЕ в Stack (как и кнопка
                // «Развернуть», которая работает), попадает в
                // Flutter-хиттест — и разворачивает карту.
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.onTap,
                    behavior: HitTestBehavior.opaque,
                  ),
                ),

                // Кнопка — верхний правый угол: внизу она
                // перекрывала строку атрибуции OSM (лицензия требует
                // ВИДИМОЙ атрибуции — TextPainter-строка длинная на
                // всю ширину превью).
                Positioned(
                  right: 12,
                  top: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: AppShadows.floating(
                          AppPalette.of(context).onSurface),
                    ),
                    child: Material(
                      color: palette.info,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      elevation: 0,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        onTap: widget.onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.maximize2,
                                size: 13,
                                color: palette.accentOn,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Развернуть',
                                style: AppText.caption.copyWith(
                                  color: palette.accentOn,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Бумажный» плейсхолдер невидимого превью (D6).
class _PaperPlaceholder extends StatelessWidget {
  const _PaperPlaceholder({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: palette.sandLight),
        Center(
          child: Icon(
            LucideIcons.compass,
            size: 30,
            color: palette.info.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}
