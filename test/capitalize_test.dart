// capitalize: первая буква заголовка — в верхний регистр.
//
// Применяется к названиям из манифестов/каталога; обещание
// «кириллицу обрабатывает корректно» держим тестом (регрессия —
// заголовки вида «остров Кекова» с маленькой буквы).

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/utils/capitalize.dart';

void main() {
  test('латиница', () {
    expect(capitalize('fethiye'), 'Fethiye');
  });

  test('кириллица', () {
    expect(capitalize('кекова'), 'Кекова');

    expect(capitalize('остров Кекова'), 'Остров Кекова');
  });

  test('уже с большой буквы — не меняется', () {
    expect(capitalize('Гемилер'), 'Гемилер');
  });

  test('пустая строка и один символ', () {
    expect(capitalize(''), '');

    expect(capitalize('а'), 'А');
  });

  test('не трогает остальные символы строки', () {
    expect(capitalize('залив Фетхие — 2'), 'Залив Фетхие — 2');
  });
}
