import '../../../../core/services/database_service.dart';

/// Хранилище настроек (native): таблица `settings` в SQLite.
final class AppSettings {
  String? read(String key) {
    if (!DatabaseService.instance.isOpen) {
      return null;
    }

    final rows = DatabaseService.instance.select(
      'SELECT value FROM settings WHERE key = ?',
      [key],
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['value'] as String?;
  }

  void write(String key, String value) {
    if (!DatabaseService.instance.isOpen) {
      return;
    }

    DatabaseService.instance.execute(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  /// Удаляет ключ (миграции настроек).
  void remove(String key) {
    if (!DatabaseService.instance.isOpen) {
      return;
    }

    DatabaseService.instance.execute(
      'DELETE FROM settings WHERE key = ?',
      [key],
    );
  }
}
