/// Шлюз админки: без входа показывает экран пароля,
/// с входом — сразу редактор с оглавлением слева.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets.dart';
import 'admin_editor_page.dart';
import 'admin_login_page.dart';
import '../../search/models/search_index_entry.dart';
import '../../search/providers/search_providers.dart';
import '../providers/admin_providers.dart';

/// Внутренний виджет-шлюз: не авторизован — пароль, иначе контент.
class AdminGate extends ConsumerWidget {

  const AdminGate({super.key, this.islandId, this.poiId});

  final String? islandId;

  final String? poiId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final authed = ref.watch(adminAuthedProvider);

    if (!authed) {
      return const AdminLoginPage();
    }

    // Без выбранной точки — сразу открыть первую из индекса:
    // /admin должен показывать структуру и текст без лишнего клика.
    if (poiId == null || islandId == null) {

      final index = ref.watch(searchIndexProvider);

      return index.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: StatePlaceholder(
              icon: LucideIcons.cloudOff,
              title: 'Индекс не загрузился',
              description: '$e',
            ),
          ),
        ),
        data: (entries) {

          final pois = entries
              .where((e) => e.kind == SearchEntryKind.poi)
              .toList();

          if (pois.isEmpty) {
            return const Scaffold(
              body: Center(
                child: StatePlaceholder(
                  icon: LucideIcons.mapPinOff,
                  title: 'В индексе нет точек',
                ),
              ),
            );
          }

          // Память «с чего продолжить»: если запомненная точка
          // есть в индексе — открыть её, иначе первую (раньше
          // ВСЕГДА открывалась первая — замечание владельца).
          final last = ref.watch(adminLastPoiProvider);

          SearchIndexEntry? chosen;

          if (last != null) {

            final parts = last.split('/');

            if (parts.length == 2) {
              for (final entry in pois) {
                if (entry.locationId == parts[0] && entry.id == parts[1]) {
                  chosen = entry;

                  break;
                }
              }
            }
          }

          chosen ??= pois.first;

          return AdminEditorPage(
            // Тот же ключ, что у шлюза с явной точкой: смена
            // выбранной точки пересоздаёт редактор.
            key: ValueKey('${chosen.locationId}/${chosen.id}'),
            islandId: chosen.locationId,
            poiId: chosen.id,
          );
        },
      );
    }

    return AdminEditorPage(
      // Пункт 2 замечаний Sonnet: без ключа GoRoute.builder при
      // go() на ту же /admin/poi/:id переиспользовал State —
      // заголовок менялся, а текст и пути сохранения оставались
      // от прежней точки.
      key: ValueKey('$islandId/$poiId'),
      islandId: islandId!,
      poiId: poiId!,
    );
  }
}
