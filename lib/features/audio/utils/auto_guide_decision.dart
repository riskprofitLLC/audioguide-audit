import '../../settings/providers/settings_providers.dart';

/// Что делать автогиду при входе в радиус точки (B5.4, 8-й
/// проход; A5, 9-й).
enum AutoGuideDecision {
  /// Запустить рассказ сразу.
  play,

  /// Не перебивать играющий трек — показать пилюлю «Рядом».
  suggest,

  /// Ничего не делать.
  ignore,
}

/// Решение автогида по событию входа в радиус POИ.
///
/// Выделено в чистую функцию для тестов (A5): поведение зависит
/// только от режима, состояния плеера и того, не звучит ли уже
/// предложенный трек.
AutoGuideDecision decideAutoGuide({
  required AutoGuideMode mode,
  required bool isPlaying,
  required String? currentFile,
  required String? suggestedFile,
}) {
  switch (mode) {
    case AutoGuideMode.off:
      return AutoGuideDecision.ignore;

    case AutoGuideMode.always:
      return AutoGuideDecision.play;

    case AutoGuideMode.suggest:
      // Тишина — автозапуск как раньше.
      if (!isPlaying) {
        return AutoGuideDecision.play;
      }

      // Точка без аудио предложить не может (A5).
      if (suggestedFile == null) {
        return AutoGuideDecision.ignore;
      }

      // Вошли в радиус точки, которую УЖЕ слушаем, — предложение
      // бессмысленно (A5).
      if (currentFile == suggestedFile) {
        return AutoGuideDecision.ignore;
      }

      return AutoGuideDecision.suggest;
  }
}
