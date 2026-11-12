// Тесты сопоставления файла полного текста POI с номером папки.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/services/poi_text_loader.dart';

void main() {
  group('PoiTextLoader.matchesTextAsset', () {
    const base = 'content/fethiye/gemiler';

    test('файл своей папки матчится', () {
      expect(
        PoiTextLoader.matchesTextAsset('$base/text/01 - Церковь.md', base, 1),
        isTrue,
      );

      expect(
        PoiTextLoader.matchesTextAsset('$base/text/11 - Погост.md', base, 11),
        isTrue,
      );
    });

    test('«101 - …» не матчится с номером 1 (contains-ловушка)', () {
      // Раньше шёл через contains('01 - '): имя «101 - …»
      // содержит подстроку «01 - », и номер 1 мог «найти» чужой
      // файл (или firstOrNull брал не тот из нескольких).
      expect(
        PoiTextLoader.matchesTextAsset('$base/text/101 - Far.md', base, 1),
        isFalse,
      );
    });

    test('файл чужой папки не матчится', () {
      expect(
        PoiTextLoader.matchesTextAsset('$base/text/11 - Погост.md', base, 1),
        isFalse,
      );

      expect(
        PoiTextLoader.matchesTextAsset(
          'content/lykia/coast/text/01 - Plyazh.md',
          base,
          1,
        ),
        isFalse,
      );
    });

    test('файлы вне text/ не матчатся', () {
      expect(
        PoiTextLoader.matchesTextAsset('$base/audio/01 - X.mp3', base, 1),
        isFalse,
      );
    });
  });

  group('PoiTextLoader.stripMarkdownTitle (markdown к показу)', () {
    test('H1 выбрасывается, подзаголовки теряют решётки', () {
      final result = PoiTextLoader.stripMarkdownTitle(
        '# Заголовок файла\n'
        '## Подзаголовок\n'
        'Текст после подзаголовка.',
      );

      expect(result, 'Подзаголовок\nТекст после подзаголовка.');
    });

    test('инлайновые **жирный**/__жирный__ не показываются звёздочками',
        () {
      final result = PoiTextLoader.stripMarkdownTitle(
        '**Живописные острова** и __природные локации__ в заливе.',
      );

      expect(result, 'Живописные острова и природные локации в заливе.');
      expect(result.contains('**'), isFalse);
      expect(result.contains('__'), isFalse);
    });
  });
}
