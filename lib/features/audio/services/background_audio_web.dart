import 'package:just_audio/just_audio.dart';

/// Web: фоновый режим не настраиваем — just_audio_background
/// на web не подключаем, воспроизведение при скрытой вкладке
/// работает средствами HTML5-аудио.
Future<void> initBackgroundAudio() async {}

Future<AudioSource> assetAudioSource(
  String path,
) async =>
    AudioSource.asset(path);
