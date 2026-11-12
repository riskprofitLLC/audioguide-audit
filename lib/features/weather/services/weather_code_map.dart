/// Перевод кодов погоды сторонних источников в WMO-коды,
/// которые понимает [weatherGlyph]. Open-Meteo отдаёт WMO
/// напрямую, поэтому карты нужны только резервным шлюзам:
/// wttr.in — коды WorldWeatherOnline, met.no — текстовые
/// symbol_code.
library;

/// WorldWeatherOnline (wttr.in) → WMO.
int wwoToWmo(int code) {
  switch (code) {
    case 113:
      return 0;
    case 116:
      return 2;
    case 119:
    case 122:
      return 3;
    case 143:
    case 248:
      return 45;
    case 260:
      return 48;
    case 176:
      return 80;
    case 179:
    case 227:
    case 323:
    case 326:
      return 71;
    case 182:
    case 311:
    case 317:
      return 66;
    case 185:
    case 281:
      return 56;
    case 200:
    case 386:
    case 392:
      return 95;
    case 230:
    case 335:
    case 338:
      return 75;
    case 263:
      return 51;
    case 266:
      return 53;
    case 284:
      return 57;
    case 293:
    case 296:
      return 61;
    case 299:
    case 302:
      return 63;
    case 305:
    case 308:
      return 65;
    case 314:
    case 320:
      return 67;
    case 329:
    case 332:
      return 73;
    case 350:
    case 374:
    case 377:
      return 77;
    case 353:
      return 80;
    case 356:
      return 81;
    case 359:
      return 82;
    case 362:
    case 368:
      return 85;
    case 365:
    case 371:
      return 86;
    case 389:
    case 395:
      return 96;
    default:
      return 2;
  }
}

/// met.no symbol_code → WMO. Порядок проверок важен:
/// «lightrainshowers» содержит «rainshowers», поэтому
/// уточняющие префиксы идут раньше общих.
int metNoSymbolToWmo(String symbol) {
  if (symbol.contains('thunder')) {
    return 95;
  }

  if (symbol.contains('clearsky')) {
    return 0;
  }

  if (symbol.contains('fair')) {
    return 1;
  }

  if (symbol.contains('partlycloudy')) {
    return 2;
  }

  if (symbol.contains('cloudy')) {
    return 3;
  }

  if (symbol.contains('fog')) {
    return 45;
  }

  if (symbol.contains('heavyrainshowers')) {
    return 82;
  }

  if (symbol.contains('lightrainshowers')) {
    return 80;
  }

  if (symbol.contains('rainshowers')) {
    return 81;
  }

  if (symbol.contains('heavysnowshowers')) {
    return 86;
  }

  if (symbol.contains('snowshowers')) {
    return 85;
  }

  if (symbol.contains('heavysleet')) {
    return 67;
  }

  if (symbol.contains('lightsleet')) {
    return 66;
  }

  if (symbol.contains('sleet')) {
    return 66;
  }

  if (symbol.contains('heavyrain')) {
    return 65;
  }

  if (symbol.contains('lightrain')) {
    return 61;
  }

  if (symbol.contains('rain')) {
    return 63;
  }

  if (symbol.contains('heavysnow')) {
    return 75;
  }

  if (symbol.contains('lightsnow')) {
    return 71;
  }

  if (symbol.contains('snow')) {
    return 73;
  }

  if (symbol.contains('drizzle')) {
    return 53;
  }

  return 2;
}
