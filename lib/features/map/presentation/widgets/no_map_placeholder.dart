import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/widgets/error_state.dart';

/// Плейсхолдер для локации без офлайн-карты — единый стиль
/// пустых состояний (B8, 9-й проход).
class NoMapPlaceholder extends StatelessWidget {

  const NoMapPlaceholder({super.key});


  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SingleChildScrollView(
        child: StatePlaceholder(
          icon: LucideIcons.map,
          title: 'Офлайн-карта ещё не загружена',
          description:
              'Локация работает и без карты: точки, маршруты '
              'и аудио доступны',
        ),
      ),
    );
  }
}
