import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';


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
    this.activeFill = AppColors.depth,
    this.activeTextColor = AppColors.accentOn,
    this.activeIconColor,
  });


  final List<ChipRailItem> items;


  final String activeId;


  final ValueChanged<String> onSelect;


  /// Иконка слева от подписи — единая для всех чипов ленты.
  final IconData? icon;


  /// Заливка активного чипа.
  final Color activeFill;


  final Color activeTextColor;


  /// Цвет иконки активного чипа (по умолчанию — цвет текста).
  final Color? activeIconColor;


  @override
  State<ScrollableChipRail> createState() => _ScrollableChipRailState();
}


class _ScrollableChipRailState extends State<ScrollableChipRail> {

  final ScrollController _controller = ScrollController();

  final Map<String, GlobalKey> _keys = {};

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

    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {

        final maxWidth = constraints.maxWidth;

        const gap = 7.0;

        final widths = [
          for (final item in widget.items)
            _labelWidth(item, theme),
        ];

        final total =
            widths.fold(0.0, (sum, w) => sum + w) +
            gap * (widget.items.length - 1);

        // Мало чипов — растягиваем на всю ширину (свайп не нужен).
        // Порог с запасом ×0.92: при узком экране и textScale 1.3
        // Row с Expanded ужимает подписи (softWrap:false) до
        // переполнения — лучше сразу уйти в горизонтальный скролл.
        if (total <= maxWidth * 0.92) {

          return Row(
            children: [

              for (var i = 0; i < widget.items.length; i++) ...[

                if (i > 0) const SizedBox(width: gap),

                // flex пропорционален естественной ширине чипа:
                // лишнее пространство распределяется равномерно,
                // но чип никогда не сожмётся уже своей подписи.
                Expanded(
                  flex: widths[i].round().clamp(1, 1 << 20).toInt(),
                  child: _Chip(
                    key: _keyFor(widget.items[i].id),
                    label: widget.items[i].label,
                    icon: widget.icon,
                    active: widget.items[i].id == widget.activeId,
                    activeFill: widget.activeFill,
                    activeTextColor: widget.activeTextColor,
                    activeIconColor: widget.activeIconColor,
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
                    child: _Chip(
                      key: _keyFor(item.id),
                      label: item.label,
                      icon: widget.icon,
                      active: item.id == widget.activeId,
                      activeFill: widget.activeFill,
                      activeTextColor: widget.activeTextColor,
                      activeIconColor: widget.activeIconColor,
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
  double _labelWidth(ChipRailItem item, ThemeData theme) {

    final cacheKey = _widthCacheKey(item.label);

    final cached = _widthCache[cacheKey];

    if (cached != null) {
      return cached;
    }

    final style = AppText.chip.copyWith(
      letterSpacing: 0.15,
    );

    final painter = TextPainter(
      text: TextSpan(text: item.label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();

    final iconWidth = widget.icon != null ? 15.0 + 6.0 : 0.0;

    final width = painter.width + 26.0 + iconWidth;

    // TextPainter держит нативные ресурсы — освобождаем сразу
    // после замера, иначе на каждом build копятся утечки.
    painter.dispose();

    _widthCache[cacheKey] = width;

    return width;
  }
}


/// Чип ленты: пилюля по ширине текста, плавная перекраска
/// активного состояния.
class _Chip extends StatelessWidget {

  const _Chip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.activeFill,
    required this.activeTextColor,
    this.icon,
    this.activeIconColor,
  });


  final String label;

  final bool active;

  final VoidCallback onTap;

  final IconData? icon;

  final Color activeFill;

  final Color activeTextColor;

  final Color? activeIconColor;


  @override
  Widget build(BuildContext context) {


    final palette = AppPalette.of(context);

    final background = active ? activeFill : palette.surfaceRaised;

    final foreground = active ? activeTextColor : palette.onSurface;

    final iconColor =
        active ? (activeIconColor ?? activeTextColor) : AppColors.depth;

    // Семантика чипа: это КНОПКА с состоянием выбора (P1-1).
    return Semantics(
      button: true,
      selected: active,
      child: AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color:
              active ? activeFill : palette.sand.withValues(alpha: 0.9),
          width: 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: activeFill.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () {
            // Лёгкий тактильный отклик переключения.
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  if (icon != null) ...[

                    Icon(icon, size: 15, color: iconColor),

                    const SizedBox(width: 6),
                  ],

                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: AppText.chip.copyWith(
                      color: foreground,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }
}
