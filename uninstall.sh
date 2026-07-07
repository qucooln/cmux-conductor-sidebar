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

# Remove the speed-mode Ghostty title lock we added (identified by our marker).
# Leaves a pre-existing user `title =` line alone (we never touch that case).
GCFG="$HOME/.config/ghostty/config"
if [ -f "$GCFG" ] && grep -q "conductor-sidebar speed mode" "$GCFG"; then
  python3 - "$GCFG" <<'PY'
import sys, re
p=sys.argv[1]; out=[]; drop_next_title=False
for ln in open(p).read().splitlines(keepends=True):
    if "conductor-sidebar speed mode" in ln or "title-change floods (cmux #4681)" in ln:
        drop_next_title=True; continue        # drop our comment lines
    if drop_next_title and re.match(r'\s*title\s*=', ln):
        drop_next_title=False; continue        # drop the title = line we added
    out.append(ln)
open(p,"w").write("".join(out))
PY
  echo "   removed speed-mode Ghostty title lock"
fi

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
