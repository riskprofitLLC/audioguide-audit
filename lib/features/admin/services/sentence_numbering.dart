/// Нумерация предложений админки — ВНУТРИ текста поля.
///
/// Порядок и границы предложений — ТЕ ЖЕ, что у озвучки
/// (`tool/voicy_voice.py`): абзацы делятся по `\n`, предложения —
/// по `.` `!` `?` `…` с последующим пробелом, точка после одиночной
/// буквы («г. Москва») концом предложения не считается, счётчик
/// сквозной по всему тексту — как номера файлов 001.mp3 в озвучке.
///
/// Номер НЕ хранится в тексте статьи и не попадает в коммит: перед
/// каждым предложением в значение поля вставляются невидимые
/// заполнители [kNumberPlaceholder] ровно по числу знаков номера,
/// а отрисовка (`RichEditingController.buildTextSpan`) подставляет на
/// их место синий жирный номер. Длины значения и отрисовки совпадают
/// символ в символ — курсор и выделение не съезжают.
library;

import 'rich_text_model.dart';

/// Невидимый заполнитель номера в значении поля редактора.
const String kNumberPlaceholder = '\u200b';

/// Знаков в номере — как в именах файлов озвучки (`001.mp3`):
/// номер в тексте визуально совпадает с именем файла при сверке.
const int kNumberDigits = 3;

/// Предложение текста с границами в сыром тексте редактора.
class SentenceRef {
  const SentenceRef({
    required this.number,
    required this.paragraph,
    required this.text,
    required this.start,
    required this.end,
  });

  /// Сквозной номер (1-based) — как у файлов озвучки 001.mp3, …
  final int number;

  /// Индекс абзаца (строки текста) — для группировки списка.
  final int paragraph;

  /// Текст предложения (без разделительных пробелов).
  final String text;

  /// Границы в сыром тексте (end — исключительно).
  final int start;

  final int end;
}

// . ! ? …
const Set<int> _terminators = {0x2E, 0x21, 0x3F, 0x2026};

bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0B || c == 0x0C || c == 0x0D || c == 0x0A;

bool _isLetter(int c) {
  if (c >= 0x41 && c <= 0x5A) return true; // A-Z
  if (c >= 0x61 && c <= 0x7A) return true; // a-z
  if (c >= 0x410 && c <= 0x44F) return true; // А-я
  return c == 0x401 || c == 0x451; // Ё ё
}

bool _isWordChar(int c) => _isLetter(c) || (c >= 0x30 && c <= 0x39);

/// Точка после одиночной буквы с границей слова перед ней
/// («г. Москва», «т. д.») — не конец предложения (как защита
/// `\b([А-ЯЁA-Zа-яёa-z])\.` в озвучке).
bool _isInitialDot(String s, int i) {
  if (s.codeUnitAt(i) != 0x2E) return false;
  if (i == 0 || !_isLetter(s.codeUnitAt(i - 1))) return false;
  if (i - 1 == 0) return true;
  return !_isWordChar(s.codeUnitAt(i - 2));
}

class _Range {
  const _Range(this.start, this.end);

  final int start;

  final int end;
}

/// Абзац на предложения: границы в пределах СТРОКИ (абзаца).
List<_Range> _splitLine(String line) {
  final ranges = <_Range>[];

  var start = 0;

  var i = 0;

  while (i < line.length) {
    final c = line.codeUnitAt(i);

    if (_terminators.contains(c) && !_isInitialDot(line, i)) {
      var j = i + 1;

      while (j < line.length && _isSpace(line.codeUnitAt(j))) {
        j++;
      }

      // Разделитель — пробелы ПОСЛЕ терминатора (как `(?<=[.!?…])\s+`).
      if (j > i + 1) {
        ranges.add(_Range(start, i + 1));

        start = j;

        i = j;

        continue;
      }
    }

    i++;
  }

  if (start < line.length) {
    ranges.add(_Range(start, line.length));
  }

  // Предложение триммуется, как `.strip()` в озвучке.
  final out = <_Range>[];

  for (final r in ranges) {
    var a = r.start;

    var b = r.end;

    while (a < b && _isSpace(line.codeUnitAt(a))) {
      a++;
    }

    while (b > a && _isSpace(line.codeUnitAt(b - 1))) {
      b--;
    }

    if (b > a) {
      out.add(_Range(a, b));
    }
  }

  return out;
}

/// Строки вне нумерации: заголовки и блок квиза их не читают
/// (`strip_markdown` в озвучке), поэтому номер им не выдаётся.
({bool skip}) _lineKind(String trimmed, bool inQuiz) {
  if (inQuiz) {
    return (
      skip: true,
    );
  }

  return (
    skip: trimmed.startsWith('#') || trimmed.startsWith(':::quiz'),
    // закрытие квиза обрабатывается вызывающей стороной
  );
}

/// Все предложения текста по порядку со сквозной нумерацией.
List<SentenceRef> parseSentences(String text) {
  final out = <SentenceRef>[];

  var offset = 0;

  var paragraph = 0;

  var inQuiz = false;

  for (final line in text.split('\n')) {
    final trimmed = line.trim();

    var skip = false;

    if (inQuiz) {
      skip = true;

      if (trimmed.startsWith(':::')) {
        inQuiz = false;
      }
    } else if (_lineKind(trimmed, false).skip) {
      skip = true;

      if (trimmed.startsWith(':::quiz')) {
        inQuiz = true;
      }
    }

    if (!skip) {
      for (final r in _splitLine(line)) {
        out.add(
          SentenceRef(
            number: out.length + 1,
            paragraph: paragraph,
            text: line.substring(r.start, r.end),
            start: offset + r.start,
            end: offset + r.end,
          ),
        );
      }
    }

    offset += line.length + 1;

    paragraph++;
  }

  return out;
}

