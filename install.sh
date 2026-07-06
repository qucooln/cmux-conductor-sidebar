#!/bin/bash
# cmux Conductor Sidebar — one-command install
# What it installs: a Conductor-style sidebar with live per-tab agent status
# (Claude Code & trae). Before touching anything it backs up your existing
# settings.json / cmux.json / trae hooks / any same-named sidebar into a
# timestamped directory.
set -e

die() { echo "✗ $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/files"
CMUX="${CMUX_BUNDLED_CLI_PATH:-}"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="$(command -v cmux 2>/dev/null || true)"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
if [ ! -x "$CMUX" ]; then
  die "cmux CLI not found. Install cmux first (https://cmux.com) and retry."
fi
command -v python3 >/dev/null 2>&1 || die "python3 not found (ships with macOS; check your PATH)."

DEST="$HOME/.config/cmux/conductor-sidebar"
SIDEBARS="$HOME/.config/cmux/sidebars"
TS="$(date +%Y%m%d%H%M%S)"
BAK="$HOME/.config/cmux/conductor-backup-$TS"

echo "==> 1/5 Backing up existing config to $BAK"
mkdir -p "$BAK"
for f in "$HOME/.claude/settings.json" "$HOME/.config/cmux/cmux.json" \
         "$HOME/.trae/hooks.json" "$SIDEBARS/conductor.swift"; do
  if [ -e "$f" ]; then
    cp "$f" "$BAK/$(echo "$f" | sed "s#$HOME/##; s#/#__#g")" \
      || die "Failed to back up $f — aborting (nothing has been modified yet)."
    echo "   backed up $f"
  fi
done
echo "$BAK" > "$HOME/.config/cmux/.conductor-last-backup"

echo "==> 2/5 Installing scripts and sidebar files"
mkdir -p "$DEST" "$SIDEBARS"
install -m 0755 "$FILES/cmux-status.sh"       "$DEST/cmux-status.sh"
install -m 0755 "$FILES/cmux-rename-hook.sh"  "$DEST/cmux-rename-hook.sh"
install -m 0644 "$FILES/conductor.swift"      "$SIDEBARS/conductor.swift"
echo "   -> $DEST/{cmux-status.sh,cmux-rename-hook.sh}"
echo "   -> $SIDEBARS/conductor.swift"

echo "==> 3/5 Merging hooks and cmux config (idempotent)"
if ! python3 "$SCRIPT_DIR/merge.py" install; then
  echo "✗ Config merge failed. Your original config is fully backed up at: $BAK" >&2
  echo "  Manual rollback: copy the backup files back into place (__ in a" >&2
  echo "  filename stands for /), or run bash \"$SCRIPT_DIR/uninstall.sh\" to" >&2
  echo "  remove the files this package installed." >&2
  exit 1
fi

echo "==> 4/5 Validating cmux.json"
WARN=0
if "$CMUX" config check >/dev/null 2>&1; then
  echo "   cmux.json valid ✓"
else
  echo "   ⚠ cmux.json failed validation — restoring it"
  CMUX_JSON_BAK="$BAK/.config__cmux__cmux.json"
  if [ -e "$CMUX_JSON_BAK" ]; then
    cp "$CMUX_JSON_BAK" "$HOME/.config/cmux/cmux.json" \
      || die "Failed to restore cmux.json! Copy it back manually: $CMUX_JSON_BAK -> ~/.config/cmux/cmux.json"
  else
    # cmux.json didn't exist before this install: faithfully restore to
    # "nonexistent" instead of leaving a broken file behind
    rm -f "$HOME/.config/cmux/cmux.json"
  fi
  WARN=1
fi

echo "==> 5/5 Loading and activating the sidebar"
"$CMUX" sidebar validate conductor >/dev/null 2>&1 || echo "   ⚠ Sidebar validation failed (cmux may not be running)"
# Important: reload-config first so cmux adds the freshly installed
# conductor.swift to its sidebar list — otherwise the select right after
# fails because cmux hasn't discovered the file yet.
"$CMUX" reload-config >/dev/null 2>&1 || true
ACTIVATED=0
for _ in 1 2 3; do
  if "$CMUX" sidebar select conductor >/dev/null 2>&1; then ACTIVATED=1; break; fi
  sleep 1
done
if [ "$ACTIVATED" = 1 ]; then
  echo "   Conductor sidebar activated ✓"
else
  echo "   ⚠ Could not auto-activate (cmux may not be running). Run this once in any cmux terminal:"
  echo "        cmux sidebar select conductor"
fi

if [ "$WARN" = 1 ]; then
  DONE_MSG="⚠ Installed with warnings: cmux.json could not be merged; the original file was restored.
   Impact: the right-click rename menu and the notification-reorder tweak are unavailable;
   the core sidebar and status lights are unaffected.
   Retry later with: python3 \"$SCRIPT_DIR/merge.py\" install"
else
  DONE_MSG="✅ Install complete."
fi

cat <<EOF

$DONE_MSG

Usage:
  • The sidebar has been switched to Conductor. If it didn't take effect:
    right-click the sidebar-toggle button (bottom left) and pick "conductor".
  • While Claude Code / trae runs in a tab, that row shows a blue spinner;
    the workspace name gets a RUNNING / WAITING / READY status pill.
  • Status hooks take effect immediately for new sessions; already-running
    sessions may need one restart.

Rollback:
  bash "$SCRIPT_DIR/uninstall.sh"
  Full backup kept at ${BAK} — you can restore everything manually.
EOF
