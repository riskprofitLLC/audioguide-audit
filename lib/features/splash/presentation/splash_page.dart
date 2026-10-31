import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/chart_frame.dart';
import '../../content/providers/content_providers.dart';


class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}


class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {

  /// Длительность появления одного элемента.
  static const int _fadeMs = 500;

  /// Шаг каскада между соседними элементами.
  static const int _stepMs = 70;

  /// Сколько элементов участвует в каскаде.
  static const int _revealCount = 5;

  /// Подъём элемента в начале появления (px).
  static const double _riseOffset = 14;

  late final AnimationController _entrance;

  late final List<Animation<double>> _reveals;


  @override
  void initState() {
    super.initState();

    // Прогрев контента стартовой локации во время заставки
    // (900 мс, P1-7, 7-й проход): манифесты, POI и маршруты
    // грузятся ПАРАЛЛЕЛЬНО сплэшу — главная открывается без
    // скелетона, сидинг SQLite не откладывается на первый кадр.
    // Ошибки не важны: главная покажет свой баннер/скелетон.
    Future.microtask(() {
      if (!mounted) return;

      final locationId = ref.read(currentIslandIdProvider);

      unawaited(
        ref.read(poisFamily(locationId).future).then(
          (_) => null,
          onError: (_) => null,
        ),
      );

      unawaited(
        ref.read(trailsFamily(locationId).future).then(
          (_) => null,
          onError: (_) => null,
        ),
      );

      unawaited(
        ref.read(islandContentProvider.future).then(
          (_) => null,
          onError: (_) => null,
        ),
      );

      unawaited(
        ref.read(regionsProvider.future).then(
          (_) => null,
          onError: (_) => null,
        ),
      );

      unawaited(
        ref.read(islandsProvider.future).then(
          (_) => null,
          onError: (_) => null,
        ),
      );
    });

    final totalMs =
        _fadeMs + (_revealCount - 1) * _stepMs;

    _entrance = AnimationController(
      duration: Duration(milliseconds: totalMs),
      vsync: this,
    );

    // Каскад появления: интервалы ОДНОГО контроллера — никаких
    // Timer/Future.delayed, под FakeAsync висящий таймер роняет
    // widget-тесты.
    _reveals = List<Animation<double>>.generate(
      _revealCount,
      (i) {

        final delay = i * _stepMs;

        return CurvedAnimation(
          parent: _entrance,
          curve: Interval(
            delay / totalMs,
            (delay + _fadeMs) / totalMs,
            curve: AppMotion.curve,
          ),
        );
      },
    );

    _entrance.forward();

    _openHome();
  }


  @override
  void dispose() {

    _entrance.dispose();

    super.dispose();
  }


  Future<void> _openHome() async {

    // Короткая заставка: контент приложению на этом экране не нужен,
    // реальной «готовности» ждать нечего — бренд-экран не должен
    // держать пользователя лишнюю секунду.
    await Future.delayed(
      const Duration(milliseconds: 900),
    );

    if (!mounted) return;

    context.go('/home');
  }


  /// Элемент каскада: fade + подъём. При Reduce Motion —
  /// статичный показ (B12).
  Widget _reveal(
    int index,
    Widget child,
  ) {

    final animation = _reveals[index];

    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return child;
    }

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {

        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(
              0,
              _riseOffset * (1 - animation.value),
            ),
            child: child,
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    return Scaffold(
      // Фон — из темы (B5, 11-й проход): ночное превью не
      // рвётся бумажной подложкой.
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // Знак: компас на листе морской карты, по кромке —
              // градусные тики.
              _reveal(
                0,
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius:
                        BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: palette.sand.withValues(alpha: 0.9),
                      width: 1,
                    ),
                    boxShadow: AppShadows.card(palette.onSurface),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppRadius.card),
                    child: const Stack(
                      alignment: Alignment.center,
                      children: [

                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: ChartTicksPainter(),
                            ),
                          ),
                        ),

                        Icon(
                          LucideIcons.compass,
                          size: 44,
                          color: AppColors.depth,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _reveal(
                1,
                Text(
                  'ISLAND GUIDE',
                  style: AppText.display.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Сигнальная линия — цвет маячного огня.
              _reveal(
                2,
                Container(
                  width: 40,
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.signal,
                    borderRadius: BorderRadius.circular(AppRadius.hairline),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _reveal(
                3,
                Text(
                  'Офлайн-гид по побережью',
                  style: AppText.label.copyWith(
                    letterSpacing: 1.2,
                    color: palette.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),

              const SizedBox(height: 36),

              _reveal(
                4,
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.depth.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
