import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Сохраняет GPX во временный файл и открывает шторку «Поделиться».
Future<void> shareGpx(String gpx, String name) async {
  final dir = await getTemporaryDirectory();

  final stamp = DateTime.now().millisecondsSinceEpoch;

  final file = File('${dir.path}/$stamp.gpx');

  await file.writeAsString(gpx, flush: true);

  await Share.shareXFiles(
    [XFile(file.path)],
    subject: name,
    text: name,
  );
}
