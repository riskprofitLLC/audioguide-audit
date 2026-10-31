import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../overlay_tracker.dart';
import '../theme.dart';



/// Публикуемые шеллом вставки контента.
///
/// AnimatedBuilder в [NavigationShell.build] пересобирает Row
/// при смене видимости мини-плеера, но передаёт тот же
/// identical-инстанс child — поддерево страниц НЕ перестраивалось,
/// и прочитанный один раз отступ застревал (P0-2, 5-й проход).
/// Теперь пересборка создаёт НОВЫЙ [ShellInsets] с актуальным
/// значением: страницы читают отступ через
/// [NavigationShell.contentBottomInset] (зависимость от
/// InheritedWidget) и реально перестраиваются при смене.
class ShellInsets extends InheritedWidget {
  const ShellInsets({
    super.key,
    required this.bottomInset,
    required super.child,
  });

  final double bottomInset;

  @override
  bool updateShouldNotify(ShellInsets oldWidget) =>
      bottomInset != oldWidget.bottomInset;
}

/// Плавающая навигация: капсула-пилюля на телефоне (<600 px),
/// рельс на планшете/десктопе (>=600 px).
///
/// Капсула парит НАД контентом (Scaffold.body — Stack): список
/// и карта продолжаются под ней до нижней кромки экрана,
/// снизу не остаётся полосы фона. Страницы считают нижний
/// отступ через [NavigationShell.contentBottomInset].
class NavigationShell extends ConsumerStatefulWidget {
  const NavigationShell({
    super.key,
    required this.child,
    this.selectedIndex = 0,
  });

  final Widget child;
  final int selectedIndex;

  /// Высота капсулы (NavigationBar внутри).
  static const double capsuleHeight = 64;

  /// Отступ капсулы от нижней кромки экрана (жест-бар выше —
  /// через MediaQuery).
  static const double capsuleBottomGap = 10;

  /// Занятый капсулой блок над нижней кромкой SafeArea.
  static const double capsuleExtent = capsuleHeight + capsuleBottomGap;

  /// Нижний отступ контента шелла: парящая капсула + воздух +
  /// системный жест-бар. На десктопе (рельс слева, капсулы нет)
  /// — обычный отступ. Пока мини-плеер виден, добавляется
  /// высота пилюли (+66): конец списка не уходит под неё
  /// (продолжение A2c, 4-й проход).
  ///
  /// Внутри шелла значение приходит из [ShellInsets] — при
  /// смене видимости мини-плеера InheritedWidget пересоздаётся,
  /// и все читатели отступа перестраиваются (P0-2).
  static double contentBottomInset(BuildContext context) {
    final shell =
        context.dependOnInheritedWidgetOfExactType<ShellInsets>();

    if (shell != null) {
      return shell.bottomInset;
    }

    // Вне шелла (страницы деталей на root-навигаторе, тесты):
    // прежний расчёт по MediaQuery и глобальным нотификаторам.
    return _computeBottomInset(context);
  }

  static double _computeBottomInset(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    final playerLift =
        miniPlayerVisible.value && modalSheetOpenCount.value == 0
            ? 66.0
            : 0.0;

    if (width >= 600) {
      return 24 + MediaQuery.paddingOf(context).bottom + playerLift;
    }

    return capsuleExtent +
        12 +
        MediaQuery.paddingOf(context).bottom +
        playerLift;
  }

  /// Есть ли под [context] парящая капсула навигации.
  ///
  /// Капсула существует только на телефоне (<600 px) и только
  /// внутри шелла: страницы деталей лежат на root-навигаторе
  /// НАД капсулой, и модальные шторки/SnackBar, открытые из них,
  /// не должны получать отступ «под капсулу» — раньше они
  /// получали лишние ~74 px снизу (P0-2, 7-й проход).
  /// Наличие шелла определяется по [ShellInsets] в дереве.
  static bool hasCapsule(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) {
      return false;
    }

