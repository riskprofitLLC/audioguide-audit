part of 'map_widget.dart';


/// Порог сброса слежения по дрейфу камеры (Б7, замечание
/// Sonnet) — вынесен в FollowCameraController (D5); здесь
/// forwarding-константа для регрессионных тестов map_gps_follow.
@visibleForTesting
const double kFollowDropDriftMeters =
    follow_camera_controller.kFollowDropDriftMeters;

/// Сбрасывать ли слежение по дрейфу цели камеры — forwarding на
/// контроллер (логика и предикат живут в FollowCameraController).
@visibleForTesting
bool shouldDropFollowing(double driftMeters) =>
    follow_camera_controller.shouldDropFollowing(driftMeters);


/// Методы подписки на поток позиций GPS, обновления маркера
/// пользователя, чипа «ближайший POI» и карточки навигации
/// по маршруту, а также кнопок управления картой (зум, «Моё
/// местоположение»).
///
/// Вынесены из `_MapWidgetState` в отдельный файл, чтобы уменьшить
/// размер основного файла карты.
mixin _MapTrackingMixin on _MapCameraMixin {

  /// Начинает подписку на поток позиций.
  ///
  /// Мягкий запрос разрешения (P1-1, 7-й проход): раньше здесь
  /// мгновенно выскакивал системный диалог при открытии карты.
  /// Теперь статус только ПРОВЕРЯЕТСЯ: без разрешения на карте
  /// появляется плашка «Включить геолокацию», а сам запрос
  /// происходит по явному тапу (плашка или кнопка GPS).
  void _startTracking() {

    if (_trackingStarted) {
      return;
    }

    _trackingStarted = true;

    AppLogger.info('[MapWidget] _startTracking begin');

    final location =
        ref.read(locationServiceProvider);

    location.checkPermission().then((status) {

      AppLogger.info('[MapWidget] _startTracking status=$status');

      if (!mounted) {
        return;
      }

      if (status == LocationPermissionStatus.granted) {

        // A3 (18-й проход): автогид УЖЕ жив — его запустил
        // ref.listen(poiEntryProvider) в MapPage, и invalidate
        // здесь пересоздавал вотчер с пустым `_inside`: replay
        // позиции давал повторное событие входа (повторный трек).
        // Инвалидация — только при переходе «не было прав → стало»
        // (тап по плашке/кнопке GPS).
        _handlePermissionGranted(invalidateAutoGuide: false);

        return;
      }

      // Канал не ответил (A11) — ничего не меняем: плашка «Включить
      // геолокацию» у человека с правами врала бы.
      if (status == LocationPermissionStatus.unknown) {

        AppLogger.warning(
          '[MapWidget] _startTracking: статус неизвестен — без плашки',
        );

        return;
      }

      // Разрешения нет — единая плашка статуса вместо молчаливого
      // бездействия GPS (автогид заработает после явного разрешения).
      _setLocationStatus(_statusFromPermission(status));
    });
  }


  /// Статус плашки для «сырого» статуса разрешения (B3).
  ///
  /// A11 (18-й проход): `unknown` → [MapLocationStatus.none] —
  /// «не смогли проверить» НЕ «нет разрешения», плашку не трогаем.
  /// Статус плашки по статусу разрешения — forwarding на
  /// GpsStatusController.statusFromPermission (D5).
  static MapLocationStatus _statusFromPermission(
    LocationPermissionStatus status,
  ) =>
      GpsStatusController.statusFromPermission(status);


  /// Меняет статус единой плашки (B3) с перестройкой.
  void _setLocationStatus(MapLocationStatus status) {

    if (!gpsStatus.setStatus(status)) {
      return;
    }

    setState(() {});
  }


  /// Подписывается на поток позиций (разрешение уже есть).
  void _subscribePositions() {

    final hadSub = _positionSub != null;

    _positionSub ??=
        ref.read(locationServiceProvider).positions.listen(
      _onPosition,
    );

    if (!hadSub) {

      AppLogger.info('[MapWidget] listening to positions');

      // B3: трекинг включён — если первого фикса нет дольше
      // 15 с, показываем «Ищем сигнал GPS…» (снимается фиксом).
      _signalSearchTimer?.cancel();

      _signalSearchTimer = Timer(const Duration(seconds: 15), () {

        if (mounted && gpsStatus.markSearchingSignal()) {

          setState(() {});
        }
      });

      // B1 (18-й проход): контроль свежести маркера — каскад
      // таймеров после последнего фикса: 20 с — точка тускнеет,
      // ещё 10 с — «сигнал потерян». Новые фиксы сбрасывают счётчик.
      _restartMarkerFreshnessTimers();
    }
  }

  /// Останавливает «побочные» таймеры трекинга (поиск сигнала,
  /// свежесть маркера, грубая точность) — при отзыве разрешения
  /// или уходе с карты.
  void _stopTrackingTimers() {

    _signalSearchTimer?.cancel();

    _signalSearchTimer = null;

    _restartMarkerFreshnessStop();

    _poorAccuracyTimer?.cancel();

    _poorAccuracyTimer = null;

    _poorAccuracySince = null;
  }


  /// Сбрасывает таймеры свежести маркера (без отмены
  /// «сигнал потерян» — им управляет отдельный [_onSignalLost]).
  void _restartMarkerFreshnessStop() {

    userMarker.stopStaleTimer();
  }


  /// Перезапускает каскад свежести после живого фикса (B1):
  /// 20 с без нового фикса — точка тускнеет, ещё 10 с — «потерян».
  ///
  /// Таймеры вместо «периодической сверки DateTime.now()»: возраст
  /// фикса считается фейковыми часами теста, поведение
  /// детерминировано.
  void _restartMarkerFreshnessTimers() {

    userMarker.restartFreshnessTimers();
  }


  /// 20 с без живого фикса — маркер тускнеет (B1): переписываем
  /// слой с `fresh: false`, планируем «сигнал потерян».
  void _onMarkerStale() {

    if (!mounted || _positionSub == null) {
      return;
    }

    if (userMarker.shownFresh) {

      final position = _userMarker.last;

      final controller = _controller;

      if (position != null && controller != null) {

        unawaited(
          _userMarker.write(
            position,
            _MapLibreUserMarkerSink(controller),
            fresh: false,
          ),
        );
      }
    }

    // Таймер «потерян» — внутри контроллера (userMarker).
  }


  /// 30 с без живого фикса — сигнал потерян (B1): тоннель,
  /// помещение. Плашка снимается первым же фиксом.
  void _onSignalLost() {

    if (!mounted || _positionSub == null) {
      return;
    }

    if (gpsStatus.markSignalLost()) {

      setState(() {});

      _announce('Сигнал GPS потерян');
    }
  }


  /// Перепроверка при возврате в приложение (15-й проход) и
  /// после переключения службы (A7, 17-й проход).
  ///
  /// Пользователь мог разрешить доступ в настройках телефона
  /// мимо приложения — приложение обязано это увидеть без
  /// перезапуска: плашка гаснет, включается трекинг и автогид.
  ///
  /// A7: ранний выход при живой подписке убран — отзыв
  /// разрешения при работающем трекинге раньше не замечался:
  /// поток умирал, сервис ретраился вечно, UI молчал. Теперь
  /// «нет разрешения» при живой подписке отменяет её и
  /// показывает плашку.
  void _recheckPermissionOnResume() {

    if (widget.preview) {
      return;
    }

    ref.read(locationServiceProvider).checkPermission().then((status) {

      if (!mounted) {

        return;
      }

      if (status == LocationPermissionStatus.granted) {

        // Подписка умерла (пока права не было) — будим.
        ref.read(locationServiceProvider).ensureGatewayActive();

        if (_positionSub == null) {

          _handlePermissionGranted(invalidateAutoGuide: true);

        } else {

          // checkPermission granted ⇒ служба включена — «служба
          // выключена» больше не актуален.
          if (gpsStatus.serviceTurnedOn()) {
            setState(() {});
          }

          // A4 (18-й проход): статус точности — по факту, а не
          // безусловно «всё хорошо»: приблизительная геолокация
          // могла быть и раньше — плашка обязана остаться; могла
          // стать точной в настройках — обязана уйти.
          unawaited(_applyAccuracyStatus());
        }

        return;
      }

      // A11: не смогли проверить — ничего не меняем (не отменять
      // же живой трекинг из-за зависшего метод-канала).
      if (status == LocationPermissionStatus.unknown) {

        return;
      }

      // Разрешения нет: могли отозвать при живой подписке —
      // отменяем её, чтобы не жечь батарею в пустую.
      if (_positionSub != null) {

        AppLogger.warning(
          '[MapWidget] разрешение отозвано при живой подписке — '
          'трекинг останавливается',
        );

        _positionSub?.cancel();

        _positionSub = null;

        _stopTrackingTimers();
      }

      _setLocationStatus(_statusFromPermission(status));
    });
  }

  /// Разрешение получено (тап по плашке или кнопке GPS):
  /// прячем плашку, запускаем трекинг и — при переходе «не было
  /// прав → стало» ([invalidateAutoGuide]) — автогид.
  ///
  /// A3 (18-й проход): на старте карты с уже выданным правом
  /// провайдер автогида жив от ref.listen в MapPage — инвалидация
  /// сбрасывала его состояние входа (повторный трек).
  void _handlePermissionGranted({required bool invalidateAutoGuide}) {

    if (gpsStatus.clearPermissionStatuses()) {
      setState(() {});
    }

    _subscribePositions();

    // Подписка могла умереть, пока разрешения не было (A7) —
    // сервис не перезапустил бы её сам: его контроллер всё это
    // время держал слушателей (автогид), onListen не сработает.
    ref.read(locationServiceProvider).ensureGatewayActive();

    // Состояние СЛУЖБЫ геолокации (A7, 17-й проход): выключение
    // в шторке телефона замечаем сразу, без ожидания возврата
    // в приложение (native-поток; web — пустой). Подписка живёт,
    // пока карта вообще зависит от GPS.
    _serviceStatusSub ??= ref
        .read(locationServiceProvider)
        .serviceStatusChanges
        .listen((enabled) {

      if (!mounted) {
        return;
      }

      if (enabled) {

        // Службу включили — будим подписку, если она умерла,
        // и перепроверяем разрешение (его могли дать там же).
        ref.read(locationServiceProvider).ensureGatewayActive();

        _recheckPermissionOnResume();
      } else {

        if (gpsStatus.serviceTurnedOff()) {
          setState(() {});
        }
      }
    });

    // A13/A4: приблизительная геолокация — ставим И снимаем плашку
    // по факту (18-й проход): раньше при выдаче точных прав из
    // «примерных» подсказка оставалась висеть навсегда.
    unawaited(_applyAccuracyStatus());

    // Автогид ждёт разрешения (poiEntryProvider вернулся без
    // потока) — перезапускаем его. Только при реальном переходе
    // (A3): повторный invalidate у живого провайдера сбрасывает
    // его состояние входа.
    if (invalidateAutoGuide) {

      ref.invalidate(poiEntryProvider);
    }
  }

  /// Ставит/снимает плашку «Точная геолокация выключена» по
  /// фактическому статусу точности (A4, 18-й проход).
  Future<void> _applyAccuracyStatus() async {

    final reduced =
        await ref.read(locationServiceProvider).isLocationAccuracyReduced();

    if (!mounted) {
      return;
    }

    if (gpsStatus.applyReducedAccuracy(reduced)) {
      setState(() {});
    }
  }


  /// Запрос разрешения с защитой от параллельных диалогов (Б11,
  /// замечание Sonnet): системный диалог может висеть до минуты —
  /// повторные тапы по кнопке/плашке обязаны игнорироваться, а не
  /// открывать второй диалог поверх первого.
  Future<LocationPermissionStatus?> _ensurePermissionGuarded() async {

    if (_permissionRequestInFlight) {

      return null;
    }

    _permissionRequestInFlight = true;

    try {

      return await ref.read(locationServiceProvider).ensurePermission();

    } finally {

      _permissionRequestInFlight = false;
    }
  }


  /// Тап по плашке статуса (B3): действие зависит от варианта.
  Future<void> _onStatusPillTap() async {

    switch (gpsStatus.status) {

      case MapLocationStatus.none:
        break;

      // Можно спросить систему — спрашиваем, по успеху трекинг.
      case MapLocationStatus.noPermission:

        final status = await _ensurePermissionGuarded();

        if (!mounted || status == null) {
          return;
        }

        if (status == LocationPermissionStatus.granted) {
          _handlePermissionGranted(invalidateAutoGuide: true);
        } else if (status == LocationPermissionStatus.unknown) {
          _showPermissionHint(status);
        } else {
          _showPermissionHint(status);
          _setLocationStatus(_statusFromPermission(status));
        }

      // Дальше — подсказки с выходом в настройки (native) или
      // шторка шагов браузера (web).
      case MapLocationStatus.deniedForever:
      case MapLocationStatus.serviceOff:
      case MapLocationStatus.reducedAccuracy:
        _showPillStatusHint(gpsStatus.status);

      // Сигнал ищется/потерян — пробуем разовую позицию (на web она
      // берётся по WiFi/вышкам и может прийти быстрее потока).
      case MapLocationStatus.searchingSignal:
      case MapLocationStatus.signalLost:
        unawaited(_locateMe());

      // Грубая точность затянулась — объясняем, почему молчит
      // автогид (B5, 18-й проход).
      case MapLocationStatus.lowAccuracy:
        _showPillStatusHint(MapLocationStatus.lowAccuracy);
    }
  }


  /// Подсказка для статуса РАЗРЕШЕНИЯ (A11, 18-й проход:
  /// типизированный параметр вместо `Object` с кастами).
  void _showPermissionHint(LocationPermissionStatus status) {

    if (!mounted) {
      return;
    }

    // Канал завис — честно говорим «не смогли», а не «нет доступа».
    if (status == LocationPermissionStatus.unknown) {

      showAppSnackBar(
        context,
        'Не удалось проверить разрешение на геолокацию',
        actionLabel: 'Повторить',
        onAction: () => _locateMe(),
      );

      return;
    }

    showLocationPermissionHint(
      context,
      status,
      onRetry: _locateMe,
    );
  }


  /// Подсказка для варианта ПЛАШКИ (A11, 18-й проход).
  void _showPillStatusHint(MapLocationStatus status) {

    if (!mounted) {
      return;
    }

    switch (status) {

      case MapLocationStatus.deniedForever:
        showLocationPermissionHint(
          context,
          LocationPermissionStatus.deniedForever,
          onRetry: _locateMe,
        );

      case MapLocationStatus.serviceOff:
        showLocationPermissionHint(
          context,
          LocationPermissionStatus.serviceOff,
          onRetry: _locateMe,
        );

      case MapLocationStatus.reducedAccuracy:
        _showReducedAccuracyHint();

      case MapLocationStatus.lowAccuracy:
        _showAutoguideAccuracyHelp();

      case MapLocationStatus.none:
      case MapLocationStatus.noPermission:
      case MapLocationStatus.searchingSignal:
      case MapLocationStatus.signalLost:
        break;
    }
  }


  /// A13: подсказка про приблизительную геолокацию с переходом
  /// в настройки приложения (native).
  void _showReducedAccuracyHint() {

    showAppSnackBar(
      context,
      'Выдана только приблизительная геолокация (точность до '
      'пару километров): автогид с ней не работает. Включите '
      '«Точную геолокацию» в настройках приложения',
      actionLabel: 'Настройки',
      onAction: () => Geolocator.openAppSettings(),
    );
  }


  /// B5: шторка «Почему молчит автогид» — объяснение порога
  /// точности при затянувшейся грубой точности.
  Future<void> _showAutoguideAccuracyHelp() {

    acquireMapInputLock();

    return showAutoguideAccuracyHelpSheet(
      context,
      accuracyMeters: _lastAccuracyMeters,
    ).whenComplete(releaseMapInputLock);
  }


  /// Анонс для скринридера (B7, 18-й проход): смена состояний
  /// слежения/сигнала. Без активного дерева семантики — no-op.
  void _announce(String message) {

    if (widget.preview || !mounted) {
      return;
    }

    // sendAnnouncement (не deprecated announce): отправка в окно.
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        TextDirection.ltr,
      ),
    );
  }


  void _onPosition(UserPosition position) {

    // Логов на каждый тик нет сознательно: это самый горячий
    // путь карты (интерполяция строк + запись в лог ~1 раз/сек
    // при активном GPS).

    if (!mounted) {
      return;
    }

    // A1 (18-й проход): фикс из буфера фона/кеша датчика —
    // устаревшие события не обрабатываются вовсе (после свёртого
    // приложения пачка фиксов запускала чужой рассказ и вела
    // маркер в прошлое место).
    if (LocationService.isStaleFix(position)) {
      return;
    }

    // A6 (18-й проход): разовая позиция с кнопки GPS приходит и
    // общим потоком (сервис пушит её), и прямым вызовом —
    // обрабатываем один раз.
    if (identical(_lastProcessedPosition, position)) {
      return;
    }

    _lastProcessedPosition = position;

    MapWidget.debugPositionTicks++;

    // Свежесть маркера (B1): живой фикс — точка «яркая», каскад
    // тусклости/потери стартует заново.
    userMarker.markFresh();

    // Первый фикс: плашки поиска/потери сигнала больше не нужны.
    _signalSearchTimer?.cancel();
    _signalSearchTimer = null;

    final wasLost = gpsStatus.onFixReceived();

    if (wasLost != null) {

      setState(() {});

      if (wasLost) {
        _announce('Сигнал GPS найден');
      }
    }

    // Грубая точность затянулась — подсказка (A11, 18-й проход);
    // точный фикс — сброс счётчика и плашки.
    _trackPoorAccuracy(position.accuracy);

    // Курс пользователя (A17): heading платформы, иначе —
    // вычисленный по смещению между фиксами (универсально для
    // web, где браузер курс не отдаёт).
    _updateCourse(position);

    // Маркер: конус направления требует курс — подмешиваем
    // свежий вычисленный, если платформа его не дала.
    _updateUserMarker(_withCourse(position));

    _updateNearestPoi(position);

    _updateNavigation(position);

    // Режим «по курсу» (B3): поворот карты за направлением
    // движения с троттлингом.
    if (followCamera.following && followCamera.courseUp) {

      _rotateCourseUp(_freshCourse());
    }

    if (followCamera.following) {
      unawaited(_followUser(position));
    }
  }


  /// Счётчик затянувшейся грубой точности (A11, 18-й проход):
  /// автогид при accuracy > 100 м молчит (гейт вотчера), а
  /// пользователь не понимает почему — после 20 с подряд
  /// показываем плашку с текущей точностью.
  void _trackPoorAccuracy(double? accuracy) {

    _lastAccuracyMeters = accuracy;

    final poor =
        accuracy != null && accuracy > _poorAccuracyMeters;

    if (poor) {

      final since = _poorAccuracySince ??= DateTime.now();

      _poorAccuracyTimer?.cancel();

      final remaining =
          _poorAccuracyDelay - DateTime.now().difference(since);

      _poorAccuracyTimer =
          Timer(remaining > Duration.zero ? remaining : Duration.zero, () {

        if (!mounted) {
          return;
        }

        if (_poorAccuracySince != null && gpsStatus.markLowAccuracy()) {

          setState(() {});
        }
      });

      return;
    }

    _poorAccuracySince = null;

    _poorAccuracyTimer?.cancel();

    _poorAccuracyTimer = null;

    if (gpsStatus.status == MapLocationStatus.lowAccuracy) {

      _setLocationStatus(MapLocationStatus.none);
    }
  }


  /// Обновляет курс: heading фикса или смещение от предыдущего
  /// (A17). Курс запоминается ВМЕСТЕ со временем и скоростью —
  /// использоваться может только свежим и при движении (A5,
  /// 18-й проход).
  void _updateCourse(UserPosition position) {

    final prev = _prevPosition;

    _prevPosition = position;

    // Скорость (A7): платформенная, иначе — вычисленная по
    // смещению и времени между фиксами (web часто без speed).
    final computedSpeed = _computedSpeedMps(prev, position);

    _lastComputedSpeedMps = computedSpeed;

    final platformHeading = position.heading;

    if (platformHeading != null) {

      _course = platformHeading;

      _courseAt = DateTime.now();

      _courseSpeedMps = position.speed ?? computedSpeed;

      return;
    }

    if (prev == null) {
      return;
    }

    // Смещение меньше ~5 м — курс неустойчив (шум GPS),
    // оставляем прежний.
    final moved = LocationService.distanceMeters(
      prev.latitude,
      prev.longitude,
      position.latitude,
      position.longitude,
    );

    if (moved >= 5) {

      _course = LocationService.bearingDegrees(
        prev.latitude,
        prev.longitude,
        position.latitude,
        position.longitude,
      );

      _courseAt = DateTime.now();

      _courseSpeedMps = position.speed ?? computedSpeed;
    }
  }


  /// Скорость по смещению и времени между фиксами (A7, 18-й
  /// проход). `null` — считать нельзя (нет меток времени или
  /// интервал слишком мал).
  double? _computedSpeedMps(
    UserPosition? from,
    UserPosition to,
  ) {

    if (from == null) {
      return null;
    }

    final fromAt = from.timestamp;

    final toAt = to.timestamp;

    if (fromAt == null || toAt == null) {
      return null;
    }

    final dt = toAt.difference(fromAt).inMilliseconds / 1000;

    if (dt < 0.5) {
      return null;
    }

    final moved = LocationService.distanceMeters(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );

    return moved / dt;
  }


  /// Свежий ли курс — можно ли на него опираться (A5, 18-й
  /// проход): не старше ~5 с И скорость движения выше ~0.8 м/с.
  /// У стоящего/давно не двигавшегося — `null` (стрелки и
  /// подсказки возвращаются к порядку вершин).
  double? _freshCourse() {

    final course = _course;

    final at = _courseAt;

    if (course == null || at == null) {
      return null;
    }

    if (DateTime.now().difference(at) > _courseFreshAge) {
      return null;
    }

    final speed = _courseSpeedMps;

    if (speed == null || speed < _courseMinSpeedMps) {
      return null;
    }

    return course;
  }


  /// Позиция с подмешанным курсом и скоростью (для маркера):
  /// конус направления рисуется только при свежем движении.
  UserPosition _withCourse(UserPosition position) {

    final course = _freshCourse();

    final speed = position.speed ?? _lastComputedSpeedMps;

    if (position.heading != null && position.speed != null) {
      return position;
    }

    return UserPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: speed,
      heading: position.heading ?? course,
      timestamp: position.timestamp,
    );
  }


  void _updateNavigation(UserPosition position) {

    if (_trails.isEmpty) {

      return;
    }

    var state = _trailNavigator.update(
      position,
      _trails,
      // Курс известен и свеж (A5) — подсказка «Идти …»
      // перевыбирается при движении против порядка вершин (A17).
      course: _freshCourse(),
    );

    // Дальше порога «ближнего объекта» карточка не показывается:
    // в режиме «все регионы» ближайший маршрут может лежать в
    // другом регионе (показывали «Отклонение 120000 м»).
    if (state != null &&
        !withinNearbyDisplayRadius(state.distanceToTrack)) {

      state = null;
    }

    final prev = _navState;

    if (identical(state, prev)) {

      return;
    }

    // Rebuild только на содержательное изменение: без порогов
    // каждый GPS-тик перестраивал весь MapWidget (~1 Гц), даже
    // когда пользователь стоит на месте. Стрелка направления
    // и дистанция обновляются шагами по 5 м / 5° — для глаза
    // это плавно.
    if (state != null && prev != null) {

      final sameTrail = state.trail.id == prev.trail.id;

      final sameOffRoute = state.offRoute == prev.offRoute;

      final sameDistance =
          (state.distanceToTrack - prev.distanceToTrack).abs() < 5;

      final sameBearing = anglesWithin(state.bearing, prev.bearing, 5);

      final sameReversed = state.reversed == prev.reversed;

      if (sameTrail &&
          sameOffRoute &&
          sameDistance &&
          sameBearing &&
          sameReversed) {

        return;
      }
    }

    setState(() {

      _navState = state;
    });
  }




  /// Обновляет маркер пользователя (A9/B2, 18-й проход):
  ///
  /// - позиция запоминается ДО проверки контроллера — без карты
  ///   фикс не теряется (восстановится после сборки слоя);
  /// - маркер ЕДЕТ между фиксами (~700 мс интерполяции), а не
  ///   прыгает; Reduce Motion — прямая запись;
  /// - промежуточные кадры пишутся в слой, не подменяя
  ///   запомненный реальный фикс.
  Future<void> _updateUserMarker(
    UserPosition position,
  ) async {

    // A9: запомнить всегда — контроллер ещё может не существовать.
    _userMarker.remember(position);

    final controller = _controller;

    if (controller == null) {
      return;
    }

    final sink = _MapLibreUserMarkerSink(controller);

    final from = userMarker.shownPosition;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (reduceMotion || from == null || identical(from, position)) {

      _stopMarkerTween();

      userMarker.writeDirect(position, DateTime.now());

      await _userMarker.write(
        position,
        sink,
        fresh: userMarker.shownFresh,
      );

      return;
    }

    userMarker.beginTween(from, position);

    _markerTween?.forward(from: 0);
  }


  /// Кадр интерполяции маркера (B2): троттлинг записи ~80 мс,
  /// финальный кадр — всегда (позиция совпадает с реальным
  /// фиксом).
  void _onMarkerTweenTick() {

    final from = userMarker.tweenFrom;

    final to = userMarker.tweenTo;

    final controller = _controller;

    if (from == null || to == null || !mounted) {
      return;
    }

    final pos = UserMarkerSource.lerp(from, to, _markerTween!.value);

    userMarker.shownPosition = pos;

    final isLastFrame = _markerTween!.isCompleted;

    final now = DateTime.now();

    if (!userMarker.shouldWriteFrame(isLastFrame: isLastFrame, now: now)) {
      return;
    }

    userMarker.markWritten(now);

    if (controller != null) {

      unawaited(
        _userMarker.write(
          pos,
          _MapLibreUserMarkerSink(controller),
          fresh: userMarker.shownFresh,
        ),
      );
    }
  }


  /// Останавливает текущую интерполяцию маркера (новый фикс или
  /// прямая запись).
  void _stopMarkerTween() {

    _markerTween?.stop();

    userMarker.stopTween();
  }


  /// Слежение «следую за мной» (B2, 17-й проход): держим
  /// пользователя в центре. B2 (18-й): камера едет короткой
  /// анимацией (~500 мс) вместо мгновенного moveCamera на каждый
  /// тик — на каднице GPS цепочка анимаций сливается в плавный
  /// ход. Reduce Motion — прежний мгновенный перенос.
  ///
  /// Б7 (замечание Sonnet): на время СОБСТВЕННОЙ анимации поднимается
  /// поколение — во время полёта камеры дрейф не оценивается
  /// (камера едет от старой цели к новой и «запаздывает» на десятки
  /// метров на скорости лодки/машины — раньше это ложно роняло
  /// слежение).
  Future<void> _followUser(UserPosition position) async {

    final controller = _controller;

    if (controller == null) {
      return;
    }

    final target = LatLng(position.latitude, position.longitude);

    followCamera.lastFollowTarget = target;

    final generation = followCamera.beginOwnCameraMove();

    try {

      if (MediaQuery.disableAnimationsOf(context)) {

        await controller.moveCamera(CameraUpdate.newLatLng(target));

      } else {

        await controller.animateCamera(
          CameraUpdate.newLatLng(target),

          duration: const Duration(milliseconds: 500),
        );
      }

    } catch (error) {

      AppLogger.warning('[MapWidget] follow camera failed: $error');

    } finally {

      // Анимация отыграла (или её прервали) — дрейф снова
      // оценивается.
      followCamera.endOwnCameraMove(generation);
    }
  }


  /// Камера сдвинулась: пока включено слежение, отличаем свою
  /// анимацию (цель совпадает с [_lastFollowTarget]) от
  /// ручного панорамирования — жест сбрасывает режим (B2).
  ///
  /// B4 (18-й проход): здесь же пишем bearing камеры — стрелки
  /// «относительно экрана» (чип ближайшей точки) обязаны
  /// переворачиваться при повороте карты. Нотификатор обновляется
  /// шагами ≥2° — чип перестраивается сам, без setState карты.
  void _onCameraMove(CameraPosition camera) {

    if ((camera.bearing - _cameraBearingNotifier.value).abs() >= 2) {
      _cameraBearingNotifier.value = camera.bearing;
    }

    // Решение о дрейфе — в контроллере (Б7: во время собственной
    // анимации дрейф не оценивается; порог 40 м — shouldDropFollowing).
    if (followCamera.shouldDropForDrift(camera.target)) {

      _setFollowing(false);
    }
  }


  /// Включает/выключает режим слежения (B2) с перестройкой
  /// кнопки. B7 (18-й проход): смена состояния анонсируется
  /// скринридеру; выключение слежения сбрасывает и «по курсу» —
  /// повёрнутая карта без слежения сбивает ориентацию.
  void _setFollowing(bool following) {

    if (!followCamera.setFollowing(following)) {
      return;
    }

    setState(() {});

    _announce(following ? 'Слежение включено' : 'Слежение выключено');

    if (!following) {

      unawaited(_resetBearingToNorth());
    }
  }


  /// Включает режим «карта по курсу» (B3, 18-й проход): bearing
  /// камеры = направлению движения («course-up», как в навигаторах).
  void _enterCourseUp() {

    if (followCamera.courseUp) {
      return;
    }

    followCamera.enterCourseUp();

    setState(() {});

    _announce('Карта повёрнута по курсу');

    _rotateCourseUp(_freshCourse());
  }


  /// Возвращает карту «севером вверх» (третий тап по кнопке GPS
  /// в course-up возвращает обычную ориентацию).
  void _exitCourseUp() {

    if (!followCamera.courseUp) {
      return;
    }

    followCamera.exitCourseUp();

    setState(() {});

    _announce('Карта возвращена к северу');

    unawaited(_resetBearingToNorth());
  }


  /// Поворот карты за курсом (B3): троттлинг ≥10° — постоянные
  /// микроповороты дёргали бы карту на каждом GPS-тике.
  void _rotateCourseUp(double? course) {

    // Троттлинг поворотов ≥10° — в контроллере.
    if (!followCamera.shouldRotateCourseUp(course)) {
      return;
    }

    unawaited(
      _animateCameraSafe(CameraUpdate.bearingTo(course!)),
    );
  }


  /// Безопасная анимация камеры (A11, 18-й проход): контроллер
  /// мог уже уничтожаться — тихо логируем, а не роняем тик GPS.
  Future<void> _animateCameraSafe(
    CameraUpdate update, {
    Duration? duration,
  }) async {

    final controller = _controller;

    if (controller == null) {
      return;
    }

    try {

      await controller.animateCamera(update, duration: duration);

    } catch (error) {

      AppLogger.warning('[MapWidget] animateCamera failed: $error');
    }
  }


  void _updateNearestPoi(UserPosition position) {

    // A15 (17-й проход): при активном фильтре категорий ближайшей
    // считается ВИДИМАЯ точка — чип не ведёт к объекту, спрятанному
    // фильтром (правило «что на карте, то и в подсказке»). Список
    // локаций параллелен точкам; пустой (защитный случай) — все
    // точки считаются точками текущей локации.
    final locations = _poiLocations.isEmpty && _pois.isNotEmpty
        ? List<String>.filled(_pois.length, _effectiveIslandId)
        : _poiLocations;

    final match = nearestVisiblePoi(
      position: position,
      pois: _pois,
      locations: locations,
      category: _activeCategoryFilter,
    );

    Poi? nearest;

    String? nearestLocation;

    double? nearestDistance;

    double? nearestBearing;

    // Дальше порога «ближнего объекта» чип скрывается: в режиме
    // «все регионы» ближайшая точка может быть в другом регионе.
    if (match != null && withinNearbyDisplayRadius(match.distance)) {

      nearest = match.poi;

      nearestLocation = match.locationId;

      nearestDistance = match.distance;

      nearestBearing = match.bearing;
    }

    // Чип «ближайший POI» пересобираем только при смене объекта
    // или заметном изменении дистанции, а не на каждый GPS-тик.
    final titleChanged = nearest?.title != _nearestPoiTitle;

    final oldDistance = _nearestPoiDistance;

    final distanceChanged = nearestDistance != oldDistance &&
        (nearestDistance == null ||
            oldDistance == null ||
            (nearestDistance - oldDistance).abs() >= 5);

    // Курс обновляем и при заметном повороте (реальный угол
    // >=15°, с учётом перехода через север): дистанция может
    // стоять на месте, пока пользователь разворачивается.
    final oldBearing = _nearestPoiBearing;

    final bearingChanged = nearestBearing != oldBearing &&
        (nearestBearing == null ||
            oldBearing == null ||
            !anglesWithin(nearestBearing, oldBearing, 15));

    if (!titleChanged && !distanceChanged && !bearingChanged) {

      return;
    }

    setState(() {

      _nearestPoiTitle = nearest?.title;

      _nearestPoiDistance = nearestDistance;

      _nearestPoiBearing = nearestBearing;

      _nearestPoi = nearest == null || nearestLocation == null
          ? null
          : (nearest, nearestLocation);
    });
  }


  /// Границы, относительно которых решаем «далеко от региона»
  /// (A10, 18-й проход): bbox точек локации (islandBounds),
  /// иначе — границы региона.
  Future<MapBounds?> _mappedRegionBounds() async {

    final islandBounds = _manifest?.islandBounds;

    if (islandBounds != null) {
      return islandBounds;
    }

    try {

      final manifests = await ref.read(regionsProvider.future);

      final region = regionOfLocation(_effectiveIslandId);

      for (final manifest in manifests) {
        if (manifest.id == region.id) {
          return manifest.mapBounds;
        }
      }

    } catch (error) {

      AppLogger.warning(
        '[MapWidget] не удалось прочитать границы региона: '
        '${error.runtimeType}',
      );
    }

    return null;
  }


