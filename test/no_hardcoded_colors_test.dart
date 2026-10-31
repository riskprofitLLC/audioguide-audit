import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Страж тёмной темы (D1, замечания Sonnet): в UI-слое
/// (lib/**/presentation + lib/core/widgets) запрещены прямые
/// СВЕТЛЫЕ константы AppColors — только роли AppPalette.of(context)
/// либо осознанно-постоянные роли над контентом (onScrim, scrimDark,
/// scrimInk, accentOn, map*-константы, signal).
///
/// ink/card/sand/sandLight/chart/onSurface/onSurfaceMuted —
/// светло-тематические значения: в ночной теме чернильный текст на
/// тёмном фоне шторок почти не виден. Нарушение = ошибка со списком.
void main() {
  test('в UI-слое нет прямых светлых AppColors (только палитра)', () {
    // Файлы, которым разрешено нарушать правило (осознанный белый
    // список). Пока пуст: миграция D1 завершена, страж держит её.
    const whitelist = <String>{
      // 'lib/features/…/example.dart',
    };

    final libDir = Directory('lib');

    final forbidden = RegExp(
      r'AppColors\.(ink|card|sand|sandLight|chart|onSurface|onSurfaceMuted)\b',
    );

    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final path = file.path.replaceAll('\\', '/');

          if (whitelist.contains(path)) {
            return false;
          }

          return path.contains('/presentation/') ||
              path.startsWith('lib/core/widgets/');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final violations = <String>[];

    for (final file in files) {
      final rel = file.path.replaceAll('\\', '/');

      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        var code = lines[i];

        // Комментарии не считаются (упоминания в доках допустимы).
        final comment = code.indexOf('//');

        if (comment >= 0) {
          code = code.substring(0, comment);
        }

        if (forbidden.hasMatch(code)) {
          violations.add('$rel:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Прямые светлые AppColors в UI — мигрировать на '
          'AppPalette.of(context) (или осознанную постоянную роль '
          'scrimInk/onScrim поверх фото) и/или добавить файл в '
          'белый список теста:\n'
          '${violations.join('\n')}',
    );
  });
}
