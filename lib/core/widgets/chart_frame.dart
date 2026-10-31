import 'package:flutter/material.dart';

import '../../app/theme.dart';


/// Двойная линия по кромке листа — как поля печатного атласа.
///
/// Редизайн «Атлас»: вместо градусных тиков — две параллельные
/// волосяные линии (внешняя по самому краю и внутренняя с
/// отступом), плюс короткие угловые засечки.
class ChartTicksPainter extends CustomPainter {

  const ChartTicksPainter({
    this.gap = 4,
    this.tickColor,
    this.corners = true,
  });


  /// Зазор между внешней и внутренней линией.
  final double gap;


  /// Цвет линий (по умолчанию — чернила с лёгким альфа).
  final Color? tickColor;


  /// Угловые засечки.
  final bool corners;


  @override
  void paint(Canvas canvas, Size size) {

    final color = tickColor ?? const Color(0xFF16333C).withValues(alpha: 0.22);

    final outer = Paint()
      ..color = color
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    final inner = Paint()
      ..color = color.withValues(alpha: color.a * 0.6)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    // Внешняя линия — по самому краю.
    canvas.drawRect(Offset.zero & size, outer);

    // Внутренняя линия — с отступом gap.
    canvas.drawRect(
      Offset(gap, gap) & Size(size.width - gap * 2, size.height - gap * 2),
      inner,
    );

    if (corners) {

      final corner = Paint()
        ..color = color
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke;

      const c = 8.0;

      canvas.drawLine(const Offset(0, c), const Offset(0, 0), corner);
      canvas.drawLine(const Offset(0, 0), const Offset(c, 0), corner);

      canvas.drawLine(
        Offset(size.width - c, 0), Offset(size.width, 0), corner);
      canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, c), corner);

      canvas.drawLine(
        Offset(0, size.height - c), Offset(0, size.height), corner);
      canvas.drawLine(
        Offset(0, size.height), Offset(c, size.height), corner);

      canvas.drawLine(
        Offset(size.width - c, size.height),
        Offset(size.width, size.height), corner);
      canvas.drawLine(
        Offset(size.width - c, size.height),
        Offset(size.width, size.height - c), corner);
    }
  }


  @override
  bool shouldRepaint(covariant ChartTicksPainter oldDelegate) =>
      oldDelegate.gap != gap ||
      oldDelegate.tickColor != tickColor ||
      oldDelegate.corners != corners;
}


/// Рамка атласа: воротник листа с двойной линией по кромке,
/// внутри — содержимое с тонкой чернильной линией.
///
/// Используется вокруг живых карт (превью на главной и в
/// деталях) — карта выглядит врезкой в лист атласа.
class ChartFrame extends StatelessWidget {

  /// Ширина воротника по умолчанию.
  static const double defaultCollar = 10;

  const ChartFrame({
    super.key,
    required this.child,
    this.height,
    this.collar = defaultCollar,
    this.radius = 18,
  });


  /// Содержимое рамки (карта).
  final Widget child;


  /// Общая высота рамки (воротник включён).
  final double? height;


  /// Ширина воротника — полей вокруг содержимого.
  final double collar;


  /// Радиус внешних углов рамки.
  final double radius;


  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    // Линии полей — цветом «чернил» текущей темы (D1: пэинтер
    // без контекста, цвет передаём параметром).
    final lineColor = palette.onSurface.withValues(alpha: 0.22);

    return Container(

      height: height,

      decoration: BoxDecoration(
        // Ролевые поверхности (B5).
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: palette.sand.withValues(alpha: 0.9),
          width: 1,
        ),
      ),

      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),

        child: Stack(

          children: [

            Padding(
              padding: EdgeInsets.all(collar),

              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius - collar),
                  border: Border.all(
                    color: palette.onSurface,
                    width: 0.75,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius - collar),
                  child: child,
                ),
              ),
            ),

            // Двойная линия полей поверх воротника — не перехватывает жесты.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: ChartTicksPainter(tickColor: lineColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
