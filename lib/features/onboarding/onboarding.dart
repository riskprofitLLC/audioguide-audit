import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/widgets/chart_frame.dart';
import '../gps/providers/location_providers.dart';
import '../settings/services/app_settings.dart';

/// Показывать ли онбординг первого запуска (B8, 8-й проход).
///
/// Значение вычисляется ОДИН раз при старте приложения (в
/// `main.dart` по флагу `onboarding_done`) и передаётся
/// оверрайдом провайдера: тесты строят свои ProviderScope без
/// оверрайда — дефолт false, диалог их не ломает.
final showOnboardingProvider = Provider<bool>((ref) {
  return false;
});

/// Открывает онбординг первого запуска (2 экрана, один раз).
///
/// Крестик — можно пропустить; «Разрешить» на втором экране
/// запрашивает геолокацию (системный диалог — только по явному
/// тапу, P1-1). Флаг onboarding_done пишется при ЛЮБОМ исходе
/// (Б2, замечание Sonnet): раньше закрытие тапом по барьеру
/// или системной кнопкой «Назад» флаг не писало — и онбординг
/// показывался при каждом запуске.
Future<void> showFirstLaunchOnboarding(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => const _OnboardingDialog(),
  ).whenComplete(() {
    // Дискриптор завершения диалога: и закрытие по барьеру,
    // и системный «Назад», и _finish — один и тот же финал.
    AppSettings().write('onboarding_done', '1');
  });
}

class _OnboardingDialog extends ConsumerStatefulWidget {
  const _OnboardingDialog();

  @override
  ConsumerState<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends ConsumerState<_OnboardingDialog> {
  static const _stepCount = 2;

  int _step = 0;

  bool _permissionRequested = false;

  void _finish() {
    Navigator.of(context).pop();

    // ЛЮБОЙ исход — онбординг не показываем повторно.
    AppSettings().write('onboarding_done', '1');
  }

  Future<void> _requestPermission() async {
    // Сервис — из провайдера, а не прямое создание (A9): единый
    // синглтон с остальным приложением, тестируемо через оверрайд.
    await ref.read(locationServiceProvider).ensurePermission();

    if (mounted) {
      setState(() {
        _permissionRequested = true;
      });
    }

    // Небольшая пауза, чтобы статус прочитался — и к финалу.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    if (mounted) {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final isWide = MediaQuery.sizeOf(context).width >= 600;

    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    return Dialog(
      // Фон — из темы (B5, 11-й проход).
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 20,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Контент шага — с анимацией перехода (B3, 10-й
                  // проход): фейд + лёгкий сдвиг; Reduce Motion
                  // глушит анимацию. Flexible + скролл: на узких
                  // экранах при textScale 1.6 длинный текст шага
                  // не рвёт диалог (B6), индикатор и кнопки
                  // остаются прижатыми внизу.
                  Flexible(
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration:
                            reduceMotion ? Duration.zero : AppMotion.normal,
                        switchInCurve: AppMotion.curve,
                        switchOutCurve: AppMotion.curve,
                        transitionBuilder: (child, animation) {
                          final curved = CurvedAnimation(
                            parent: animation,
                            curve: AppMotion.curve,
                          );

                          return FadeTransition(
                            opacity: curved,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(curved),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Крупный глиф шага в «бумажном» круге с
                              // градусными тиками — как знак сплэша.
                              Center(
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: palette.surfaceRaised,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: palette.sand
                                          .withValues(alpha: 0.9),
                                      width: 1,
                                    ),
                                    boxShadow: AppShadows.card(palette.onSurface),
                                  ),
                                  child: ClipOval(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        const Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: ChartTicksPainter(),
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          _step == 0
                                              ? LucideIcons.audioLines
                                              : LucideIcons.compass,
                                          size: 38,
                                          color: palette.info,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpace.m),

                              Text(
                                _step == 0
                                    ? 'Слушайте рассказы по пути'
                                    : 'Геолокация нужна только на карте',
                                textAlign: TextAlign.center,
                                style: AppText.h2
                                    .copyWith(color: palette.onSurface),
                              ),
                              const SizedBox(height: AppSpace.s),
                              Text(
                                _step == 0
                                    ? 'Аудиогид сам заиграет, когда вы подойдёте '
                                        'к достопримечательности. Наденьте '
                                        'наушники — и руки останутся свободны. '
                                        'Всё работает офлайн: карта и аудио уже '
                                        'на устройстве.'
                                    : 'Мы не следим за вами: GPS работает, только '
                                        'пока открыта карта, и помогает показывать, '
                                        'где вы и что рядом. Разрешение можно выдать '
                                        'сейчас — или позже, прямо с карты.',
                                textAlign: TextAlign.center,
                                style: AppText.body.copyWith(
                                  color: palette.onSurface.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpace.l),

                  // Индикатор шагов: две точки, активная — depth.
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _stepCount; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          AnimatedContainer(
                            key: ValueKey('onboarding-dot-$i'),
                            duration: reduceMotion
                                ? Duration.zero
                                : AppMotion.fast,
                            curve: AppMotion.curve,
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _step
                                  ? palette.info
                                  : palette.sand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpace.l),

                  // Кнопки одного роста (48): «Далее»/«Разрешить» —
                  // filled, «Не сейчас» — outlined (B3).
                  if (_step == 0)
                    FilledButton.icon(
                      onPressed: () => setState(() => _step = 1),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(LucideIcons.arrowRight, size: 18),
                      label: const Text('Далее'),
                    ),
                  if (_step == 1) ...[
                    FilledButton.icon(
                      onPressed: _requestPermission,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(LucideIcons.compass, size: 18),
                      label: Text(
                        _permissionRequested ? 'Готово' : 'Разрешить',
                      ),
                    ),
                    const SizedBox(height: AppSpace.s),
                    OutlinedButton(
                      onPressed: _finish,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Не сейчас'),
                    ),
                  ],
                ],
              ),
            ),

            // Крестик-пропуск (тап-цель 44).
            Positioned(
              top: 8,
              right: 8,
              child: Semantics(
                button: true,
                label: 'Пропустить',
                child: IconButton(
                  tooltip: 'Пропустить',
                  onPressed: _finish,
                  icon: const Icon(LucideIcons.x, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
