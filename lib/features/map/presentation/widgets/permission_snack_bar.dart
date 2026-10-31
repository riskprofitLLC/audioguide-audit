import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../gps/services/location_gateway.dart';

/// Подсказка «как включить геолокацию» для статуса отказа
/// (вынесена из MapWidget в тестируемый модуль, 13-й проход).
///
/// На web кнопка «Настройки» через geolocator — тихое ничто
/// (у geolocator_web НЕТ openAppSettings): вместо неё — шторка
/// с шагами браузера. На native — прежние SnackBar'ы с прямым
/// переходом в системные настройки приложения.
void showLocationPermissionHint(
  BuildContext context,
  LocationPermissionStatus status, {
  VoidCallback? onRetry,
}) {
  if (status == LocationPermissionStatus.granted) {
    return;
  }

  if (kIsWeb) {
    // Браузер: разрешение меняется в настройках сайта —
    // системного диалога «Настройки» тут не существует.
    // prompt (denied) — запрос можно показать снова кнопкой.
    showWebLocationHelpSheet(
      context,
      serviceOff: status == LocationPermissionStatus.serviceOff,
      promptPending: status == LocationPermissionStatus.denied,
      onRetry: onRetry,
    );
    return;
  }

  switch (status) {
    // Зависший канал — честный текст, а не «нет доступа» (A11).
    case LocationPermissionStatus.unknown:
      showAppSnackBar(
        context,
        'Не удалось проверить разрешение на геолокацию',
        // Б14, замечание Sonnet: кнопка без обработчика — обман;
        // «Повторить» показываем, только если есть onRetry.
        actionLabel: onRetry != null ? 'Повторить' : null,
        onAction: onRetry,
      );

    case LocationPermissionStatus.deniedForever:
      showAppSnackBar(
        context,
        'Приложению запрещён доступ к местоположению (это отдельное '
        'разрешение — GPS телефона тут ни при чём). Разрешите его '
        'в настройках — и вернитесь в приложение',
        actionLabel: 'Настройки',
        onAction: () => Geolocator.openAppSettings(),
      );

    case LocationPermissionStatus.serviceOff:
      showAppSnackBar(
        context,
        'Служба геолокации на устройстве отключена',
        actionLabel: 'Настройки',
        onAction: () => Geolocator.openLocationSettings(),
      );

    case LocationPermissionStatus.denied:
      // A10 (17-й проход): раньше «тупик» — сообщение без единого
      // действия; повторный запрос на native всегда возможен.
      showAppSnackBar(
        context,
        'Нет доступа к геолокации',
        // Б14: без обработчика кнопку не рисуем (Б14, Sonnet).
        actionLabel: onRetry != null ? 'Повторить' : null,
        onAction: onRetry,
      );

    case LocationPermissionStatus.granted:
      break;
  }
}

/// Шторка «Как включить геолокацию» (web): шаги браузера —
/// geolocator_web не умеет ни openAppSettings, ни открытие
/// настроек сайта, ведём пользователя словами.
Future<void> showWebLocationHelpSheet(
  BuildContext context, {
  bool serviceOff = false,
  bool promptPending = false,
  VoidCallback? onRetry,
}) {
  return showAppBottomSheet(
    context,
    title: 'Как включить геолокацию',
    maxHeightFactor: 0.7,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            promptPending
                ? 'Браузер ещё не дал разрешение — запрос мог '
                    'просто проскочить мимо. Нажмите «Спросить '
                    'разрешение» и подтвердите запрос браузера '
                    '(появится снизу экрана):'
                : 'GPS на телефоне может быть включён — это '
                    'другое. Браузер запретил доступ к '
                    'местоположению именно этому сайту и повторно '
                    'спрашивать уже не может: разрешение меняется '
                    'только вручную:',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.5,
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          ),

          // Запрос можно показать снова — кнопка повтора.
          if (promptPending && onRetry != null) ...[
            const SizedBox(height: AppSpace.xs),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();

                onRetry();
              },
              icon: const Icon(LucideIcons.locateFixed, size: 16),
              label: const Text('Спросить разрешение'),
            ),
            const SizedBox(height: AppSpace.s),
          ],

          // Разрешение меняли в настройках браузера — даём
          // перепроверить состояние без перезагрузки страницы
          // (B3, 17-й проход).
          if (!promptPending && onRetry != null) ...[
            const SizedBox(height: AppSpace.xs),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();

                onRetry();
              },
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Проверить снова'),
            ),
            const SizedBox(height: AppSpace.s),
          ],
          const SizedBox(height: AppSpace.s),
          if (!promptPending)
            const _HelpStep(
              icon: LucideIcons.lock,
              text: 'Chrome на Android: значок замка слева от адреса → '
                  '«Разрешения» → «Геоположение» → «Разрешить» '
                  '(после двух отказов Chrome сам больше не спрашивает)',
            ),
          const _HelpStep(
            icon: LucideIcons.compass,
            text: 'Safari на iPhone: кнопка «aA» в адресной строке → '
                '«Настройки веб-сайта» → «Геоположение» → «Разрешить»',
          ),
          const _HelpStep(
            icon: LucideIcons.refreshCw,
            text: 'После изменения разрешите браузеру спросить снова — '
                'страницу придётся обновить',
          ),
          if (serviceOff) ...[
            const SizedBox(height: AppSpace.s),
            Text(
              'Если служба геолокации выключена на самом телефоне — '
              'включите её в шторке быстрых настроек или в настройках '
              'системы.',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: AppPalette.of(context).onSurfaceMuted,
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// Шторка «Почему молчит автогид» (B5, 18-й проход): грубая
/// точность GPS затянулась — автогид с ней не работает (гейт
/// точности вотчера), объясняем порог и что делать.
Future<void> showAutoguideAccuracyHelpSheet(
  BuildContext context, {
  double? accuracyMeters,
}) {
  return showAppBottomSheet(
    context,
    title: 'Почему молчит автогид',
    maxHeightFactor: 0.55,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            accuracyMeters == null
                ? 'Автогид включает рассказ, когда точность GPS '
                    'лучше 100 метров — так он уверен, что вы '
                    'действительно у точки. Сейчас сигнал грубый.'
                : 'Автогид включает рассказ, когда точность GPS '
                    'лучше 100 метров — так он уверен, что вы '
                    'действительно у точки. Сейчас она '
                    '±${accuracyMeters.round()} м.',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.5,
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          ),
          const SizedBox(height: AppSpace.s),
          const _HelpStep(
            icon: LucideIcons.trees,
            text: 'Выйдите под открытое небо — в помещении и у '
                'высоких скал сигнал путается по отражениям',
          ),
          const _HelpStep(
            icon: LucideIcons.compass,
            text: 'Пара минут на месте помогает телефону '
                'поймать спутники — не бегайте по кругу',
          ),
          const _HelpStep(
            icon: LucideIcons.mapPin,
            text: 'На карте круг вокруг точки «Вы здесь» — это зона '
                'неуверенности: чем он меньше, тем точнее сигнал. '
                'Точка тускнеет, когда фикс устарел',
          ),
          const SizedBox(height: AppSpace.s),
          Text(
            'Слушать рассказы вручную можно всегда: тапните по точке '
            'на карте или откройте её с главной страницы.',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.5,
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          ),
        ],
      );
    },
  );
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({required this.icon, required this.text});

  final IconData icon;

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.depth),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color:
                    AppPalette.of(context).onSurface
                        .withValues(alpha: 0.87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
