// П9 (29-й проход): план дня из набора точек — пешее время
// между соседями (4 км/ч) + длительность аудио, итоговая оценка.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/models/manifest.dart';
import 'package:island_guide/features/favorites/models/user_collection.dart';
import 'package:island_guide/features/favorites/presentation/widgets/day_plan_sheet.dart';
import 'package:island_guide/features/favorites/utils/day_plan.dart';
import 'package:island_guide/features/poi/models/poi.dart';

void main() {
  group('computeDayPlan', () {
    test('две точки: пешее время между ними + аудио, итог', () {
      final a = const Poi(
        id: 'poi-01',
        title: 'A',
        latitude: 36.0,
        longitude: 29.0,
        radius: 50,
        description: '',
        category: 'bay',
        audioMs: 6 * 60 * 1000,
      );

      // ~1,11 км на север — пешком ~17 мин.
      final b = const Poi(
        id: 'poi-02',
        title: 'B',
        latitude: 36.01,
        longitude: 29.0,
        radius: 50,
        description: '',
        category: 'bay',
      );

      final plan = computeDayPlan([a, b]);

      expect(plan.legs.length, 2);

      expect(plan.legs.first.walkMeters, 0);

      expect(plan.legs.first.audioMinutes, 6);

      expect(plan.legs[1].walkMinutes, 17);

      expect(plan.legs[1].audioMinutes, 0);

      expect(plan.walkMinutes, 17);

      expect(plan.audioMinutes, 6);

      expect(plan.totalMinutes, 23);

      expect(plan.totalLabel, '23 мин');
    });

    test('formatMinutes: часы и минуты', () {
      expect(formatMinutes(59), '59 мин');

      expect(formatMinutes(60), '1 ч');

      expect(formatMinutes(80), '1 ч 20 мин');
    });

    test('пустой план — нули', () {
      final plan = computeDayPlan(const []);

      expect(plan.legs, isEmpty);

      expect(plan.totalMinutes, 0);
    });
  });

  group('buildDayPlanSources', () {
    const preset = PresetCollection(
      name: 'Гемилер: главные точки',
      keys: ['gemiler/poi-01', 'gemiler/poi-02'],
    );

    test('готовые подборки — источник плана наравне со своими (фикс)', () {
      final sources = buildDayPlanSources(
        favorites: const {},
        presets: const [preset],
        hiddenPresets: const {},
        collections: const [],
      );

      expect(sources, hasLength(1));

      expect(sources.single.name, 'Гемилер: главные точки');

      expect(sources.single.keys, hasLength(2));

      expect(sources.single.id, startsWith('preset-'));
    });

    test('скрытая пользователем подборка не предлагается', () {
      final sources = buildDayPlanSources(
        favorites: const {},
        presets: const [preset],
        hiddenPresets: const {'Гемилер: главные точки'},
        collections: const [],
      );

      expect(sources, isEmpty);
    });

    test('избранное, готовые и свои — порядок и уникальные id', () {
      final sources = buildDayPlanSources(
        favorites: const {'gemiler/poi-03'},
        presets: const [preset],
        hiddenPresets: const {},
        collections: const [
          UserCollection(
            id: 'c1',
            name: 'Гемилер: главные точки',
            keys: {'gemiler/poi-04'},
          ),
          UserCollection(id: 'c2', name: 'Пустая', keys: {}),
        ],
      );

      expect(
        sources.map((s) => s.name).toList(),
        ['Избранное', 'Гемилер: главные точки', 'Гемилер: главные точки'],
      );

      // Одинаковые названия у готовой и своей подборки — ключи
      // виджетов обязаны различаться (иначе Duplicate keys).
      expect(sources.map((s) => s.id).toSet(), hasLength(3));

      // Пустая своя подборка в список не попадает.
      expect(sources.where((s) => s.name == 'Пустая'), isEmpty);
    });
  });
}
