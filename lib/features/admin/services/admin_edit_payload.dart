/// Чистые функции правок: обёртка выделения разметкой,
/// сборка описания POI из markdown и обновление poi.json.
///
/// Всё тестируемое без сети и Flutter — чистый Dart.
library;

import 'dart:convert';

/// Оборачивает выделение в [start;end) маркером (`**` или `*`).
///
/// Если выделение уже обёрнуто — маркеры снимаются (повторный
/// тап по кнопке снимает жирность). Смещение курсора после
/// правки возвращает результат.
({String text, int selectionOffset}) wrapSelection(
  String text,
  int start,
  int end,
  String marker,
) {

  final clampedStart = start.clamp(0, text.length);

  final clampedEnd = end.clamp(0, text.length);

  final isRange = clampedEnd > clampedStart;

  // Снятие обёртки: маркер стоит непосредственно перед и после.
  final prefixStart = clampedStart - marker.length;

  final suffixEnd = clampedEnd + marker.length;

  if (prefixStart >= 0 &&
      suffixEnd <= text.length &&
      text.substring(prefixStart, clampedStart) == marker &&
      text.substring(clampedEnd, suffixEnd) == marker) {

    // Убираем маркеры по отдельности, сохраняя внутренний текст:
    // сначала хвост (исходные позиции), затем префикс.
    final stripped = text
        .replaceRange(clampedEnd, suffixEnd, '')
        .replaceRange(prefixStart, clampedStart, '');

    // Курсор после снятия — на конец внутреннего текста.
    final offset = prefixStart + (clampedEnd - clampedStart);

    return (text: stripped, selectionOffset: offset);
  }

  if (isRange) {

    final wrapped = text
        .replaceRange(clampedEnd, clampedEnd, marker)
        .replaceRange(clampedStart, clampedStart, marker);

    return (
      text: wrapped,
      selectionOffset: clampedEnd + marker.length * 2,
    );
  }

  // Нет выделения — вставляем пустые маркеры, курсор внутрь.
  return (
    text: text.replaceRange(clampedStart, clampedStart, marker * 2),
    selectionOffset: clampedStart + marker.length,
  );
}

/// Описание для poi.json из полного markdown-файла:
/// H1 выбрасывается, блоки :::quiz вырезаются, инлайновые
/// маркеры **/__ убираются (в описании они не рендерятся).
String descriptionFromMarkdown(String raw) {

  final lines = <String>[];

  var inQuiz = false;

  for (final line in raw.split('\n')) {

    final trimmed = line.trim();

    if (trimmed.startsWith(':::quiz')) {
      inQuiz = true;
      continue;
    }

    if (inQuiz) {
      if (trimmed == ':::') {
        inQuiz = false;
      }
      continue;
    }

    if (trimmed.startsWith('# ')) {
      continue;
    }

    lines.add(
      line.replaceAll('**', '').replaceAll('__', '').replaceAll('==', ''),
    );
  }

  return lines.join('\n').trim();
}

/// Короткое описание для poi.json (пункт 3, А2 замечаний Sonnet):
/// описание poi.json — НЕ весь файл, а первые абзацы полного
/// текста. Логика повторяет `short_text()` из tool/sync_texts.py:
/// первые 3 абзаца (без H1 и квизов); если их суммарный объём
/// меньше 1500 символов — добавляется четвёртый.
String shortDescriptionFromMarkdown(String raw) {

  // Квизы вырезаем, инлайновые маркеры снимаем (в описании
  // они не рендерятся) — как в descriptionFromMarkdown.
  final stripped = descriptionFromMarkdown(raw);

  final paragraphs = stripped
      .split('\n\n')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList(growable: false);

  if (paragraphs.isEmpty) {
    return '';
  }

  var picked = paragraphs.take(3).toList();

  if (paragraphs.length > 3 &&
      picked.join().length < 1500) {
    picked = [...picked, paragraphs[3]];
  }

  return picked.join('\n\n').trim();
}

/// Обновляет `description` точки в сыром poi.json.
///
/// Файл перегенерируется с отступом 1 пробел — как пишет
/// tool/sync_texts.py (json.dumps(..., indent=1)).
String updatePoiJsonDescription(
  String rawJson,
  String poiId,
  String description,
) {

  final pois = jsonDecode(rawJson) as List<Object?>;

  final updated = pois.map((item) {

    if (item is! Map<String, Object?>) {
      return item;
    }

    if (item['id'] != poiId) {
      return item;
    }

    final copy = Map<String, Object?>.of(item);

    copy['description'] = description;

    return copy;
  }).toList();

  return const JsonEncoder.withIndent(' ').convert(updated);
}

