import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/models/manifest.dart';
import '../../content/providers/content_providers.dart';
import '../models/weather.dart';
import '../services/open_meteo_weather_gateway.dart';
import '../services/weather_gateway.dart';

/// Платформенный шлюз погоды (П7, 12-й проход).
final weatherGatewayProvider = Provider<WeatherGateway>((ref) {
  final gateway = OpenMeteoWeatherGateway();

  ref.onDispose(gateway.close);

  return gateway;
});

/// Точка локации для запроса погоды: центр карты из манифеста,
/// иначе центр границ (П7).
double? _weatherLatitude(Manifest? manifest) {
  return manifest?.mapCenter?.lat ?? _boundsCenter(manifest)?.$1;
}

double? _weatherLongitude(Manifest? manifest) {
  return manifest?.mapCenter?.lng ?? _boundsCenter(manifest)?.$2;
}

(double, double)? _boundsCenter(Manifest? manifest) {
  final bounds = manifest?.islandBounds ?? manifest?.mapBounds;

  if (bounds == null) {
    return null;
  }

  // (широта, долгота) — центр прямоугольника локации.
  return (
    (bounds.north + bounds.south) / 2,
    (bounds.west + bounds.east) / 2,
  );
}

// Кеш ответов: координаты → (время, данные). TTL — 30 минут:
// погода не та переменная, чтобы дёргать API на каждый экран.
final _cache = <String, ({DateTime at, LocationWeather weather})>{};

const _cacheTtl = Duration(minutes: 30);

/// Общий запрос погоды по координатам. [force] — игнорировать
/// кеш: кнопка «Обновить» шторки POI просит свежие данные.
Future<LocationWeather?> _fetchWeather(
  Ref ref,
  double lat,
  double lng, {
  bool force = false,
}) async {
  final key = '$lat,$lng';

  final cached = _cache[key];

  final now = DateTime.now();

  if (!force && cached != null && now.difference(cached.at) < _cacheTtl) {
    return cached.weather;
  }

  // Пункт 6: шлюз читается read'ом — провайдеры-вызывающие
  // держат его watch до первого await (см. locationWeatherProvider).
  final gateway = ref.read(weatherGatewayProvider);

  final weather = await gateway.fetch(lat, lng);

  if (weather != null) {
    _cache[key] = (at: now, weather: weather);
  }

  return weather;
}

/// Сброс кеша погоды (только тесты).
void clearWeatherCache() {
  _cache.clear();
}

/// Погода ТЕКУЩЕЙ локации (П7): онлайн-обогащение поверх
/// офлайн-ядра — нет сети/API — значение `null`, интерфейс
/// просто не показывает чип.
final locationWeatherProvider =
    FutureProvider.autoDispose<LocationWeather?>((ref) async {
  // watch держит шлюз живым/реактивным до первого await;
  // само значение шлюзу не нужно — его возьмёт _fetchWeather.
  ref.watch(weatherGatewayProvider);

  final manifest = await ref.watch(islandContentProvider.future);

  final lat = _weatherLatitude(manifest);
  final lng = _weatherLongitude(manifest);

  if (lat == null || lng == null) {
    return null;
  }

  return _fetchWeather(ref, lat, lng);
});

/// Погода КОНКРЕТНОЙ точки (страница POI): запрос по требованию
/// с координатами самой достопримечательности. `gen` — счётчик
/// обновлений: рост `gen` создаёт новый инстанс провайдера,
/// принудительно перезапрашивая API мимо кеша (кнопка
/// «Обновить»).
final poiWeatherProvider = FutureProvider.autoDispose
    .family<LocationWeather?, ({double lat, double lng, int gen})>(
        (ref, point) {
  ref.watch(weatherGatewayProvider);

  return _fetchWeather(ref, point.lat, point.lng, force: point.gen > 0);
});
