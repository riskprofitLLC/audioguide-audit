import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/glass_icon_button.dart';
import '../../../gps/providers/track_recorder_provider.dart';
import '../../../gps/utils/gpx_share.dart';

/// Кнопка записи собственного GPS-трека на карте (29-й проход, П5).
///
/// Idle — «Начать запись» (кружок); во время записи — «Стоп»
/// (квадрат): трек уходит в GPX и открывается шторка «Поделиться».
class TrackRecordButton extends ConsumerWidget {

  const TrackRecordButton({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackRecorderProvider);

    final palette = AppPalette.of(context);

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          GlassIconButton(
            key: ValueKey(
              state.isRecording
                  ? 'track-stop-button'
                  : 'track-record-button',
            ),
            icon: state.isRecording
                ? LucideIcons.square
                : LucideIcons.circle,
            tooltip: state.isRecording
                ? 'Остановить запись и сохранить GPX'
                : 'Начать запись трека',
            onTap: () => _toggle(context, ref),
          ),
          if (state.isRecording)
            Positioned(
              right: 9,
              top: 9,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: palette.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.surfaceRaised,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }


  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(trackRecorderProvider.notifier);

    if (!ref.read(trackRecorderProvider).isRecording) {
      notifier.start();

      return;
    }

    final gpx = notifier.stopAndBuildGpx();

    if (gpx == null) {
      showAppSnackBar(
        context,
        'Трек слишком короткий — запишите маршрут подольше',
      );

      return;
    }

    await shareGpx(gpx, 'Мой трек — Island Guide');

    if (context.mounted) {
      showAppSnackBar(context, 'Трек сохранён в формате GPX');
    }
  }
}
