/// Правки контента через серверный прокси на собственном сервере.
///
/// GitHub-репозиторий удалён (12.11.2026): правки живут в локальном
/// git на Frankfurt, клиент ходит только в прокси — токен и пароль
/// из бандла уходят. Контракт — `tool/admin_proxy/README.md`.
///
/// Наследник [GitHubContentService]: потребители (AdminContentOps,
/// редактор, CRUD) работают без изменений.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_content_service.dart';
import '../providers/admin_providers.dart' show kAdminPassword;

class ProxyAdminService extends GitHubContentService {

  /// [password] — пароль прокси; по умолчанию тот же, что и на экране
  /// входа ([kAdminPassword]), чтобы администратор знал один пароль.
  ProxyAdminService({
    required this.proxyUrl,
    String? password,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        password = password ?? kAdminPassword,
        super(token: '', repo: '');

  /// Базовый URL прокси, например `https://ednar.duckdns.org/audioguide/admin/api`.
  final String proxyUrl;

  /// Пароль входа: прокси обменивает его на сессионный токен.
  final String password;

  final http.Client _client;

  String? _token;

  static const _timeout = Duration(seconds: 30);

  @override
  Future<GhFileContent?> fetchFile(String path) async {
    final token = await _session();
    if (token == null) return null;

    final uri = Uri.parse('$proxyUrl/file')
        .replace(queryParameters: {'path': path});
    final res = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_timeout);

    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw StateError('прокси: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return GhFileContent(
      content: data['content'] as String? ?? '',
      sha: data['sha'] as String? ?? '',
      fromEditsBranch: data['fromEditsBranch'] as bool? ?? false,
    );
  }

  @override
  Future<void> commitFiles(
    List<GhCommitFile> files,
    String message,
  ) async {
    await commitChanges(files: files, deletes: const [], message: message);
  }

  @override
  Future<void> commitChanges({
    required List<GhCommitFile> files,
    required List<String> deletes,
    required String message,
  }) async {
    if (files.isEmpty && deletes.isEmpty) return;

    final token = await _session();
    if (token == null) {
      throw StateError('Не удалось авторизоваться в прокси админки');
    }

    final res = await _client.post(
      Uri.parse('$proxyUrl/commit'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'files': [
          for (final f in files) {'path': f.path, 'content': f.content},
        ],
        'message': message,
      }),
    ).timeout(_timeout);

    if (res.statusCode != 200) {
      throw StateError('прокси: ${res.statusCode} ${res.body}');
    }
  }

  /// Сеанс прокси: пароль обменивается на токен один раз.
  Future<String?> _session() async {
    if (_token != null) return _token;

    final res = await _client.post(
      Uri.parse('$proxyUrl/session'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'password': password}),
    ).timeout(_timeout);

    if (res.statusCode != 200) return null;
    _token = (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String?;
    return _token;
  }
}
