import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// Включает фоновое воспроизведение: медиа-уведомление и контролы
/// на экране блокировки. Вызывается один раз из main() до runApp.
Future<void> initBackgroundAudio() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.islandguide.island_guide.channel.audio',
    androidNotificationChannelName: 'Аудиогид',
    androidNotificationChannelDescription: 'Воспроизведение экскурсии',
    // Уведомление не смахивается, пока трек играет — сервис держит
    // foreground и Android не глушит звук при заблокированном экране.
    androidNotificationOngoing: true,
    // На паузе сервис не снимается: трек возобновляется с lock screen.
    androidStopForegroundOnPause: false,
  );
}

/// Источник ассета с тегом MediaItem — по нему audio_service строит
/// уведомление и экран блокировки (название точки вместо пути к файлу).
Future<AudioSource> assetAudioSource(
  String path,
) async =>
    AudioSource.asset(
      path,
      tag: MediaItem(
        id: path,
        title: titleFromAssetPath(path),
        artist: 'Аудиогид Island Guide',
      ),
    );

/// «01 - Fethiye.mp3» → «Fethiye»: имя файла без номера папки и расширения.
String titleFromAssetPath(
  String path,
) {
  final base = path.split('/').last;

  final noExt = base.contains('.')
      ? base.substring(0, base.lastIndexOf('.'))
      : base;

  final dash = noExt.indexOf(' - ');

  return dash >= 0 ? noExt.substring(dash + 3) : noExt;
}
