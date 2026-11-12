import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/trails/models/trail_point.dart';

void main() {

  test('TrailPoint.fromJson читает обязательные поля', () {

    final point = TrailPoint.fromJson({
      'id': 'p1',
      'latitude': 42.93,
      'longitude': 131.75,
      'order': 3,
    });

    expect(point.id, 'p1');
    expect(point.latitude, 42.93);
    expect(point.longitude, 131.75);
    expect(point.order, 3);
  });

  test('TrailPoint.fromJson кидает FormatException без координат', () {

    expect(
      () => TrailPoint.fromJson({
        'id': 'p1',
        'latitude': 42.93,
      }),
      throwsFormatException,
    );

    expect(
      () => TrailPoint.fromJson({
        'id': 'p1',
        'longitude': 131.75,
      }),
      throwsFormatException,
    );
  });

  test('TrailPoint.fromJson кидает FormatException без id', () {

    expect(
      () => TrailPoint.fromJson({
        'latitude': 42.93,
        'longitude': 131.75,
      }),
      throwsFormatException,
    );
  });
}