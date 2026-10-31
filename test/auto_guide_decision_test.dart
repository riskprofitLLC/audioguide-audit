// A5 (9-й проход): решение автогида при входе в радиус точки —
// чистая функция, поведённая из MapPage для тестов.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/audio/utils/auto_guide_decision.dart';
import 'package:island_guide/features/settings/providers/settings_providers.dart';

void main() {
  group('decideAutoGuide', () {
    test('выключен — ничего не происходит', () {
      expect(
        decideAutoGuide(
          mode: AutoGuideMode.off,
          isPlaying: false,
          currentFile: null,
          suggestedFile: 'a.mp3',
        ),
        AutoGuideDecision.ignore,
      );
    });

    test('«Всегда» — автозапуск даже поверх другого трека', () {
      expect(
        decideAutoGuide(
          mode: AutoGuideMode.always,
          isPlaying: true,
          currentFile: 'b.mp3',
          suggestedFile: 'a.mp3',
        ),
        AutoGuideDecision.play,
      );
    });

    test('«Предлагать» в тишине — автозапуск как раньше', () {
      expect(
        decideAutoGuide(
          mode: AutoGuideMode.suggest,
          isPlaying: false,
          currentFile: null,
          suggestedFile: 'a.mp3',
        ),
        AutoGuideDecision.play,
      );
    });

    test('«Предлагать» поверх другого трека — пилюля', () {
      expect(
        decideAutoGuide(
          mode: AutoGuideMode.suggest,
          isPlaying: true,
          currentFile: 'b.mp3',
          suggestedFile: 'a.mp3',
        ),
        AutoGuideDecision.suggest,
      );
    });

    test('«Предлагать» точку, которую УЖЕ слушаем — тишина (A5)', () {
      expect(
        decideAutoGuide(
          mode: AutoGuideMode.suggest,
          isPlaying: true,
          currentFile: 'a.mp3',
          suggestedFile: 'a.mp3',
        ),
        AutoGuideDecision.ignore,
        reason: 'вошли в радиус точки, чей трек играет, — пилюля '
            '«Рядом» не нужна',
      );
    });

    test('«Предлагать» точку без аудио поверх трека — тишина (A5)', () {
      expect(
        decideAutoGuide(
          mode: AutoGuideMode.suggest,
          isPlaying: true,
          currentFile: 'b.mp3',
          suggestedFile: null,
        ),
        AutoGuideDecision.ignore,
        reason: 'предложить нечего: у точки нет аудио',
      );
    });
  });
}
