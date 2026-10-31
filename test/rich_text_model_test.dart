// Rich-модель редактора «как в Word» (замечание владельца):
// в поле чистый текст, разметка — в диапазонах; при сериализации
// звёздочки восстанавливаются.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/admin/services/rich_text_model.dart';

void main() {
  group('parseRich', () {
    test('жирный и курсив уходят в диапазоны, звёздочек в тексте нет', () {
      final doc = parseRich('Текст **смелый** и *курсив* конец');

      expect(doc.plain, 'Текст смелый и курсив конец');

      expect(doc.spans.length, 2);

      expect(doc.plain.substring(doc.spans[0].start, doc.spans[0].end), 'смелый');
      expect(doc.spans[0].bold, isTrue);

      expect(doc.plain.substring(doc.spans[1].start, doc.spans[1].end), 'курсив');
      expect(doc.spans[1].italic, isTrue);
    });

    test('текст без разметки — без диапазонов', () {
      final doc = parseRich('Просто текст\n\nЕщё абзац');

      expect(doc.plain, 'Просто текст\n\nЕщё абзац');
      expect(doc.spans, isEmpty);
    });

    test('==красный== уходит в red-диапазон, «==» в тексте нет', () {
      final doc = parseRich('Текст ==важное== конец');

      expect(doc.plain, 'Текст важное конец');
      expect(doc.spans, hasLength(1));
      expect(doc.plain.substring(doc.spans[0].start, doc.spans[0].end), 'важное');
      expect(doc.spans[0].red, isTrue);
      expect(doc.spans[0].bold, isFalse);
      expect(doc.spans[0].italic, isFalse);
    });
  });

  group('serializeRich', () {
    test('roundtrip: parse→serialize сохраняет текст и разметку', () {
      const md = 'Текст **смелый** и *курсив* конец';

      final doc = parseRich(md);

      expect(serializeRich(doc.plain, doc.spans), md);
    });

    test('bold+italic → ***текст***', () {
      expect(
        serializeRich(
          'важно',
          const [RichSpan(0, 5, bold: true, italic: true)],
        ),
        '***важно***',
      );
    });

    test('текст без стилей — как есть', () {
      expect(serializeRich('Просто текст', const []), 'Просто текст');
    });

    test('red → ==текст== (roundtrip с parseRich)', () {
      const md = 'Текст ==**важное**== конец';

      final doc = parseRich(md);

      expect(serializeRich(doc.plain, doc.spans), md);
      expect(serializeRich('важное', const [RichSpan(0, 6, bold: false, italic: false, red: true)]), '==**важное**==');
    });
  });

  group('toggleStyle', () {
    const plain = 'Текст смелый и курсив';

    test('выделение + жирный → диапазон добавлен', () {
      final spans = toggleStyle(const [], plain, 6, 12, bold: true);

      expect(spans.length, 1);

      expect(plain.substring(spans.first.start, spans.first.end), 'смелый');
      expect(spans.first.bold, isTrue);
    });

    test('полное покрытие + повторное применение снимает стиль', () {
      const plain = 'Текст смелый и курсив';

      final spans1 = toggleStyle(const [], plain, 6, 12, bold: true);

      final spans2 = toggleStyle(spans1, plain, 6, 12, bold: true);

      expect(spans2.where((s) => s.bold), isEmpty);
    });
  });

  group('adjustSpans', () {
    test('вставка перед диапазоном сдвигает его на длину вставки', () {
      const oldPlain = 'смелый курсив';

      final shifted = adjustSpans(
        const [RichSpan(0, 6, bold: true, italic: false)],
        oldPlain,
        'раз два смелый курсив',
      );

      expect(shifted.single.start, 8);
      expect(shifted.first.end, 14);
    });

    test('удаление до диапазона тоже сдвигает', () {
      const oldPlain = 'аа смелый';

      final shifted = adjustSpans(
        const [RichSpan(3, 9, bold: true, italic: false)],
        oldPlain,
        'смелый',
      );

      expect(shifted.single.start, 0);

      expect(shifted.first.end, 6);
    });

    test('удаление внутри диапазона обрезает его', () {
      const oldPlain = 'Текст смелый';

      final spans = adjustSpans(
        const [RichSpan(6, 12, bold: true, italic: false)],
        oldPlain,
        'Текст смлый',
      );

      // «е» удалена из середины: диапазон уменьшился на 1.
      expect(spans.first.end - spans.first.start, 5);
    });
  });
}