/// Позиция вне карты всех регионов (A10, 18-й проход):
  /// пользователь в другой стране — камера не летит в пустоту
  /// (тайлов там нет), вместо этого подсказка с явным выбором.
  Future<bool> _isFarFromMappedRegion(UserPosition position) async {

    const farThresholdMeters = 50000.0;

    final bounds = await _mappedRegionBounds();

    if (bounds == null) {
      return false;
    }

    return LocationService.distanceToBoundsMeters(
          position.latitude,
          position.longitude,
          bounds,
        ) >
        farThresholdMeters;
  }


  /// Центрирует карту на текущей позиции пользователя (A5, 17-й
  /// проход).
  ///
  /// Типизированный результат вместо null: таймаут, запрет
  /// доступа и выключенная служба получают свои тексты. Повторный
  /// тап во время поиска — отмена (спиннер гаснет, устаревший
  /// результат отбрасывается по поколению запроса). Зум после
  /// поиска — не ниже 15: в режиме «все регионы» точка иначе
  /// остаётся вне читаемого масштаба. По успеху включается
  /// слежение «следую за мной» (B2).
  ///
  /// Инвалидация автогида — только при переходе «разрешения не
  /// было → стало» (A2, 8-й проход): раньше каждое успешное
  /// нажатие звало [_handlePermissionGranted], тот делал
  /// `ref.invalidate(poiEntryProvider)`, провайдер пересоздавал
  /// PoiProximityWatcher с пустым `_inside` — и пользователь,
  /// стоящий в радиусе POI, получал повторное событие входа
  /// (автогид перезапускал/переключал трек). Признак «разрешение
  /// уже было» — живая подписка на поток позиций.
  ///
  /// A6/A10/A11 (18-й проход): разовая позиция не обрабатывается
  /// дважды (общий поток доставляет её сам), «далеко от региона»
  /// не уводит камеру в пустоту, ошибки камеры не роняют тик.
  Future<void> _locateMe() async {

    AppLogger.info('[MapWidget] _locateMe called, _locating=$_locating');

    // Повторный тап во время поиска — отмена (A5).
    if (_locating) {

      _locateGeneration++;

      _setLocating(false);

      return;
    }

    // Запрос разрешения уже идёт (Б11): повторный тап игнорируем.
    if (_permissionRequestInFlight) {

      return;
    }

    final wasTracking = _positionSub != null;

    final location =
        ref.read(locationServiceProvider);

    final status = await _ensurePermissionGuarded();

    if (status == null) {
      return;
    }

    AppLogger.info(
      '[MapWidget] _locateMe status=$status',
    );

    if (!mounted) {
      return;
    }

    if (status == LocationPermissionStatus.unknown) {

      _showPermissionHint(status);

      return;
    }

    if (status != LocationPermissionStatus.granted) {

      _showPermissionHint(status);

      _setLocationStatus(_statusFromPermission(status));

      return;
    }

    if (!wasTracking) {
      _handlePermissionGranted(invalidateAutoGuide: true);
    } else if (gpsStatus.status == MapLocationStatus.noPermission ||
        gpsStatus.status == MapLocationStatus.deniedForever ||
        gpsStatus.status == MapLocationStatus.serviceOff) {
      // Плашка могла остаться видимой, если разрешение выдали
      // в системных настройках мимо приложения. Статусы
      // точности/сигнала не трогаем — ими управляют свои тики.
      _setLocationStatus(MapLocationStatus.none);
    }

    _setLocating(true);

    final generation = ++_locateGeneration;

    try {

      final result = await location.currentPosition();

      // Отмена по повторному тапу: результат устаревшего запроса
      // не применяется.
      if (!mounted || generation != _locateGeneration) {

        AppLogger.info('[MapWidget] _locateMe canceled (generation)');

        return;
      }

      switch (result) {

        case LocatePosition(:final position):

          AppLogger.info('[MapWidget] _locateMe position received');

          if (!mounted) {
            return;
          }

          // A6 (18-й проход): при живой подписке фикс уже
          // обработан общим потоком (сервис пушит разовую
          // позицию в него) — прямой вызов дублировал обработку
          // (двойной пересчёт курса, две записи маркера).
          if (_positionSub == null) {

            _onPosition(position);
          }

          // A10: далеко от всех карт региона — не летим в
          // пустоту, даём осознанный выбор.
          final far = await _isFarFromMappedRegion(position);

          if (!mounted || generation != _locateGeneration) {
            return;
          }

          if (far) {

            showAppSnackBar(
              context,
              'Вы далеко от карты региона — здесь нет наших '
              'маршрутов и точек',
              actionLabel: 'Всё равно показать',
              onAction: () {

                if (!mounted) {
                  return;
                }

                _presentLocated(position);
              },
            );

            break;
          }

          _presentLocated(position);

        case LocateTimeout():

          if (mounted) {

            showAppSnackBar(
              context,
              'GPS отвечает слишком долго — возможно, вы в помещении. '
              'Попробуйте под открытым небом',
            );
          }

        case LocatePermissionDenied():

          if (mounted) {

            _showPermissionHint(LocationPermissionStatus.denied);

            _setLocationStatus(MapLocationStatus.noPermission);
          }

        case LocateServiceOff():

          if (mounted) {

            _showPermissionHint(LocationPermissionStatus.serviceOff);

            if (gpsStatus.serviceTurnedOff()) {
          setState(() {});
        }
          }

        case LocateUnavailable():

          if (mounted) {

            showAppSnackBar(
              context,
              'Не удалось определить текущую позицию. '
              'Проверьте сигнал GPS',
            );
          }
      }

    } finally {

      if (mounted && generation == _locateGeneration) {

        _setLocating(false);
      }
    }
  }


  /// Успешно определённая позиция: слежение + подлёт камеры
  /// (зум не ниже 15 — в «всех регионах» точка иначе
  /// неразличима среди кластеров).
  void _presentLocated(UserPosition position) {

    if (!mounted) {
      return;
    }

    // По успеху — режим слежения (B2): кнопка заливается,
    // карта держит пользователя в центре.
    _setFollowing(true);

    unawaited(_flyToPosition(position));
  }


  /// Подлёт камеры к позиции (A11, 18-й проход: ошибки камеры
  /// глушатся — контроллер мог уже уничтожаться).
  Future<void> _flyToPosition(UserPosition position) async {

    final controller = _controller;

    if (controller == null) {
      return;
    }

    try {

      final camera = await controller.queryCameraPosition();

      final zoom = max(camera?.zoom ?? 15.0, 15.0);

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(
            position.latitude,
            position.longitude,
          ),
          zoom,
        ),
      );

    } catch (error) {

      AppLogger.warning('[MapWidget] fly camera failed: $error');
    }
  }


  /// Спиннер поиска на кнопке GPS (A5).
  void _setLocating(bool locating) {

    if (_locating == locating) {
      return;
    }

    setState(() {
      _locating = locating;
    });
  }


  /// Тап по кнопке GPS в режиме слежения (B2/B3, 18-й проход):
  /// слежение+север → «по курсу» → снова север.
  Future<void> _resetBearingToNorth() async {

    await _animateCameraSafe(CameraUpdate.bearingTo(0));
  }


  /// Приближает карту (увеличивает масштаб).
  Future<void> _zoomIn() async {
    await _controller?.animateCamera(CameraUpdate.zoomIn());
  }


  /// Отдаляет карту (уменьшает масштаб).
  Future<void> _zoomOut() async {
    await _controller?.animateCamera(CameraUpdate.zoomOut());
  }
}