/// Заголовок точки из сырого poi.json (null — точки нет).
String? poiTitleFromJson(String rawJson, String poiId) {

  final pois = jsonDecode(rawJson) as List<Object?>;

  for (final item in pois) {

    if (item is! Map<String, Object?> || item['id'] != poiId) {
      continue;
    }

    return item['title'] as String?;
  }

  return null;
}

/// Обновляет `title` точки в сыром poi.json.
String updatePoiJsonTitle(
  String rawJson,
  String poiId,
  String title,
) {

  final pois = jsonDecode(rawJson) as List<Object?>;

  final updated = pois.map((item) {

    if (item is! Map<String, Object?> || item['id'] != poiId) {
      return item;
    }

    final copy = Map<String, Object?>.of(item);

    copy['title'] = title;

    return copy;
  }).toList();

  return const JsonEncoder.withIndent(' ').convert(updated);
}

/// Меняет `name` локации в сыром манифесте.
String updateManifestName(String rawJson, String name) {

  final manifest = jsonDecode(rawJson) as Map<String, Object?>;

  final copy = Map<String, Object?>.of(manifest);

  copy['name'] = name;

  return const JsonEncoder.withIndent(' ').convert(copy);
}

/// Читает `name` из сырого манифеста локации.
String? manifestName(String rawJson) =>
    (jsonDecode(rawJson) as Map<String, Object?>)['name'] as String?;

/// Тип строки диффа по абзацам (A3 замечаний Sonnet: режим
/// «Было/Стало» в редакторе).
enum ParagraphDiffKind { same, removed, added }

/// Строка диффа: абзац и его статус относительно загруженной версии.
class ParagraphDiff {

  const ParagraphDiff(this.kind, this.text);

  final ParagraphDiffKind kind;

  final String text;
}

/// Дифф абзацев «Было → Стало» (LCS): совпавшие — [same],
/// удалённые из «было» — [removed], новые в «стало» — [added].
/// Изменённый абзац показывается парой «− старый / + новый».
List<ParagraphDiff> diffParagraphs(
  String oldText,
  String newText,
) {
  final old = _splitParagraphs(oldText);

  final fresh = _splitParagraphs(newText);

  // Таблица LCS: (n+1) x (m+1), тексты — сотни абзацев максимум.
  final n = old.length;

  final m = fresh.length;

  final table = List.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
  );

  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = old[i] == fresh[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
              ? table[i + 1][j]
              : table[i][j + 1]);
    }
  }

  final result = <ParagraphDiff>[];

  var i = 0;

  var j = 0;

  while (i < n || j < m) {
    if (i < n && j < m && old[i] == fresh[j]) {
      result.add(ParagraphDiff(ParagraphDiffKind.same, old[i]));

      i++;

      j++;
    } else if (j < m && (i >= n || table[i + 1][j] < table[i][j + 1])) {
      result.add(ParagraphDiff(ParagraphDiffKind.added, fresh[j]));

      j++;
    } else if (i < n) {
      result.add(ParagraphDiff(ParagraphDiffKind.removed, old[i]));

      i++;
    } else {
      result.add(ParagraphDiff(ParagraphDiffKind.added, fresh[j]));

      j++;
    }
  }

  return result;
}

List<String> _splitParagraphs(String text) {
  return text
      .split('\n\n')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
}

/// Склейка «осиротевших» маркеров разметки после правки (баг
/// владельца): backspace у края выделенного слова оголяет половину
/// пары — «**Смелый*» → пара разваливается, оставшаяся звёздочка
/// начинает съедать соседний текст. Функция удаляет ОДИНОКИЕ
/// `*`, у которых нет пары в той же строке (пары `**` внутри
/// строки считаются парно). Вызывается перед сохранением.
String repairOrphanMarkers(String raw) {
  final outLines = <String>[];

  for (final line in raw.split('\n')) {
    // Пары в строке: `**` обрабатываем первыми, затем одиночные `*`.
    final count = '*'.allMatches(line).length;

    if (count.isEven) {
      outLines.add(line);

      continue;
    }

    // Нечётное число звёздочек: гасим последнюю одиночную —
    // это и есть «оголённый» хвост разметки.
    final idx = line.lastIndexOf('*');

    outLines.add(line.replaceRange(idx, idx + 1, ''));
  }

  return outLines.join('\n');
}
