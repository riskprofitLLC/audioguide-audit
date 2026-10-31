// Запись своего трека (П5, 29-й проход).
//
// Запись включается на карте кнопкой: точки фильтруются по
// смещению (≥3 м), иначе стоящий пользователь «пишет» шум GPS и
// трек разрастается тысячами точек. Логика покрыта тестом —
// ошибка тихая (трек просто выглядит сломанным).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/services/track_recorder.dart';

UserPosition pos(double lat, double lng) =>
    UserPosition(latitude: lat, longitude: lng);

void main() {
  late StreamController<UserPosition> controller;
  late TrackRecorder recorder;

  setUp(() {
    controller = StreamController<UserPosition>.broadcast();

    recorder = TrackRecorder(positions: controller.stream);
  });

  tearDown(() {
    // dispose закрывает подписку и нотификатор; контроллер — свой.
    recorder.dispose();

    return controller.close();
  });

  test('до старта ничего не пишется', () async {
    controller.add(pos(36.0, 29.0));

    await Future<void>.delayed(Duration.zero);

    expect(recorder.points, isEmpty);

    expect(recorder.pointsCount.value, 0);

    expect(recorder.isRecording, isFalse);
  });

  test('старт обнуляет трек и включает запись', () async {
    controller.add(pos(36.0, 29.0));

    await Future<void>.delayed(Duration.zero);

    recorder.start();

    expect(recorder.isRecording, isTrue);

    expect(recorder.points, isEmpty);

    expect(recorder.pointsCount.value, 0);

    expect(recorder.startedAt, isNotNull);
  });

  test('точки ближе 3 м не пишутся (фильтр шума GPS)', () async {
    recorder.start();

    controller.add(pos(36.0, 29.0));

    await Future<void>.delayed(Duration.zero);

    // ~1,1 м на север — меньше порога.
    controller.add(pos(36.00001, 29.0));

    await Future<void>.delayed(Duration.zero);

    expect(recorder.points, hasLength(1));

    expect(recorder.pointsCount.value, 1);
  });

  test('точки дальше 3 м пишутся, счётчик растёт', () async {
    recorder.start();

    controller.add(pos(36.0, 29.0));

    await Future<void>.delayed(Duration.zero);

    // ~11 м на север.
    controller.add(pos(36.0001, 29.0));

    await Future<void>.delayed(Duration.zero);

    expect(recorder.points, hasLength(2));

    expect(recorder.pointsCount.value, 2);
  });

  test('stop отдаёт точки и выключает запись', () async {
    recorder.start();

    controller.add(pos(36.0, 29.0));

    await Future<void>.delayed(Duration.zero);

    final points = recorder.stop();

    expect(points, hasLength(1));

    expect(recorder.isRecording, isFalse);

    // После stop поток больше не пишется.
    controller.add(pos(36.001, 29.0));

    await Future<void>.delayed(Duration.zero);

    expect(recorder.points, hasLength(1));
  });

  test('повторный start очищает предыдущий трек', () async {
    recorder.start();

    controller.add(pos(36.0, 29.0));

    await Future<void>.delayed(Duration.zero);

    recorder.stop();

    recorder.start();

    expect(recorder.points, isEmpty);

    expect(recorder.pointsCount.value, 0);
  });

  test('повторный start во время записи — no-op', () async {
    recorder.start();

    controller.add(pos(36.0, 29.0));

    await Future<void>.delayed(Duration.zero);

    final startedAt = recorder.startedAt;

    recorder.start();

    expect(recorder.startedAt, startedAt);

    expect(recorder.points, hasLength(1));
  });
}
