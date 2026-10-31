#!/usr/bin/env python3
"""Проверка регистрации контентных ассетов в pubspec.yaml.

Flutter пакует в asset-бандл только то, что перечислено в секции
`assets:` pubspec.yaml. Каталог (`content/.../audio/`) включает
только файлы НЕПОСРЕДСТВЕННО в нём — подпапки требуют своей
строки (flutter_tools читает каталоги через listSync() без
recursive). Новый регион/локацию нужно зарегистрировать вручную,
и легко забыть подпапку `images/no-way/poi-NN/` или нового
маршрута.

Скрипт проходит по `content/` и для каждого файла проверяет, есть
ли зарегистрированный путь, который его покрывает: точная запись
файла или ЕГО непосредственный родительский каталог. Выход != 0,
если найдены незарегистрированные файлы. Подключён в
`tool/verify.sh`. Самотест логики: `python3 tool/check_assets.py
--selftest`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONTENT = REPO / "content"
PUBSPEC = REPO / "pubspec.yaml"


def read_registered_assets() -> list[str]:
    """Возвращает список путей из секции `assets:` pubspec.yaml."""
    lines = PUBSPEC.read_text(encoding="utf-8").splitlines()
    in_assets = False
    entries: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped == "assets:":
            in_assets = True
            continue
        if not in_assets:
            continue
        if line.startswith("  ") or line.startswith("\t"):
            if stripped.startswith("- "):
                entries.append(stripped[2:].strip())
        else:
            # Секция закончилась (другая секция на верхнем уровне).
            break
    return entries


def build_covered_prefixes(entries: list[str]) -> tuple[set[str], set[str]]:
    """Разбивает записи на покрытые каталоги (`каталог/`) и файлы."""
    dirs: set[str] = set()
    files: set[str] = set()
    for entry in entries:
        if entry.endswith("/"):
            dirs.add(entry)
        else:
            files.add(entry)
    return dirs, files


def is_covered(
    rel: str,
    covered_dirs: set[str],
    covered_files: set[str],
) -> bool:
    """Покрыт ли файл (rel) зарегистрированным путём.

    Каталоги в `assets:` НЕ рекурсивны (flutter_tools читает их
    через listSync() без recursive): запись `images/no-way/`
    покрывает только файлы НЕПОСРЕДСТВЕННО в ней, а подпапки
    `poi-NN/` требуют своей строки. Поэтому файл покрыт, только
    если зарегистрирован ЕГО непосредственный родительский
    каталог (или сам файл). Прежняя проверка по всем предкам
    пропускала ту ошибку, ради которой скрипт написан —
    незарегистрированную подпапку нового POI (баг 10, замечания
    Sonnet).
    """
    if rel in covered_files:
        return True
    parent = Path(rel).parent.as_posix()
    if parent == ".":
        return False
    return parent + "/" in covered_dirs


def is_payload_file(rel: str) -> bool:
    """Является ли файл «контентом», который должен попасть в бандл.

    Проверяем только то, что реально грузит приложение:
    manifest.json/poi.json/trails.* в корне локации и всё под
    images/, audio/, text/. «Черновые» файлы (bay_texts.md в корне
    локации, каталог content/new/ с исходниками) не пакуются — их
    регистрация не требуется.

    Служебные каталоги `content/_*` (`_copy` — снимок фотографий,
    `_new`/`_tmp` — черновики) никогда не грузятся приложением,
    даже когда внутри есть `images/`, и в `assets:` не регистрируются.
    """
    parts = Path(rel).parts
    if any(p.startswith("_") for p in parts[1:-1]):
        return False
    if "images" in parts or "audio" in parts or "text" in parts:
        return True
    return (
        rel.startswith("content/")
        and len(parts) == 4
        and parts[3]
        in {"manifest.json", "poi.json", "trails.geojson", "trails.gpx",
            "search_index.json", "credits.json"}
    ) or (
        # Файлы РЕГИОНА: манифест и карта — тоже бандл.
        rel.startswith("content/")
        and len(parts) == 3
        and parts[2] in {"manifest.json", "map.pmtiles"}
    )


def validate_poi_audio_ms() -> list[str]:
    """У каждого POI с аудио обязателен audioMs (A8, 8-й проход).


    Длительность нужна плееру сразу — без неё он грузит весь mp3
    через rootBundle ради одной цифры. Проставляет
    tool/generate_audio.py (--durations-only тоже).
    """
    problems: list[str] = []
    for poi_path in sorted(CONTENT.glob("*/*/poi.json")):
        rel = poi_path.relative_to(REPO).as_posix()
        try:
            pois = json.loads(poi_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as error:
            problems.append(f"{rel}: не читается ({error})")
            continue
        for poi in pois:
            audio = poi.get("audio")
            if not audio:
                continue
            ms = poi.get("audioMs")
            if not isinstance(ms, int) or ms <= 0:
                problems.append(
                    f"{rel}: POI {poi.get('id')} с аудио без audioMs "
                    f"(запустите: python3 tool/generate_audio.py "
                    f"--durations-only)"
                )
    return problems


def validate_search_index_fresh() -> list[str]:
    """search_index.json каждой локации обязан существовать и не
    устареть (A10.2, 8-й проход): поиск больше не читает poi.json —
    протухший индекс молча теряет новые точки.

    Свежесть — по digest из build_search_index.py (poi.json +
    манифест + треки).
    """
    import hashlib

    problems: list[str] = []
    for loc_dir in sorted(CONTENT.glob("*/*/")):
        if not (loc_dir / "poi.json").exists():
            continue
        rel = (loc_dir / "search_index.json").relative_to(REPO).as_posix()
        digest = hashlib.sha256()
        for name in ["poi.json", "manifest.json", "trails.geojson"]:
            path = loc_dir / name
            if path.exists():
                digest.update(name.encode())
                digest.update(path.read_bytes())
        expected = digest.hexdigest()
        index_path = loc_dir / "search_index.json"
        if not index_path.exists():
            problems.append(
                f"{rel}: нет индекса (запустите: "
                f"python3 tool/build_search_index.py)"
            )
            continue
        try:
            index = json.loads(index_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as error:
            problems.append(f"{rel}: не читается ({error})")
            continue
        if index.get("source") != expected:
            problems.append(
                f"{rel}: устарел — контент изменился "
                f"(запустите: python3 tool/build_search_index.py)"
            )
    return problems


def run_selftest() -> int:
    """Самотест покрытия (баг 10): файл в НЕзарегистрированной
    подпапке зарегистрированного каталога обязан быть НЕ покрыт.

    Выход != 0, если логика is_covered снова стала «рекурсивной».
    """
    covered_dirs = {
        "content/x/images/",
        "content/x/images/no-way/",
        "content/x/images/no-way/poi-01/",
    }
    covered_files = {"content/x/poi.json"}
    failures: list[str] = []

    def check(rel: str, expected: bool) -> None:
        actual = is_covered(rel, covered_dirs, covered_files)
        if actual != expected:
            failures.append(
                f"{rel}: ожидалось covered={expected}, получено {actual}"
            )

    # Файл в зарегистрированной подпапке — покрыт.
    check("content/x/images/no-way/poi-01/a.jpg", True)
    # Файл в НЕзарегистрированной подпапке зарегистрированного
    # каталога — НЕ покрыт (главный кейс скрипта).
    check("content/x/images/no-way/poi-42/a.jpg", False)
    # Файл непосредственно в зарегистрированном каталоге — покрыт.
    check("content/x/images/cover.jpg", True)
    # Файл в НЕзарегистрированном подкаталоге — не покрыт.
    check("content/x/audio/no-way/01.mp3", False)
    # Точечная регистрация файла — покрыт.
    check("content/x/poi.json", True)
    # Чужой файл — не покрыт.
    check("content/x/manifest.json", False)

    if failures:
        print("Самотест is_covered провален:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print("Самотест is_covered: OK")
    return 0


def main() -> int:
    if "--selftest" in sys.argv:
        return run_selftest()

    if not CONTENT.is_dir():
        print("Нет каталога content/ — проверка пропущена", file=sys.stderr)
        return 0

    entries = read_registered_assets()
    covered_dirs, covered_files = build_covered_prefixes(entries)

    missing: list[str] = []
    for path in sorted(CONTENT.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(REPO).as_posix()
        if not is_payload_file(rel):
            continue
        if not is_covered(rel, covered_dirs, covered_files):
            missing.append(rel)

    metadata_problems = validate_poi_audio_ms()

    index_problems = validate_search_index_fresh()

    metadata_problems += index_problems

    if not missing and not metadata_problems:
        print(f"Ассеты контента: все файлы зарегистрированы "
              f"({len(entries)} записей в assets:), audioMs на месте. OK")
        return 0

    print(f"Незарегистрированные ассеты: {len(missing)}", file=sys.stderr)
    for rel in missing[:50]:
        print(f"  - {rel}", file=sys.stderr)
    if len(missing) > 50:
        print(f"  … и ещё {len(missing) - 50}", file=sys.stderr)
    for problem in metadata_problems:
        print(f"  ! {problem}", file=sys.stderr)
    print("Добавьте их в секцию assets: pubspec.yaml — КАЖДУЮ "
          "подпапку отдельной строкой (каталоги в assets "
          "нерекурсивны, только файлы непосредственно внутри).",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())