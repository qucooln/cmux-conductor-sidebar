#!/bin/bash
# cmux-tabname.sh — name the current cmux tab from the user's prompt, once per
# turn. Registered as a Claude Code UserPromptSubmit hook.
#
# Pairs with `title = " "` in ~/.config/ghostty/config, which locks the Ghostty
# title and makes cmux IGNORE the per-output title-change escapes that an agent
# streams — those floods are what make cmux ~10x slower than the bare engine
# (see cmux #4681). With the flood gone, cmux runs at full speed; this hook
# restores meaningful tab names at a sane cadence (one rename per turn, not
# hundreds per second). rename-tab sets cmux's own custom_title, independent of
# the locked Ghostty title.

[ -n "$CMUX_WORKSPACE_ID" ] || exit 0        # only inside cmux
CMUX="${CMUX_CLAUDE_HOOK_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
[ -x "$CMUX" ] || CMUX="$(command -v cmux)" || exit 0

# UserPromptSubmit delivers JSON on stdin; pull the first line of the prompt.
name="$(cat | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
p = d.get("prompt") or d.get("user_prompt") or d.get("message") or ""
line = next((l for l in p.splitlines() if l.strip()), "").strip()
# trim, drop a leading slash-command token noise, cap length
print(line[:48])
' 2>/dev/null)"

[ -n "$name" ] || exit 0
"$CMUX" rename-tab --surface "${CMUX_SURFACE_ID:-}" --workspace "$CMUX_WORKSPACE_ID" "$name" >/dev/null 2>&1
exit 0