/// Вставляет заполнители номеров перед каждым предложением ЧИСТОГО
/// текста и возвращает значение поля редактора.
///
/// Идемпотентна по смыслу: применяется к чистому тексту без
/// заполнителей ([stripSentenceNumbers] их убирает).
String injectSentenceNumbers(String clean) {
  final sb = StringBuffer();

  var inQuiz = false;

  for (final line in clean.split('\n')) {
    final trimmed = line.trim();

    var skip = false;

    if (inQuiz) {
      skip = true;

      if (trimmed.startsWith(':::')) {
        inQuiz = false;
      }
    } else if (_lineKind(trimmed, false).skip) {
      skip = true;

      if (trimmed.startsWith(':::quiz')) {
        inQuiz = true;
      }
    }

    var cursor = 0;

    if (!skip) {
      for (final r in _splitLine(line)) {
        sb.write(line.substring(cursor, r.start));

        // Ровно [kNumberDigits] символов на номер любого размера —
        // длина значения и отрисовки совпадают всегда.
        sb.write(kNumberPlaceholder * kNumberDigits);

        sb.write(line.substring(r.start, r.end));

        cursor = r.end;
      }
    }

    sb.write(line.substring(cursor));

    if (line != clean.split('\n').last) {
      sb.write('\n');
    }
  }

  return sb.toString();
}

/// Убирает все заполнители номеров: чистый текст статьи для
/// сохранения, диффа и сверки с озвучкой.
String stripSentenceNumbers(String value) =>
    value.replaceAll(kNumberPlaceholder, '');

/// Число заполнителей перед каждой позицией значения поля.
List<int> zwspPrefixCounts(String value) {
  final out = List<int>.filled(value.length + 1, 0);

  var count = 0;

  for (var i = 0; i < value.length; i++) {
    out[i] = count;

    if (value.codeUnitAt(i) == kNumberPlaceholder.codeUnitAt(0)) {
      count++;
    }
  }

  out[value.length] = count;

  return out;
}

/// Переводит диапазоны стилей из координат значения поля (с
/// заполнителями) в координаты чистого текста.
List<RichSpan> remapSpansToClean(String value, List<RichSpan> spans) {
  final counts = zwspPrefixCounts(value);

  final out = <RichSpan>[];

  for (final span in spans) {
    final start = (span.start - counts[span.start.clamp(0, value.length)])
        .clamp(0, value.length);

    final end = (span.end - counts[span.end.clamp(0, value.length)])
        .clamp(0, value.length);

    if (end <= start) {
      continue;
    }

    out.add(
      RichSpan(
        start,
        end,
        bold: span.bold,
        italic: span.italic,
        red: span.red,
      ),
    );
  }

  return out;
}

/// Смещение значения поля (с заполнителями) → координата чистого
/// текста: вычитаем заполнители, стоящие раньше него.
int valueOffsetToClean(String value, int offset) {
  final o = offset.clamp(0, value.length);

  var placeholders = 0;

  for (var i = 0; i < o; i++) {
    if (value.codeUnitAt(i) == kNumberPlaceholder.codeUnitAt(0)) {
      placeholders++;
    }
  }

  return o - placeholders;
}

/// Координата чистого текста → смещение значения поля: индекс символа
/// чистого текста с таким номером (конец значения, если текст кончился).
int cleanOffsetToValue(String value, int cleanOffset) {
  final index = cleanIndexMap(value);

  return index[cleanOffset.clamp(0, index.length - 1)];
}

/// Индексы символов чистого текста в значении поля: элемент [i] —
/// смещение i-го символа чистого текста, последний — конец значения.
/// Строится один раз за перестройку (не на каждый диапазон).
List<int> cleanIndexMap(String value) {
  final out = <int>[];

  for (var i = 0; i < value.length; i++) {
    if (value.codeUnitAt(i) != kNumberPlaceholder.codeUnitAt(0)) {
      out.add(i);
    }
  }

  out.add(value.length);

  return out;
}

/// Переводит диапазоны стилей из координат чистого текста в координаты
/// значения поля — точное обратное к [remapSpansToClean].
///
/// Нужно при расстановке номеров: заполнитель вставляется перед
/// КАЖДЫМ предложением, а сдвиг по общему префиксу/суффиксу
/// ([adjustSpans]) умеет одну правку — при множестве вставок
/// диапазоны между ними оставались на старых координатах и выделение
/// уезжало на чужие буквы.
List<RichSpan> remapSpansToNumbered(String value, List<RichSpan> cleanSpans) {
  final index = cleanIndexMap(value);

  final out = <RichSpan>[];

  for (final span in cleanSpans) {
    final start = index[span.start.clamp(0, index.length - 1)];

    final end = index[span.end.clamp(0, index.length - 1)];

    if (end <= start) {
      continue;
    }

    out.add(
      RichSpan(
        start,
        end,
        bold: span.bold,
        italic: span.italic,
        red: span.red,
      ),
    );
  }

  return out;
}
