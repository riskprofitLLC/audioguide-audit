import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_player_service.dart';


/// Провайдер сервиса голосового гида.
///
/// Один экземпляр на всё приложение — переключение аудио
/// между экранами не прерывает воспроизведение.
final audioPlayerServiceProvider =
    Provider<AudioPlayerService>((ref) {

  final service = AudioPlayerService();

  ref.onDispose(service.dispose);

  return service;
});
