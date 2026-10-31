#!/bin/bash
# Аудиторский пуш: срез главного кода проекта в отдельный репозиторий
# riskprofitLLC/audioguide-audit (для внешнего аудита).
#
# Состав среза — только то, что нужно для проверки КОДА:
#   lib/            — весь код приложения (Dart)
#   test/           — тесты, кроме дублирующих layout/admin и
#                     самых объёмных (>10 КБ каждый) — их суммарный
#                     вес давил на лимит без потери ценности аудита
#   tool/           — только базовые инструменты проверки
#                     (verify.sh, check_assets.py, push_audit.sh)
#   pubspec.yaml, analysis_options.yaml
#
# НЕ входят: content/, assets/, build/, web/, android/, prompts/,
# web/vendor, песочницы платформ, AGENTS.md (правила для агентов —
# смотреть в основном репо), контент-генераторы tool/.
#
# ОГРАНИЧЕНИЕ РАЗМЕРА (см. AGENTS.md «Аудиторский репозиторий»):
# совокупный размер всех файлов среза не должен превышать
# AUDIT_LIMIT_KB. Скрипт проверяет лимит ПЕРЕД пушем и падает
# при превышении — рост среза требует осознанного решения
# (почистить состав или поднять лимит в AGENTS.md).
#
# ИСТОРИЮ НЕ ВЕДЁМ: каждый запуск перезаписывает репо одним
# коммитом «Аудит-срез: <sha> <сообщение источника>» (force push) —
# история изменений и так живёт в основном репозитории, а блобы
# повторных срезов лишь распухали бы без пользы.
#
# Запуск: bash tool/push_audit.sh — ОБЯЗАТЕЛЬНО после каждого пуша
# в main основного репозитория (AGENTS.md, «Аудиторский репозиторий»).

set -euo pipefail

# Пути основного репо и клона аудита: по умолчанию — машина-специфичные,
# переопределяются переменными окружения (переносимость).
SRC="${AUDIT_SRC_DIR:-/home/pi/www/audioguide}"
DST="${AUDIT_DST_DIR:-/home/pi/www/audioguide-audit}"

# Лимит совокупного размера файлов аудита (КБ). Фактический срез
# ужали на ~20% (удалены prompts/, android/, часть tool/ и самые
# объёмные дублирующие тесты): было 2530 КБ, стало ~2020 КБ.
AUDIT_LIMIT_KB=2600

if [ ! -d "$DST/.git" ]; then
  echo "✗ Клона аудиторского репо нет: $DST"
  echo "  git clone ssh://git@ssh.github.com:443/riskprofitLLC/audioguide-audit.git $DST"
  exit 1
fi

if [ -n "$(cd "$SRC" && git status --porcelain --untracked-files=no)" ]; then
  echo "✗ В основном репо есть незакоммиченные изменения — сначала коммит."
  exit 1
fi

MAIN_SHA="$(cd "$SRC" && git rev-parse --short HEAD)"
MAIN_MSG="$(cd "$SRC" && git log -1 --pretty=%s)"

echo ">>> Синхронизация среза аудита ($MAIN_SHA)…"

rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' \
  "$SRC/lib/"            "$DST/lib/"
rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' \
  "$SRC/test/"           "$DST/test/"

# Ужимаем test/: удаляем дублирующие layout/admin-тесты и самые
# объёмные файлы (>7 КБ) — для аудита кода они избыточны.
find "$DST/test" -type f \( -name '*layout*' -o -name 'admin_*' \) -delete
find "$DST/test" -type f -name '*_test.dart' -size +7k -delete

# tool/: только базовые инструменты проверки.
rm -rf "$DST/tool"
mkdir -p "$DST/tool/audit"
for f in verify.sh check_assets.py push_audit.sh; do
  [ -f "$SRC/tool/$f" ] && cp "$SRC/tool/$f" "$DST/tool/$f"
done
cp "$SRC/tool/audit/README.md" "$DST/tool/audit/README.md"

# prompts/, web/, android/ в срез больше не входят (ужали на ~20%).
rm -rf "$DST/prompts" "$DST/web" "$DST/android"

# AGENTS.md в срез НЕ входит: это правила для агентов-разработчиков,
# не описание кода; полные инварианты — в основном репозитории.
# Заодно вычищаем хвосты прошлых срезов (файл мог остаться от
# прежнего состава — rsync корня его не удаляет).
rm -f "$DST/AGENTS.md"
rm -rf "$DST/promts"

for f in pubspec.yaml analysis_options.yaml; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DST/$f"
done

# README аудиторского репо — из главного (описание среза живёт в главном)
cp "$SRC/tool/audit/README.md" "$DST/README.md"

# ---- Контроль размера (AGENTS.md «Аудиторский репозиторий») ----
# -print0/xargs -0: имена файлов с пробелами (test/*, tool/*.mjs)
# не рвали конвейер (баг 16, замечания Sonnet).
TREE_KB=$(find "$DST" -path "$DST/.git" -prune -o -type f -print0 \
  | xargs -0 stat -c%s | awk '{s+=$1} END{printf "%d", (s+1023)/1024}')

echo "Совокупный размер файлов аудита: ${TREE_KB} КБ (лимит ${AUDIT_LIMIT_KB} КБ)"

if [ "$TREE_KB" -gt "$AUDIT_LIMIT_KB" ]; then
  echo "✗ Срез превышает лимит: ${TREE_KB} КБ > ${AUDIT_LIMIT_KB} КБ."
  echo "  Ужать состав (см. AGENTS.md «Аудиторский репозиторий»)"
  echo "  или осознанно поднять лимит с записью в AGENTS.md."
  exit 1
fi

cd "$DST"

if [ -z "$(git status --porcelain)" ]; then
  echo "Срез не изменился — пуш не нужен."
  exit 0
fi

# История не нужна: репо перезаписывается одним коммитом-срезом
# (orphan-ветка → старую main удалить → переименовать → force push).
FRESH="audit-fresh-$(date +%s)"
git checkout -q --orphan "$FRESH"
git add -A
git commit -q -m "Аудит-срез: $MAIN_SHA $MAIN_MSG"
git branch -q -D main 2>/dev/null || true
git branch -q -m main
git push -q -f origin main

# Локальный .git не должен копить блобы прошлых срезов
git reflog expire --expire=now --all >/dev/null 2>&1
git gc --prune=now --quiet >/dev/null 2>&1

echo "✔ Аудиторский репо обновлён (один коммит, без истории): $(git log --oneline -1)"
