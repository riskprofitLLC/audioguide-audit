import '../models/poi.dart';


/// Результат разделения точек интереса на «с номером» и «без номера».
///
/// Единый примитив, который используют и отображение
/// ([sortPoisForDisplay]), и нумерация файлов текстов/аудио
/// ([folderNumberFor]) — чтобы номер
/// в папке `text/NN - …` не разъезжался с номером на карте.
typedef PoiPartition = ({
  List<Poi> numbered,
  List<Poi> unnumbered,
  int maxNumber,
});


/// Разделяет POI на «пронумерованные» (по возрастанию [Poi.number])
/// и «без номера» (в исходном порядке `poi.json`). Отдаёт максимальный
/// явный номер (0, если пронумерованных нет) — от него продолжается
/// нумерация ненумерованных при именовании файлов.
PoiPartition partitionPoisForDisplay(
  Iterable<Poi> pois,
) {

  final numbered = <Poi>[];
  final unnumbered = <Poi>[];

  var maxNumber = 0;

  for (final poi in pois) {

    final num = poi.number;

    if (num == null) {

      unnumbered.add(poi);

    } else {

      numbered.add(poi);

      if (num > maxNumber) {
        maxNumber = num;
      }
    }
  }

  numbered.sort((a, b) => a.number!.compareTo(b.number!));

  return (
    numbered: numbered,
    unnumbered: unnumbered,
    maxNumber: maxNumber,
  );
}


/// Сортирует точки интереса для показа: сначала «пронумерованные»
/// (у которых есть [Poi.number]) по возрастанию номера, затем все
/// остальные в исходном порядке `poi.json`.
List<Poi> sortPoisForDisplay(
  Iterable<Poi> pois,
) {

  final partition = partitionPoisForDisplay(pois);

  return [...partition.numbered, ...partition.unnumbered];
}


/// Номер файла в папке `text/` для POI: пронумерованные — свой
/// [Poi.number], внемаршрутные — `maxNumber+1, +2…` в порядке
/// следования в `poi.json`. Повторяет логику `folder_numbers` из
/// `tool/sync_texts.py`. 0 — POI не найден.
int folderNumberFor(String poiId, Iterable<Poi> pois) {

  final partition = partitionPoisForDisplay(pois);

  final byNumber = <String, int>{
    for (final poi in partition.numbered) poi.id: poi.number!,
  };

  var nextNumber = partition.maxNumber + 1;

  for (final poi in partition.unnumbered) {

    if (poi.id == poiId) {
      return nextNumber;
    }

    nextNumber += 1;
  }

  return byNumber[poiId] ?? 0;
}