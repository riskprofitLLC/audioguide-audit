import 'package:flutter/foundation.dart';


class AppLogger {

  AppLogger._();


  /// Информационные сообщения пишутся только в debug-сборках
  /// (в release они засоряют лог и тормозят).
  static void info(
    String message,
  ) {

    if (!kDebugMode) return;

    _print(
      'INFO',
      message,
    );

  }


  /// Ленивый [info]: сообщение вычисляется ТОЛЬКО в debug-сборке.
  ///
  /// Для горячих мест (GPS-тики) и дорогих интерполяций
  /// (списки, map/join): `info('…$heavy…')` вычисляет строку
  /// в release до отбрасывания вызова.
  static void infoFn(
    String Function() message,
  ) {

    if (!kDebugMode) return;

    _print(
      'INFO',
      message(),
    );

  }


  /// Предупреждения — только в debug-сборках.
  static void warning(
    String message,
  ) {

    if (!kDebugMode) return;

    _print(
      'WARNING',
      message,
    );

  }


  /// Ленивый [warning]: сообщение вычисляется только в debug.
  static void warningFn(
    String Function() message,
  ) {

    if (!kDebugMode) return;

    _print(
      'WARNING',
      message(),
    );

  }



  /// Ошибки пишутся всегда — в т.ч. в release (для диагностики
  /// в поддержке).
  ///
  /// Правило: в [message]/[error] никогда не должно быть персональных
  /// данных (координаты пользователя, история поиска, тексты ввода,
  /// ключи / файлы / пути пользовательского устройства). Ошибки
  /// содержат только технический контекст острова/локации
  /// (id ассетов, идентификаторы сущностей). Пользовательские данные
  /// (например, координаты GPS) логируются как «получена позиция»
  /// без самих значений.
  static void error(
    String message, {

    Object? error,

    StackTrace? stackTrace,

  }) {

    _print(
      'ERROR',
      message,
    );


    if (error != null) {

      _print(
        'ERROR DETAILS',
        error.toString(),
      );

    }


    if (stackTrace != null) {

      _print(
        'STACK',
        stackTrace.toString(),
      );

    }

  }



  static void _print(
    String level,
    String message,
  ) {
    // ignore: avoid_print
    print('[$level] $message');
  }
}