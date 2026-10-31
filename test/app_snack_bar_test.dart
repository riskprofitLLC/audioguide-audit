// showAppSnackBar (P0-2, 6-й проход): плавающая плашка и её
// кнопка действия обязаны стоять ВЫШЕ парящей капсулы навигации.
// Обычный floating SnackBar встаёт у нижней кромки экрана, и
// капсула перекрывает кнопку «Отменить».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/navigation/navigation_shell.dart';
import 'package:island_guide/app/overlay_tracker.dart';
import 'package:island_guide/core/widgets.dart';

void main() {
  testWidgets('плашка и кнопка «Отменить» — над капсулой (400×800)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    miniPlayerVisible.value = false;

    addTearDown(() => miniPlayerVisible.value = false);

    // Сообщение читается из переменной в момент тапа — можно
    // показать вторую плашку без пересборки дерева.
    var message = 'Удалено из избранного';

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NavigationShell(
            selectedIndex: 0,
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: () => showAppSnackBar(
                          context,
                          message,
                          actionLabel: 'Отменить',
                          onAction: () {},
                        ),
                        child: const Text('Показать'),
                      ),
                      // Явное скрытие плашки: авто-таймер зависит от
                      // анимаций — прячем сами, без хрупких пауз.
                      OutlinedButton(
                        onPressed: () =>
                            ScaffoldMessenger.of(context)
                                .hideCurrentSnackBar(),
                        child: const Text('Скрыть'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Показать'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);

    // Прогоняем анимацию появления: таймер длительности
    // стартует только ПОСЛЕ неё.
    await tester.pump(const Duration(milliseconds: 400));

    // Рект SnackBar включает margin (визуальная плашка внутри),
    // поэтому меряем по контенту: текст сообщения и кнопка.
    final messageRect = tester.getRect(find.text(message));

    final capsuleRect = tester.getRect(find.byType(NavigationBar));

    expect(
      messageRect.bottom,
      lessThan(capsuleRect.top),
      reason: 'контент SnackBar обязан стоять выше капсулы навигации, '
          'иначе капсула парит поверх плашки и перекрывает кнопку действия',
    );

    final actionRect = tester.getRect(find.text('Отменить'));

    expect(
      actionRect.bottom,
      lessThan(capsuleRect.top),
      reason: 'кнопка «Отменить» должна быть над капсулой',
    );

    // Прячем первую плашку — иначе вторая встанет в очередь
    // мессенджера и не появится.
    await tester.tap(find.text('Скрыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SnackBar), findsNothing);

    // Пока мини-плеер виден, он занимает ту же зону над капсулой —
    // плашка поднимается выше него.
    miniPlayerVisible.value = true;

    message = 'Поднятая плашка';

    await tester.pump();

    await tester.tap(find.text('Показать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final liftedRect = tester.getRect(find.text('Поднятая плашка'));

    expect(
      liftedRect.bottom,
      lessThan(messageRect.top),
      reason: 'при видимом мини-плеере плашка поднимается выше '
          'обычного положения',
    );
  });
}
