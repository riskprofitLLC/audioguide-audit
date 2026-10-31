import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../services/map_input_lock.dart';


/// Обёртка для плавающих элементов управления картой.
///
/// Пока палец/курсор на контроле, карта не реагирует на
/// жесты: на web канвас maplibre (платформенный вид) получает
/// события напрямую из DOM поверх Flutter-контента, и даже лёгкое
/// дрожание пальца при нажатии кнопки сдвигало карту. Блокировка
/// включается при нажатии (pointer down) и снимается при
/// отпускании (pointer up/cancel) либо при уходе курсора
/// (hover, только для мыши). На тач-устройствах hover-событий нет,
/// поэтому держится исключительно логика нажатия. На нативных
/// платформах вызовы безопасны (no-op).
///
/// Замок — refcount: несколько одновременно зажатых контролов и
/// открытые шторки не снимают блокировку друг друга.
class MapControlsHoverLock extends StatefulWidget {

  const MapControlsHoverLock({
    super.key,
    required this.child,
  });

  final Widget child;


  @override
  State<MapControlsHoverLock> createState() => _MapControlsHoverLockState();
}


class _MapControlsHoverLockState extends State<MapControlsHoverLock> {

  int _pointersDown = 0;

  bool _mouseInside = false;

  bool _held = false;


  void _sync() {

    final held = _pointersDown > 0 || _mouseInside;

    if (held == _held) {

      return;
    }

    _held = held;

    if (held) {
      acquireMapInputLock();
    } else {
      releaseMapInputLock();
    }
  }


  @override
  void dispose() {

    // Снимаем только свою блокировку: лишний release съел бы
    // чужой acquire (например, открытой шторки).
    if (_held) {

      releaseMapInputLock();
    }

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {

    // Hover-события браузер генерирует и для тача (совместимость
    // с мышью): после отпускания они снова включили бы блокировку,
    // поэтому hover учитывается только для настоящей мыши. Тач
    // обрабатывается событиями нажатия (Listener): down — блок,
    // up/cancel — разблок. Счётчик даёт корректный баланс при
    // мультитаче (два пальца на кнопке = два down/два up).
    return Listener(
      onPointerDown: (_) {
        _pointersDown++;
        _sync();
      },
      onPointerUp: (_) {
        if (_pointersDown > 0) {
          _pointersDown--;
        }
        _sync();
      },
      onPointerCancel: (_) {
        if (_pointersDown > 0) {
          _pointersDown--;
        }
        _sync();
      },
      child: MouseRegion(
        onEnter: (event) {
          if (event.kind == PointerDeviceKind.mouse) {
            _mouseInside = true;
            _sync();
          }
        },
        onExit: (event) {
          if (event.kind == PointerDeviceKind.mouse) {
            _mouseInside = false;
            _sync();
          }
        },
        child: widget.child,
      ),
    );
  }
}
