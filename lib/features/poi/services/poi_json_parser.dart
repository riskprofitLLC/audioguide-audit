import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/poi.dart';

/// Разбирает poi.json в список [Poi] через `compute`.
///
/// poi.json бывает крупным (bay — 122 КБ): синхронный jsonDecode на
/// главном изоляте подвешивал первый кадр карты «все регионы»
/// (9 локаций подряд). На web `compute` выполняется синхронно —
/// это ок (изолятов нет) (P1-3, 6-й проход).
Future<List<Poi>> parsePoisJson(String raw) {
  return compute(_parsePoisJson, raw);
}

List<Poi> _parsePoisJson(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;

  final pois = list
      .whereType<Map<String, dynamic>>()
      .map(Poi.fromJson)
      .toList();

  validateUniquePoiIds(pois);

  return pois;
}
