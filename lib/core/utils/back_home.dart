import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Безопасный возврат «назад».
///
/// На глубоких ссылках (`/poi/:id`, `/trail/:id`, открыты
/// по share-ссылке или запуску) стека маршрутов нет — `pop()`
/// молчит и ничего не делает. В этом случае уводим на главную.
void goBackOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}
