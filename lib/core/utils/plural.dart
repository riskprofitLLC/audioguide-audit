/// Склонение русских существительных после числительных.
///
/// `pluralRu(2, 'место', 'места', 'мест')` → «места».
/// Правило: всё, что кончается на 1 (кроме …11) — единственное
/// число; 2–4 (кроме 12–14) — родительный единственного; иначе —
/// родительный множественного.
String pluralRu(int n, String one, String few, String many) {
  final abs = n.abs();

  final mod10 = abs % 10;

  final mod100 = abs % 100;

  if (mod10 == 1 && mod100 != 11) {
    return one;
  }

  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return few;
  }

  return many;
}
