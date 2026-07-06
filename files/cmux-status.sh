#!/bin/bash
# cmux workspace status sync (called from Claude Code / trae hooks)
# Usage: cmux-status.sh <running|waiting|ready|done|clear|seen <surface-id>>
#
# States: running / waiting (needs input) / done (finished, unseen) /
#         ready (idle, seen) / clear (session exited)
# Aggregation priority: any running -> RUNNING; else any waiting -> WAITING; else READY.
# progress.label = "<AGG> run:<uuid> ... done:<uuid> ..."
#   run:  -> sidebar draws an animated spinner; done: -> sidebar draws a red
#   "finished, needs review" dot.
# seen <sid>: flip a surface's done to ready (seen — red dot disappears);
#   triggered when the sidebar opens that tab.
#
# Safety net: a running entry not refreshed for STALE_SECS is treated as
# stopped (Ctrl+C etc.) and downgraded to done (still surfaces a dot).

CMUX="${CMUX_CLAUDE_HOOK_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
[ -x "$CMUX" ] || CMUX="$(command -v cmux)" || exit 0

ROOT="$HOME/.cache/cmux-status"
STALE_SECS=180
SWEEP_EVERY=60

# Aggregate one workspace and push ($1 = workspace uuid)
push_ws() {
  local ws="$1" dir="$ROOT/$1" agg="" ids="" f v L C I
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    v="$(cat "$f" 2>/dev/null)"
    case "$v" in
      running) agg="running" ;;
      waiting) [ "$agg" != "running" ] && agg="waiting" ;;
      done|ready) [ -z "$agg" ] && agg="ready" ;;
    esac
  done
  if [ -z "$agg" ]; then
    "$CMUX" clear-progress --workspace "$ws" 2>/dev/null
    "$CMUX" clear-status claude --workspace "$ws" 2>/dev/null
    return
  fi
  case "$agg" in
    running) L="RUNNING"; C="#60a5fa"; I="play.circle.fill" ;;
    waiting) L="WAITING"; C="#fb923c"; I="hourglass" ;;
    ready)   L="READY";   C="#4ade80"; I="checkmark.circle.fill" ;;
  esac
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    v="$(cat "$f" 2>/dev/null)"
    case "$v" in
      running) ids="$ids run:$(basename "$f")" ;;
      done)    ids="$ids done:$(basename "$f")" ;;
    esac
  done
  ids="${ids# }"
  # Separator is a plain ASCII space; cmux has a bug with multi-byte
  # characters (e.g. §) that swallows the prefix.
  "$CMUX" set-progress 1.0 --label "$L $ids" --workspace "$ws" 2>/dev/null
  "$CMUX" set-status claude "$L" --workspace "$ws" --icon "$I" --color "$C" --priority 1 2>/dev/null
}

# Special case: seen <sid> — a tab was opened; flip its done to ready so the
# red dot disappears (search across all workspaces).
if [ "$1" = "seen" ]; then
  target="$2"
  [ -n "$target" ] || exit 0
  for wsdir in "$ROOT"/*/; do
    [ -d "$wsdir" ] || continue
    f="$wsdir$target"
    if [ -e "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "done" ]; then
      printf 'ready' > "$f"
      push_ws "$(basename "$wsdir")"
    fi
  done
  exit 0
fi

# Regular status events below need workspace context (seen doesn't — handled
# and exited above).
[ -n "$CMUX_WORKSPACE_ID" ] || exit 0
WS="$CMUX_WORKSPACE_ID"
SF="${CMUX_SURFACE_ID:-$WS}"
DIR="$ROOT/$WS"
mkdir -p "$DIR"

# 1) Record this session's state.
# ready is special: if this surface was just running (i.e. it "finished"),
# upgrade to done (finished-needs-review red dot). This way we don't depend
# on whether the Stop hook was mounted with ready or done — both old and new
# sessions produce the dot.
case "$1" in
  running|waiting|done) printf '%s' "$1" > "$DIR/$SF" ;;
  ready)
    if [ "$(cat "$DIR/$SF" 2>/dev/null)" = "running" ]; then
      printf 'done' > "$DIR/$SF"
    else
      printf 'ready' > "$DIR/$SF"
    fi ;;
  clear) rm -f "$DIR/$SF" ;;
  *)     exit 0 ;;
esac

# 2) Clean up leftovers from closed surfaces (cmux tree is relatively heavy,
# so only do this on low-frequency events).
case "$1" in
  ready|done|clear)
    LIVE="$("$CMUX" tree --id-format both 2>/dev/null \
            | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')"
    if [ -n "$LIVE" ]; then
      for f in "$DIR"/*; do
        [ -e "$f" ] || continue
        b="$(basename "$f")"
        case "$LIVE" in *"$b"*) : ;; *) rm -f "$f" ;; esac
      done
    fi ;;
esac

# 3) Push this workspace.
push_ws "$WS"

# 4) Global safety net: stale running means it stopped -> done (rate-limited).
now="$(date +%s)"
stamp="$ROOT/.last-sweep"
last="$(cat "$stamp" 2>/dev/null || echo 0)"
if [ $((now - last)) -ge "$SWEEP_EVERY" ]; then
  printf '%s' "$now" > "$stamp"
  for wsdir in "$ROOT"/*/; do
    [ -d "$wsdir" ] || continue
    changed=0
    for f in "$wsdir"*; do
      [ -e "$f" ] || continue
      [ "$(cat "$f" 2>/dev/null)" = "running" ] || continue
      mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
      if [ $((now - mt)) -ge "$STALE_SECS" ]; then
        printf 'done' > "$f"; changed=1
      fi
    done
    [ "$changed" = 1 ] && push_ws "$(basename "$wsdir")"
  done
fi
exit 0
