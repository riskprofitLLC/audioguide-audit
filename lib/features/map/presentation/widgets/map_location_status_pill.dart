import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/floating_pill.dart';

/// Вариант плашки статуса геолокации (B3, 17-й проход;
/// lowAccuracy/signalLost — 18-й).
enum MapLocationStatus {
  /// Всё хорошо — плашки нет.
  none,

  /// Разрешение не выдано — можно запросить (системный диалог).
  noPermission,

  /// Отклонено навсегда — выход только через настройки приложения.
  deniedForever,

  /// Служба геолокации выключена на устройстве.
  serviceOff,

  /// Выдана только ПРИБЛИЗИТЕЛЬНАЯ геолокация (A13): точность
  /// 1–3 км, автогид молчит — предлагаем включить точную.
  reducedAccuracy,

  /// Трекинг активен, но GPS-фикса нет дольше 15 с — сигнал
  /// ищется (плашка снимается первым же фиксом).
  searchingSignal,

  /// Сигнал ПОТЕРЯН после первого фикса (B1, 18-й проход): 30 с
  /// без живого фикса — тоннель, помещение. Снимается фиксом.
  signalLost,

  /// Грубая точность затянулась (A11, 18-й проход): accuracy
  /// больше 100 м дольше 20 с — автогид с таким фиксом молчит,
  /// объясняем почему.
  lowAccuracy,
}

/// Единая плашка статуса геолокации на карте (B3, 17-й проход;
/// B5/B7, 18-й: анимация появления, палитра темы, точность).
///
/// Заменяет разрозненные SnackBar и мелкий чип: в левом верхнем
/// углу одна компактная пилюля в языке NearbySuggestPill/мини-
/// плеера (радиус pill, тень floating, значок в круге, тап-цель
/// ≥44). Показывает ТОЛЬКО статус — детали («как включить» в
/// настройках браузера, «почему молчит автогид») остаются в
/// шторке/SnackBar по тапу.
class MapLocationStatusPill extends StatelessWidget {

  const MapLocationStatusPill({
    super.key,
    required this.status,
    required this.onTap,
    this.accuracyMeters,
  });


  /// Показываемый статус (не [MapLocationStatus.none]).
  final MapLocationStatus status;


  /// Тап по плашке: действие зависит от статуса (запрос
  /// разрешения, шторка подсказки, разовая позиция).
  final VoidCallback onTap;


  /// Точность текущего фикса (для подписи «±N м» у lowAccuracy).
  final double? accuracyMeters;


  /// Подпись плашки (без динамической точности — для тестов и
  /// статусов, которым она не нужна).
  static String labelOf(MapLocationStatus status) {

    switch (status) {

      case MapLocationStatus.none:
        return '';

      case MapLocationStatus.noPermission:
        return 'Включить геолокацию';

      case MapLocationStatus.deniedForever:
        return 'Открыть настройки';

      case MapLocationStatus.serviceOff:
        return 'Включить службу';

      case MapLocationStatus.reducedAccuracy:
        return 'Точная геолокация выключена';

      case MapLocationStatus.searchingSignal:
        return 'Ищем сигнал GPS…';

      case MapLocationStatus.signalLost:
        return 'Сигнал GPS потерян';

      case MapLocationStatus.lowAccuracy:
        return 'Ждём точный сигнал GPS…';
    }
  }


  /// Семантика для скринридера по статусу (B5/B7).
  static String semanticsOf(MapLocationStatus status) {

    switch (status) {

      case MapLocationStatus.none:
        return '';

      case MapLocationStatus.noPermission:
        return 'Геолокация выключена. Нажмите, чтобы разрешить доступ';

      case MapLocationStatus.deniedForever:
        return 'Доступ к геолокации запрещён. Нажмите, чтобы открыть настройки';

      case MapLocationStatus.serviceOff:
        return 'Служба геолокации отключена. Нажмите, чтобы открыть настройки';

      case MapLocationStatus.reducedAccuracy:
        return 'Приблизительная геолокация: точность около километра. '
            'Нажмите, чтобы открыть настройки';

      case MapLocationStatus.searchingSignal:
        return 'Ищем сигнал GPS. Нажмите, чтобы определить позицию ещё раз';

      case MapLocationStatus.signalLost:
        return 'Сигнал GPS потерян. Нажмите, чтобы определить позицию '
            'ещё раз';

      case MapLocationStatus.lowAccuracy:
        return 'Точность GPS низкая, автогид ждёт точного сигнала. '
            'Нажмите, чтобы узнать подробности';
    }
  }


  /// Подпись с учётом текущей точности (lowAccuracy, B6).
  String _labelFor() {

    if (status == MapLocationStatus.lowAccuracy &&
        accuracyMeters != null) {

      return 'Точность ±${accuracyMeters!.round()} м';
    }

    return labelOf(status);
  }


  /// Семантика с учётом текущей точности (B5).
  String _semanticsFor() {

    if (status == MapLocationStatus.lowAccuracy &&
        accuracyMeters != null) {

      final meters = accuracyMeters!.round();

      return 'Точность плюс-минус $meters метров — автогид ждёт '
          'точного сигнала. Нажмите, чтобы узнать подробности';
    }

    return semanticsOf(status);
  }


  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final label = _labelFor();

    // D2: каркас — единый FloatingPill (радиус/тень/стекло/
    // семантика/тап-цель), тон — по статусу.
    return PointerInterceptor(
      child: FloatingPill(
        icon: _iconOf(status),
        tone: _toneOf(status),
        onTap: onTap,
        semanticsLabel: _semanticsFor(),
        tooltip: label,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.onSurface,
            ),
          ),
        ),
      ),
    );
  }


  /// Тон пилюли по статусу (D2): потери/служба — сигнальный.
  FloatingPillTone _toneOf(MapLocationStatus status) {

    switch (status) {

      case MapLocationStatus.serviceOff:
      case MapLocationStatus.signalLost:
      case MapLocationStatus.lowAccuracy:
        return FloatingPillTone.warning;

      case MapLocationStatus.none:
      case MapLocationStatus.noPermission:
      case MapLocationStatus.deniedForever:
      case MapLocationStatus.reducedAccuracy:
      case MapLocationStatus.searchingSignal:
        return FloatingPillTone.info;
    }
  }


  IconData _iconOf(MapLocationStatus status) {

    switch (status) {

      case MapLocationStatus.noPermission:
        return LucideIcons.locateFixed;

      case MapLocationStatus.deniedForever:
        return LucideIcons.settings;

      case MapLocationStatus.serviceOff:
      case MapLocationStatus.searchingSignal:
        return LucideIcons.compass;

      case MapLocationStatus.reducedAccuracy:
        return LucideIcons.mapPin;

      case MapLocationStatus.signalLost:
        return LucideIcons.wifiOff;

      case MapLocationStatus.lowAccuracy:
        return LucideIcons.signalLow;

      case MapLocationStatus.none:
        return LucideIcons.locateFixed;
    }
  }
}
