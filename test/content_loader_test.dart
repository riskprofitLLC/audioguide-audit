// Тесты ContentLoader: информативные ошибки загрузки манифеста.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/services/content_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const loader = ContentLoader();

  test('успешная загрузка валидного манифеста', () async {
    final manifest = await loader.loadManifest(
      'content/fethiye/gemiler/manifest.json',
    );

    expect(manifest.id, 'gemiler');
  });

  test('отсутствующий манифест — FormatException с путём файла', () async {
    expect(
      () => loader.loadManifest('content/fethiye/no-such/manifest.json'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.toString(),
          'toString',
          contains('content/fethiye/no-such/manifest.json'),
        ),
      ),
    );
  });
}