/// Разбор полного текста точки на редактируемые блоки и сборка обратно.
///
/// Блок = абзац (мультистрочный текст), заголовок `# …` или квиз
/// `:::quiz … :::` (в квизе сохраняем сырые строки — формат terse:
/// вопрос, `+`/`-` варианты, `> пояснение`). Всё чисто, без Flutter.
library;

enum AdminBlockType { heading, paragraph, quiz }

class AdminBlock {

  const AdminBlock({required this.type, required this.text});

  final AdminBlockType type;

  /// Текст блока без завершающих переводов строк; у квиза —
  /// сырые строки от `:::quiz` до `:::` включительно.
  final String text;

  AdminBlock copyWith({String? text}) =>
      AdminBlock(type: type, text: text ?? this.text);
}

/// Разбивает markdown-файл на блоки по пустым строкам и квизам.
List<AdminBlock> splitAdminBlocks(String raw) {

  final blocks = <AdminBlock>[];

  final buffer = <String>[];

  var inQuiz = false;

  void flushParagraph() {

    if (buffer.isEmpty) {
      return;
    }

    blocks.add(
      AdminBlock(type: AdminBlockType.paragraph, text: buffer.join('\n')),
    );

    buffer.clear();
  }

  for (final line in raw.split('\n')) {

    final trimmed = line.trim();

    if (inQuiz) {

      buffer.add(line);

      if (trimmed == ':::') {
        blocks.add(AdminBlock(type: AdminBlockType.quiz, text: buffer.join('\n')));
        buffer.clear();
        inQuiz = false;
      }

      continue;
    }

    if (trimmed.startsWith(':::quiz')) {
      flushParagraph();
      inQuiz = true;
      buffer.add(line);
      continue;
    }

    if (trimmed.isEmpty) {
      flushParagraph();
      continue;
    }

    if (trimmed.startsWith('# ') && buffer.isEmpty) {
      blocks.add(AdminBlock(type: AdminBlockType.heading, text: trimmed));
      continue;
    }

    buffer.add(line);
  }

  // Незакрытый квиз (битый ввод) — всё равно блок, чтобы не терять текст.
  if (buffer.isNotEmpty && inQuiz) {
    blocks.add(AdminBlock(type: AdminBlockType.quiz, text: buffer.join('\n')));
  } else {
    flushParagraph();
  }

  return blocks;
}

/// Собирает блоки обратно в файл: блоки через пустую строку.
String joinAdminBlocks(List<AdminBlock> blocks) => blocks
    .map((b) => b.text.trim())
    .where((t) => t.isNotEmpty)
    .join('\n\n');

/// Пустой абзац-болванка для вставки.
AdminBlock emptyParagraph() =>
    const AdminBlock(type: AdminBlockType.paragraph, text: '');

/// Пустой квиз-шаблон.
const kQuizTemplate = ':::quiz\nВопрос?\n+ Верный ответ\n- Неверный\n'
    '> Пояснение.\n:::';

AdminBlock emptyQuiz() =>
    const AdminBlock(type: AdminBlockType.quiz, text: kQuizTemplate);

// --- структурированный квиз ---

/// Один вариант ответа квиза.
class AdminQuizOption {

  const AdminQuizOption({required this.text, required this.correct});

  final String text;

  final bool correct;
}

/// Квиз в структурированном виде: вопрос, варианты, пояснение.
class AdminQuiz {

  const AdminQuiz({
    required this.question,
    required this.options,
    this.note,
  });

  final String question;

  final List<AdminQuizOption> options;

  final String? note;
}

/// Парсит блок `:::quiz … :::` (текст блока из AdminBlock) в AdminQuiz.
/// Null — блок не распарсился (пустой).
AdminQuiz? parseQuizBlock(String raw) {

  final body = raw
      .trim()
      .replaceFirst(RegExp(r'^:::quiz\s*\n?'), '')
      .replaceFirst(RegExp(r'\n?:::\s*$'), '');

  String? question;

  final options = <AdminQuizOption>[];

  final noteLines = <String>[];

  for (final line in body.split('\n')) {

    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      continue;
    }

    if (trimmed.startsWith('+ ') || trimmed == '+') {
      options.add(AdminQuizOption(
        text: trimmed.length > 2 ? trimmed.substring(2).trim() : '',
        correct: true,
      ));
    } else if (trimmed.startsWith('- ') || trimmed == '-') {
      options.add(AdminQuizOption(
        text: trimmed.length > 2 ? trimmed.substring(2).trim() : '',
        correct: false,
      ));
    } else if (trimmed.startsWith('> ') || trimmed == '>') {
      noteLines.add(trimmed.length > 2 ? trimmed.substring(2).trim() : '');
    } else {
      question ??= trimmed;
    }
  }

  if (question == null) {
    return null;
  }

  return AdminQuiz(
    question: question,
    options: List.unmodifiable(options),
    note: noteLines.isEmpty ? null : noteLines.join(' '),
  );
}

/// Собирает блок `:::quiz … :::` из структуры.
String serializeQuiz(AdminQuiz quiz) {

  final lines = <String>[':::quiz', quiz.question];

  for (final option in quiz.options) {
    lines.add('${option.correct ? '+' : '-'} ${option.text}');
  }

  final note = quiz.note?.trim();

  if (note != null && note.isNotEmpty) {
    lines.add('> $note');
  }

  lines.add(':::');

  return lines.join('\n');
}

/// Квиз считается заполненным: вопрос и минимум два варианта.
bool isQuizFilled(AdminQuiz quiz) =>
    quiz.question.trim().isNotEmpty &&
    quiz.options.where((o) => o.text.trim().isNotEmpty).length >= 2;

/// Вставляет/заменяет/удаляет квиз в полном тексте файла.
///
/// [quiz] null или незаполненный → существующий квиз удаляется
/// (если был); иначе — заменяется существующий или добавляется
/// в конец. Всегда возвращает непустой результат.
String applyQuizToText(String raw, AdminQuiz? quiz) {

  final blocks = splitAdminBlocks(raw);

  final quizIndex = blocks.indexWhere(
    (b) => b.type == AdminBlockType.quiz,
  );

  final effective = (quiz != null && isQuizFilled(quiz)) ? quiz : null;

  if (effective == null) {
    if (quizIndex < 0) {
      return raw;
    }

    blocks.removeAt(quizIndex);

    return joinAdminBlocks(blocks);
  }

  final block = AdminBlock(
    type: AdminBlockType.quiz,
    text: serializeQuiz(effective),
  );

  if (quizIndex >= 0) {
    blocks[quizIndex] = block;
  } else {
    blocks.add(block);
  }

  return joinAdminBlocks(blocks);
}

/// Находит блок квиза в полном тексте (null — квиза нет).
AdminQuiz? quizFromText(String raw) {

  for (final block in splitAdminBlocks(raw)) {
    if (block.type == AdminBlockType.quiz) {
      return parseQuizBlock(block.text);
    }
  }

  return null;
}
