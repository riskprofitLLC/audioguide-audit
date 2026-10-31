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
  final flattened = _flattenSpans(plain, expanded);

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

  final covered = spans.any((s) => styleOf(s) && s.covers(start, end));

  final out = <RichSpan>[];

  for (final span in spans) {
    if (!span.overlapsRange(start, end)) {
      out.add(span);

      continue;
    }

    // Снимаем/добавляем стиль на пересечении.
    final hasStyle = styleOf(span);

    final remove = covered && hasStyle && span.covers(start, end);

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
      out.add(RichSpan(
        lo,
        hi,
        bold: red ? span.bold : (remove ? false : (bold ? true : span.bold)),
        italic: red ? span.italic : (remove ? false : (bold ? span.italic : true)),
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

  // Инвариант «список отсортирован по start»: новый span добавляется в
  // конец списка, и если выделение было РАНЬШЕ уже стилизованного
  // фрагмента, список становится неотсортированным. buildTextSpan идёт
  // по списку подряд и рисует текст по позиции курсора — неотсортированный
  // span рендерится НЕ на своём месте (фрагмент «копируется» в другой
  // конец текста).
  out.sort((a, b) => a.start.compareTo(b.start));

  return out;
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
List<RichSpan> _flattenSpans(String plain, List<RichSpan> spans) {
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
