/// Web-заглушка [DatabaseService].
///
/// `package:sqlite3` использует `dart:ffi` и недоступен
/// на web, поэтому на этой платформе база не работает.
/// Все операции — безопасные no-op: приложение продолжает
/// запускаться, но данные из SQLite на web не читаются.
library;

class DatabaseService {

  DatabaseService._();


  static final DatabaseService instance =
      DatabaseService._();


  bool get isOpen => false;


  Future<void> initialize({
    String? databaseDirectory,
  }) async {
    // На web база не инициализируется.
  }


  void close() {
    // Нет базы — закрывать нечего.
  }


  void execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    // no-op
  }


  void insertBatch(
    String sql,
    Iterable<List<Object?>> rows,
  ) {
    // no-op
  }


  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) {

    return const [];
  }
}
