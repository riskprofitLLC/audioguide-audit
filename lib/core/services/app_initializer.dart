import 'package:flutter/foundation.dart';

import '../utils/logger.dart';

import 'database_service.dart';


class AppInitializer {


  AppInitializer._();


  /// Ошибка инициализации сервисов (SQLite и т.п.).
  ///
  /// `null` — инициализация прошла успешно (или не требовалась, например
  /// на web). Из неё `initErrorProvider` показывает баннер на главном
  /// экране с кнопкой «Повторить» — вместо молчаливой деградации, когда
  /// приложение стартует, но репозитории падают или возвращают пустые
  /// списки (например, база не открылась).
  static Object? lastError;



  static Future<void> initialize() async {

    AppLogger.info(
      'Application initialization started',
    );


    try {

      await _initializeServices();

    } catch (error, stackTrace) {

      AppLogger.error(
        'Ошибка инициализации',
        error: error,
        stackTrace: stackTrace,
      );

      lastError = error;

    }


    AppLogger.info(
      'Application initialization completed',
    );

  }


  /// Повторяет инициализацию сервисов после сбоя (кнопка «Повторить»
  /// на баннере главного экрана).
  ///
  /// Сбрасывает [lastError], пробует инициализироваться заново и
  /// возвращает новую ошибку (или `null` при успехе). Вызывающий
  /// обязан занести результат в `initErrorProvider`, чтобы баннер
  /// обновился.
  static Future<Object?> retry() async {

    lastError = null;

    try {

      await _initializeServices();

    } catch (error, stackTrace) {

      AppLogger.error(
        'Ошибка повторной инициализации',
        error: error,
        stackTrace: stackTrace,
      );

      lastError = error;

    }

    return lastError;
  }




  static Future<void> _initializeServices() async {

    // Инициализация локальной базы данных (SQLite).
    //
    // На web пакет sqlite3 не работает (dart:ffi),
    // поэтому там база пропускается.

    if (kIsWeb) {

      AppLogger.warning(
        'Web: SQLite недоступен, база не инициализируется',
      );

      return;
    }

    await DatabaseService.instance.initialize();

    AppLogger.info(
      'SQLite database initialized',
    );

    // Здесь позже будут:

    // - подготовка хранилища;
    // - проверка стартового острова;
    // - миграции данных;
    // - подготовка настроек.

  }

}
