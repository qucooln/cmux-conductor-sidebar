#!/bin/bash
# cmux Conductor Sidebar — uninstall
# Precisely removes only what this package added (hooks / config keys / files);
# the rest of your config is left alone.
# The full install-time backup is kept at ~/.config/cmux/conductor-backup-*
# in case you want to restore everything manually.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMUX="${CMUX_BUNDLED_CLI_PATH:-}"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="$(command -v cmux 2>/dev/null || true)"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"

echo "==> 1/4 Removing this package's entries from hooks / cmux config"
python3 "$SCRIPT_DIR/merge.py" uninstall

echo "==> 2/4 Deleting installed files"
rm -f "$HOME/.config/cmux/sidebars/conductor.swift"
rm -rf "$HOME/.config/cmux/conductor-sidebar"
rm -rf "$HOME/.cache/cmux-status"
echo "   removed sidebar, status scripts, status cache"

echo "==> 3/4 Switching back to the default sidebar"
"$CMUX" sidebar select default >/dev/null 2>&1 || echo "   ⚠ Right-click the sidebar-toggle button and pick \"default\" manually"

echo "==> 4/4 Reloading config"
"$CMUX" reload-config >/dev/null 2>&1 || true

BAK="$(cat "$HOME/.config/cmux/.conductor-last-backup" 2>/dev/null || true)"
echo ""
echo "✅ Uninstall complete."
[ -n "$BAK" ] && echo "   Pre-install backup still available at: $BAK"
