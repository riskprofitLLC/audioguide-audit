// A17 (17-й проход): направление по маршруту зависит от курса
// пользователя.
//
// Раньше bearing всегда вёл к СЛЕДУЮЩЕЙ вершине по порядку:
// человек, идущий навстречу порядку вершин, слышал «Идти на …»
// в противоположную сторону. Теперь при известном курсе (heading
// фикса или смещение между фиксами) «следующая» точка
// перевыбирается по направлению движения.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/services/trail_navigator.dart';
import 'package:island_guide/features/trails/models/trail.dart';
import 'package:island_guide/features/trails/models/trail_point.dart';

Trail _trail(List<List<double>> points) {
  return Trail(
    id: 'trail-01',
    name: 'Маршрут',
    points: [
      for (var i = 0; i < points.length; i++)
        TrailPoint(
          id: 'p$i', latitude: points[i].first, longitude: points[i].last, order: i),
    ],
  );
}

UserPosition _at(double lat, double lng) {
  return UserPosition(latitude: lat, longitude: lng);
}

void main() {
  final navigator = TrailNavigator();

  // Прямой маршрут ЗАПАД → ВОСТОК по параллели 36.55.
  final trail = _trail([
    [36.55, 29.06],
    [36.55, 29.07],
    [36.55, 29.08],
  ]);

  // Пользователь — ровно посередине среднего сегмента.
  final position = _at(36.55, 29.075);

  group('TrailNavigator.update(course:) (A17)', () {
    test('без курса — по порядку вершин (на восток)', () {

      final state = navigator.update(position, [trail]);

      expect(state, isNotNull);

      // Азимут ~90° (восток), прежнее поведение сохранено.
      expect(state!.bearing, inExclusiveRange(80, 100));
      expect(state.reversed, isFalse);
    });

    test('курс на восток — та же вершина впереди', () {

      final state = navigator.update(position, [trail], course: 90);

      expect(state!.bearing, inExclusiveRange(80, 100));
      expect(state.reversed, isFalse);
    });

    test('курс на запад — подсказка развёрнута к идущему', () {

      // Человек идёт ПРОТИВ порядка вершин (запад): «вперёд» для
      // него — западная вершина. Раньше азимут оставался на восток
      // и карточка говорила «Идти на восток» человеку, идущему
      // на запад.
      final state = navigator.update(position, [trail], course: 270);

      expect(state!.bearing, inExclusiveRange(260, 280));
      expect(state.reversed, isTrue);
    });

    test('курс поперёк маршрута — порядок не переворачивается', () {

      // Свежий навигатор: гистерезис — состояние между тиками,
      // предыдущие тесты оставили «назад» включённым.
      final freshNavigator = TrailNavigator();

      // Курс на юг от восточного азимута — угол ~90°: спорный
      // случай (не «явно навстречу»), оставляем порядок вершин.
      final state = freshNavigator.update(position, [trail], course: 175);

      expect(state!.reversed, isFalse);
    });
  });

  group('гистерезис разворота (A5, 18-й проход)', () {

    test('мёртвая зона 70–110° не мерцает «Идти назад»', () {

      // Азимут маршрута ~90° (восток). Двигаем курс плавно —
      // решение меняется только за порогами 110/70.

      // Далеко навстречу (diff ~180°) — разворот.
      expect(
        navigator.update(position, [trail], course: 270)!.reversed,
        isTrue,
      );

      // Diff ~110° — на пороге входа: прежнее решение сохраняется
      // (не дребезг на границе).
      expect(
        navigator.update(position, [trail], course: 200)!.reversed,
        isTrue,
        reason: '110° — мёртвая зона, «назад» удерживается',
      );

      // Diff ~85° — всё ещё внутри мёртвой зоны.
      expect(
        navigator.update(position, [trail], course: 175)!.reversed,
        isTrue,
      );

      // Diff ~60° < 70° — возврат к порядку вершин.
      expect(
        navigator.update(position, [trail], course: 150)!.reversed,
        isFalse,
        reason: 'уход от разворота — только за порогом 70°',
      );

      // Обратно в мёртвую зону — решение не меняется мгновенно.
      expect(
        navigator.update(position, [trail], course: 175)!.reversed,
        isFalse,
      );
    });

    test('курс пропал (стоящий) — прежнее направление сохраняется', () {

      // Шли навстречу — разворот включён.
      expect(
        navigator.update(position, [trail], course: 270)!.reversed,
        isTrue,
      );

      // Курс устарел (стоит на месте) — подсказка не мигает:
      // сохраняем последнее решение.
      expect(
        navigator.update(position, [trail])!.reversed,
        isTrue,
      );
    });

    test('разворот разворачивает азимут к предыдущей вершине', () {

      // Навстречу порядку: bearing должен вести на ЗАПАД.
      final state = navigator.update(position, [trail], course: 270);

      expect(state!.bearing, inExclusiveRange(260, 280));
    });
  });
}
