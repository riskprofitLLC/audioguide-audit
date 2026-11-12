/// Экран входа в админ-панель: одно поле пароля, без логина.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../providers/admin_providers.dart';

class AdminLoginPage extends ConsumerStatefulWidget {

  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {

  final _controller = TextEditingController();

  String? _error;

  @override
  void dispose() {

    _controller.dispose();

    super.dispose();
  }

  void _submit() {

    if (_controller.text.trim() == kAdminPassword) {
      ref.read(adminAuthedProvider.notifier).signIn();
      context.go('/admin');
      return;
    }

    setState(() {
      _error = 'Неверный пароль';
    });
  }

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                const Text(
                  'Администрирование',
                  style: AppText.h2,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                Text(
                  'Введите пароль администратора',
                  style: AppText.body.copyWith(
                    color: palette.onSurfaceMuted,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                TextField(
                  controller: _controller,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    errorText: _error,
                  ),
                ),

                const SizedBox(height: 16),

                FilledButton(
                  onPressed: _submit,
                  child: const Text('Войти'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
