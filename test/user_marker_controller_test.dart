// UserMarkerController (D5/R1): интерполяция маркера, троттлинг записи
// и каскад свежести (тускнеет → сигнал потерян) — юнит-тесты с
// фейковыми часами, без виджетов.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/map/controllers/user_marker_controller.dart';

UserPosition _pos(double lat) => UserPosition(
      latitude: lat,
      longitude: 29.1,
      timestamp: DateTime(2026, 10, 20),
    );

void main() {
  group('UserMarkerController', () {
    test('троттлинг записи: последний кадр всегда, остальные — не чаще 80 мс', () {
      final c = UserMarkerController();

      final t0 = DateTime(2026, 10, 20, 12, 0, 0);

      c.markWritten(t0);

      expect(
        c.shouldWriteFrame(isLastFrame: false, now: t0.add(const Duration(milliseconds: 30))),
        isFalse,
      );

      expect(
        c.shouldWriteFrame(isLastFrame: false, now: t0.add(const Duration(milliseconds: 90))),
        isTrue,
      );

      // Финальный кадр пишется всегда, даже сразу после записи.
      expect(
        c.shouldWriteFrame(isLastFrame: true, now: t0.add(const Duration(milliseconds: 5))),
        isTrue,
      );
    });

    test('прямая запись останавливает твин', () {
      final c = UserMarkerController();

      c.beginTween(_pos(36.60), _pos(36.61));

      expect(c.tweenFrom, isNotNull);

      c.writeDirect(_pos(36.62), DateTime(2026, 10, 20));

      expect(c.tweenFrom, isNull);
      expect(c.tweenTo, isNull);
      expect(c.shownPosition?.latitude, 36.62);
    });

    test('каскад свежести: 20 с тускнеет, ещё 10 с — потерян, фикс сбрасывает', () {
      fakeAsync((async) {
        final c = UserMarkerController();

        var stale = 0;
        var lost = 0;

        c.onStale = () => stale++;
        c.onSignalLost = () => lost++;

        c.markFresh();

        expect(c.shownFresh, isTrue);

        async.elapse(const Duration(seconds: 19));

        expect(stale, 0);

        async.elapse(const Duration(seconds: 1));

        expect(stale, 1, reason: '20 с без фикса — маркер тускнеет');

        expect(c.shownFresh, isFalse);

        async.elapse(const Duration(seconds: 9));

        expect(lost, 0);

        async.elapse(const Duration(seconds: 1));

        expect(lost, 1, reason: '30 с без фикса — сигнал потерян');

        // Новый фикс сбрасывает каскад.
        c.markFresh();

        async.elapse(const Duration(seconds: 25));

        expect(stale, 2);
        expect(lost, 1, reason: 'после markFresh «потерян» не срабатывает раньше 30 с');
      });
    });
  });
}
