// Атрибуция фото из credits.json (A9, 8-й проход).
//
// Фото Wikimedia Commons под CC BY / CC BY-SA требуют указания
// автора и лицензии рядом с изображением. Подпись «Фото: автор ·
// лицензия» показывается в галерее — формат проверяем тестом,
// чтобы лицензия не потеряла автора при правках.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/services/photo_credits.dart';

void main() {
  test('caption: автор и лицензия', () {
    const credit = PhotoCredit(author: 'Иван Петров', license: 'CC BY-SA 4.0');

    expect(credit.caption, 'Фото: Иван Петров · CC BY-SA 4.0');
  });

  test('caption: только автор', () {
    const credit = PhotoCredit(author: 'Иван Петров');

    expect(credit.caption, 'Фото: Иван Петров');
  });

  test('caption: только лицензия', () {
    const credit = PhotoCredit(license: 'CC0');

    expect(credit.caption, 'Фото: CC0');
  });

  test('caption: пустые/отсутствующие поля — подписи нет (ничего не '
      'выдумываем)', () {
    expect(const PhotoCredit().caption, isNull);

    expect(const PhotoCredit(author: '', license: '').caption, isNull);
  });

  test('fromJson: читает все поля и терпит отсутствующие', () {
    final credit = PhotoCredit.fromJson(const {
      'author': 'A',
      'license': 'CC BY 4.0',
      'licenseUrl': 'https://creativecommons.org/licenses/by/4.0/',
      'title': 'File:X.jpg',
      'page': 'https://commons.wikimedia.org/wiki/File:X.jpg',
    });

    expect(credit.author, 'A');

    expect(credit.license, 'CC BY 4.0');

    expect(credit.licenseUrl, contains('creativecommons'));

    expect(credit.title, 'File:X.jpg');

    expect(credit.page, contains('commons.wikimedia.org'));

    final empty = PhotoCredit.fromJson(const {});

    expect(empty.caption, isNull);
  });
}
