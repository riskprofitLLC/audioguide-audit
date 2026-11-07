/// Сервис правок контента через GitHub API.
///
/// Админ-панель сохраняет тексты коммитом в ветку `content-edits`.
/// Приложение на Layero ничего хранить не может — GitHub здесь
/// единственное хранилище правок. Мы потом забираем ветку,
/// переозвучиваем и деплоим.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Один файл для коммита.
class GhCommitFile {

  const GhCommitFile({required this.path, required this.content});

  /// Путь в репозитории: `content/fethiye/gemiler/poi.json`.
  final String path;

  /// Новое содержимое файла (UTF-8).
  final String content;
}

/// Содержимое файла из репозитория.
class GhFileContent {

  const GhFileContent({
    required this.content,
    required this.sha,
    required this.fromEditsBranch,
  });

  /// Сырой текст файла (UTF-8).
  final String content;

  /// SHA файла.
  final String sha;

  /// Файл взят из ветки правок (правка ещё не опубликована).
  final bool fromEditsBranch;
}

class GitHubContentService {

  GitHubContentService({
    required this.token,
    required this.repo,
    this.branch = 'content-edits',
    this.baseBranch = 'main',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String token;

  /// Репозиторий в формате `owner/name`.
  final String repo;

  /// Ветка правок (создаётся автоматически при первом сохранении).
  final String branch;

  /// Базовая ветка: откуда читаем, если правок ещё не было.
  final String baseBranch;

  final http.Client _client;

  /// Таймаут одного HTTP-запроса: редактором пользуются с борта,
  /// сеть может вешаться — без таймаута спиннер «Сохранить» крутится
  /// вечно.
  static const _requestTimeout = Duration(seconds: 30);

  /// Читает файл: сначала ветка правок, потом базовая ветка.
  /// Возвращает null, если файла нет нигде (404 в обеих).
  ///
  /// Локальная сборка БЕЗ токена (see kAdminGithubToken): GitHub
  /// отдаёт 401 на приватный репозиторий — не бросаем ошибку,
  /// а возвращаем null: редактор падает на фолбэк к ассетам бандла
  /// и просмотр работает офлайн (сохранение при этом недоступно —
  /// commitFiles бросит внятную ошибку).
  Future<GhFileContent?> fetchFile(String path) async {

    if (token.isEmpty) {
      return null;
    }

    final fromEdits = await _fetchFrom(path, branch);

    if (fromEdits != null) {
      return fromEdits;
    }

    return _fetchFrom(path, baseBranch);
  }

  /// Список путей всех blob-файлов под префиксом `pathPrefix`
  /// (Git Trees API, recursive). Сначала ветка правок, при 404 —
  /// базовая ветка. Пустой список — пути нет ни в одной ветке.
  Future<List<String>> listTreeFiles(String pathPrefix) async {

    if (token.isEmpty) {
      return const [];
    }

    final fromEdits = await _listTreeFilesFrom(branch, pathPrefix);

    if (fromEdits != null) {
      return fromEdits;
    }

    return await _listTreeFilesFrom(baseBranch, pathPrefix) ?? const [];
  }

  /// Пути blob-файлов под префиксом из конкретной ветки
  /// (null — ветки или пути нет, 404).
  Future<List<String>?> _listTreeFilesFrom(String ref, String pathPrefix) async {

    final response = await _client
        .get(
          _apiGet(
            '/repos/$repo/git/trees/$ref:$pathPrefix?recursive=1',
          ),
          headers: _headers,
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw GitHubException(
        'trees $ref:$pathPrefix → ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;

    final tree = body['tree'] as List<Object?>? ?? const [];

    return [
      for (final entry in tree)
        if (entry is Map<String, Object?> && entry['type'] == 'blob')
          entry['path'] as String,
    ];
  }

  /// Коммит нескольких файлов одной ревизией (Git Data API):
  /// blobs → tree → commit → ref.
  Future<void> commitFiles(
    List<GhCommitFile> files,
    String message,
  ) async {
    await commitChanges(files: files, deletes: const [], message: message);
  }

  /// Коммит с созданием/перезаписью [files] и удалением [deletes]
  /// одной ревизией (Git Data API: blobs → tree → commit → ref;
  /// удаление — запись дерева с `sha: null`).
  Future<void> commitChanges({
    required List<GhCommitFile> files,
    required List<String> deletes,
    required String message,
  }) async {

    if (files.isEmpty && deletes.isEmpty) {
      return;
    }

    // Локальная сборка без токена: сохранять некуда — внятная
    // ошибка вместо 401-мусора от GitHub.
    if (token.isEmpty) {
      throw const GitHubException(
        'Токен GitHub не задан (соберите с --dart-define='
        'ADMIN_GITHUB_TOKEN=…), сохранение недоступно',
      );
    }

    final base = await _resolveBase();

    final treeEntries = <Map<String, Object?>>[];

    for (final file in files) {

      final blobSha = await _createBlob(file.content);

      treeEntries.add({
        'path': file.path,
        'mode': '100644',
        'type': 'blob',
        'sha': blobSha,
      });
    }

    // Удаление файла в Git Data API — запись дерева с sha: null.
    for (final path in deletes) {
      treeEntries.add({
        'path': path,
        'mode': '100644',
        'type': 'blob',
        'sha': null,
      });
    }

    final newTree = await _postJson('/repos/$repo/git/trees', {
      'base_tree': base.treeSha,
      'tree': treeEntries,
    });

    final commit = await _postJson('/repos/$repo/git/commits', {
      'message': message,
      'tree': newTree['sha'],
      'parents': [base.commitSha],
    });

    await _updateRef(commit['sha'] as String);
  }

  // --- внутреннее ---

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Uri _api(String path) => Uri.parse('https://api.github.com$path');

  /// GET с защитой от браузерного кеша: GitHub шлёт
  /// `Cache-Control: max-age=60`, редактору нужна свежая версия файла.
  Uri _apiGet(String path) {

    final sep = path.contains('?') ? '&' : '?';

    return Uri.parse(
      'https://api.github.com$path${sep}_nocache='
      '${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Читает файл из конкретной ветки (JSON: base64 + sha).
  Future<GhFileContent?> _fetchFrom(String path, String ref) async {

    final response = await _client
        .get(
          _apiGet('/repos/$repo/contents/$path?ref=$ref'),
          headers: _headers,
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw GitHubException(
        'GET $path [$ref] → ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;

    final encoded = body['content'] as String? ?? '';

    return GhFileContent(
      content: utf8.decode(
        base64.decode(encoded.replaceAll('\n', '')),
      ),
      sha: body['sha'] as String? ?? '',
      fromEditsBranch: ref == branch,
    );
  }

  Future<_RefHead> _resolveBase() async {

    final head = await _refHead(branch);

    if (head != null) {
      return head;
    }

    final baseHead = await _refHead(baseBranch);

    if (baseHead == null) {
      throw GitHubException('Ветка $baseBranch не найдена');
    }

    return baseHead;
  }

  /// Голова ветки (sha коммита и его дерева) или null, если ветки нет.
  Future<_RefHead?> _refHead(String ref) async {

    final response = await _client
        .get(
          _apiGet('/repos/$repo/git/ref/heads/$ref'),
          headers: _headers,
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw GitHubException(
        'ref $ref → ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;

    final object = body['object'] as Map<String, Object?>;

    final commitSha = object['sha'] as String;

    return _RefHead(
      commitSha: commitSha,
      treeSha: await _commitTreeSha(commitSha),
    );
  }

  Future<String> _commitTreeSha(String commitSha) async {

    final body = await _getJson(
      Uri.parse('https://api.github.com/repos/$repo/git/commits/$commitSha'),
    );

    final tree = body['tree'] as Map<String, Object?>;

    return tree['sha'] as String;
  }

  Future<String> _createBlob(String content) async {
    final body = await _postJson('/repos/$repo/git/blobs', {
      'content': base64.encode(utf8.encode(content)),
      'encoding': 'base64',
    });

    return body['sha'] as String;
  }

  Future<void> _updateRef(String commitSha) async {

    final existing = await _client
        .get(
          _apiGet('/repos/$repo/git/refs/heads/$branch'),
          headers: _headers,
        )
        .timeout(_requestTimeout);

    // Ветка правок ещё не существует — создаём указатель.
    if (existing.statusCode == 404) {
      await _postJson('/repos/$repo/git/refs', {
        'ref': 'refs/heads/$branch',
        'sha': commitSha,
      });

      return;
    }

    final response = await _client
        .patch(
          _api('/repos/$repo/git/refs/heads/$branch'),
          headers: _headers,
          body: jsonEncode({'sha': commitSha, 'force': false}),
        )
        .timeout(_requestTimeout);

    // GitHub отдаёт 200 на успешный PATCH.
    if (response.statusCode != 200) {
      throw GitHubException(
        'PATCH ref → ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<http.Response> _get(Uri uri) async {
    return _client
        .get(_apiGet(uri.path + (uri.hasQuery ? '?${uri.query}' : '')), headers: _headers)
        .timeout(_requestTimeout);
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {

    final response = await _get(uri);

    if (response.statusCode != 200) {
      throw GitHubException(
        '${uri.path} → ${response.statusCode}',
      );
    }

    return jsonDecode(response.body) as Map<String, Object?>;
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Object payload,
  ) async {

    final response = await _client
        .post(
          _api(path),
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw GitHubException(
        'POST $path → ${response.statusCode}: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, Object?>;
  }
}

class _RefHead {

  const _RefHead({required this.commitSha, required this.treeSha});

  /// SHA головного коммита ветки.
  final String commitSha;

  /// SHA дерева коммита (base_tree для нового дерева).
  final String treeSha;
}

class GitHubException implements Exception {

  const GitHubException(this.message);

  final String message;

  @override
  String toString() => 'GitHubException: $message';
}
