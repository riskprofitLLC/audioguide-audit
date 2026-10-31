import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../features/content/services/markdown_blocks.dart';


/// Текст с ограничением высоты и кнопкой «Развернуть».
///
/// Показывает максимум [collapsedLines] строк; если текст длиннее —
/// внизу появляется кнопка «Развернуть», по нажатию которой текст
/// отображается целиком (а кнопка меняется на «Свернуть»). Если
/// текст помещается целиком — кнопка не показывается.
///
/// Свёрнутое состояние — журнальный клип: абзацы разделены
/// отступами, последняя видимая строка растворяется градиентом
/// (без резкого эллипсиса). Развёрнутое — статья с буквицей
/// первого абзаца (серифная Prata) и межабзацными отступами;
/// вокруг статьи [SelectionArea] — текст можно выделять и
/// копировать (web/desktop). «Свернуть» докручивает страницу к
/// началу статьи, если та ушла выше экрана.
///
/// B3.4 (8-й проход): структура передаётся блоками markdown
/// ([blocks]) — подзаголовки `##` рисуются h3, списки — буллетами,
/// инлайновые *курсив*/`**жирный**`/ссылки — типографикой. Замер
/// свёрнутого клипа повторяет рендер по тем же блокам, буквица —
/// первый граф первого абзаца. Режим [text] оставлен прежним
/// (шторки POI/маршрута, фолбэк).
class ExpandableText extends StatefulWidget {

  const ExpandableText({
    super.key,
    this.text,
    this.blocks,
    this.collapsedLines = 4,
    this.style,
  }) : assert(
          (text != null) != (blocks != null),
          'либо text, либо blocks',
        );


  final String? text;

  /// Блоки markdown (приоритетнее [text]).
  final List<MdBlock>? blocks;


  final int collapsedLines;

  final TextStyle? style;


  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}


/// Единица рендера статьи: абзац/подзаголовок/пункт списка.
/// Единица потока статьи: спан, флаг «абзац» и исходный блок
/// markdown (null для текстового режима) — буквица берёт блок
/// из ЕДИНИЦЫ, а не по индексу списка blocks (A4: квиз исключён
/// из единиц, индексы разъезжаются).
typedef _ArticleUnit = ({
  TextSpan span,
  bool isParagraph,
  MdBlock? block,
});

class _ExpandableTextState extends State<ExpandableText> {

  /// Межабзацный отступ рендера. Замер обязан его учитывать:
  /// раньше высота клипа считалась по сплошному тексту, и
  /// видимое число строк расходилось с collapsedLines (P0-6,
  /// 5-й проход).
  static const double _paragraphGap = 10.0;

  bool _expanded = false;

  bool _overflows = false;

  /// Высота свёрнутого клипа (N строк потока без эллипсиса).
  double? _collapsedHeight;


  /// Ширина, на которой последний раз мерили переполнение:
  /// повторные build на той же ширине не запускают лишний замер.
  double? _checkedWidth;


