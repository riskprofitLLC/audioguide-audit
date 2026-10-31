/// «Поделиться» GPX-треком (29-й проход, П5): на нативе — файл
/// через share_plus, на web — текст (Web Share API / буфер).
library;
export 'gpx_share_io.dart'
    if (dart.library.js_interop) 'gpx_share_web.dart';
