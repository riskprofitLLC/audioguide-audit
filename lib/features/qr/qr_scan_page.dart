import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import '../../core/widgets/glass_icon_button.dart';
import 'qr_poi_parser.dart';

/// Полноэкранный сканер QR-кодов точек аудиогида.
///
/// Сканирует печатные QR (tool/gen_qr.py) и открывает страницу
/// точки: `https://audioguide.layero.app/#/poi/poi-08?island=gemiler`
/// → роут `/poi/poi-08?island=gemiler`.
Future<void> showQrScanner(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const QrScanPage(),
      fullscreenDialog: true,
    ),
  );
}

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController();

  /// Защита от повторного срабатывания одного и того же кода.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }

    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;

    final route = parsePoiRouteFromQr(raw);

    if (route == null) {
      return;
    }

    _handled = true;

    Navigator.of(context).pop();

    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: const Text('Сканировать QR точки'),
        actions: [
          GlassIconButton(
            icon: LucideIcons.x,
            tooltip: 'Закрыть',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Затемнение с «окном» сканирования поверх.
          IgnorePointer(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.55),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: palette.accent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Наведите камеру на QR-код на стикере точки — откроется её страница',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onScrim,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
