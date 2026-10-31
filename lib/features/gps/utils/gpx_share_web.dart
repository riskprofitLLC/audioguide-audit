import 'package:share_plus/share_plus.dart';

/// Web: shareXFiles не работает, отдаём GPX текстом
/// (Web Share API или копирование в буфер).
Future<void> shareGpx(String gpx, String name) async {
  await Share.share('$name\n\n$gpx');
}
