import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Страж дизайн-системы (D1, замечания Sonnet): «храповик» на
/// типографику/геометрию в UI-слое (lib/**/presentation +
/// lib/core/widgets). Новые места обязаны брать токены —
/// AppText (fontSize), AppRadius (радиусы), AppSpace (отступы) —
/// либо явно расширять лимит с обоснованием в этом файле.
///
/// Это ratchet: существующие литералы зафиксированы лимитами
/// (замена сотен мест — отдельная кампания, не страж); страж
/// падает, когда число вхождений ПРЕВЫШАЕТ лимит. Уменьшение —
/// приветствуется: уменьшил — подними лимит вниз.
void main() {
  test('лимиты литералов типографики/геометрии не растут (ratchet)', () {
    // Лимиты зафиксированы 24-м проходом (A3/D1), снижены после
    // чистки литералов (этап D2 аудита Sonnet): fontSize и радиусы
    // в UI-слое теперь только через AppText/AppRadius. Комментарий
    // в коде не считается, строки-литералы MapLibre не считаются.
    const limits = <String, int>{
      'fontSize: <число> вне AppText': 0,
      'FontWeight.w800 вне design_tokens': 31,
      'BorderRadius.circular(<число>)': 0,
    };

    final libDir = Directory('lib');

    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final path = file.path.replaceAll('\\', '/');

          // Токены живут тут — сам источник не считаем.
          if (path.endsWith('core/design_tokens.dart') ||
              path.endsWith('app/design_tokens.dart')) {
            return false;
          }

          return path.contains('/presentation/') ||
              path.startsWith('lib/core/widgets/');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    var fontSizeCount = 0;
    var w800Count = 0;
    var borderRadiusCount = 0;

    final violations = <String>[];

    for (final file in files) {
      final rel = file.path.replaceAll('\\', '/');

      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        var code = lines[i];

        final comment = code.indexOf('//');

        if (comment >= 0) {
          code = code.substring(0, comment);
        }

        if (RegExp(r'fontSize:\s*[0-9]').hasMatch(code)) {
          fontSizeCount++;

          violations.add('$rel:${i + 1}: $code'.trim());
        }

        if (code.contains('FontWeight.w800')) {
          w800Count++;
        }

        if (RegExp(r'BorderRadius\.circular\(\s*[0-9]').hasMatch(code)) {
          borderRadiusCount++;
        }
      }
    }

    expect(fontSizeCount, lessThanOrEqualTo(limits['fontSize: <число> вне AppText']!),
        reason: 'новые fontSize-литералы — только через AppText\n'
            '${violations.take(20).join('\n')}');
    expect(w800Count,
        lessThanOrEqualTo(limits['FontWeight.w800 вне design_tokens']!),
        reason: 'веса 800 — только токены AppText/тема');
    expect(borderRadiusCount,
        lessThanOrEqualTo(limits['BorderRadius.circular(<число>)']!),
        reason: 'радиусы — AppRadius');
  });
}
