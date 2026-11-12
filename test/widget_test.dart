// Базовый smoke-тест приложения.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets('Приложение запускается без ошибок', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Стартовый остров (Исторический «первый = стартовый» — Гемилер).
        // Пакет bay на старте не грузим: его poi.json (>100KB) виснет
        // в rootBundle.loadString под FakeAsync (см. AGENTS.md).
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
        child: const IslandGuideApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(IslandGuideApp), findsOneWidget);

    // Прогоняем таймер сплэш-экрана (2 сек) до перехода на /home.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
