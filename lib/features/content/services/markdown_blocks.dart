import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Инлайновый сегмент абзаца markdown (B3.4, 8-й проход).
sealed class MdSpan {
  const MdSpan();

  String get plainText;
}

/// Обычный текст.
class MdText extends MdSpan {
  const MdText(this.text);

  final String text;

  @override
  String get plainText => text;
}

/// *Курсив*.
class MdItalic extends MdSpan {
  const MdItalic(this.text);

  final String text;

  @override
  String get plainText => text;
}

/// **Жирный**.
class MdBold extends MdSpan {
  const MdBold(this.text);

  final String text;

  @override
  String get plainText => text;
}

/// ==Красное выделение== (админка: кнопка «Красный», маркер `==`;
/// сериализуется как `==**текст**==` — всегда жирное).
class MdRed extends MdSpan {
  const MdRed(this.text, {this.bold = true});

  final String text;

  final bool bold;

  @override
  String get plainText => text;
}

/// [текст](url) — ссылка.
class MdLink extends MdSpan {
  const MdLink(this.text, this.url);

  final String text;

  final String url;

  @override
  String get plainText => text;
}

/// Блок markdown-документа.
sealed class MdBlock {
  const MdBlock();
}

/// Абзац (спаны инлайновой разметки).
class MdParagraph extends MdBlock {
  const MdParagraph(this.spans);

  final List<MdSpan> spans;
}

/// Подзаголовок `## …` — h3 Manrope 800 (не строка текста).
class MdHeading extends MdBlock {
  const MdHeading(this.text);

  final String text;
}

/// Пункт маркированного списка `- …`.
class MdListItem extends MdParagraph {
  MdListItem(super.spans);
}

/// Вариант ответа квиза (П6, 12-й проход).
class MdQuizOption {
  const MdQuizOption(this.text, {required this.correct});

  final String text;

  final bool correct;
}

/// Блок-квиз `:::quiz … :::` (П6, 12-й проход): вопрос, варианты
/// (`+` — верный, `-` — неверный) и пояснение `>` после ответа.
/// Внутри статьи не рендерится текстом — карточкой ниже
/// (expandable_text пропускает, poi-страница рисует QuizCard).
class MdQuiz extends MdBlock {
  const MdQuiz(this.question, this.options, {this.note});

  final String question;

  final List<MdQuizOption> options;

  final String? note;
}

/// Простой парсер markdown полных текстов POI (B3.4, 8-й проход).
///
/// Минимальный, но честный рендер: подзаголовки `##`/`###` —
/// отдельными блоками (h3), маркированные списки — пунктами с
/// буллетом, инлайновые `*курсив*` / `**жирный**` / `[ссылка](url)` —
/// сегментами. Остальная разметка не поддерживается
/// (таблиц/блок-цитат в текстах нет).
///
/// Заголовок `# …` (H1) выбрасывается: он уже показан карточкой POI.
List<MdBlock> parseMarkdownBlocks(String raw) {
  final blocks = <MdBlock>[];

  // Абзацы собираются по пустым строкам; строки списков —
  // отдельными пунктами (смежные пункты образуют список).
  final spans = <MdSpan>[];

  void flushParagraph() {
    if (spans.isEmpty) {
      return;
    }

    blocks.add(MdParagraph(List.unmodifiable(spans)));

    spans.clear();
  }

  final lines = raw.split('\n');

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex].trim();

    // Пустая строка — граница абзаца.
    if (line.isEmpty) {
      flushParagraph();

      continue;
    }

    // Блок-квиз (П6): `:::quiz` … `:::` собирается до конца
    // блока, абзац до него закрыт.
    if (line == ':::quiz') {
      flushParagraph();

      var question = '';

      final options = <MdQuizOption>[];

      String? note;

      while (++lineIndex < lines.length) {
        final quizLine = lines[lineIndex].trim();

        if (quizLine == ':::') {
          break;
        }

        if (quizLine.startsWith('+ ')) {
          options.add(MdQuizOption(quizLine.substring(2), correct: true));
        } else if (quizLine.startsWith('- ')) {
          options.add(MdQuizOption(quizLine.substring(2), correct: false));
        } else if (quizLine.startsWith('> ')) {
          note = quizLine.substring(2);
        } else if (quizLine.isNotEmpty && question.isEmpty) {
          question = quizLine;
        }
      }

      if (question.isNotEmpty && options.isNotEmpty) {
        blocks.add(MdQuiz(question, options, note: note));
      }

      continue;
    }

    // H1 — заголовок самого файла, в статье не нужен.
    if (line.startsWith('# ')) {
      flushParagraph();

      continue;
    }

    // Подзаголовок — отдельный блок.
    if (line.startsWith('## ') || line.startsWith('### ')) {
      flushParagraph();

      blocks.add(MdHeading(line.replaceFirst(RegExp(r'^#{2,6}\s*'), '')));

      continue;
    }

    // Пункт списка: `- текст` / `* текст` (в начале строки).
    if (RegExp(r'^[-*]\s+').hasMatch(line)) {
      flushParagraph();

      blocks.add(MdListItem(parseInline(line.replaceFirst(RegExp(r'^[-*]\s+'), ''))));

      continue;
    }

    // Строка абзаца: инлайновая разметка.
    final parsed = parseInline(line);

    // Склейка строк одного абзаца пробелом (мягкий перенос).
    if (spans.isNotEmpty) {
      spans.add(const MdText(' '));
    }

    spans.addAll(parsed);
  }

  flushParagraph();

  return blocks;
}

