import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';

/// Единая звезда избранного с РЕАЛЬНОЙ заливкой.
///
/// Пустое состояние — контурная звезда (а не перечёркнутая
/// `starOff`, которая читалась как «отключено»), залитое —
/// полная звезда сигнального цвета.
///
/// Pop-анимация и haptic — ТОЛЬКО по сигналу тапа [tapSignal],
/// который родительская кнопка инкрементит в onPressed.
/// Раньше они срабатывали на любую смену `filled` в
/// didUpdateWidget — и при подгрузке избранного при старте
/// список мигал и вибрировал десятком звёзд сразу (P0-4,
/// 5-й проход).
///
/// Пилюли-кнопки с фоновой заливкой состояния (FavoriteButton,
/// звезда в шторке POI) остаются на Lucide-иконках — на них
/// опираются тесты; этот виджет — для «строчных» звёзд на
/// карточках и в шапках.
class FavoriteStar extends StatefulWidget {
  const FavoriteStar({
    super.key,
    required this.filled,
    this.size = 20,
    this.filledColor,
    this.emptyColor,
    this.tapSignal,
  });

  final bool filled;

  final double size;

  /// Цвет залитой звезды (по умолчанию — сигнальный акцент).
  final Color? filledColor;

  /// Цвет контурной звезды.
  final Color? emptyColor;

  /// Импульс пользовательского тапа: родительская кнопка
  /// инкрементит значение в своём onPressed — только тогда
  /// звезда «пружинит» и даёт тактильный отклик.
  final ValueListenable<int>? tapSignal;

  @override
  State<FavoriteStar> createState() => _FavoriteStarState();
}

class _FavoriteStarState extends State<FavoriteStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _pop = AnimationController(
      vsync: this,
      duration: AppMotion.normal,
    );

    // easeOutBack сам даёт «перелёт» (~1.1) и возврат к 1 —
    // ровно тот pop, что нужен звезде.
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pop, curve: AppMotion.pop),
    );

    widget.tapSignal?.addListener(_handleTapSignal);
  }

  @override
  void didUpdateWidget(covariant FavoriteStar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Смена filled здесь НИЧЕГО не запускает: подгрузка
    // избранного при старте не должна мигать звёздами (P0-4).
    if (oldWidget.tapSignal != widget.tapSignal) {
      oldWidget.tapSignal?.removeListener(_handleTapSignal);

      widget.tapSignal?.addListener(_handleTapSignal);
    }
  }

  /// Тап пользователя по родительской кнопке: haptic + pop.
  void _handleTapSignal() {
    HapticFeedback.selectionClick();

    _pop.forward(from: 0);
  }

  @override
  void dispose() {
    widget.tapSignal?.removeListener(_handleTapSignal);

    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filledColor = widget.filledColor ?? AppColors.brandAccent;
    // Контурная звезда — приглушённая роль (B2): ink@0.45 давал
    // ~2.9:1 — не читалась как «нажимаемая».
    final emptyColor = widget.emptyColor ?? AppPalette.of(context).onSurfaceMuted;

    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) {
        // В покое — единичный масштаб: непружинившая звезда не
        // должна быть меньше пружинившей.
        return Transform.scale(
          scale: _pop.isAnimating ? _scale.value : 1.0,
          child: child,
        );
      },
      child: Icon(
        widget.filled ? Icons.star_rounded : Icons.star_outline_rounded,
        size: widget.size,
        color: widget.filled ? filledColor : emptyColor,
      ),
    );
  }
}
