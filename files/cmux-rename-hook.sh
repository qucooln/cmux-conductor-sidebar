#!/bin/bash
# Notification hook for the conductor sidebar (called via notifications.hooks).
# Intercepts two internal "magic notifications" and swallows them; every other
# notification passes through unchanged:
#   cmux-rename  -> show a macOS input dialog to rename a workspace (body=workspace-id)
#   cmux-seen    -> a tab was opened; clear its "finished, needs review" red dot (body=surface-id)
# Note: socket authorization is based on the process ancestry chain, so we
# print the policy, close stdout, and stay resident as the authorization
# anchor for our child process.

INPUT=$(cat)
CMUX="${CMUX_BUNDLED_CLI_PATH:-/Applications/cmux.app/Contents/Resources/bin/cmux}"

# Locate cmux-status.sh (package installs it next to this script; also check
# legacy locations)
STATUS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/cmux-status.sh"
[ -x "$STATUS" ] || STATUS="$HOME/.claude/hooks/cmux-status.sh"
[ -x "$STATUS" ] || STATUS="$HOME/.config/cmux/conductor-sidebar/cmux-status.sh"

swallow() {  # swallow the current notification: turn off all its effects
  printf '%s' "$INPUT" | /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)
for k in d.get("effects",{}): d["effects"][k]=False
print(json.dumps(d))'
}

case "$CMUX_NOTIFICATION_TITLE" in
  cmux-rename)
    WS="$CMUX_NOTIFICATION_BODY"
    (
      CUR=$("$CMUX" workspace list --id-format both 2>/dev/null | grep -F "$WS" | sed -E 's/^[* ]+workspace:[0-9]+ [0-9A-Fa-f-]{36} +//; s/ +\[selected\].*$//' | head -1)
      NAME=$(osascript -e "tell application id \"com.cmuxterm.app\" to activate" \
                       -e "text returned of (display dialog \"New name:\" default answer \"$CUR\" with title \"Rename Workspace\")" 2>/dev/null)
      [ -n "$NAME" ] && "$CMUX" workspace rename --workspace "$WS" --title "$NAME"
    ) &
    CHILD=$!
    swallow; exec 1>&- 2>&-; wait $CHILD
    ;;
  cmux-seen)
    ( bash "$STATUS" seen "$CMUX_NOTIFICATION_BODY" >/dev/null 2>&1 ) &
    CHILD=$!
    swallow; exec 1>&- 2>&-; wait $CHILD
    ;;
  *)
    printf '%s' "$INPUT"
    ;;
esac
exit 0
