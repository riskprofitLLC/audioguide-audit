// Безопасный возврат «назад» с глубоких ссылок (back_home.dart).
//
// Share-ссылка `#/poi/:id` (или запуск по ссылке) открывает
// страницу деталей БЕЗ стека маршрутов: `pop()` там молчит, и
// пользователь застревал на странице. goBackOrHome уводит на
// главную — поведение покрыто тестом на настоящем GoRouter.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:island_guide/core/utils/back_home.dart';

void main() {
  GoRouter buildRouter({required String initialLocation}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('ГЛАВНАЯ')),
          ),
        ),
        GoRoute(
          path: '/poi/:id',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => goBackOrHome(context),
                child: const Text('НАЗАД'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  testWidgets('глубокая ссылка без стека: назад уводит на главную',
      (tester) async {
    final router = buildRouter(initialLocation: '/poi/poi-01');

    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.pumpAndSettle();

    expect(find.text('НАЗАД'), findsOneWidget);

    await tester.tap(find.text('НАЗАД'));

    await tester.pumpAndSettle();

    expect(find.text('ГЛАВНАЯ'), findsOneWidget,
        reason: 'без стека маршрутов pop() молчал — уводим на главную');
  });

  testWidgets('есть стек: назад возвращает на предыдущий экран, а не '
      'на главную', (tester) async {
    final router = buildRouter(initialLocation: '/home');

    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.pumpAndSettle();

    unawaited(router.push('/poi/poi-01'));

    await tester.pumpAndSettle();

    await tester.tap(find.text('НАЗАД'));

    await tester.pumpAndSettle();

    expect(find.text('ГЛАВНАЯ'), findsOneWidget);
  });
}
