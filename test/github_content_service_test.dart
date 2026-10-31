/// Тесты GitHub-сервиса админ-панели на мок-клиенте http.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:island_guide/features/admin/services/github_content_service.dart';

/// Мок-клиент, ведущий себя как GitHub: состояния в памяти.
http.Client _mockClient({

  Map<String, String> filesOnEdits = const {},
  Map<String, String> filesOnMain = const {},
  void Function(String method, Uri uri, String? body)? onRequest,
}) {
  return MockClient((request) async {

    onRequest?.call(request.method, request.url, request.body);

    final path = request.url.path;

    // /repos/{repo}/contents/{...}
    if (path.contains('/contents/') && request.method == 'GET') {

      final ref = request.url.queryParameters['ref'] ?? 'main';

      final relPath = path
          .split('/contents/')
          .last;

      final files = ref == 'content-edits'
          ? filesOnEdits
          : filesOnMain;

      final content = files[relPath];

      if (content == null) {
        return http.Response('{"message":"Not Found"}', 404);
      }

      return http.Response(
        jsonEncode({
          'content': base64.encode(utf8.encode(content)),
          'sha': 'file-sha-$ref',
        }),
        200,
      );
    }

    // /repos/{repo}/git/ref/heads/{branch}
    if (path.contains('/git/ref/heads/')) {

      final branch = path.split('/').last;

      if (branch == 'content-edits' && filesOnEdits.isEmpty) {
        return http.Response('{"message":"Not Found"}', 404);
      }

      return http.Response(
        jsonEncode({
          'object': {'sha': 'commit-1'},
        }),
        200,
      );
    }

    // /repos/{repo}/git/commits/{sha}
    if (path.contains('/git/commits/')) {
      return http.Response(
        jsonEncode({
          'tree': {'sha': 'tree-1'},
        }),
        200,
      );
    }

    // Создание blob/tree/commit и refs.
    if (request.method == 'POST') {
      return http.Response(
        jsonEncode({'sha': 'new-sha'}),
        201,
      );
    }

    if (request.method == 'PATCH') {
      return http.Response('{"sha":"new-sha"}', 200);
    }

    return http.Response('{"message":"Unexpected"}', 400);
  });
}

GitHubContentService _service(http.Client client) {
  return GitHubContentService(
    token: 'test-token',
    repo: 'owner/repo',
    client: client,
  );
}

void main() {

  group('fetchFile', () {

    test('предпочитает ветку правок', () async {

      final service = _service(
        _mockClient(
          filesOnEdits: {'content/x/poi.json': 'edits'},
          filesOnMain: {'content/x/poi.json': 'main'},
        ),
      );

      final file = await service.fetchFile('content/x/poi.json');

      expect(file!.content, 'edits');
      expect(file.fromEditsBranch, isTrue);
    });

    test('фолбэк на базовую ветку', () async {

      final service = _service(
        _mockClient(filesOnMain: {'content/x/poi.json': 'main'}),
      );

      final file = await service.fetchFile('content/x/poi.json');

      expect(file!.content, 'main');
      expect(file.fromEditsBranch, isFalse);
    });

    test('нет файла нигде — null', () async {

      final service = _service(_mockClient());

      expect(
        await service.fetchFile('content/x/poi.json'),
        isNull,
      );
    });

    test('каждый GET уходит с cache-buster — свежая версия файла', () async {

      final nocacheValues = <String>[];

      final service = _service(
        _mockClient(
          filesOnEdits: {'content/x/a.md': 'v1'},
          onRequest: (method, uri, body) {
            final v = uri.queryParameters['_nocache'];
            if (method == 'GET' && v != null) {
              nocacheValues.add(v);
            }
          },
        ),
      );

      await service.fetchFile('content/x/a.md');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.fetchFile('content/x/a.md');

      expect(nocacheValues.length, 2);
      expect(nocacheValues[0], isNot(nocacheValues[1]));
      expect(int.tryParse(nocacheValues[0]), isNotNull);
    });
  });

  group('commitFiles', () {

    test('полный цикл: blob → tree → commit → ref', () async {

      final calls = <String>[];

      final service = _service(
        _mockClient(
          filesOnEdits: {'content/x/poi.json': 'old'},
          onRequest: (method, uri, body) {
            calls.add('$method ${uri.path}');
          },
        ),
      );

      await service.commitFiles(
        const [
          GhCommitFile(path: 'content/x/poi.json', content: 'новый'),
        ],
        'Правка',
      );

      final paths = calls.map((c) => c.split(' ')[1]).toList();

      expect(
        paths.any((p) => p.contains('/git/blobs')),
        isTrue,
      );

      expect(
        paths.any((p) => p.contains('/git/trees')),
        isTrue,
      );

      expect(
        paths.any((p) => p.contains('/git/commits')),
        isTrue,
      );

      expect(
        paths.any(
          (p) => p.endsWith('/git/refs/heads/content-edits'),
        ),
        isTrue,
      );
    });

    test('пустой список — никаких запросов', () async {

      final calls = <String>[];

      final service = _service(
        _mockClient(
          onRequest: (method, uri, body) {
            calls.add(uri.path);
          },
        ),
      );

      await service.commitFiles(const [], 'x');

      expect(calls, isEmpty);
    });
  });

  test('без токена fetchFile возвращает null, а не 401', () async {
    final service = GitHubContentService(
      token: '',
      repo: 'test/test',
      client: MockClient((request) async {
        fail('сеть не должна дёргаться без токена');
      }),
    );

    final result = await service.fetchFile('content/x/text/a.md');

    expect(result, isNull);
  });

  test('без токена commitFiles бросает внятную ошибку', () async {
    final service = GitHubContentService(
      token: '',
      repo: 'test/test',
      client: MockClient((request) async => http.Response('401', 401)),
    );

    await expectLater(
      service.commitFiles(
        const [GhCommitFile(path: 'a.json', content: '{}')],
        'msg',
      ),
      throwsA(
        isA<GitHubException>().having(
          (e) => e.message,
          'message',
          contains('Токен GitHub не задан'),
        ),
      ),
    );
  });
}
