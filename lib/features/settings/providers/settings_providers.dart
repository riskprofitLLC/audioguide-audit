import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/providers/audio_player_provider.dart';
import '../services/app_settings.dart';

/// Режим автогида (B5.4, 8-й проход):
///   always  — запускать рассказ при входе в радиус точки;
///   suggest — если трек уже играет вручную, НЕ прерывать:
///             пилюля «Рядом: <точка>. Слушать?» на 10 секунд
///             (тап запускает); тишина — автозапуск как раньше;
///   off     — не запускать ничего.
///
/// По умолчанию — suggest: с наушниками в кармане перебивание
/// начатой истории раздражает сильнее, чем лишний тап по
/// предложению; тишина по-прежнему заводит рассказ сама.
enum AutoGuideMode {
  always,
  suggest,
  off;

  static AutoGuideMode fromName(String? name) {
    return switch (name) {
      'always' => AutoGuideMode.always,
      'off' => AutoGuideMode.off,
      _ => AutoGuideMode.suggest,
    };
  }
}

final autoGuideModeProvider =
    NotifierProvider<AutoGuideModeNotifier, AutoGuideMode>(
  AutoGuideModeNotifier.new,
);

class AutoGuideModeNotifier extends Notifier<AutoGuideMode> {
  static const _key = 'auto_guide_mode';

  /// Старый ключ P1-6: 'auto_guide_enabled' == '0' → выключен.
  /// Читается ТОЛЬКО пока не записан новый ключ (A1, 9-й проход):
  /// раньше legacy перекрывал выбор пользователя навсегда.
  static const _legacyKey = 'auto_guide_enabled';

  @override
  AutoGuideMode build() {
    final saved = AppSettings().read(_key);

    // Новый ключ всегда прав: выбор, сделанный после миграции,
    // не затирает устаревший флаг.
    if (saved != null) {
      return AutoGuideMode.fromName(saved);
    }

    if (AppSettings().read(_legacyKey) == '0') {
      return AutoGuideMode.off;
    }

    return AutoGuideMode.suggest;
  }

  void setMode(AutoGuideMode mode) {
    if (state == mode) {
      return;
    }

    state = mode;

    AppSettings().write(_key, mode.name);

    // Миграция завершена: legacy-ключ больше не должен
    // мешать (A1).
    AppSettings().remove(_legacyKey);
  }
}

/// Автогид включён в любом виде, кроме «Выключен».
final autoGuideEnabledProvider = Provider<bool>((ref) {
  return ref.watch(autoGuideModeProvider) != AutoGuideMode.off;
});

/// Режим темы приложения (D3): светлая / системная / тёмная.
/// Персист в настройках; по умолчанию — СВЕТЛАЯ (системная
/// тема применяется только если пользователь выбрал её сам).
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    return switch (AppSettings().read(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
  }

  void setMode(ThemeMode mode) {
    if (state == mode) {
      return;
    }

    state = mode;

    AppSettings().write(
      _key,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }
}

/// Скорость воспроизведения плеера с персистом (P2, 7-й проход):
/// native — таблица settings, web — localStorage.
///
/// При первом чтении (карточка плеера читает провайдер в build)
/// сохранённое значение применяется к глобальному плееру;
/// setSpeed обновляет плеер и пишет настройку одной операцией.
final playbackSpeedProvider =
    NotifierProvider<PlaybackSpeedNotifier, double>(
  PlaybackSpeedNotifier.new,
);

class PlaybackSpeedNotifier extends Notifier<double> {
  static const _key = 'playback_speed';

  @override
  double build() {
    final saved = double.tryParse(
      AppSettings().read(_key) ?? '',
    );

    if (saved != null && saved != 1.0) {
      // Применяем к плееру сразу при первом чтении: карточка
      // плеера «спрашивает» провайдер в своём build.
      ref.read(audioPlayerServiceProvider).setSpeed(saved);
    }

    return saved ?? 1.0;
  }

  /// Меняет скорость: глобальный плеер + персист одной
  /// операцией (чип скорости зовёт только это).
  void setSpeed(double value) {
    if (state == value) {
      return;
    }

    state = value;

    AppSettings().write(_key, value.toString());

    ref.read(audioPlayerServiceProvider).setSpeed(value);
  }
}

/// Недавние объекты для поиска (P1-4): последние 5 открытых
/// точек/маршрутов в порядке новизны. Ключ —
/// `poi:<локация>:<id>` / `trail:<локация>:<id>`.
final recentItemsProvider =
    NotifierProvider<RecentItemsNotifier, List<String>>(
  RecentItemsNotifier.new,
);

class RecentItemsNotifier extends Notifier<List<String>> {
  static const _key = 'recent_items';

  static const limit = 5;

  @override
  List<String> build() {
    final raw = AppSettings().read(_key);

    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        return decoded
            .whereType<String>()
            .take(limit)
            .toList(growable: false);
      }
    } catch (_) {
      // Битая запись — начинаем с пустого списка.
    }

    return const [];
  }

  /// Запоминает объект: поднимает его в начало и обрезает
  /// список до [limit].
  void push(String item) {
    final next = <String>[
      item,
      ...state.where((existing) => existing != item),
    ].take(limit).toList(growable: false);

    if (listEquals(next, state)) {
      return;
    }

    state = next;

    AppSettings().write(_key, jsonEncode(next));
  }

  /// Очищает список недавних (кнопка в настройках, P2).
  void clear() {
    if (state.isEmpty) {
      return;
    }

    state = const [];

    AppSettings().write(_key, jsonEncode(const []));
  }
}
