import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'glass_icon_button.dart';

/// Отдельная плавающая кнопка «Домой» — возврат на главную.
///
/// Играющий трек НЕ останавливает (A3, 9-й проход): аудиогид —
/// фон путешествия, а не атрибут страницы; остановка — только
/// явным действием (мини-плеер, шторка «Сейчас играет»).
class HomeButton extends ConsumerWidget {

  const HomeButton({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {

    return GlassIconButton(
      tooltip: 'На главную',
      icon: LucideIcons.house,
      isPrimary: true,
      onTap: () => context.go('/home'),
    );
  }
}
