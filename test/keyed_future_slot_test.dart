// Тест однослотового кеша future с ключом — механизма,
// защищающего карту от гонки быстрого переключения локации
// (map_camera.dart, _ensureDataFuture).

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/utils/keyed_future_slot.dart';

void main() {
  group('KeyedFutureSlot', () {
    test('тот же ключ возвращает существующий future', () async {
      final slot = KeyedFutureSlot<int>();

      var created = 0;

      Future<int> create() async {
        created++;
        return 42;
      }

      final first = slot.obtain('gemiler', create);

      final second = slot.obtain('gemiler', create);

      expect(identical(first, second), isTrue);
      expect(created, 1);

      expect(await first, 42);
    });

    test('другой ключ отбрасывает чужой future', () async {
      final slot = KeyedFutureSlot<String>();

      final gemiler = slot.obtain(
        'gemiler',
        () async => 'данные гемилера',
      );

      // Быстрая смена локации до завершения загрузки: future
      // гемилера НЕ должен достаться бэю.
      final bay = slot.obtain(
        'bay',
        () async => 'данные бэя',
      );

      expect(identical(gemiler, bay), isFalse);

      expect(await bay, 'данные бэя');
      expect(await gemiler, 'данные гемилера');
    });

    test('после reset создаётся новый future', () async {
      final slot = KeyedFutureSlot<int>();

      final first = slot.obtain('gemiler', () async => 1);

      await first;

      slot.reset();

      expect(slot.hasValue, isFalse);

      final second = slot.obtain('gemiler', () async => 2);

      expect(identical(first, second), isFalse);

      expect(await second, 2);
    });

    test('упавший future не застревает в слоте', () async {
      final slot = KeyedFutureSlot<int>();

      var attempts = 0;

      Future<int> create() async {
        attempts++;

        if (attempts == 1) {
          throw StateError('asset failed');
        }

        return 7;
      }

      final failed = slot.obtain('gemiler', create);

      await expectLater(failed, throwsStateError);

      // Ошибка дошла до подписчиков слота — слот освобождён.
      await Future<void>.delayed(Duration.zero);

      final retried = slot.obtain('gemiler', create);

      expect(await retried, 7);
      expect(attempts, 2);
    });
  });
}
