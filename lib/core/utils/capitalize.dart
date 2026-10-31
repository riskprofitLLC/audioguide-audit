/// Первая буква строки — в верхний регистр (для заголовков из
/// манифестов/каталога). Кириллицу обрабатывает корректно.
String capitalize(String s) {

  if (s.isEmpty) {
    return s;
  }

  return s[0].toUpperCase() + s.substring(1);
}
