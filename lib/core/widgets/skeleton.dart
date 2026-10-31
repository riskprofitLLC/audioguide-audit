import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Скелетон загрузки: мягкий прямоугольник с shimmer-волной.
///
/// Заменяет спиннеры там, где известна будущая форма контента
/// (карточки, строки списков). В widget-тестах волна замирает:
/// вечный тикер не даёт `pumpAndSettle` завершиться, поэтому
/// анимация включается только в реальном биндинге (как «живая»
/// волна плеера).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;

  final double height;

  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();

    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    // Запуск/стоп — в didChangeDependencies: MediaQuery (Reduce
    // Motion) нельзя читать в initState.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Смена Reduce Motion на живом устройстве — перезапуск/стоп.
    _syncShimmer();
  }

  /// Волна-блик ходит только на реальном биндинге и при
  /// включённых системных анимациях (B12).
  void _syncShimmer() {
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    final allowed =
        WidgetsBinding.instance is WidgetsFlutterBinding && !reduceMotion;

    if (allowed && !_shimmer.isAnimating) {
      _shimmer.repeat();
    } else if (!allowed && _shimmer.isAnimating) {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ролевые поверхности волны (B5): светлая тема — те же
    // песочные плашки, тёмная — тёмные ступени.
    final palette = AppPalette.of(context);

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        final t = _shimmer.value;

        // Волна-блик ходит по скелетону слева направо.
        final begin = Alignment(-1.6 + 2.6 * t, -0.3);
        final end = Alignment(-0.6 + 2.6 * t, 0.3);

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [
                palette.sandLight,
                palette.surfaceRaised,
                palette.sandLight,
              ],
              stops: const [0.4, 0.5, 0.6],
            ),
          ),
        );
      },
    );
  }
}

/// Появление изображения без прыжков раскладки (B4, 10-й проход):
/// скелетон держит геометрию до первого кадра, затем кроссфейд.
///
/// Единый `frameBuilder` для `Image.asset` во всех поверхностях —
/// прежде блок был скопирован в 5 местах (обложка карточки,
/// карусель галереи, миниатюра, «Сейчас играет», «Продолжить»).
///
/// [radius] — радиус скелетона; [size] — конечная геометрия для
/// мест, где из Row приходят неограниченные констрейнты (Stack
/// с expand обязан получить конечную геометрию).
Widget skeletonFrameBuilder(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded, {
  double radius = 0,
  double? size,
}) {
  if (wasSynchronouslyLoaded) {
    return child;
  }

  final stack = Stack(
    fit: StackFit.expand,
    children: [
      if (frame == null) SkeletonBox(radius: radius),
      child,
    ],
  );

  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 200),
    curve: AppMotion.curve,
    child: size == null
        ? stack
        : SizedBox(width: size, height: size, child: stack),
  );
}

/// Скелетон строки списка: круглая иконка + две «строки текста».
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.trailing = false});

  /// Показать ли «вторичную кнопку» справа.
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          const SkeletonBox(
            width: 52,
            height: 52,
            radius: 14,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 13, radius: 6),
                SizedBox(height: 8),
                SkeletonBox(height: 11, radius: 6),
              ],
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: 12),
            const SkeletonBox(width: 28, height: 28, radius: 14),
          ],
        ],
      ),
    );
  }
}

/// Скелетон карточки маршрута (фото-блок + строка бейджей).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(height: 132, radius: 18),
        SizedBox(height: 10),
        Row(
          children: [
            SkeletonBox(width: 84, height: 10, radius: 5),
            SizedBox(width: 8),
            SkeletonBox(width: 52, height: 10, radius: 5),
          ],
        ),
      ],
    );
  }
}

/// Скелетон страницы деталей (POI/маршрут): hero-блок,
/// заголовок, карта-превью и строки текста — вместо спиннера.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        SkeletonBox(height: 300, radius: 0),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 130, height: 12, radius: 6),
              SizedBox(height: 14),
              SkeletonBox(width: 240, height: 26, radius: 10),
              SizedBox(height: 18),
              SkeletonBox(height: 184, radius: 18),
              SizedBox(height: 20),
              SkeletonBox(height: 13),
              SizedBox(height: 8),
              SkeletonBox(height: 13),
            ],
          ),
        ),
      ],
    );
  }
}
