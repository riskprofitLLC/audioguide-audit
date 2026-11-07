// Панель выделенных слов админки: живой список из диапазонов
// rich-модели — слова появляются сразу после «Красный» и уезжают
// в поле highlightedWords poi.json при сохранении.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/admin/presentation/widgets/highlighted_words_panel.dart';

void main() {
  testWidgets('слова показаны чипами со счётчиком в шапке', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HighlightedWordsPanel(words: ['базилики', 'подъём']),
        ),
      ),
    );

    expect(find.text('ВЫДЕЛЕННЫЕ СЛОВА · 2'), findsOneWidget);

    expect(find.text('базилики'), findsOneWidget);

    expect(find.text('подъём'), findsOneWidget);

    expect(find.byKey(const ValueKey('highlighted-word-0')), findsOneWidget);

    expect(find.byKey(const ValueKey('highlighted-word-1')), findsOneWidget);
  });

  testWidgets('пустой список — подсказка вместо чипов', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HighlightedWordsPanel(words: []),
        ),
      ),
    );

    expect(find.textContaining('Выдели слово'), findsOneWidget);

    expect(find.text('ВЫДЕЛЕННЫЕ СЛОВА · 0'), findsNothing);

    expect(find.byKey(const Key('highlighted-words-panel')), findsOneWidget);
  });
}
