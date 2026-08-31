#!/bin/bash
# Full verification pass for this plugin.
# Cheap guards (JS syntax, manifest sanity, secret scan) run first and need no
# external tooling. Then qmllint + `omarchy plugin validate` prove the QML is
# well-formed and the manifest is valid, and vitest proves the JS logic passes.
#
# Mirrors the "Local dev" steps in README.md, but `omarchy plugin validate` runs
# on a clean staged copy (excluding node_modules/tests/coverage) since it rejects
# symlinks such as the ones npm creates under node_modules/.bin.
#
# NOTE: this only proves the QML is well-formed and the JS logic passes its unit
# tests. It does NOT prove the change renders correctly in a running shell — per
# CLAUDE.md, always fully restart quickshell and take a live screenshot before
# calling a QML/Quickshell UI change verified.
set -euo pipefail
cd "$(dirname "$0")/.."

SHIPPED_FILES=(manifest.json Overlay.qml BarWidget.qml NewsModel.js Config.js I18n.js suggested-feeds.json)

# Build qmllint include path only if the omarchy shell import dir exists
# (it does on a dev machine; absent on CI where qmllint isn't run).
QML_INCLUDE=()
if [ -d /usr/share/omarchy/shell ]; then
  QML_INCLUDE=(-I /usr/share/omarchy/shell)
fi

echo "==> JS syntax (node --check, pragma-stripped)"
# Shipped QML JS modules start with `.pragma library`, which plain Node can't
# parse; strip that one line before checking (mirrors vitest.config.js transform).
for f in Config.js NewsModel.js I18n.js; do
  [ -f "$f" ] || continue
  tmp="$(mktemp -t verify-XXXXXX.js)"
  sed '/^\.pragma library$/d' "$f" > "$tmp"
  node --check "$tmp"
  rm -f "$tmp"
done

echo "==> manifest sanity"
python3 - <<'PY'
import json, sys
try:
    m = json.load(open("manifest.json"))
except Exception as e:
    print("manifest.json is not valid JSON:", e); sys.exit(1)
for k in ("id", "name", "entryPoints"):
    if k not in m:
        print("manifest.json missing required key:", k); sys.exit(1)
if not isinstance(m.get("id"), str) or not m["id"].strip():
    print("manifest.json id is empty/invalid"); sys.exit(1)
print("manifest id:", m["id"])
PY

echo "==> secret scan (staged content)"
DQ='"'; SQ="'"
SECRET_RE="(-----BEGIN [A-Z ]*PRIVATE KEY-----)|(api[_-]?key|secret|token|passwd|password)[[:space:]]*[=:][[:space:]]*[$DQ$SQ][A-Za-z0-9/+=_-]{12,}[$DQ$SQ]|(AKIA[0-9A-Z]{16})"
if git grep --cached -nE "$SECRET_RE" -- '*.js' '*.qml' '*.json' ':(exclude)package-lock.json' >/dev/null 2>&1; then
  echo "ERROR: possible secret/key committed in staged content:" >&2
  git grep --cached -nE "$SECRET_RE" -- '*.js' '*.qml' '*.json' ':(exclude)package-lock.json' >&2 || true
  exit 1
fi

echo "==> qmllint"
qmllint "${QML_INCLUDE[@]}" -- *.qml

echo "==> omarchy plugin validate (staged copy)"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp "${SHIPPED_FILES[@]}" "$STAGE_DIR/"
omarchy plugin validate "$STAGE_DIR"

echo "==> vitest"
npm test --silent

echo "==> all checks passed"
