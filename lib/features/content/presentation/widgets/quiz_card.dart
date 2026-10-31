import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../services/markdown_blocks.dart';

/// Карточка «Проверьте себя» (П6, 12-й проход): один вопрос по
/// точке, варианты ответа и пояснение после выбора. Полностью
/// офлайн — данные в тексте статьи (`:::quiz … :::`).
///
/// D5 (замечание Sonnet): варианты — полноценные семантические
/// кнопки с selected, результат анонсируется liveRegion, выбор
/// анимируется [AppMotion.fast], после ответа — «Ответить
/// снова».
class QuizCard extends StatefulWidget {
  const QuizCard({super.key, required this.quiz});

  final MdQuiz quiz;

  @override
  State<QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<QuizCard> {
  /// Индекс выбранного варианта; null — ещё не отвечено.
  int? _selected;

  void _reset() {
    setState(() {
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final theme = Theme.of(context);

    final quiz = widget.quiz;

    final answered = _selected != null;

    final chosen = _selected;

    final correct = chosen != null && quiz.options[chosen].correct;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.circleHelp,
                size: 16,
                color: palette.info,
              ),
              const SizedBox(width: 8),
              Text(
                'Проверьте себя',
                style: AppText.chip.copyWith(
                  color: palette.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            quiz.question,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: AppSpace.s),
          for (var i = 0; i < quiz.options.length; i++)
            _optionTile(
              context,
              index: i,
              answered: answered,
            ),
          if (answered) ...[
            const SizedBox(height: AppSpace.xs),

            // Итог и пояснение — живой регион: скринридер
            // анонсирует результат выбора без повторного фокуса.
            Semantics(
              liveRegion: true,
              child: Text(
                correct ? 'Верно!' : 'Не совсем',
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w800,
                  color: correct ? palette.success : palette.accent,
                ),
              ),
            ),

            if (quiz.note != null) ...[
              const SizedBox(height: 4),
              Text(
                quiz.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.45,
                  color: palette.onSurfaceMuted,
                ),
              ),
            ],

            const SizedBox(height: AppSpace.s),

            // D5: ответ не «прилипает» навсегда — можно сыграть
            // заново (варианты при этом снова становятся кнопками).
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _reset,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(44, 44),
                ),
                icon: const Icon(LucideIcons.rotateCw, size: 15),
                label: const Text('Ответить снова'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Вариант ответа: до выбора — кнопка; после — подсветка
  /// верного (успех) и неверного выбранного (сигнал), тапы
  /// заблокированы.
  Widget _optionTile(
    BuildContext context, {
    required int index,
    required bool answered,
  }) {
    final palette = AppPalette.of(context);

    final theme = Theme.of(context);

    final option = widget.quiz.options[index];

    final isChosen = _selected == index;

    // После ответа: верный — зелёная рамка, выбранный неверный —
    // сигнальная; остальные — спокойные.
    final Color borderColor;

    final Color? fillColor;

    if (answered && option.correct) {
      borderColor = theme.colorScheme.primary;

      fillColor = null;
    } else if (answered && isChosen && !option.correct) {
      borderColor = theme.colorScheme.error;

      fillColor = theme.colorScheme.errorContainer;
    } else {
      borderColor = palette.sand;

      fillColor = null;
    }

    final borderWidth = answered && (option.correct || isChosen) ? 2 : 1;

    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: true,
        enabled: !answered,
        // Выбранный вариант помечается «selected» — скринридер
        // прочитает текущий выбор до ответа. Аннотации мержатся
        // с InkWell (container не ставим — без дублей узлов).
        selected: isChosen,
        label: option.text,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.field),
          onTap: answered ? null : () => setState(() => _selected = index),
          child: AnimatedContainer(
            // D5: подсветка приходит мягкой анимацией; Reduce
            // Motion — мгновенно.
            duration:
                answered && !reduceMotion ? AppMotion.fast : Duration.zero,
            curve: AppMotion.curve,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(AppRadius.field),
              border: Border.all(
                color: borderColor,
                width: borderWidth.toDouble(),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  answered
                      ? (option.correct
                          ? LucideIcons.circleCheck
                          : (isChosen
                              ? LucideIcons.circleX
                              : LucideIcons.circle))
                      : LucideIcons.circle,
                  size: 18,
                  color: answered
                      ? (option.correct
                          ? theme.colorScheme.primary
                          : (isChosen
                              ? theme.colorScheme.error
                              : palette.onSurfaceMuted))
                      : palette.onSurfaceMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.onSurface.withValues(alpha: 0.87),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
