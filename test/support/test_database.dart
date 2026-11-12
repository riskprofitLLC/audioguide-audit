import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/services/database_service.dart';


/// Инициализирует SQLite на временную директорию для виджет-тестов,
/// рендерящих `HomePage`/POI-провайдеры.
///
/// После перехода на чтение контента из SQLite такие тесты идут в
/// `ContentSeeder.ensureSeeded` → `DatabaseService.instance`, поэтому
/// база должна быть открыта заранее, иначе — `StateError`.
///
/// Вызывается в `main()` теста (не в теле testWidgets): `setUp`/`tearDown`
/// выполняются вне FakeAsync-зоны, реальные асинхронные операции допустимы.

void initTestDatabase() {

  // Мок канала geolocator (13-й проход): MapPage-тесты pump'ят
  // карту, та проверяет разрешение — реальный invokeMethod под
  // FakeAsync не отвечает, а таймаут-фикс шлюза (5 с) оставляет
  // висячий таймер после конца теста («A Timer is still
  // pending»). Отвечаем мгновенно: служба включена, доступ
  // не выдан.
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
        case 'requestPermission':
          return 1; // LocationPermission.denied
        case 'getLastKnownPosition':
        case 'getCurrentPosition':
          return null;
        default:
          return null;
      }
    },
  );

  Directory? tempDir;

  setUp(() async {

    final dir = await Directory.systemTemp.createTemp(
      'island_guide_test_',
    );

    tempDir = dir;

    await DatabaseService.instance.initialize(
      databaseDirectory: dir.path,
    );
  });

  tearDown(() {

    DatabaseService.instance.close();

    tempDir?.deleteSync(recursive: true);

    tempDir = null;
  });
}