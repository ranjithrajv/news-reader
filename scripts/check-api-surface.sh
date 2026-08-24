#!/bin/bash
# Best-effort check that the Quickshell/omarchy-shell API surface documented
# in API-SURFACE.md still exists. Run this after upgrading Quickshell or
# /usr/share/omarchy/shell, or in CI on a schedule, to catch upstream churn
# before it shows up as a silently-broken overlay.
#
# This is NOT a substitute for a full qmllint run against the live shell
# (scripts/verify.sh does that) — it specifically targets the omarchy-shell
# theme files (qs.Commons / qs.Ui), which are plain QML and more likely to
# silently rename a property than the compiled Quickshell core types.
set -euo pipefail

SHELL_DIR="${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}"
FAIL=0

check() {
  local desc="$1" file="$2" pattern="$3"
  if [[ ! -f "$file" ]]; then
    echo "MISSING FILE: $file ($desc)"
    FAIL=1
    return
  fi
  if ! grep -qE "$pattern" "$file"; then
    echo "MISSING SYMBOL: $desc not found in $file"
    FAIL=1
  fi
}

echo "==> checking omarchy-shell theme surface under $SHELL_DIR"
check "Color.menu"            "$SHELL_DIR/Commons/Color.qml" 'property QtObject menu'
check "Style.font"            "$SHELL_DIR/Commons/Style.qml" 'property QtObject font'
check "Style.spacing"         "$SHELL_DIR/Commons/Style.qml" 'property QtObject spacing'
check "Style.cornerRadius"    "$SHELL_DIR/Commons/Style.qml" 'property int cornerRadius'
check "Ui/WidgetButton.qml"   "$SHELL_DIR/Ui/WidgetButton.qml" 'property'
check "Ui/PanelToolTip.qml"   "$SHELL_DIR/Ui/PanelToolTip.qml" 'property'

echo "==> checking Quickshell.Wayland module is present"
if [[ ! -f /usr/lib/qt6/qml/Quickshell/Wayland/qmldir ]]; then
  echo "MISSING MODULE: Quickshell.Wayland qmldir not found"
  FAIL=1
fi

echo "==> qmllint (authoritative check for compiled Quickshell core types)"
if ! qmllint -I "$SHELL_DIR" "$(dirname "$0")/../Overlay.qml" "$(dirname "$0")/../BarWidget.qml"; then
  echo "qmllint reported issues — see above"
  FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "==> API surface matches API-SURFACE.md"
else
  echo "==> API surface drift detected — update API-SURFACE.md and fix the code above"
  exit 1
fi
