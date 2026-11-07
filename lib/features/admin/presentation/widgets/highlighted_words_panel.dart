/// Панель выделенных слов админки: слова с красным выделением
/// появляются здесь СРАЗУ после нажатия «Красный» (список строится
/// из диапазонов rich-модели, не из маркеров markdown) и при
/// сохранении уезжают в поле `highlightedWords` poi.json — панель,
/// файл и коммит всегда показывают один и тот же список.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';

class HighlightedWordsPanel extends StatelessWidget {

  const HighlightedWordsPanel({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Container(
      key: const Key('highlighted-words-panel'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: palette.outline),
      ),
      child: words.isEmpty ? _buildHint(palette) : _buildList(palette),
    );
  }

  Widget _buildHint(AppPalette palette) {
    return Row(
      children: [
        Icon(LucideIcons.highlighter, size: 16, color: palette.onSurfaceMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Выдели слово и нажми «Красный» — оно появится здесь '
            'и попадёт в коммит',
            style: AppText.caption.copyWith(color: palette.onSurfaceMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildList(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ВЫДЕЛЕННЫЕ СЛОВА · ${words.length}',
          style: AppText.eyebrowMuted.copyWith(color: palette.onSurfaceMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < words.length; i++)
              Container(
                key: ValueKey('highlighted-word-$i'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.sandLight,
                  borderRadius: BorderRadius.circular(AppRadius.capsule),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.redText,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      words[i],
                      style: AppText.caption.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
