import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_chip.dart';


/// Элемент горизонтальной ленты чипов: id и подпись.
typedef ChipRailItem = ({String id, String label});


/// Горизонтальная лента чипов с автопрокруткой к активному элементу.
///
/// Заменяет сегментированные контролы главного экрана: чипы занимают
/// ширину по тексту, поэтому длинные названия регионов и локаций не
/// обрезаются — лишнее уезжает в горизонтальную прокрутку. Полосы
/// прокрутки нет; свайп работает пальцем и, на web, мышью.
class ScrollableChipRail extends StatefulWidget {

  const ScrollableChipRail({
    super.key,
    required this.items,
    required this.activeId,
    required this.onSelect,
    this.icon,
    // B1: null — берём роли палитры (info/onInfo). Прежние значения
    // по умолчанию были хардкодом AppColors.depth/accentOn, и в тёмной
    // теме белый текст на светло-голубой заливке давал ~2:1.
    this.activeFill,
    this.activeTextColor,
    this.activeIconColor,
    this.tall = false,
  });


  final List<ChipRailItem> items;


  final String activeId;


  final ValueChanged<String> onSelect;


  /// Иконка слева от подписи — единая для всех чипов ленты.
  final IconData? icon;


  /// Заливка активного чипа; `null` — [AppPalette.info].
  final Color? activeFill;

  /// Текст/иконка активного чипа; `null` — [AppPalette.onInfo].
  final Color? activeTextColor;


  /// Цвет иконки активного чипа (по умолчанию — цвет текста).
  final Color? activeIconColor;


  /// Крупные чипы (ленты регионов/локаций главной): пилюля ~34 px,
  /// подпись [AppText.button] — переключатели читаются как кнопки,
  /// а не как мелкие подписи.
  final bool tall;


  @override
  State<ScrollableChipRail> createState() => _ScrollableChipRailState();
}


class _ScrollableChipRailState extends State<ScrollableChipRail> {

  final ScrollController _controller = ScrollController();

  final Map<String, GlobalKey> _keys = {};

  /// Насколько естественная сумма чипов может превышать ленту, чтобы
  /// всё равно растянуться на всю ширину.
  ///
  /// До 40%: при пропорциональном flex каждый чип теряет не больше
  /// ~30% своей ширины — подписи читаются, лента выглядит рядами
  /// кнопок во всю ширину вместо двух чипов в прокрутке.
  static const double kStretchOverflowFactor = 1.4;

  /// Сколько чипов считается «мало» — им разрешено растянуться даже
  /// при легком переполнении ([kStretchOverflowFactor]).

  /// Регионы из ДВУХ локаций («Фетхие и Гёчек» + «Гемилер»,
  /// «Побережье» + «Остров Кекова», «Даламан» + «Мармарис») своими
  /// названиями шире телефона и уходили в горизонтальную прокрутку,
  /// хотя чипов мало и пустого места в ленте нет.

  /// Три и больше («Памфилия», «Киликия», все регионы) при
  /// переполнении всё равно прокручиваются: растяжение дробило бы
  /// их подписи до нечитаемости.
  static const int kStretchMaxItems = 2;

  /// Кеш замеров ширины чипов: ключ — подпись + иконка +
  /// текст-скейл (P1-1: TextPainter больше не гоняется на
  /// каждый build).
  final Map<String, double> _widthCache = {};

  String _widthCacheKey(String label) {
    final scale = MediaQuery.textScalerOf(context).scale(1);

    return '$label|${widget.icon ?? ''}|$scale';
  }


  @override
  void initState() {

    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }


  @override
  void didUpdateWidget(covariant ScrollableChipRail oldWidget) {

    super.didUpdateWidget(oldWidget);

    if (oldWidget.activeId != widget.activeId) {

      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
    }
  }


  @override
  void dispose() {

    _controller.dispose();

    super.dispose();
  }


