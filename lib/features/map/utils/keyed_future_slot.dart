/// Однослотовый кеш future с ключом.
///
/// Привязывает future загрузки данных к ключу (локация карты или
/// режим «все регионы»). Гонка быстрого переключения локации:
/// future стартует для одной локации, и пока он не завершится,
/// карта переключается на другую — без привязки к ключу новая
/// локация получала бы данные старой.
class KeyedFutureSlot<T> {

  Future<T>? _future;

  String? _key;


  /// Есть ли в слоте живой future.
  bool get hasValue => _future != null;


  /// Возвращает future для [key].
  ///
  /// Если слот пуст, занят ДРУГИМ ключом или прежний future упал —
  /// создаёт новый через [create]; иначе возвращает существующий
  /// (повторные вызовы для того же ключа делят один future, данные
  /// не читаются дважды).
  Future<T> obtain(
    String key,
    Future<T> Function() create,
  ) {

    final existing = _future;

    if (existing != null && _key == key) {

      return existing;
    }

    final created = create();

    // Упавший future не остаётся в слоте: иначе первая ошибка
    // (сбой ассета, сидинга) держала бы слот занятым проваленным
    // future до конца жизни виджета.
    created.then(
      (_) {},

      onError: (_) {

        if (identical(_future, created)) {

          _future = null;

          _key = null;
        }
      },
    );

    _future = created;

    _key = key;

    return created;
  }


  /// Сбрасывает слот (смена локации: данные прежней больше не нужны).
  void reset() {

    _future = null;

    _key = null;
  }
}
