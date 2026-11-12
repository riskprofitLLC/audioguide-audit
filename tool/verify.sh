#!/usr/bin/env bash
# Полная автономная проверка приложения: analyze → test → сборки.
# Выход с ненулевым кодом при любой ошибке (для CI / автономного запуска).
#
# Использование:
#   tool/verify.sh                # всё
#   tool/verify.sh --skip-apk     # без сборки Android (быстрее, web-проверка)
#   tool/verify.sh --no-build     # только analyze + test
#   tool/verify.sh --release-apk  # вдобавок к debug — release-APK (R8/минификация)

set -uo pipefail

# Flutter SDK: по умолчанию машина-специфичный путь, переопределяется
# переменной окружения (переносимость на другие хосты/CI).
FLUTTER_ROOT="${FLUTTER_ROOT:-/home/pi/flutter}"

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  echo "✗ Flutter не найден: $FLUTTER_ROOT/bin/flutter"
  echo "  Задай FLUTTER_ROOT=<путь к SDK> и повтори."
  exit 1
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"

cd "$(dirname "$0")/.."

SKIP_APK=0
NO_BUILD=0
RELEASE_APK=0
for arg in "$@"; do
  case "$arg" in
    --skip-apk) SKIP_APK=1 ;;
    --no-build) NO_BUILD=1 ;;
    --release-apk) RELEASE_APK=1 ;;
    *) echo "Неизвестный аргумент: $arg" >&2; exit 2 ;;
  esac
done

failures=0

step() {
  echo ""
  echo "=== $1 ==="
}

run() {
  local name="$1"; shift
  echo ">>> $*"
  if ! "$@"; then
    echo "!!! СТУПЕНЬ '$name' ПРОВАЛЕНА" >&2
    failures=$((failures + 1))
  fi
}

step "flutter analyze"
# Только реальные ошибки считаем блокирующими; известные info/warning-линты
# (dangling doc comments, depend_on_referenced_packages и т.п.) игнорируем.
run "analyze" flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos

step "flutter test"
run "test" flutter test --no-pub

step "проверка регистрации ассетов контента"
run "assets" python3 tool/check_assets.py

if [ "$NO_BUILD" = "0" ]; then
  # --no-pub обязателен: сетевой pub get на этой машине падает (403) и
  # стирает вручную положенные пакеты из ~/.pub-cache (см. AGENTS.md).
  step "flutter build web --debug"
  run "build web" flutter build web --debug --no-pub --no-web-resources-cdn

  # Декодируем %-escape в именах ассетов — как это делает прод-пайплайн
  # (Layero декодирует пути дважды, см. tool/fix_web_asset_names.py).
  run "decode asset names" python3 tool/fix_web_asset_names.py build/web

  # Секреты не должны попадать в дефолтную сборку (пункт 1 замечаний
  # Sonnet): сканируем web-бандл на GitHub-токены.
  run "bundle secrets" bash tool/check_bundle_secrets.sh build/web

  if [ "$SKIP_APK" = "0" ]; then
    step "flutter build apk --debug"
    run "build apk" flutter build apk --debug --no-pub
  else
    echo ">>> APK пропущен (--skip-apk)"
  fi

  # Release-APK включает R8 (isMinifyEnabled/isShrinkResources):
  # минификатор может вырезать JNI-классы sqlite3/maplibre/just_audio.
  # Флаг выключен по умолчанию — сборка долгая (P0-10, 6-й проход).
  if [ "$RELEASE_APK" = "1" ]; then
    step "flutter build apk --release (R8)"
    run "build release apk" flutter build apk --release --no-pub
  fi
else
  echo ">>> Сборки пропущены (--no-build)"
fi

echo ""
if [ "$failures" -eq 0 ]; then
  echo "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ✔"
  exit 0
else
  echo "ПРОВЕРЕНО С ОШИБКАМИ: $failures ступеней не прошло ✘"
  exit 1
fi
