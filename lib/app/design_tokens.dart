import 'package:flutter/material.dart';

/// Дизайн-токены «Ликийского дневника»: радиусы, тени,
/// отступы и константы анимаций.
///
/// Цвета живут в `AppColors` (theme.dart) — здесь только
/// «геометрия» системы, чтобы виджеты не расползались
/// по магическим числам.
abstract class AppRadius {
  /// Волосная рамка (1 px).
  static const double hairline = 1;

  /// Миниатюрные скругления (2 px) — точки-индикаторы, мелкие бейджи.
  static const double xs = 2;

  /// Точечные элементы (3 px).
  static const double mini = 3;

  /// Мелкие плашки (8 px).
  static const double sm = 8;

  /// Чипы и фильтры (10 px).
  static const double chip = 10;

  /// Средние блоки (8 px) — «Атлас»: печатные прямоугольники.
  static const double lg = 8;

  /// Крупные блоки внутри карточек (10 px).
  static const double block = 10;

  /// Карточки и крупные блоки (8 px).
  static const double card = 8;

  /// Плитки списков и мелкие блоки (6 px).
  static const double tile = 6;

  /// Поля ввода и мелкие контролы (8 px).
  static const double field = 8;

  /// Иконки-миниатюры в списках (6 px).
  static const double thumb = 6;

  /// Крупные фото и галереи (8 px).
  static const double image = 8;

  /// Нижние шторки (20 px).
  static const double sheet = 20;

  /// Плавающая капсула навигации.
  static const double capsule = 26;

  /// Полноценная «пилюля».
  static const double pill = 999;
}

/// Мягкие двухслойные тени: лёгкая «подложка» + узкий
/// контактный полутон. Жёсткие Material-тени не используем.
abstract class AppShadows {
  static List<BoxShadow> card(Color ink) => [
        BoxShadow(
          color: ink.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: ink.withValues(alpha: 0.04),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  /// Для плавающих элементов (кнопки на карте, капсула навбара).
  static List<BoxShadow> floating(Color ink) => [
        BoxShadow(
          color: ink.withValues(alpha: 0.12),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: ink.withValues(alpha: 0.06),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
}

/// Базовая вертикальная шкала отступов (P1-8, 6-й проход).
///
/// Секции главной, избранного и шторок сводятся к шагам
/// 8/12/16/24 — раньше встречались 9/10/14/18/20. Новые места
/// используют токены; существующие «вне шкалы» значения
/// приведены к ближайшему шагу (9→8, 10→8, 14→16, 18→16,
/// 20→16) в явных нарушителях, весь проект не переписывается.
abstract class AppSpace {
  /// Межблочный «воздух» внутри секции.
  static const double xs = 8;

  /// Отступ до подзаголовка / мелкой группы.
  static const double s = 12;

  /// Стандартный межсекционный шаг.
  static const double m = 16;

  /// Крупный разрыв между секциями.
  static const double l = 24;

  /// «Атлас»: крупные editorial-отступы — воздух между блоками
  /// на главной и деталях.
  static const double xl = 32;

  /// Самый крупный разрыв (герой → контент).
  static const double xxl = 48;
}

/// Константы анимаций: короткие, 150–340 мс, плавные кривые.
abstract class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);

  static const Duration normal = Duration(milliseconds: 260);

  static const Duration slow = Duration(milliseconds: 340);

  /// Основная кривая появления/переходов.
  static const Curve curve = Curves.easeOutCubic;

  /// Пружинистая кривая для «поп»-эффектов (звезда, пульс).
  static const Curve pop = Curves.easeOutBack;
}

/// Типографическая шкала «Ликийского дневника» (B1, 8-й проход).
///
/// Единая точка типографики: новые места берут отсюда, а не заводят
/// магические fontSize. Prata — дисплейные заголовки (один вес, без
/// fontWeight/letterSpacing); Manrope — UI и тексты.
///
/// Минимумы читаемости: 11 px — только CAPS/цифры (eyebrow), 12 px —
/// обычный текст (caption).
abstract class AppText {
  /// Крупные дисплейные моменты: сплэш, пустые состояния.
  /// «Атлас»: дисплей стал заметно крупнее — заголовки должны
  /// читаться как обложка, а не как подпись.
  static const TextStyle display = TextStyle(
    fontFamily: 'Prata',
    fontSize: 40,
    height: 1.1,
  );

  /// Заголовки страниц.
  static const TextStyle h1 = TextStyle(
    fontFamily: 'Prata',
    fontSize: 28,
    height: 1.12,
  );

  /// Заголовок точки/маршрута на телефоне.
  static const TextStyle h2 = TextStyle(
    fontFamily: 'Prata',
    fontSize: 23,
    height: 1.1,
  );

  /// Подзаголовки статьи (markdown `##`).
  static const TextStyle h3 = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    fontSize: 17,
    height: 1.25,
  );

  /// Статья POI (текст — главное): в «Атласе» больше воздуха
  /// между строками — длинное чтение легче.
  static const TextStyle bodyL = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 16,
    height: 1.75,
  );

  /// Основной текст UI (списки, шторки).
  static const TextStyle body = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14,
    height: 1.6,
  );

  /// Подписи и вторичные тексты.
  static const TextStyle caption = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 12,
    height: 1.4,
  );

  /// Кнопочные подписи: единый размер всех кнопок темы (B3,
  /// 9-й проход) — раньше 14.5 жил магией в четырёх местах
  /// theme.dart.
  static const TextStyle button = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );

  /// Eyebrow-строки: CAPS, трекинг 1.0, минимум 11 px.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 1.0,
  );

  /// Eyebrow-вариант для надзаголовков карточек с плотным
  /// трекингом («ПРОДОЛЖИТЬ», «АУДИОГИД», «МАРШРУТ • 2.4 КМ»).
  /// Цвет задают места использования (палитра/глубина).
  static const TextStyle eyebrowMuted = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 0.8,
  );

  /// Подписи бейджей («№ 5», категории): 11 px w800, лёгкий
  /// трекинг. Цвет — по подложке (accentOn на бирюзе,
  /// onSurface на песке).
  static const TextStyle badge = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    fontSize: 11,
    height: 1.25,
    letterSpacing: 0.4,
  );

  /// Мета-строки (подписи под заголовками: «аудио 6:33 · чтение
  /// 4 мин», «Старт · 12 м»). Приглушённый цвет — на месте.
  static const TextStyle meta = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w700,
    fontSize: 11,
    height: 1.35,
    letterSpacing: 0.3,
  );

  /// Крупный заголовок-герой на деталях — обложка точки в атласе.
  static const TextStyle headline = TextStyle(
    fontFamily: 'Prata',
    fontSize: 34,
    height: 1.08,
  );

  /// Заголовок секции списка (компактный SectionTitle, 15 px w800).
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    fontSize: 15,
    letterSpacing: -0.2,
    height: 1.3,
  );

  /// Подписи чипов и фильтров (13 px w800).
  static const TextStyle chip = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    fontSize: 13,
    height: 1.3,
  );

  /// Мелкие подписи — эквивалент labelSmall темы (11 px w700).
  static const TextStyle label = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1.0,
    height: 1.2,
  );

  /// Заголовок карточки поверх фото (19 px).
  static const TextStyle cardTitle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 19,
    height: 1.18,
  );
}
