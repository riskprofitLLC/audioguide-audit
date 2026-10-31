// Пункт 5 замечаний Sonnet: резолв пути аудио при падающей
// загрузке локации не должен ретраиться на каждом тике позиции.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/settings/providers/listened_providers.dart';

void main() {
  setUp(() {
    debugResetPlayedPoiCache();
  });

  tearDown(() {
    loadPoisForTest = null;

    debugResetPlayedPoiCache();
  });

  test('10 тиков при падающей загрузке → 1 обращение за окно', () async {
    var calls = 0;

    loadPoisForTest = (location) async {
      calls += 1;

      throw StateError('провайдер локации недоступен');
    };

    final file =
        'content/fethiye/gemiler/audio/way/poi-01.mp3';

    // Первый вызов — падает и попадает в негативный кеш.
    final first = await resolvePlayedPoiForTests('fake', file);

    // 10 тиков позиции подряд в том же окне TTL.
    final results = <(String, String, int?)?>[];

    for (var i = 0; i < 10; i++) {
      results.add(await resolvePlayedPoiForTests('fake', file));
    }

    expect(calls, 1, reason: 'негативный кеш: дубли не дёргают загрузку');
    expect(first, isNull);
    expect(results, everyElement(isNull));
  });

  test('in-flight дедуп: параллельные тики ждут один запрос', () async {
    var calls = 0;

    loadPoisForTest = (location) async {
      calls += 1;

      // Задержка эмулирует медленную загрузку: тики приходят чаще.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      return [];
    };

    final file = 'content/fethiye/gemiler/audio/way/poi-02.mp3';

    final batch = List.generate(
      10,
      (_) => resolvePlayedPoiForTests('fethiye', file),
    );

    final results = await Future.wait(batch);

    expect(calls, 1, reason: 'параллельные тики дедупицируются');
    // Пустой список — честное «нет такой точки», кешируется.
    expect(results, everyElement(isNull));
  });

  test('успешный резолв кешируется навсегда (путь стабилен)', () async {
    var calls = 0;

    loadPoisForTest = (location) async {
      calls += 1;

      return [];
    };

    final file = 'content/fethiye/gemiler/audio/way/poi-03.mp3';

    for (var i = 0; i < 5; i++) {
      await resolvePlayedPoiForTests('fethiye', file);
    }

    expect(calls, 1);
  });
}
