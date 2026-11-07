import 'dart:js_interop';
import 'dart:js_interop_unsafe';


/// Обработчики жестов maplibre, которые глушатся при блокировке.
const List<String> _gestureHandlers = [
  'dragPan',
  'scrollZoom',
  'boxZoom',
  'touchZoomRotate',
  'doubleClickZoom',
  'keyboard',
];


/// Блокирует/разблокирует жесты карты на web.
///
/// Канвас maplibre — платформенный вид: получает события напрямую
/// из DOM поверх Flutter-контента, из-за чего дрожание пальца при
/// нажатии на кнопку управления сдвигало карту, а открытая шторка
/// не мешала перетаскиванию. Инстансы карт собираются хуком в
/// `web/index.html` (`window.__maplibreMaps`); на время наведения
/// на контролы или открытой шторки обработчики жестов отключаются,
/// при уходе/закрытии возвращаются.
/// Помечает ТОЛЬКО ЧТО созданную карту как превью (Б6, замечание
/// Sonnet).
///
/// Раньше disablePreviewCanvasPointerEvents брал ПОСЛЕДНЮЮ карту
/// из `__maplibreMaps`: при позднем style.load превью (возврат на
/// главную, ресайз) «последней» могла оказаться уже ПОЛНОЭКРАННАЯ
/// карта — и её канвас терял pointer-events навсегда (карта не
/// панорамировалась). Теперь пометка ставится в onMapCreated
/// превью-виджета, а глушение работает только по помеченным
/// картам.
///
/// Вызов сразу после onMapCreated превью-карты: только что
/// созданная карта — последняя в массиве (карты создаются
/// последовательно, превью и полная — на разных экранах).
void tagPreviewMapInstance() {
  final raw = globalContext.getProperty('__maplibreMaps'.toJS);

  if (raw == null || raw.isUndefined) {
    return;
  }

  final maps = raw as JSArray<JSAny>;

  if (maps.length == 0) {
    return;
  }

  final map = maps[maps.length - 1] as JSObject;

  // Флаг живёт на самом экземпляре: dispose карты (remove)
  // выпиливает её из массива вместе с пометкой.
  map.setProperty('_islandGuidePreview'.toJS, true.toJS);
}


/// Убирает КОНКРЕТНЫЕ превью-карты из DOM hit-test (Б6): работает
/// только с картами, помеченными [tagPreviewMapInstance] —
/// полноэкранная карта никогда не попадает под операцию.
///
/// Превью-карта не-интерактивна (жесты выключены, тап ловит
/// Flutter-распознаватель в `map_preview.dart`), поэтому канвасу
/// можно безопасно запретить приём DOM-событий: во встроенных
/// браузерах (Orca) перехваченный канвасом клик у правого/нижнего
/// края уезжал по координатам — видимая кнопка и область нажатия
/// не совпадали. С отключённым канвасом попадание считает сам
/// Flutter-слой, и геометрия совпадает с отрисовкой.
void disablePreviewCanvasPointerEvents() {
  final raw = globalContext.getProperty('__maplibreMaps'.toJS);

  if (raw == null || raw.isUndefined) {
    return;
  }

  final maps = raw as JSArray<JSAny>;

  for (var i = 0; i < maps.length; i++) {
    final map = maps[i] as JSObject;

    final tagged = map.getProperty('_islandGuidePreview'.toJS);

    // Полноэкранные карты не трогаем (Б6).
    if (tagged == null ||
        tagged.isUndefined ||
        tagged.dartify() != true) {
      continue;
    }

    final container = map.callMethod('getContainer'.toJS) as JSObject?;

    if (container != null) {
      final style = container.getProperty('style'.toJS) as JSObject?;

      if (style != null) {
        style.setProperty('pointerEvents'.toJS, 'none'.toJS);
      }

      // flt-platform-view — DOM-обёртка платформенного вида.
      // Она стоит выше контейнера maplibre и по умолчанию
      // перехватывает DOM-события (pointer-events: auto),
      // не давая Flutter-распознавателю жестов добраться до
      // GestureDetector в MapPreview.  Снимаем с неё
      // pointer-events и ставим курсор-указатель.
      _disablePlatformViewPointerEvents(container);
    }

    final canvas = map.callMethod('getCanvas'.toJS) as JSObject?;

    if (canvas == null) {
      continue;
    }

    final canvasStyle = canvas.getProperty('style'.toJS) as JSObject?;

    if (canvasStyle == null) {
      continue;
    }

    canvasStyle.setProperty('pointerEvents'.toJS, 'none'.toJS);
  }
}


/// Находит ближайший flt-platform-view и снимает pointer-events,
/// чтобы DOM-события «проваливались» в Flutter-слой.
/// Использует element.closest() — без ручного обхода DOM.
void _disablePlatformViewPointerEvents(JSObject container) {
  final pv = container.callMethod(
    'closest'.toJS,
    'flt-platform-view'.toJS,
  );

  if (pv == null) {
    return;
  }

  final pvStyle = (pv as JSObject).getProperty('style'.toJS) as JSObject?;

  if (pvStyle != null) {
    pvStyle.setProperty('pointerEvents'.toJS, 'none'.toJS);
    pvStyle.setProperty('cursor'.toJS, 'pointer'.toJS);
  }
}


/// Счётчик владельцев блокировки.
///
/// Замок общий для многих владельцев (шторки POI/маршрута/дерева
/// навигации, до 5+ обёрток [MapControlsHoverLock]). Простой
/// глобальный bool ломался: hover на кнопке + открытая шторка →
/// уход курсора с кнопки разблокировал карту при открытом шите.
/// Refcount гарантирует, что жесты возвращаются карте только когда
/// отпустили ВСЕ владельцы.
int _lockCount = 0;


/// Блокирует жесты карты (вызов владельцем блокировки).
void acquireMapInputLock() {

  _lockCount++;

  if (_lockCount == 1) {

    _applyLock(true);
  }
}


/// Снимает одну блокировку. Карта оживает, когда счётчик
/// дошёл до нуля; лишние release игнорируются.
void releaseMapInputLock() {

  if (_lockCount <= 0) {

    return;
  }

  _lockCount--;

  if (_lockCount == 0) {

    _applyLock(false);
  }
}


void _applyLock(bool locked) {
  final raw = globalContext.getProperty('__maplibreMaps'.toJS);

  if (raw == null || raw.isUndefined) {
    return;
  }

  final maps = raw as JSArray<JSAny>;

  for (var i = 0; i < maps.length; i++) {
    final map = maps[i] as JSObject;

    for (final name in _gestureHandlers) {
      final handler = map.getProperty(name.toJS) as JSObject?;

      if (handler == null) {
        continue;
      }

      handler.callMethod(
        locked ? 'disable'.toJS : 'enable'.toJS,
      );
    }
  }
}