/// Инлайновая разметка: **жирный**, __жирный__, *курсив*, [текст](url).
List<MdSpan> parseInline(String text) {
  final spans = <MdSpan>[];

  // Жирный раньше курсива: ** не должен ловиться как два *.
  final linkPattern = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');

  var position = 0;

  // Ссылки вырезаются первыми: их текст может содержать *.
  final linkMatches = linkPattern.allMatches(text).toList();

  for (final link in linkMatches) {
    if (link.start > position) {
      spans.addAll(_inlineNoLinks(text.substring(position, link.start)));
    }

    spans.add(MdLink(link.group(1)!, link.group(2)!));

    position = link.end;
  }

  if (position < text.length) {
    spans.addAll(_inlineNoLinks(text.substring(position)));
  }

  return spans;
}

List<MdSpan> _inlineNoLinks(String text) {
  final spans = <MdSpan>[];

  // Красное выделение ==…== ловим первым: внутри жирного/курсива
  // оно не разбирается, поэтому вырезаем до остальной разметки.
  final redPattern = RegExp(r'==(.+?)==');

  var position = 0;

  for (final match in redPattern.allMatches(text)) {
    if (match.start > position) {
      spans.addAll(_inlineBoldItalic(text.substring(position, match.start)));
    }

    var inner = match.group(1)!;

    var bold = true;

    if (inner.startsWith('**') && inner.endsWith('**') && inner.length > 4) {
      inner = inner.substring(2, inner.length - 2);
    } else {
      bold = false;
    }

    spans.add(MdRed(inner, bold: bold));

    position = match.end;
  }

  if (position < text.length) {
    spans.addAll(_inlineBoldItalic(text.substring(position)));
  }

  return spans;
}

List<MdSpan> _inlineBoldItalic(String text) {
  final spans = <MdSpan>[];

  final boldPattern = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');

  var position = 0;

  for (final match in boldPattern.allMatches(text)) {
    if (match.start > position) {
      spans.addAll(_plainItalic(text.substring(position, match.start)));
    }

    spans.add(MdBold(match.group(1) ?? match.group(2)!));

    position = match.end;
  }

  if (position < text.length) {
    spans.addAll(_plainItalic(text.substring(position)));
  }

  return spans;
}

/// Курсив: *текст* (нижние подчёркивания заняты записью URL).
final RegExp _italicMatcher = RegExp(r'\*(.+?)\*');

List<MdSpan> _plainItalic(String text) {
  final spans = <MdSpan>[];

  var position = 0;

  for (final match in _italicMatcher.allMatches(text)) {
    if (match.start > position) {
      spans.add(MdText(text.substring(position, match.start)));
    }

    spans.add(MdItalic(match.group(1)!));

    position = match.end;
  }

  if (position < text.length) {
    spans.add(MdText(text.substring(position)));
  }

  return spans;
}

/// Текстовое представление блока (для замеров и кешей).
String blockPlainText(MdBlock block) {
  return block.spansPlain.map((s) => s.plainText).join();
}

extension on MdBlock {
  Iterable<MdSpan> get spansPlain => switch (this) {
        // MdListItem — наследник MdParagraph, общий кейс.
        MdParagraph(:final spans) => spans,
        MdHeading(:final text) => [MdText(text)],
        // Квиз в текст статьи не входит (П6).
        MdQuiz() => const <MdSpan>[],
      };
}

