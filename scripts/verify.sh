#!/bin/bash
# Full verification pass for this plugin: qmllint -> omarchy plugin validate -> vitest.
# Mirrors the "Local dev" steps in README.md, but validates a clean staged copy
# (excluding node_modules/tests/coverage) since `omarchy plugin validate` rejects
# symlinks such as the ones npm creates under node_modules/.bin.
#
# NOTE: this only proves the QML is well-formed and the JS logic passes its unit
# tests. It does NOT prove the change renders correctly in a running shell — per
# CLAUDE.md, always fully restart quickshell and take a live screenshot before
# calling a QML/Quickshell UI change verified.
set -euo pipefail
cd "$(dirname "$0")/.."

SHIPPED_FILES=(manifest.json Overlay.qml BarWidget.qml NewsModel.js Config.js suggested-feeds.json)

echo "==> qmllint"
qmllint -I /usr/share/omarchy/shell Overlay.qml BarWidget.qml

echo "==> omarchy plugin validate (staged copy)"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp "${SHIPPED_FILES[@]}" "$STAGE_DIR/"
omarchy plugin validate "$STAGE_DIR"

echo "==> vitest"
npm test --silent

echo "==> all checks passed"
