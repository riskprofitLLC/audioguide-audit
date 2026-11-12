// Тест: полный текст POI читается из text/NN - Title.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';

import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets('poiFullTextProvider читает текст из .md (gemiler poi-01)',
      (tester) async {
    String? result;
    var done = false;

    await tester.pumpWidget(
      ProviderScope(
        child: _Probe(
          onResult: (value) {
            result = value;
            done = true;
          },
        ),
      ),
    );

    await tester.runAsync(() async {
      // ждём завершения провайдеров
      while (!done) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    expect(done, isTrue);
    expect(result, isNotNull);
    expect(result!.isNotEmpty, isTrue);
  });
}

class _Probe extends ConsumerWidget {
  const _Probe({required this.onResult});

  final void Function(String? value) onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(
      poiFullTextProvider(
        (islandId: 'gemiler', poiId: 'poi-01'),
      ),
    );
    text.when(
      data: (value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onResult(value);
        });
      },
      error: (e, _) => onResult(null),
      loading: () {},
    );
    return const SizedBox.shrink();
  }
}
