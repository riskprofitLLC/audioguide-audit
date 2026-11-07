// П6 (12-й проход): блок-квиз `:::quiz … :::` — парсер и
// карточка «Проверьте себя» (выбор, подсветка, пояснение).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/content/presentation/widgets/quiz_card.dart';
import 'package:island_guide/features/content/services/markdown_blocks.dart';

void main() {
  group('parseMarkdownBlocks: :::quiz (П6)', () {
    test('вопрос, варианты, пояснение разбираются', () {
      const raw = '''
Первый абзац статьи.

:::quiz
Что звенело на острове по вечерам?
+ Якорные цепи
- Колокола
- Птицы
> Якорные цепи звенели у причала, когда лодки качались на волнах.
:::

Последний абзац.
''';

      final blocks = parseMarkdownBlocks(raw);

      // Абзац — квиз — абзац.
      expect(blocks, hasLength(3));

      final quiz = blocks[1];

      expect(quiz, isA<MdQuiz>());

      final mdQuiz = quiz as MdQuiz;

      expect(mdQuiz.question, 'Что звенело на острове по вечерам?');

      expect(mdQuiz.options, hasLength(3));

      expect(mdQuiz.options[0].text, 'Якорные цепи');
      expect(mdQuiz.options[0].correct, isTrue);

      expect(mdQuiz.options[1].correct, isFalse);
      expect(mdQuiz.options[2].correct, isFalse);

      expect(mdQuiz.note, contains('Якорные цепи'));
    });

    test('квиз без пояснения и без пары-опции не ломает статью',
        () {
      const raw = '''
:::quiz
Вопрос без вариантов?
:::

Текст после.
''';

      final blocks = parseMarkdownBlocks(raw);

      // Блок без вариантов отбрасывается, статья цела.
      expect(blocks, hasLength(1));
      expect(blocks[0], isA<MdParagraph>());
    });

    test('квиз не попадает в plain-текст статьи', () {
      const raw = '''
Абзац.

:::quiz
Вопрос?
+ Да
- Нет
:::
''';

      final blocks = parseMarkdownBlocks(raw);

      final plain = blocks
          .map((b) => b is MdParagraph || b is MdHeading
              ? blockPlainText(b)
              : '')
          .join();

      expect(plain, contains('Абзац'));
      expect(plain, isNot(contains('Вопрос?')));
      expect(plain, isNot(contains('Да')));
    });
  });

  group('QuizCard (П6)', () {
    const quiz = MdQuiz(
      'Чьё имя носил остров?',
      [
        MdQuizOption('Святого Николая', correct: true),
        MdQuizOption('Святого Павла', correct: false),
      ],
      note: 'Николай — покровитель моряков.',
    );

    Future<void> pumpCard(WidgetTester tester) {
      return tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: QuizCard(quiz: quiz)),
        ),
      );
    }

    testWidgets('до ответа — варианты кнопками, пояснения нет',
        (tester) async {
      await pumpCard(tester);

      expect(find.text('Проверьте себя'), findsOneWidget);
      expect(find.text('Чьё имя носил остров?'), findsOneWidget);
      expect(find.text('Святого Николая'), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleCheck), findsNothing);
      expect(find.textContaining('Николай — покровитель'), findsNothing);
    });

    testWidgets('верный ответ: успех, пояснение открыто (П6)',
        (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text('Святого Николая'));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
      expect(find.textContaining('Николай — покровитель'), findsOneWidget);
    });

    testWidgets('неверный ответ: сигнал у выбранного, верный виден',
        (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text('Святого Павла'));
      await tester.pumpAndSettle();

      // Выбранный неверный — крестик.
      expect(find.byIcon(LucideIcons.circleX), findsOneWidget);

      // Верный — галочка.
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);

      // Повторный тап заблокирован: крестик один, не два.
      await tester.tap(find.text('Святого Павла'));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.circleX), findsOneWidget);
    });
  });
}
