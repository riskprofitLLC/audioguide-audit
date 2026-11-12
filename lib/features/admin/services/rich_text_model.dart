/// Rich-модель поля текста админки (редактирование «как в Word»):
///
/// В ПОЛЕ ЖИВЁТ ЧИСТЫЙ ТЕКСТ — без звёздочек разметки. Жирный/
/// курсив — отдельные диапазоны ([RichSpan]) по позициям чистого
/// текста; рендерятся стилями через buildTextSpan. В markdown
/// звёздочки вставляются ТОЛЬКО при сериализации (сохранение,
/// просмотр, дифф). Правка текста не ломает разметку: диапазоны
/// сдвигаются по дельте вставки/удаления, невидимых символов нет —
/// позиции курсора, выделения и backspace всегда 1:1 с текстом.
///
/// Всё чисто, без Flutter — тестируемо юнит-тестами.
library;

/// Диапазон стиля по чистому тексту (end — исключительно).
/// Проверка выделения под ударение: в КАЖДОМ затронутом слове
/// выделена не больше одной буквы.
///
/// Ударение — метка на одной гласной; если администратор выделил
/// половину слова или два слова целиком, непонятно, куда ставить
/// знак U+0301. Поэтому такой случай отклоняется (решение владельца
/// 12.11.2026).
bool redSelectionIsSingleLetters(String text, int start, int end) {
  if (start < 0 || end <= start || end > text.length) return false;

  final wordRe = RegExp(r'[A-Za-zА-Яа-яЁё]+');
  for (final m in wordRe.allMatches(text)) {
    final ws = m.start;
    final we = m.end;
    // слово не затронуто выделением
    if (we <= start || ws >= end) continue;
    final covered = (end < we ? end : we) - (start > ws ? start : ws);
    if (covered > 1) return false;
  }
  return true;
}


class RichSpan {

  const RichSpan(this.start, this.end, {required this.bold, required this.italic, this.red = false});

  final int start;

  final int end;

  final bool bold;

  final bool italic;

  /// Красное выделение (маркер `==…==`, кнопка «Красный»).
  final bool red;

  RichSpan shifted(int delta) =>
      RichSpan(start + delta, end + delta, bold: bold, italic: italic, red: red);

  RichSpan clipped(int lo, int hi) =>
      RichSpan(start.clamp(lo, hi), end.clamp(lo, hi), bold: bold, italic: italic, red: red);

  bool get isEmpty => end <= start;

  bool covers(int lo, int hi) => start <= lo && hi <= end;
}

/// Чистый текст + стили.
class RichDoc {

  const RichDoc(this.plain, this.spans);

  final String plain;

  final List<RichSpan> spans;
}

