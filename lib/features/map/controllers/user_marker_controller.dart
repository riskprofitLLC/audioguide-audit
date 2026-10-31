/// Контроллер маркера «Вы здесь» (D5/R1 аудита Sonnet): интерполяция
/// (твин), троттлинг записи и каскад свежести (тускнеет → сигнал
/// потерян) вынесены из MapWidget в чистый класс без BuildContext.
///
/// Сам AnimationController твина остаётся у виджета (ему нужен
/// vsync); контроллер хранит from/to и решает, писать ли кадр.
/// Запись в слой карты (GeoJSON) — через колбэки виджета.
library;

import 'dart:async';

import '../../gps/models/user_position.dart';

class UserMarkerController {

  /// 20 с без живого фикса — точка тускнеет (B1, 18-й проход).
  static const staleAge = Duration(seconds: 20);

  /// 30 с без живого фикса — «Сигнал GPS потерян».
  static const signalLostAge = Duration(seconds: 30);

  /// Троттлинг записи кадров интерполяции (B2).
  static const writeThrottle = Duration(milliseconds: 80);

  /// Позиция, уже показанная на карте.
  UserPosition? shownPosition;

  /// Границы текущего твина (null — нет интерполяции).
  UserPosition? tweenFrom;

  UserPosition? tweenTo;

  /// Время последней записи в слой.
  DateTime? lastWriteAt;

  /// Маркер «свежий» (последний фикс недавний) — слои фильтруют
  /// по этому флагу (тусклая точка — давний фикс).
  bool shownFresh = true;

  /// Маркер потускнел — виджет переписывает слой с fresh: false.
  void Function()? onStale;

  /// Сигнал потерян (30 с без фикса) — виджет ставит плашку.
  void Function()? onSignalLost;

  Timer? _staleTimer;

  Timer? _lostTimer;

  /// Каскад свежести после живого фикса: stale → lost.
  void restartFreshnessTimers() {
    _staleTimer?.cancel();
    _lostTimer?.cancel();
    _lostTimer = null;
    _staleTimer = Timer(staleAge, _handleStale);
  }

  /// Только таймер тускления (без «потерян» — им управляет onSignalLost).
  void stopStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  void stopFreshnessTimers() {
    _staleTimer?.cancel();
    _staleTimer = null;
    _lostTimer?.cancel();
    _lostTimer = null;
  }

  void dispose() => stopFreshnessTimers();

  void _handleStale() {
    shownFresh = false;

    onStale?.call();

    _lostTimer?.cancel();
    _lostTimer = Timer(signalLostAge - staleAge, () {
      onSignalLost?.call();
    });
  }

  /// Новый живой фикс: маркер снова свежий, каскад перезапущен.
  void markFresh() {
    shownFresh = true;
    restartFreshnessTimers();
  }

  /// Писать ли кадр интерполяции в слой сейчас: последний кадр —
  /// всегда, остальные — не чаще writeThrottle.
  bool shouldWriteFrame({required bool isLastFrame, required DateTime now}) {
    if (isLastFrame) {
      return true;
    }

    final last = lastWriteAt;

    if (last != null && now.difference(last) < writeThrottle) {
      return false;
    }

    return true;
  }

  void markWritten(DateTime now) {
    lastWriteAt = now;
  }

  /// Прямая запись без интерполяции (Reduce Motion / первый фикс).
  void writeDirect(UserPosition position, DateTime now) {
    stopTween();
    shownPosition = position;
    lastWriteAt = now;
  }

  void beginTween(UserPosition from, UserPosition to) {
    tweenFrom = from;
    tweenTo = to;
  }

  void stopTween() {
    tweenFrom = null;
    tweenTo = null;
  }
}
