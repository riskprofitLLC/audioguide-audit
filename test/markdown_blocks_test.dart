// B3.4 (8-й проход): парсер markdown-блоков полных текстов POI.
//
// Подзаголовки `##` — отдельные блоки (h3), списки — пункты с
// буллетом, инлайн `*курсив*`/`**жирный**`/`[ссылка](url)` —
// сегменты. H1 выбрасывается (заголовок уже есть в карточке).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/theme.dart';
import 'package:island_guide/features/content/services/markdown_blocks.dart';

void main() {
  test('абзацы, подзаголовок, список, инлайн', () {
    const raw = '''
# Заголовок файла

Первый абзац с *курсивом* и **жирным**.

## Как добраться

- на лодке из Олюдениза
- пешком по тропе

Финальный абзац со [ссылкой](https://example.com) в тексте.
''';

    final blocks = parseMarkdownBlocks(raw);

    // H1 выброшен.
    expect(blocks, hasLength(5));

    // Абзац с инлайновой разметкой.
    final first = blocks[0] as MdParagraph;
    final kinds = first.spans.map((s) => s.runtimeType).toSet();
    expect(kinds, containsAll([MdText, MdItalic, MdBold]));

    // Подзаголовок — отдельный блок.
    final heading = blocks[1] as MdHeading;
    expect(heading.text, 'Как добраться');

    // Список — пункты.
    final item1 = blocks[2] as MdListItem;
    expect(item1.spans.first.plainText, 'на лодке из Олюдениза');
    final item2 = blocks[3] as MdListItem;
    expect(item2.spans.first.plainText, 'пешком по тропе');

    // Ссылка — сегмент с url.
    final last = blocks[4] as MdParagraph;
    final link = last.spans.whereType<MdLink>().first;
    expect(link.text, 'ссылкой');
    expect(link.url, 'https://example.com');
  });

  test('==**красное выделение**== → MdRed (жирный), рендер красным', () {
    final blocks = parseMarkdownBlocks('Это ==**очень важно**== для похода.');

    final para = blocks.single as MdParagraph;
    final red = para.spans.whereType<MdRed>().single;

    expect(red.plainText, 'очень важно');
    // Plain-текст сохраняется целиком (замеры/кеши не ломаются).
    expect(blockPlainText(blocks.single), 'Это очень важно для похода.');

    final span = mdBlockTextSpan(blocks.single, style: const TextStyle(fontSize: 16));
    final redSpan = span.children!.whereType<TextSpan>().firstWhere(
          (s) => s.text == 'очень важно',
        );
    expect(redSpan.style!.color, AppColors.redText);
    expect(redSpan.style!.fontWeight, FontWeight.w700);
  });

  test('пустой текст — пустой список блоков', () {
    expect(parseMarkdownBlocks(''), isEmpty);
    expect(parseMarkdownBlocks('\n \n'), isEmpty);
  });

  test('рендер: подзаголовок стилем h3, список с буллетом', () {
    final blocks = parseMarkdownBlocks('## Подзаголовок\n\n- пункт');

    final headingSpan = mdBlockTextSpan(blocks[0]);
    expect(headingSpan.style?.fontWeight, FontWeight.w800);
    expect(headingSpan.toPlainText(), 'Подзаголовок');

    final listSpan = mdBlockTextSpan(blocks[1]);
    expect(listSpan.toPlainText(), startsWith('•  '));
    expect(listSpan.toPlainText(), contains('пункт'));
  });

  test('буквица первого абзаца: первый граф — Prata, спаны живы', () {
    final blocks = parseMarkdownBlocks('*Курсивное* начало абзаца.');

    final span = mdBlockTextSpan(blocks[0], dropCap: true);

    final children = span.children!;

    // Первый граф — буквица.
    expect(children.first.style?.fontFamily, 'Prata');
    expect(children.first.toPlainText(), 'К');

    // Инлайн-разметка остального абзаца не потерялась.
    final rest = children
        .skip(1)
        .map((c) => c.toPlainText())
        .join();
    expect(rest, contains('урсивное'));
    expect(
      children.any((c) => c.style?.fontStyle == FontStyle.italic),
      isTrue,
      reason: 'курсивная часть абзаца сохраняется с буквицей',
    );
  });

  test('буквица: граф срезается ТОЛЬКО у первого спана (баг 6, '
      'замечания Sonnet)', () {
    // Абзац «О… *О*тец»: курсивный спан начинается с той же буквы,
    // но это НЕ продолжение буквицы — раньше «О» терялась и у него.
    final blocks = parseMarkdownBlocks('Остров. *О*тец смотрит на море.');

    final span = mdBlockTextSpan(blocks[0], dropCap: true);

    final text = span.toPlainText();

    expect(span.children!.first.toPlainText(), 'О');

    expect(
      text,
      contains('Отец'),
      reason: 'курсивный спан сохранил свою ведущую «О»',
    );

    expect(text, contains('стров'));
  });

  test('буквица: граф из нескольких UTF-16 единиц (е + ударение) '
      'срезается целиком (баг 6)', () {
    // «е\u0301» — один ГРАФ из двух UTF-16 единиц: прежний
    // substring по графемам оставлял висячее ударение.
    final blocks = parseMarkdownBlocks('е\u0301сли море спокойно.');

    final span = mdBlockTextSpan(blocks[0], dropCap: true);

    final children = span.children!;

    expect(children.first.toPlainText(), 'е\u0301');

    final rest = children
        .skip(1)
        .map((c) => c.toPlainText())
        .join();

    expect(rest, startsWith('сли'));
    expect(
      rest,
      isNot(contains('\u0301')),
      reason: 'ударение не должно оставаться висеть',
    );
  });
}