/// Разбирает сырой markdown (статья, квиз уже вырезан) в RichDoc:
/// маркеры `**…**` / `*…*` снимаются, на их месте — диапазоны.
/// Ничего не теряется: то, что не разметка, остаётся текстом
/// (включая `#`-заголовки и `-` списки).
RichDoc parseRich(String raw) {
  final buffer = StringBuffer();

  final spans = <RichSpan>[];

  // Пары обрабатываем построчно — inline-разметка не переходит
  // через абзацы.
  for (final line in raw.split('\n')) {
    var i = 0;

    final out = StringBuffer();

    // Стек открытых маркеров: (тип, позиция чистого текста открытия).
    // Close берём по верхушке стека — так примыкание маркеров
    // (red close `**==` + bold open `**` = `**==**`, bold close `**`
    // + red open `==**`) разбирается однозначно, в отличие от
    // эвристики indexOf, которая путала маркеры на границах.
    final stack = <(String, int, bool)>[];

    int plainLen() => buffer.length + out.length;

    while (i < line.length) {
      final rest = line.substring(i);

      final top = stack.isNotEmpty ? stack.last.$1 : null;

      // Close открытого красного: `**==` (канон) или `==` (старый
      // формат ==текст== без жирного; не путаем с open `==**`).
      if (top == 'red' &&
          (rest.startsWith('**==') ||
              (rest.startsWith('==') && !rest.startsWith('==**')))) {
        final bold = stack.last.$3;

        spans.add(RichSpan(stack.last.$2, plainLen(),
            bold: bold, italic: false, red: true));

        stack.removeLast();

        i += rest.startsWith('**==') ? 4 : 2;

        continue;
      }

      // Close открытого bold+italic: `***`.
      if (top == 'bold+italic' && rest.startsWith('***')) {
        spans.add(RichSpan(stack.last.$2, plainLen(),
            bold: true, italic: true));

        stack.removeLast();

        i += 3;

        continue;
      }

      // Close открытого жирного: `**`. В том числе `****` на границе
      // двух bold-сегментов (close + open) — тогда дальше откроется
      // новый bold.
      if (top == 'bold' && rest.startsWith('**')) {
        spans.add(RichSpan(stack.last.$2, plainLen(),
            bold: true, italic: false));

        stack.removeLast();

        i += 2;

        continue;
      }

      // Close открытого курсива: `*`. После flatten сериализатор не
      // создаёт `*…**…` (bold внутри italic оформляется как combo),
      // поэтому любая `*` при top=italic — это close.
      if (top == 'italic' && rest.startsWith('*')) {
        spans.add(RichSpan(stack.last.$2, plainLen(),
            bold: false, italic: true));

        stack.removeLast();

        i += 1;

        continue;
      }

      // Open маркеры (длинные раньше).
      if (rest.startsWith('==**')) {
        stack.add(('red', plainLen(), true));

        i += 4;

        continue;
      }

      // Старый формат красного: ==текст== (без жирного).
      if (rest.startsWith('==')) {
        stack.add(('red', plainLen(), false));

        i += 2;

        continue;
      }

      if (rest.startsWith('***')) {
        stack.add(('bold+italic', plainLen(), false));

        i += 3;

        continue;
      }

      if (rest.startsWith('**')) {
        stack.add(('bold', plainLen(), false));

        i += 2;

        continue;
      }

      if (rest.startsWith('*')) {
        stack.add(('italic', plainLen(), false));

        i += 1;

        continue;
      }

      out.write(line[i]);

      i++;
    }

    // Незакрытые маркеры — их символы не попали в текст (записаны
    // как open, не как текст): восстанавливаем их буквально, чтобы
    // roundtrip не терял символы.
    for (final (type, _, bold) in stack) {
      out.write(switch (type) {
        'red' => bold ? '==**' : '==',
        'bold+italic' => '***',
        'bold' => '**',
        _ => '*',
      });
    }

    buffer.write(out);

    buffer.write('\n');
  }

  // Отрезаем хвостовой перенос, добавленный последней итерацией,
  // если исходник им не кончался.
  var result = buffer.toString();

  if (!raw.endsWith('\n') && result.endsWith('\n')) {
    result = result.substring(0, result.length - 1);
  }

  return RichDoc(result, spans);
}