  /// Подводит активный чип в видимую зону (по центру) —
  /// только внутри горизонтального скролла самой ленты.
  void _revealActive() {

    final context =
        _keys[widget.activeId]?.currentContext;

    if (context == null || !mounted) {

      return;
    }

    // Когда чипы помещаются, лента — обычный Row без
    // горизонтального скролла. Scrollable.ensureVisible тогда
    // брал ближайший ВЕРТИКАЛЬНЫЙ скролл страницы и
    // автопрокручивал главную вниз на ~105 px (шапка уезжала
    // за экран). Подводим чип только внутри своей ленты.
    if (Scrollable.maybeOf(
          context,
          axis: Axis.horizontal,
        ) ==
        null) {

      return;
    }

    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: AppMotion.normal,
      curve: AppMotion.curve,
    );
  }


  GlobalKey _keyFor(String id) {

    return _keys.putIfAbsent(id, () => GlobalKey());
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {

        final maxWidth = constraints.maxWidth;

        const gap = 7.0;

        final widths = [
          for (final item in widget.items) _labelWidth(item),
        ];

        final total =
            widths.fold(0.0, (sum, w) => sum + w) +
            gap * (widget.items.length - 1);

        // Мало чипов — растягиваем на всю ширину (свайп не нужен).
        // Замер _labelWidth учитывает ФАКТИЧЕСКИЙ textScale и
        // геометрию AppChip (отступы пилюли, рамка, иконка), поэтому
        // «помещается по замеру» = «помещается в лейауте»: Expanded
        // лишь добавляет чипам ширину, подписи не ужимаются даже при
        // textScale 1.3 (там замер тоже растёт).
        //
        // Запас на лёгкое неполомание (kStretchOverflowFactor): если
        // естественная сумма ЧУТЬ шире ленты, а чипов мало
        // (kStretchMaxItems) — всё равно растягиваемся. Иначе две
        // локации с длинными названиями уходили в горизонтальную
        // прокрутку и не занимали всю ширину, хотя чипов мало:
        // «Фетхие и Гёчек» + «Гемилер» = 431 px против 361 px
        // доступных на телефоне 393 dp (и «Побережье» +
        // «Остров Кекова» = 445 px). Пропорциональный flex отдаёт
        // каждому чипу ≥70% его ширины — подписи читаются.
        // Три и больше чипов при переполнении не трогаем: их
        // растяжение дробит подписи («Памфилия», «Киликия»).
        final fewChips = widget.items.length <= kStretchMaxItems;

        if (total <= maxWidth ||
            (fewChips && total <= maxWidth * kStretchOverflowFactor)) {

          return Row(
            children: [

              for (var i = 0; i < widget.items.length; i++) ...[

                if (i > 0) const SizedBox(width: gap),

                // flex пропорционален естественной ширине чипа:
                // лишнее пространство распределяется равномерно,
                // но чип никогда не сожмётся уже своей подписи.
                Expanded(
                  flex: widths[i].round().clamp(1, 1 << 20).toInt(),
                  child: AppChip(
                    key: _keyFor(widget.items[i].id),
                    label: widget.items[i].label,
                    icon: widget.icon,
                    tall: widget.tall,
                    // Пилюля обязана заполнить слот: DecoratedBox
                    // сам по себе живёт по содержимому, и без этого
                    // флага «растянутая» лента выглядит как кнопки
                    // по тексту с пустотами между ними.
                    fillWidth: true,
                    selected: widget.items[i].id == widget.activeId,
                    fill: widget.activeFill,
                    textColor: widget.activeTextColor,
                    onTap: () => widget.onSelect(widget.items[i].id),
                  ),
                ),
              ],
            ],
          );
        }

        // Много чипов — горизонтальная прокрутка свайпом.
        return ScrollConfiguration(

          // Своя полоса не нужна, а мышь на web должна тянуть ленту.
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),

          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [

                for (final item in widget.items)
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: AppChip(
                      key: _keyFor(item.id),
                      label: item.label,
                      icon: widget.icon,
                      tall: widget.tall,
                      selected: item.id == widget.activeId,
                      fill: widget.activeFill,
                      textColor: widget.activeTextColor,
                      onTap: () => widget.onSelect(item.id),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }


  /// Естественная ширина чипа: подпись + иконка + отступы.
  /// Замер повторяет фактические параметры [AppChip] (шрифт,
  /// отступы, размер иконки) — иначе порог «помещается/скролл» и
  /// flex распределения считаются по не той ширине.
  double _labelWidth(ChipRailItem item) {

    final cacheKey = _widthCacheKey(item.label);

    final cached = _widthCache[cacheKey];

    if (cached != null) {
      return cached;
    }

    final style = widget.tall
        ? AppText.button.copyWith(letterSpacing: 0.2)
        : AppText.chip.copyWith(
            letterSpacing: 0.15,
          );

    final painter = TextPainter(
      text: TextSpan(text: item.label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();

    final iconWidth =
        widget.icon != null ? (widget.tall ? 17.0 + 6.0 : 15.0 + 6.0) : 0.0;

    // Горизонтальные отступы пилюли ×2 + волосяная рамка ×2.
    final chrome = widget.tall ? 38.0 : 26.0;

    final width = painter.width + chrome + iconWidth;

    // TextPainter держит нативные ресурсы — освобождаем сразу
    // после замера, иначе на каждом build копятся утечки.
    painter.dispose();

    _widthCache[cacheKey] = width;

    return width;
  }
}