/// Рендер блока в [Text.rich]: подзаголовок — h3 (Manrope 800),
/// пункт списка — с буллетом, абзац — спаны с инлайновой
/// типографикой. Буквица — внешняя логика (первый абзац).
TextSpan mdBlockTextSpan(
  MdBlock block, {
  TextStyle? style,
  TextStyle? headingStyle,
  bool dropCap = false,
}) {
  final base = style ?? AppText.bodyL;

  // Квиз — НЕ текст статьи (П6): карточку рисует страница POI
  // ниже ExpandableText, в потоке статьи блока не видно.
  if (block is MdQuiz) {
    return const TextSpan(text: '');
  }

  if (block is MdHeading) {
    return TextSpan(
      text: block.text,
      style: headingStyle ??
          base.copyWith(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w800,
            fontSize: 17,
            height: 1.25,
          ),
    );
  }

  if (block is MdListItem) {
    return TextSpan(
      style: base,
      children: [
        const TextSpan(text: '•  '),
        ..._spansToTextSpans(block.spans, base),
      ],
    );
  }

  if (block is MdParagraph) {
    if (dropCap && block.spans.isNotEmpty) {
      // Буквица — первый ГРАФ первого абзаца (Prata, один вес).
      final chars = blockPlainText(block).characters;

      if (chars.isNotEmpty) {
        final first = chars.first;

        // Остальное — исходные спаны без первого графа.
        return TextSpan(
          style: base,
          children: [
            TextSpan(
              text: first,
              style: base.copyWith(
                fontFamily: 'Prata',
                fontWeight: FontWeight.w400,
                fontSize: (base.fontSize ?? 16) * 2.05,
                height: 0.92,
                letterSpacing: 0,
              ),
            ),
            ..._spansWithoutLeadingGlyph(block.spans, first, base),
          ],
        );
      }
    }

    return TextSpan(
      style: base,
      children: _spansToTextSpans(block.spans, base),
    );
  }

  return TextSpan(text: '', style: base);
}

List<TextSpan> _spansToTextSpans(List<MdSpan> spans, TextStyle base) {
  return [
    for (final span in spans)
      switch (span) {
        MdText(:final text) => TextSpan(text: text),
        MdItalic(:final text) => TextSpan(
            text: text,
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        MdBold(:final text) => TextSpan(
            text: text,
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
        MdRed(:final text, :final bold) => TextSpan(
            text: text,
            // Тёмно-красный redText — заметнее signal на светлом фоне;
            // красное выделение всегда жирное (bold по умолчанию true).
            style: base.copyWith(
              color: AppColors.redText,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        MdLink(:final text) => TextSpan(
            text: text,
            // D5 (замечание Sonnet): ссылка не может быть «ложно
            // кликабельной» — подчёркивание и бирюза без тапа
            // обманывают. В контенте оффлайн-статей внешних
            // ссылок нет, url_launcher не в офлайн-кеше —
            // рендерим нейтральный текст (как MdText), не имитируя
            // клик.
          ),
      },
  ];
}

/// Спаны без ведущего графа (буквица уже отрисована отдельно).
///
/// Граф срезается ТОЛЬКО у первого непустого спана (баг 6,
/// замечания Sonnet): прежний код резал каждый спан, начинающийся
/// с той же буквы (абзац «О… *О*тец» терял вторую «О»), а длина
/// считалась в ГРАФЕМАХ — у «е+ударение» оставалось висячее
/// ударение. Теперь длина — в UTF-16 единицах самой строки
/// первого графа (`firstGrapheme.length`).
List<TextSpan> _spansWithoutLeadingGlyph(
  List<MdSpan> spans,
  String firstGrapheme,
  TextStyle base,
) {
  final result = <TextSpan>[];

  var cut = false;

  for (final span in spans) {
    var text = span.plainText;

    if (text.isEmpty) {
      continue;
    }

    if (!cut) {
      cut = true;

      // Первый непустой спан обязан начинаться тем же графом:
      // он получен склейкой plainText этих спанов.
      if (text.startsWith(firstGrapheme)) {
        text = text.substring(firstGrapheme.length);
      }
    }

    if (text.isEmpty) {
      continue;
    }

    result.addAll(_spansToTextSpans(
      switch (span) {
        MdText() => [MdText(text)],
        MdItalic() => [MdItalic(text)],
        MdBold() => [MdBold(text)],
        MdRed(:final bold) => [MdRed(text, bold: bold)],
        MdLink(:final url) => [MdLink(text, url)],
      },
      base,
    ));
  }

  return result;
}