/// Собирает markdown обратно: чистый текст + диапазоны →
/// звёздочки вставляются с конца, чтобы позиции не съезжали.
/// Диапазоны с bold+italic → ***текст***.
String serializeRich(String plain, List<RichSpan> spans) {
  // Разбиваем диапазоны по переносам: разметка не живёт через абзацы
  // (parseRich читает построчно) — иначе после переноса внутри span
  // звёздочки останутся «мусорным» текстом.
  final expanded = <RichSpan>[
    for (final s in spans.where((s) => !s.isEmpty))
      ..._splitAtNewlines(plain, s),
  ];

  // Расплющиваем в НЕПЕРЕСЕКАЮЩИЕСЯ сегменты: toggleStyle может создать
  // пересекающиеся диапазоны (красный поверх жирного), а плоская
  // markdown-разметка вложенность не поддерживает — маркеры на
  // пересечении давали неоднозначный текст, и parseRich терял стили
  // (поймано fuzz-тестом roundtrip).
  final flattened = flattenRichSpans(plain, expanded);

  // Сливаем соседние сегменты с одинаковыми флагами.
  flattened.sort((a, b) => a.start.compareTo(b.start));

  final merged = <RichSpan>[];

  for (final s in flattened) {
    final last = merged.isNotEmpty ? merged.last : null;

    if (last != null &&
        last.bold == s.bold &&
        last.italic == s.italic &&
        last.red == s.red &&
        last.end >= s.start) {
      merged[merged.length - 1] = RichSpan(
        last.start,
        s.end > last.end ? s.end : last.end,
        bold: last.bold,
        italic: last.italic,
        red: last.red,
      );
    } else {
      merged.add(s);
    }
  }

  // Собираем вставки маркеров по позициям. В одной позиции может быть
  // несколько close/open (примыкание сегментов) — порядок символов
  // критичен: close вложенного левее close внешнего, open внешнего
  // левее open вложенного. Поэтому в точке вставляем сначала open'ы
  // (они должны оказаться правее), затем close'ы; среди close —
  // сначала короткие маркеры (вставка в ту же позицию кладёт их левее).
  final inserts = <int, List<(bool isClose, String marker)>>{};

  void addInsert(int pos, bool isClose, String marker) {
    inserts.putIfAbsent(pos, () => []).add((isClose, marker));
  }

  for (final span in merged) {
    final (open, close) = span.red
        ? ('==**', '**==')
        : (span.bold && span.italic)
            ? ('***', '***')
            : (span.bold ? ('**', '**') : ('*', '*'));

    addInsert(span.start, false, open);

    addInsert(span.end, true, close);
  }

  var out = plain;

  final positions = inserts.keys.toList()
    ..sort((a, b) => b.compareTo(a));

  for (final pos in positions) {
    final items = inserts[pos]!;

    // open'ы — в порядке убывания длины маркера (длинный левее после
    // обратной вставки), close'ы — в порядке возрастания длины.
    final opens = items.where((e) => !e.$1).toList()
      ..sort((a, b) => b.$2.length.compareTo(a.$2.length));

    final closes = items.where((e) => e.$1).toList()
      ..sort((a, b) => a.$2.length.compareTo(b.$2.length));

    // replaceRange(pos, pos, s) кладёт s в pos, сдвигая уже вставленное
    // вправо — т.е. последняя вставка в pos окажется ЛЕВЕЕ. Чтобы слева
    // направо шли [close…, open…], вставляем сначала open'ы, потом close'ы.
    for (final (_, marker) in opens) {
      out = out.replaceRange(pos, pos, marker);
    }

    for (final (_, marker) in closes) {
      out = out.replaceRange(pos, pos, marker);
    }
  }

  return out;
}

/// Применяет правку текста к диапазонам: чистый текст изменился с
/// [oldPlain] на [newPlain] — диапазоны сдвигаются по дельте.
List<RichSpan> adjustSpans(
  List<RichSpan> spans,
  String oldPlain,
  String newPlain,
) {
  // Общий префикс.
  var prefix = 0;

  final minLen =
      oldPlain.length < newPlain.length ? oldPlain.length : newPlain.length;

  while (prefix < minLen && oldPlain.codeUnitAt(prefix) == newPlain.codeUnitAt(prefix)) {
    prefix++;
  }

  // Общий суффикс (не заходит в префикс).
  var suffix = 0;

  while (suffix < minLen - prefix &&
      oldPlain.codeUnitAt(oldPlain.length - 1 - suffix) ==
          newPlain.codeUnitAt(newPlain.length - 1 - suffix)) {
    suffix++;
  }

  // Границы правки.
  final oldEditEnd = oldPlain.length - suffix;

  final newEditEnd = newPlain.length - suffix;

  final delta = newEditEnd - prefix - (oldEditEnd - prefix);

  final out = <RichSpan>[];

  for (final span in spans) {
    var start = span.start;

    var end = span.end;

    if (start >= oldEditEnd) {
      // Диапазон целиком после правки — сдвиг.
      start += delta;

      end += delta;
    } else if (end <= prefix) {
      // Целиком до правки — не трогаем.
    } else {
      // Пересекается с правкой: часть до правки остаётся,
      // хвост за правкой сдвигается на дельту.
      if (end > oldEditEnd) {
        end += delta;
      }

      start = start.clamp(0, newPlain.length);

      end = end.clamp(start, newPlain.length);
    }

    final clipped = RichSpan(start, end, bold: span.bold, italic: span.italic, red: span.red);

    if (!clipped.isEmpty) {
      out.add(clipped);
    }
  }

  return out;
}