  @override
  void didUpdateWidget(covariant ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.blocks != widget.blocks ||
        oldWidget.collapsedLines != widget.collapsedLines ||
        oldWidget.style != widget.style) {
      _expanded = false;

      // Текст/блоки/стиль изменились — перемерить на следующем build.
      _checkedWidth = null;

      _collapsedHeight = null;
    }
  }


  /// Единицы статьи: либо блоки markdown, либо абзацы текста
  /// (разделены пустой строкой). Порядок = порядок рендера =
  /// порядок замера.
  List<_ArticleUnit> _units() {
    final blocks = widget.blocks;

    final style = widget.style ?? AppText.bodyL;

    if (blocks != null) {
      return [
        // Квиз — НЕ единица статьи (A4): карточку рисует страница
        // POI ниже ExpandableText; лишний отступ, замер высоты и
        // риск буквицы на квизе исключаем вместе с ним.
        for (final block in blocks)
          if (block is! MdQuiz)
            (
              span: mdBlockTextSpan(block, style: style),
              isParagraph: block is! MdHeading,
              block: block,
            ),
      ];
    }

    final paragraphs =
        (widget.text ?? '').split(RegExp(r'\n[ \t]*\n'));

    return [
      for (final paragraph in paragraphs)
        (
          span: TextSpan(text: paragraph, style: style),
          isParagraph: true,
          block: null,
        ),
    ];
  }


  /// Свёрнутый текст: единицы с отступами, обрезанные по высоте
  /// [collapsedLines] строк; нижняя строка растворяется фейдом —
  /// ТОЛЬКО когда текст реально переполняет клип (A1, 10-й
  /// проход): раньше ShaderMask вешался всегда, и у коротких
  /// описаний последняя строка выцветала без всякой кнопки.
  Widget _buildCollapsed(double fadeHeight, {required bool fade}) {
    final height = _collapsedHeight;

    if (height == null) {
      // До первого замера — жёсткий клип по maxLines: без него
      // свёрнутое состояние рендерило весь текст без
      // ограничения, и страница мигала длинным полотном (P0-6).
      return Text(
        widget.text ??
            [for (final unit in _units()) unit.span.toPlainText()].join('\n\n'),
        maxLines: widget.collapsedLines,
        style: widget.style ?? AppText.bodyL,
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildUnitWidgets(dropCap: false),
    );

    // Клип остаётся и у помещающегося текста (высота = полная
    // высота потока, резать нечего — но замер и рендер идут
    // одной структурой), а вот фейд — только при переполнении.
    final clip = ClipRect(
      child: SizedBox(
        height: height,
        width: double.infinity,
        // Единицы идут естественным потоком, лишнее срезает
        // клип; NeverScrollable — чтобы не ловить жесты
        // внешнего списка.
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: body,
        ),
      ),
    );

    if (!fade) {
      return clip;
    }

    // Градиент растворяет последнюю видимую строку — мягче
    // резкого эллипсиса «…».
    return ShaderMask(
      blendMode: BlendMode.dstOut,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [
            (1.0 - fadeHeight / bounds.height).clamp(0.0, 1.0),
            1.0,
          ],
          colors: const [
            Colors.transparent,
            Colors.black,
          ],
        ).createShader(bounds);
      },
      child: clip,
    );
  }


  /// Виджеты единиц: единицы с межабзацными отступами; в
  /// развёрнутом виде первый абзац получает буквицу.
  List<Widget> _buildUnitWidgets({required bool dropCap}) {
    final units = _units();

    // Индекс блока-абзаца для буквицы: в режиме блоков —
    // индекс в blocks (у подзаголовков буквицы нет).
    final paragraphIndex = dropCap
        ? units.indexWhere((unit) => unit.isParagraph)
        : -1;

    return [
      for (var i = 0; i < units.length; i++) ...[
        if (i > 0) const SizedBox(height: _paragraphGap),
        Text.rich(
          i == paragraphIndex
              ? (units[i].block != null
                  // Буквица с сохранением инлайновых спанов:
                  // *курсив*/жирный в первом абзаце не теряются.
                  // Блок — из САМОЙ единицы: индексы blocks после
                  // исключения квизов больше не совпадают (A4).
                  ? mdBlockTextSpan(
                      units[i].block!,
                      style: widget.style ?? AppText.bodyL,
                      dropCap: true,
                    )
                  : _withDropCap(units[i]))
              : units[i].span,
        ),
      ],
    ];
  }


  /// Буквица — первый ГРАФ абзаца целиком (ё с ударением — два
  /// юникод символа, эмодзи — несколько): разворачивается из
  /// крупной серифной Prata; вес не переопределяется (один вес).
  TextSpan _withDropCap(_ArticleUnit unit) {
    final span = unit.span;

    final plain = span.toPlainText();

    final chars = plain.characters;

    if (chars.isEmpty) {
      return span;
    }

    final first = chars.first;

    final rest = chars.skip(1).toString();

    return TextSpan(
      style: span.style,
      children: [
        TextSpan(
          text: first,
          style: (span.style ?? const TextStyle()).copyWith(
            fontFamily: 'Prata',
            fontWeight: FontWeight.w400,
            fontSize: (span.style?.fontSize ?? 14) * 2.05,
            height: 0.92,
            letterSpacing: 0,
          ),
        ),
        TextSpan(text: rest, style: span.style),
      ],
    );
  }


  /// Развёрнутая статья: буквица первого абзаца + межабзацные
  /// отступы, выделение текста (web/desktop).
  Widget _buildExpanded() {
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildUnitWidgets(dropCap: true),
      ),
    );
  }


  /// Запускает замер переполнения для [maxWidth] (после layout —
  /// реальная ширина уже известна, TextPainter её использует).
  void _checkOverflow(double maxWidth) {

    if (_checkedWidth == maxWidth) {
      return;
    }

    _checkedWidth = maxWidth;

    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (!mounted || _checkedWidth != maxWidth) {
        return;
      }

      final measured = _measureFlow(maxWidth);

      // Пересчёт и при смене переполнения, и при смене высоты
      // клипа (resize: переполнение осталось, а высота другая).
      if (measured.overflows != _overflows ||
          _collapsedHeight == null ||
          measured.height != _collapsedHeight) {
        if (!mounted) return;

        setState(() {
          _overflows = measured.overflows;

          _collapsedHeight = measured.height;
        });
      }
    });
  }

  /// Замер свёрнутого клипа — так же, как рендерится: единицы
  /// с межабзацными отступами [_paragraphGap], включая стили
  /// подзаголовков (высота больше строки текста — замер это
  /// учитывает по painter.height). Возвращает высоту первых
  /// [collapsedLines] строк потока и признак переполнения.
  ({double height, bool overflows}) _measureFlow(double maxWidth) {
    final direction = Directionality.of(context);

    final scaler = MediaQuery.textScalerOf(context);

    final style = widget.style ?? AppText.bodyL;

    var height = 0.0;

    var accLines = 0;

    var overflows = false;

    var lineHeight = 0.0;

    final units = _units();

    for (var i = 0; i < units.length; i++) {

      final span = units[i].span;

      final painter = TextPainter(
        text: span,
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: maxWidth);

      // Высота одной строки — из замера первой абзацной единицы.
      if (lineHeight == 0.0 && units[i].isParagraph) {
        final oneLine = TextPainter(
          text: TextSpan(text: span.toPlainText(), style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout(maxWidth: maxWidth);

        lineHeight = oneLine.height;

        oneLine.dispose();
      }

      final unitLines = lineHeight == 0.0
          ? 1
          : (painter.height / lineHeight).ceil();

      if (accLines + unitLines <= widget.collapsedLines) {
        height += painter.height;

        accLines += unitLines;

        if (i < units.length - 1) {
          height += _paragraphGap;
        }
      } else {
        // Единица переходит границу N строк: в клип уходит лишь
        // её видимый «хвост» высотой в оставшиеся строки.
        final remaining = widget.collapsedLines - accLines;

        if (remaining > 0) {
          height += lineHeight * remaining;
        }

        overflows = true;

        painter.dispose();

        break;
      }

      painter.dispose();
    }

    return (height: height, overflows: overflows);
  }


  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final actionStyle = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      fontSize: ((widget.style ?? AppText.bodyL).fontSize ?? 14) - 1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {

        // Реальная ширина виджета (внутри Padding/ListView/SizedBox
        // текст может быть уже экрана); в неограниченном контексте —
        // фолбэк на ширину экрана.
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        _checkOverflow(maxWidth);

        final body = _expanded
            ? _buildExpanded()
            : _buildCollapsed(26, fade: _overflows);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Плавное раскрытие/свёртывание по высоте.
            AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: body,
            ),

            if (_overflows)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });

                    // «Свернуть» возвращает прокрутку к началу
                    // статьи: после схлопывания длинной статьи
                    // читатель не остаётся «ниже» её конца.
                    if (!_expanded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;

                        Scrollable.ensureVisible(
                          context,
                          alignment: 0.2,
                          duration: AppMotion.normal,
                        );
                      });
                    }
                  },
                  icon: Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 18,
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    // Тап-цель 44 по высоте без визуального
                    // раздувания: фон у кнопки прозрачный, видны
                    // только текст и иконка. compact-плотность
                    // срезает 8 px от цели — не используем
                    // (P1-2, 7-й проход).
                    minimumSize: const Size(48, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  label: Text(
                    _expanded ? 'Свернуть' : 'Развернуть',
                    style: actionStyle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
