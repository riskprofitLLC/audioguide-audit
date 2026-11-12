// AppLogger: вызовы не бросают, ленивые варианты вычисляют сообщение
// только при печати, error переживает многострочный текст.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/utils/logger.dart';

void main() {
  test('info/warning/error выполняются без исключений', () {
    AppLogger.info('сообщение');
    AppLogger.warning('предупреждение');
    AppLogger.error('ошибка');
    AppLogger.error('многострочный\nстек\nтрейс');
  });

  test('ленивые варианты вызывают замыкание и не бросают', () {
    var computed = 0;
    AppLogger.infoFn(() {
      computed++;
      return 'дорогое сообщение';
    });
    AppLogger.warningFn(() {
      computed++;
      return 'дорогое предупреждение';
    });
    expect(computed, 2);
  });

  test('error принимает объект ошибки и стек', () {
    expect(
      () => AppLogger.error(
        'сбой',
        error: StateError('x'),
        stackTrace: StackTrace.current,
      ),
      returnsNormally,
    );
  });
}
