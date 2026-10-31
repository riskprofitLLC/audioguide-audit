import 'package:flutter/material.dart';

import 'features/onboarding/onboarding.dart';
import 'features/settings/services/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/app.dart';
import 'core/services/app_initializer.dart';
import 'features/audio/services/background_audio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Приложение светлое и работает edge-to-edge (targetSdk 36): статус-бар
  // прозрачный, поверх белого окна — тёмные значки сверху и тёмные кнопки
  // снизу. Без явной установки AOSP-образ рисовал значки светлыми, и на
  // белом фоне они не читались.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      // Бумага «Ликийского дневника» — синхронизирована с
      // launch_background.xml и styles.xml.
      systemNavigationBarColor: Color(0xFFFAF8F2),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Отражать в адресной строке web маршруты, открытые через
  // context.push()/pop() (poi, trail). С go_router 8.0.0 это
  // выключено по умолчанию, и deep-link на такие страницы не работает.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // 28-й проход: фоновое аудио (медиа-уведомление, lock screen) —
  // гид должен играть при заблокированном экране. На web — no-op.
  await initBackgroundAudio();

  await AppInitializer.initialize();

  runApp(
    ProviderScope(
      overrides: [
        // Онбординг первого запуска (B8, 8-й проход): вычисляется
        // один раз при старте; тесты без оверрайда его не видят.
        //
        // A8 (10-й проход): при сбое инициализации флаг не читается —
        // база настроек может быть недоступна, и чтение из неё
        // кидало бы новую ошибку; онбординг показывать не нужно —
        // приложение и так покажет баннер ошибки инициализации.
        showOnboardingProvider.overrideWithValue(
          AppInitializer.lastError == null &&
              AppSettings().read('onboarding_done') != '1',
        ),
      ],
      child: const IslandGuideApp(),
    ),
  );
}