    return context.getInheritedWidgetOfExactType<ShellInsets>() != null;
  }

  /// Нижний отступ контента модальных шторок. Шторки, открытые
  /// из страниц шелла, живут в шелл-навигаторе — ПОД парящей
  /// капсулой, поэтому их нижний контент (плеер, кнопки,
  /// последние строки) обязан заканчиваться выше капсулы.
  /// На десктопе (рельс) и на страницах деталей (root-навигатор
  /// НАД капсулой) капсулы под шторкой нет — обычный отступ
  /// (P0-2, 7-й проход). Системный жест-бар не добавлять:
  /// шторки сами в SafeArea.
  static double sheetBottomInset(BuildContext context) {
    if (hasCapsule(context)) {
      return capsuleExtent + 12;
    }

    return 24;
  }

  @override
  ConsumerState<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<NavigationShell> {

  static const List<_NavItem> _navItems = [
    _NavItem(
      icon: LucideIcons.home,
      activeIcon: LucideIcons.home,
      label: 'Главная',
      route: '/home',
    ),
    _NavItem(
      icon: LucideIcons.map,
      activeIcon: LucideIcons.map,
      label: 'Карта',
      route: '/map',
    ),
    _NavItem(
      icon: LucideIcons.star,
      // Активная вкладка — ЗАЛИТАЯ звезда: контурная читалась
      // как «не выбрано», выбор виден только по пилюле (A11).
      activeIcon: Icons.star_rounded,
      label: 'Избранное',
      route: '/favorites',
    ),
    _NavItem(
      icon: LucideIcons.search,
      activeIcon: LucideIcons.search,
      label: 'Поиск',
      route: '/search',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 600;

    // Клавиатура не сжимает тело шелла (P0-3, 7-й проход):
    // resizeToAvoidBottomInset: false держит карту (platform view)
    // полного размера — она не перерисовывается при вводе в поиске,
    // а капсула не всплывает над клавиатурой: она прячется ниже
    // кромки, пока viewInsets.bottom > 0 (шторка поиска сама
    // добавляет viewInsets к паддингу списка).
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [

          // Контент на всю высоту — под парящей капсулой.
          // Пересборка при смене видимости мини-плеера создаёт
          // НОВЫЙ ShellInsets: страницы-читатели отступа
          // перестраиваются с выросшим/уменьшенным значением
          // (P0-2, 5-й проход).
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge(
                [miniPlayerVisible, modalSheetOpenCount],
              ),
              builder: (context, _) => ShellInsets(
                bottomInset: NavigationShell._computeBottomInset(context),
                child: Row(
                  children: [
                    if (isDesktop) _buildNavigationRail(),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ),

          // Парящая капсула поверх контента. PointerInterceptor:
          // на web она лежит над платформенным канвасом карты
          // и должна перехватывать тапы себе, а не в холст.
          // При открытой клавиатуре капсула уезжает за нижнюю
          // кромку (Stack клипует) — не висит над клавиатурой
          // поверх результатов поиска (P0-3, 7-й проход).
          if (!isDesktop)
            Positioned(
              left: 14,
              right: 14,
              bottom: NavigationShell.capsuleBottomGap +
                  MediaQuery.paddingOf(context).bottom,
              child: AnimatedSlide(
                offset: keyboardOpen
                    ? const Offset(0, 3)
                    : Offset.zero,
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                child: PointerInterceptor(
                  child: _buildCapsule(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationRail() {
    final width = MediaQuery.sizeOf(context).width;

    // Расширенный рельс — от 800 px: подписи справа от иконок.
    final isWide = width >= 800;

    return NavigationRail(
      selectedIndex: widget.selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      // 600–800 (планшет ZENO 1 — 601 dp): подписи ПОД иконками —
      // четыре иконки без текста («Карта», «Избранное», «Поиск»)
      // были неочевидны (A5, 8-й проход). Extended требует
      // labelType none, поэтому выбор переключается вместе.
      labelType: isWide
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      extended: isWide,
      // Фон рельса — ролевой (B5).
      backgroundColor: AppPalette.of(context).surfaceRaised,
      destinations: _navItems.map((item) {
        // Tooltip на обеих иконках: у extended подпись и так видна,
        // у all-режима подсказка всплывает при наведении.
        return NavigationRailDestination(
          icon: Tooltip(
            message: item.label,
            child: Icon(item.icon, size: 24),
          ),
          selectedIcon: Tooltip(
            message: item.label,
            child: Icon(item.activeIcon, size: 24),
          ),
          label: Text(item.label),
        );
      }).toList(),
    );
  }

  /// Капсула: NavigationBar в скруглённом контейнере с мягкой
  /// тенью, парит над контентом.
  Widget _buildCapsule() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        // Тень — цветом темы (D1): чёрная тень капсулы на тёмном
        // фоне ночи была кляксой.
        boxShadow:
            AppShadows.floating(AppPalette.of(context).onSurface),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        // NavigationBar внутри себя оборачивает контент в
        // SafeArea и добавляет к своей высоте НЕПОТРЕБЛЁННЫЕ
        // системные паддинги (статус-бар + жест-бар) — на
        // устройствах с крупными вставками капсула раздувалась с
        // 64 до ~185 dp (четверть экрана). Позиционирование
        // капсулы уже учитывает inset в Positioned(bottom:), —
        // внутренние SafeArea-надбавки убираем (4-й проход).
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: NavigationBar(
            height: NavigationShell.capsuleHeight,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: _navItems.map((item) {
              return NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: item.label,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    // Подсветка вкладки следует за роутом (router.dart пересчитывает
    // selectedIndex по location), поэтому локальный стейт не нужен:
    // раньше он задавался только в initState, и подсветка не
    // обновлялась при context.go('/home') с карты.
    if (index == widget.selectedIndex) {
      // Повторный тап по уже активной вкладке «Поиск» заново
      // открывает шторку поиска: адрес /map?search=1 при закрытой
      // шторке (возврат из деталей POI) не пересобирает страницу,
      // и обычный переход ничего бы не сделал (P0-1, 6-й проход).
      if (_navItems[index].route == '/search') {
        searchSheetRequest.value++;
      }

      return;
    }

    context.go(_navItems[index].route);
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
}
