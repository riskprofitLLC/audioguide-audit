import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Одноразовое появление виджета: fade + лёгкий подъём снизу.
///
/// Анимация проигрывается только при первом появлении State —
/// перестроения родителя её не перезапускают. Для «лестницы»
/// секций передавайте [delay] (шаг 40–70 мс).
///
/// Задержка реализована интервалом общего контроллера, а не
/// `Future.delayed`: в widget-тестах под FakeAsync таймер
/// «после дерева» роняет проверку инвариантов.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.normal,
    this.offset = 18,
    this.enabled = true,
  });

  final Widget child;

  /// Пауза перед стартом — шаг staggered-лестницы.
  final Duration delay;

  final Duration duration;

  /// Сдвиг снизу в начале анимации (px).
  final double offset;

  /// Проигрывать ли анимацию. Выключенный Entrance рисует
  /// ребёнка сразу (например, каскад главной уже играл в этой
  /// сессии — возврат не «выезжает» заново).
  final bool enabled;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    final totalMs = widget.duration.inMilliseconds + widget.delay.inMilliseconds;

    final start = totalMs > 0
        ? widget.delay.inMilliseconds / totalMs
        : 0.0;

    _controller = AnimationController(
      duration: Duration(milliseconds: totalMs),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: AppMotion.curve),
    );

    if (widget.enabled) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Отключённый Entrance — без анимации и rebuild-ов на кадр.
    // Системное Reduce Motion — тоже: контент появляется сразу.
    if (!widget.enabled ||
        MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _animation.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
