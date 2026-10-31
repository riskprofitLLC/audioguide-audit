import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../content/providers/content_providers.dart';
import '../../../settings/providers/listened_providers.dart';

/// Тонкая полоса прогресса локации (B2.2, 8-й проход):
/// «Прослушано N из M» и заполнение полосы.
///
/// Считаются точки с аудио: без него «прослушать» нельзя.
/// Никакой геймификации — только тихий прогресс.
class LocationProgressBar extends ConsumerWidget {
  const LocationProgressBar({super.key, required this.islandId});

  final String islandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    // A8 (10-й проход): точки берутся из СЕМЕЙСТВА по islandId —
    // раньше виджет читал poisProvider (текущая локация
    // приложения), а ключи считал по переданному islandId:
    // при рассинхроне прогресс показывал чужие числа.
    final pois = ref.watch(poisFamily(islandId)).value;

    if (pois == null || pois.isEmpty) {
      return const SizedBox.shrink();
    }

    final withAudio = pois.where((p) => p.audioPath != null).toList();

    if (withAudio.isEmpty) {
      return const SizedBox.shrink();
    }

    final listened = ref.watch(listenedSetProvider);

    var listenedCount = 0;

    for (final poi in withAudio) {
      if (listened.contains('$islandId/${poi.id}')) {
        listenedCount++;
      }
    }

    if (listenedCount == 0) {
      // Ничего не listened — полосы нет: тишина вместо нулей.
      return const SizedBox.shrink();
    }

    final fraction = listenedCount / withAudio.length;

    return Padding(
      key: const ValueKey('location-progress'),
      // Верхний отступ AppSpace.m: блок стоит после «Продолжить»
      // (home_page.dart) — зазор живёт здесь, а не у соседа.
      padding: const EdgeInsets.only(top: AppSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прослушано $listenedCount из ${withAudio.length}',
            style: AppText.label.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: AppPalette.of(context).sand,
                color: AppColors.depth,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
