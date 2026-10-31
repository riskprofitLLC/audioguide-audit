/// Провайдеры админ-панели: конфиг GitHub, сервис, авторизация.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../settings/services/app_settings.dart';
import '../services/github_content_service.dart';

/// Пароль админ-панели. Безопасность осознанно простая:
/// одна строка, логина нет.
///
/// РЕШЕНИЕ ВЛАДЕЛЬЦА 28.10 (пункт 1 замечаний Sonnet): пароль-литерал
/// и токен в бандле — осознанный компромисс, долгосрочное закрытие —
/// серверный прокси (контракт в tool/admin_proxy/README.md). Меры:
/// роуты /admin* только в debug/ADMIN_ENABLED (ниже), дефолтные сборки
/// сканируются tool/check_bundle_secrets.sh (в verify.sh), при утечке
/// токена — ротация PAT в GitHub.
const kAdminPassword = 'misha';

/// Админка включена ТОЛЬКО в debug-сборках или с явным флагом
/// `--dart-define=ADMIN_ENABLED=true` (пункт 1 замечаний Sonnet,
/// компромисс до серверного прокси): в release-бандле для
/// посетителей роуты /admin* не регистрируются.
const kAdminEnabled = bool.fromEnvironment(
  'ADMIN_ENABLED',
  defaultValue: bool.fromEnvironment('dart.vm.product') == false,
);

/// Токен GitHub с правом записи в контент — задаётся при сборке:
/// `--dart-define=ADMIN_GITHUB_TOKEN=ghp_...`.
///
/// В prod-release токен ВШИТ в бандл по решению владельца 28.10
/// (админка работает с прода); в дефолтных/CI-сборках токена нет —
/// это контролирует tool/check_bundle_secrets.sh. Долгосрочно токен
/// уедёт на серверный прокси (tool/admin_proxy/README.md).
const kAdminGithubToken = String.fromEnvironment('ADMIN_GITHUB_TOKEN');

/// Репозиторий с контентом (`owner/name`).
const kAdminGithubRepo = String.fromEnvironment(
  'ADMIN_GITHUB_REPO',
  defaultValue: 'riskprofitLLC/audioguide',
);

final githubContentServiceProvider = Provider<GitHubContentService>((ref) {
  return GitHubContentService(
    token: kAdminGithubToken,
    repo: kAdminGithubRepo,
    client: http.Client(),
  );
});

/// Вход в админку: флаг персистится — повторный визит не
/// спрашивает пароль заново.
final adminAuthedProvider =
    NotifierProvider<AdminAuthedNotifier, bool>(AdminAuthedNotifier.new);

class AdminAuthedNotifier extends Notifier<bool> {

  static const _key = 'admin_ok';

  @override
  bool build() {
    return AppSettings().read(_key) == '1';
  }

  void signIn() {
    AppSettings().write(_key, '1');
    state = true;
  }
}

/// Последняя открытая в админке точка («локация/poi-XX»):
/// /admin без явных параметров открывает её, а не первую
/// из индекса (память «с чего продолжить»).
final adminLastPoiProvider =
    NotifierProvider<AdminLastPoiNotifier, String?>(AdminLastPoiNotifier.new);

class AdminLastPoiNotifier extends Notifier<String?> {

  static const _key = 'admin_last_poi';

  @override
  String? build() => AppSettings().read(_key);

  /// Запоминает точку после УСПЕШНОЙ загрузки редактора.
  void remember(String islandId, String poiId) {

    final value = '$islandId/$poiId';

    AppSettings().write(_key, value);

    if (state != value) {
      state = value;
    }
  }
}

/// Очередь правок имён (манифесты регионов/локаций), ожидающих
/// единой кнопки «Сохранить»: путь файла → готовый JSON.
final pendingRenamesProvider =
    NotifierProvider<PendingRenamesNotifier, Map<String, String>>(
        PendingRenamesNotifier.new);

class PendingRenamesNotifier extends Notifier<Map<String, String>> {

  @override
  Map<String, String> build() => {};

  /// Ставит правку манифеста в очередь (последняя по пути — победа).
  void put(String path, String content) {

    state = {...state, path: content};
  }

  /// Убирает правку из очереди (пункт A3 замечаний Sonnet:
  /// очередь видима пользователю, каждую правку можно отменить).
  void remove(String path) {

    if (!state.containsKey(path)) {
      return;
    }

    final next = Map<String, String>.of(state);

    next.remove(path);

    state = next;
  }

  void clear() {

    state = {};
  }
}
