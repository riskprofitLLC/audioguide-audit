/// Фоновое воспроизведение аудиогида (28-й проход).
///
/// На нативных платформах — инициализация just_audio_background
/// (медиа-сессия, уведомление, lock screen) и источник с MediaItem;
/// на web — заглушка: just_audio_background там не подключаем,
/// HTML5-аудио и так играет при скрытой вкладке.
library;

export 'background_audio_io.dart'
    if (dart.library.js_interop) 'background_audio_web.dart';
