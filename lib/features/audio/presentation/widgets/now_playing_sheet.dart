import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router.dart' show AppRouter;
import '../../../../app/theme.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/skeleton.dart';
import 'audio_guide_player.dart';
import '../../providers/audio_player_provider.dart';
import '../../../content/models/region_catalog.dart';
import '../../../content/providers/content_providers.dart';
import '../../../poi/models/poi.dart';
import '../../../poi/utils/poi_category.dart';

/// Шторка «Сейчас играет» (B5.2, 8-й проход).
///
/// Открывается тапом по мини-плееру: обложка POI, название,
/// полноценная дорожка (волна, время, ±10 с, скорость),
/// «Перейти к точке» и «Остановить». Мини-плеер остаётся
/// компактным.
///
/// B2 (10-й проход): каркас — единый AppBottomSheet (ручка,
/// шапка с заголовком, радиус, регистрация в
/// modalSheetOpenCount).
Future<void> showNowPlayingSheet(BuildContext context) {
  return showAppBottomSheet(
    context,
    title: 'Сейчас играет',
    heightFactor: 0.92,
    builder: (sheetContext) => const _NowPlayingSheet(),
  );
}

class _NowPlayingSheet extends ConsumerStatefulWidget {
  const _NowPlayingSheet();

  @override
  ConsumerState<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends ConsumerState<_NowPlayingSheet> {
  String? _file;

  StreamSubscription<String?>? _fileSub;

  /// Шторку уже закрыли кнопкой («Остановить»/«Перейти к точке») —
  /// второму pop изнутри не должно быть (баг 2, замечания
  /// Sonnet): слушатель currentFileStream получал null после
  /// stop() и, пока роут ещё закрывается (mounted == true),
  /// доезжал до pop() — он снимал уже ЧУЖОЙ роут (страницу точки
  /// или шелл).
  bool _closing = false;

  /// Закрыть шторку ОДИН раз — из кнопок.
  void _closeSheet() {
    if (_closing || !mounted) {
      return;
    }

    _closing = true;

    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();

    final service = ref.read(audioPlayerServiceProvider);

    // Живой поток файла вместо замершего снапшота сервиса (A2):
    // шторка обновляется на смену трека и закрывается на stop —
    // мёртвый контент больше не висит. Play/pause рисует
    // вложенный AudioGuidePlayer — он подписан сам.
    _file = service.currentFile;

    _fileSub = service.currentFileStream.listen((file) {
      if (!mounted) return;

      // Трек остановлен извне (крестик пилюли, шторка точки) —
      // шторка закрывается сама (A2). Но только если она ещё
      // верхний роут и не закрывается кнопками (баг 2): иначе
      // pop уходит чужому маршруту.
      if (file == null) {
        if (_closing) {
          return;
        }

        final route = ModalRoute.of(context);

        if (route == null || !route.isCurrent) {
          return;
        }

        _closing = true;

        Navigator.of(context).pop();

        return;
      }

      if (_closing) {
        return;
      }

      setState(() {
        _file = file;
      });
    });
  }

  @override
  void dispose() {
    _fileSub?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final file = _file;

    if (file == null) {
      return const SizedBox.shrink();
    }

    // Локация из пути ассета: content/<регион>/<локация>/audio/…
    final parts = file.split('/');

    if (parts.length < 5 || parts.first != 'content') {
      return const SizedBox.shrink();
    }

    final locationId = parts[2];

    final poisAsync = ref.watch(poisFamily(locationId));

    final Poi? poi = poisAsync.value
        ?.where((p) => p.audioPath != null && p.audioAssetPath(locationId) == file)
        .firstOrNull;

    if (poi == null) {
      return const SizedBox.shrink();
    }

    final height = MediaQuery.sizeOf(context).height;

    // Каркас (ручка/шапка/скролл с нижним отступом над капсулой) —
    // единый AppBottomSheet; тело строит только контент шторки.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height * 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Обложка POI (B5.2: крупная).
          AspectRatio(
            aspectRatio: 1.6,
            child: _NowPlayingCover(
              poi: poi,
              locationId: locationId,
            ),
          ),
          const SizedBox(height: AppSpace.m),

          Text(
            poi.title,
            textAlign: TextAlign.center,
            style: AppText.h2.copyWith(
              color: AppPalette.of(context).onSurface,
            ),
          ),
          const SizedBox(height: AppSpace.xs),

          if (poi.category != null)
            Text(
              poiCategoryLabel(poi.category),
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppPalette.of(context).onSurfaceMuted,
              ),
            ),
          const SizedBox(height: AppSpace.m),

          // Полная дорожка: волна, время, ±10 с, скорость —
          // тот же виджет, что на странице точки.
          AudioGuidePlayer(
            assetPath: file,
            audioMs: poi.audioMs,
            wave: poi.wave,
          ),
          const SizedBox(height: AppSpace.m),

          // Wrap: на 360 px две кнопки в ряд не лезут
          // (переносятся на вторую строку).
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpace.s,
            runSpacing: AppSpace.xs,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  // Шторка закрывается; страница точки
                  // останавливать трек не должна.
                  _closeSheet();

                  // push, а не go (A4): стек сохраняется —
                  // «Назад» с открытой точки возвращает
                  // туда, откуда открыли шторку.
                  AppRouter.router.push(
                    '/poi/${poi.id}?island=$locationId',
                  );
                },
                icon: const Icon(LucideIcons.mapPin, size: 16),
                label: const Text('Перейти к точке'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  // Флаг ДО pop (баг 2): слушатель потока получит
                  // null после stop() и не должен добавить второй.
                  _closing = true;

                  ref.read(audioPlayerServiceProvider).stop();

                  _closeSheet();
                },
                icon: const Icon(LucideIcons.square, size: 14),
                label: const Text('Остановить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Обложка «Сейчас играет»: фото точки или бумажный глиф.
class _NowPlayingCover extends StatelessWidget {
  const _NowPlayingCover({required this.poi, required this.locationId});

  final Poi poi;

  final String locationId;

  @override
  Widget build(BuildContext context) {
    final imagePath = poi.imagePaths.isEmpty
        ? null
        : '${locationAssetBase(locationId)}/images/${poi.imagePaths.first}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.image),
      child: imagePath == null
          ? Container(
              color: AppPalette.of(context).sandLight,
              child: const Center(
                child: Icon(
                  LucideIcons.audioLines,
                  size: 44,
                  color: AppColors.depth,
                ),
              ),
            )
          : Image.asset(
              imagePath,
              fit: BoxFit.cover,
              // B4 (10-й проход): без прыжков раскладки — скелетон
              // до первого кадра.
              frameBuilder: skeletonFrameBuilder,
              errorBuilder: (_, _, _) => Builder(
                builder: (context) => Container(
                  color: AppPalette.of(context).sandLight,
                  child: const Center(
                    child: Icon(
                      LucideIcons.audioLines,
                      size: 44,
                      color: AppColors.depth,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