/// Переключает стиль на выделении (кнопки «Жирный»/«Красный»,
/// Ctrl+B / Ctrl+I). Если выделение ЦЕЛИКОМ покрыто диапазоном с
/// этим стилем — стиль снимается (в т.ч. раздвоением диапазона);
/// иначе — ставится на всё выделение (сливая пересекающиеся).
/// Выделение уже оформлено стилем: повторный тап по кнопке снимет
/// его, а не добавит.
///
/// Нужен редактору, чтобы ограничение «одна буква в слове»
/// применялось только при ДОБАВЛЕНИИ стиля: снятие чужого
/// выделения из 2–3 букв (например, из старой разметки
/// `==**ов**==`) блокировать нельзя — иначе админ не сможет
/// убрать ударение с лишних букв.
bool selectionCoveredByStyle(
  List<RichSpan> spans,
  String plain,
  int selStart,
  int selEnd, {
  required bool bold,
  bool red = false,
}) {
  final clampedStart = selStart.clamp(0, plain.length);

  final clampedEnd = selEnd.clamp(0, plain.length);

  if (clampedEnd <= clampedStart) {
    return false;
  }

  final start = _snapForward(plain, clampedStart);

  final end = _snapBack(plain, clampedEnd);

  if (end <= start) {
    return false;
  }

  bool styleOf(RichSpan s) => red ? s.red : (bold ? s.bold : s.italic);

  // Покрытие считаем по ОБЪЕДИНЕНИЮ диапазонов со стилем: после правок
  // один красный фрагмент может лежать несколькими соседними span'ами —
  // проверка одним span'ом (covers) пропускала такой случай, и повторное
  // нажатие не снимало стиль, а накладывало новый поверх (дубли в рендере).
  if (_rangeCoveredBy(spans, styleOf, start, end)) {
    return true;
  }

  // Выделение «с запасом» (лишний пробел/перенос по краю) не должно
  // мешать снятию стиля: если красный фрагмент выделен вместе с
  // окружающим пробелом, повторный тап обязан СНЯТЬ стиль, а не
  // расширить его. Проверяем покрытие ещё раз по краям без пробелов
  // (сам диапазон применения не трогаем — пробел в выделении
  // по-прежнему стилизуется при добавлении).
  final trimmedStart = _trimStartSpaces(plain, start);

  final trimmedEnd = _trimEndSpaces(plain, end);

  return (trimmedStart != start || trimmedEnd != end) &&
      trimmedEnd > trimmedStart &&
      _rangeCoveredBy(spans, styleOf, trimmedStart, trimmedEnd);
}

List<RichSpan> toggleStyle(
  List<RichSpan> spans,
  String plain,
  int selStart,
  int selEnd, {
  required bool bold,
  bool red = false,
}) {
  // Выделение может быть «левым»: _lastSelection в редакторе переживает
  // смену текста (другая точка/режим/черновик) и тогда start/end указывают
  // за пределы текущего текста. Без клампа _snapBack падает с RangeError,
  // а span улетает в конец — стиль оказывается «в нижней части текста».
  final clampedStart = selStart.clamp(0, plain.length);

  final clampedEnd = selEnd.clamp(0, plain.length);

  if (clampedEnd <= clampedStart) {
    return spans;
  }

  // Ограничиваем выделение абзацами: разметка не переходит через
  // перенос строки.
  final start = _snapForward(plain, clampedStart);

  final end = _snapBack(plain, clampedEnd);

  if (end <= start) {
    return spans;
  }

  bool styleOf(RichSpan s) => red ? s.red : (bold ? s.bold : s.italic);

  final covered = selectionCoveredByStyle(
    spans,
    plain,
    selStart,
    selEnd,
    bold: bold,
    red: red,
  );

  final out = <RichSpan>[];

  for (final span in spans) {
    if (!span.overlapsRange(start, end)) {
      out.add(span);

      continue;
    }

    // Снимаем/добавляем стиль на пересечении. covered уже проверен по
    // объединению диапазонов со стилем, поэтому отдельный span покрывать
    // выделение целиком не обязан — снимаем стиль со всего тела пересечения.
    final hasStyle = styleOf(span);

    final remove = covered && hasStyle;

    RichSpan restyle(RichSpan s, {bool? newRed}) => RichSpan(
          s.start,
          s.end,
          bold: s.bold,
          italic: s.italic,
          red: newRed ?? s.red,
        );

    // Голова до выделения.
    if (span.start < start) {
      out.add(restyle(RichSpan(span.start, start, bold: span.bold, italic: span.italic, red: span.red)));
    }

    // Тело на выделении: стиль меняется.
    final lo = span.start > start ? span.start : start;

    final hi = span.end < end ? span.end : end;

    if (lo < hi) {
      // remove — полное снятие оформления с тела: красный всегда сериализуется
      // жирным (`==**…**==`), поэтому при снятии red оставшийся bold выглядел
      // как «не снятое» выделение (жирный чёрный текст).
      out.add(RichSpan(
        lo,
        hi,
        bold: remove ? false : (red ? span.bold : (bold ? true : span.bold)),
        italic: remove ? false : (red ? span.italic : (bold ? span.italic : true)),
        red: remove ? false : (red ? true : span.red),
      ));
    }

    // Хвост после выделения.
    if (span.end > end) {
      out.add(restyle(RichSpan(end, span.end, bold: span.bold, italic: span.italic, red: span.red)));
    }
  }

  if (!covered) {
    out.add(RichSpan(start, end, bold: red ? false : bold, italic: red ? false : !bold, red: red));
  }

  // Пересечения (новый span поверх частично перекрытого старого) снимаем
  // flatten'ом: buildTextSpan рисует пересекающиеся диапазоны дважды —
  // текст «дублируется» в поле. Соседние сегменты с одинаковыми флагами
  // сливаем — иначе один красный фрагмент лежит несколькими span'ами.
  final flattened = flattenRichSpans(plain, out)..sort((a, b) => a.start.compareTo(b.start));

  final merged = <RichSpan>[];

  for (final s in flattened) {
    final last = merged.isNotEmpty ? merged.last : null;

    if (last != null &&
        last.bold == s.bold &&
        last.italic == s.italic &&
        last.red == s.red &&
        last.end == s.start) {
      merged[merged.length - 1] = RichSpan(last.start, s.end,
          bold: last.bold, italic: last.italic, red: last.red);
    } else {
      merged.add(s);
    }
  }

  return merged;
}

/// Покрыт ли диапазон [lo, hi] объединением span'ов, для которых [test] истинен.
bool _rangeCoveredBy(
  List<RichSpan> spans,
  bool Function(RichSpan) test,
  int lo,
  int hi,
) {
  var coveredUntil = lo;

  final matching = spans.where(test).toList()..sort((a, b) => a.start.compareTo(b.start));

  for (final s in matching) {
    if (s.end <= coveredUntil) {
      continue;
    }

    if (s.start > coveredUntil) {
      return false;
    }

    coveredUntil = s.end;

    if (coveredUntil >= hi) {
      return true;
    }
  }

  return coveredUntil >= hi;
}

extension on RichSpan {
  bool overlapsRange(int lo, int hi) => start < hi && end > lo;
}

/// Сдвигает позицию вперёд мимо переноса строки (стиль не должен
/// начинаться на «\n»). Позиция клампится — вызов с pos за пределами
/// текста не должен падать (старое запомненное выделение).
int _snapForward(String plain, int pos) {
  var p = pos.clamp(0, plain.length);

  while (p < plain.length && plain[p] == '\n') {
    p++;
  }

  return p;
}

/// Сдвигает позицию назад мимо переноса строки (стиль не должен
/// заканчиваться на «\n»). Позиция клампится — вызов с pos за пределами
/// текста не должен падать (старое запомненное выделение).
int _snapBack(String plain, int pos) {
  var p = pos.clamp(0, plain.length);

  while (p > 0 && plain[p - 1] == '\n') {
    p--;
  }

  return p;
}

bool _isSpace(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

/// Начало текста без пробелов слева (для проверки покрытия).
int _trimStartSpaces(String plain, int pos) {
  var p = pos.clamp(0, plain.length);

  while (p < plain.length && _isSpace(plain[p])) {
    p++;
  }

  return p;
}

/// Конец текста без пробелов справа (для проверки покрытия).
int _trimEndSpaces(String plain, int pos) {
  var p = pos.clamp(0, plain.length);

  while (p > 0 && _isSpace(plain[p - 1])) {
    p--;
  }

  return p;
}

/// Разбивает диапазон на части по переносам строк внутри него
/// (разметка не переходит через абзацы). Части вне текста отбрасываются.
List<RichSpan> _splitAtNewlines(String plain, RichSpan span) {
  final start = span.start.clamp(0, plain.length);

  final end = span.end.clamp(0, plain.length);

  if (end <= start) {
    return const [];
  }

  final inner = plain.substring(start, end);

  if (!inner.contains('\n')) {
    return [RichSpan(start, end, bold: span.bold, italic: span.italic, red: span.red)];
  }

  final out = <RichSpan>[];

  var pos = start;

  for (final part in inner.split('\n')) {
    if (part.isNotEmpty) {
      out.add(RichSpan(pos, pos + part.length,
          bold: span.bold, italic: span.italic, red: span.red));
    }

    pos += part.length + 1; // + перенос
  }

  return out;
}

/// Раскладывает (возможно пересекающиеся) диапазоны на непересекающиеся
/// сегменты по всем границам: флаги сегмента — объединение покрывающих
/// диапазонов. Красный приоритетнее и всегда жирный.
///
/// Публична: рендер поля (`buildTextSpan`) обязан идти по этому списку,
/// иначе пересекающиеся диапазоны (вложенный markdown `**a *b* c**`,
/// красный поверх жирного) выводят один и тот же фрагмент ДВАЖДЫ —
/// «текст копируется рядом» (замечание владельца).
List<RichSpan> flattenRichSpans(String plain, List<RichSpan> spans) {
  final bounds = <int>{0, plain.length};

  for (final s in spans) {
    bounds.add(s.start.clamp(0, plain.length));

    bounds.add(s.end.clamp(0, plain.length));
  }

  final sorted = bounds.toList()..sort();

  final out = <RichSpan>[];

  for (var i = 0; i + 1 < sorted.length; i++) {
    final lo = sorted[i];

    final hi = sorted[i + 1];

    if (hi <= lo) {
      continue;
    }

    var bold = false;

    var italic = false;

    var red = false;

    for (final s in spans) {
      if (s.start <= lo && hi <= s.end) {
        bold = bold || s.bold;

        italic = italic || s.italic;

        red = red || s.red;
      }
    }

    if (red || bold || italic) {
      out.add(RichSpan(lo, hi, bold: bold, italic: italic, red: red));
    }
  }

  return out;
}

/// Буква или цифра — из чего складывается слово (кириллица, латиница).
bool _isWordChar(int c) {
  if (c >= 0x30 && c <= 0x39) {
    return true; // 0-9
  }

  if (c >= 0x41 && c <= 0x5A || c >= 0x61 && c <= 0x7A) {
    return true; // A-Z a-z
  }

  if (c >= 0x410 && c <= 0x44F) {
    return true; // А-Я а-я
  }

  return c == 0x401 || c == 0x451; // Ё ё
}

/// Слово, накрытое диапазоном: краевые не-буквы срезаются, затем
/// края расширяются до границ слова.
///
/// Подсветить одну букву или несколько — нормально: в списке и в
/// поле poi.json оказывается СЛОВО ЦЕЛИКОМ, попадать мышью в края
/// не требуется. Расширение не переходит через пробел — иначе
/// подсветка « остров» съела бы предыдущее слово.
String _wordAt(String plain, int start, int end) {
  var s = start;

  var e = end;

  // Краевые не-буквы (пробелы, запятые, кавычки) — не часть слова.
  while (s < e && !_isWordChar(plain.codeUnitAt(s))) {
    s++;
  }

  while (e > s && !_isWordChar(plain.codeUnitAt(e - 1))) {
    e--;
  }

  if (s >= e) {
    return '';
  }

  // Доращиваем до границ слова в пределах его букв.
  while (s > 0 && _isWordChar(plain.codeUnitAt(s - 1))) {
    s--;
  }

  while (e < plain.length && _isWordChar(plain.codeUnitAt(e))) {
    e++;
  }

  return plain.substring(s, e);
}

/// Слова с красным выделением — по порядку появления, без дублей.
///
/// Единый источник правды для панели админки и поля poi.json:
/// выделение живёт диапазоном (red: true), а не маркером в тексте,
/// поэтому список точен даже при битых маркерах в markdown.
/// Диапазон расширяется до границ слова ([_wordAt]) — частичная
/// подсветка букв даёт в списке целое слово.
List<String> highlightedWords(String plain, List<RichSpan> spans) {
  final seen = <String>{};

  final out = <String>[];

  for (final span in spans) {
    if (!span.red || span.isEmpty) {
      continue;
    }

    final start = span.start.clamp(0, plain.length);

    final end = span.end.clamp(0, plain.length);

    if (end <= start) {
      continue;
    }

    final word = _wordAt(plain, start, end);

    if (word.isEmpty || !seen.add(word)) {
      continue;
    }

    out.add(word);
  }

  return out;
}
