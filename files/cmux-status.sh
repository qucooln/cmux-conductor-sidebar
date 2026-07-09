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
# Safety net (A): a running entry not refreshed for STALE_SECS is treated as
# stopped (Ctrl+C etc.) and downgraded to done. This runs both opportunistically
# on any event AND via a self-scheduled wake, so a stuck spinner clears even
# when this is the only active session (no other hook fires to trigger a sweep).
#
# Recap guard (B): some agent harnesses emit an automatic "recap" a few seconds
# after a turn ends — a phantom turn that fires a `running` lifecycle event with
# no matching Stop, which would restart the spinner forever. We ignore a
# `running` that lands within RECAP_WINDOW of a just-finished state.

CMUX="${CMUX_CLAUDE_HOOK_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
[ -x "$CMUX" ] || CMUX="$(command -v cmux)" || exit 0

ROOT="$HOME/.cache/cmux-status"
STALE_SECS=180       # a `running` older than this with no refresh = stopped
SWEEP_EVERY=60       # opportunistic sweep rate-limit
RECAP_WINDOW=15      # a `running` within this many secs of a finished state = recap phantom

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

# Downgrade every stale `running` across all workspaces to `done` and repush.
run_sweep() {
  local now wsdir f mt changed
  now="$(date +%s)"
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
}

# Fix A: self-scheduled watchdog. After a running push, arm a single detached
# timer that runs a sweep STALE_SECS later — so a stuck `running` self-heals
# without needing another session to fire an event. Coalesced via a lock file
# to at most one pending wake at a time.
arm_watchdog() {
  local lock="$ROOT/.wake.lock" now mt
  now="$(date +%s)"
  if [ -e "$lock" ]; then
    mt="$(stat -f %m "$lock" 2>/dev/null || echo 0)"
    [ $((now - mt)) -lt "$STALE_SECS" ] && return   # a wake is already pending
  fi
  : > "$lock"
  ( trap '' HUP; sleep "$STALE_SECS"; rm -f "$lock"; run_sweep ) >/dev/null 2>&1 &
}

# Fix C: display reconciler. Pushes are non-atomic and the `running` hooks are
# async, so a stale `running` set-progress can land AFTER a later `ready` push,
# leaving cmux stuck showing a spinner while the cache already says ready. Once a
# workspace's events go quiet (~SETTLE_SECS), re-push its label from the settled
# cache so the display converges — no need to click the tab to unstick it.
# One watcher per workspace; each event just refreshes the activity marker.
SETTLE_SECS=3
reconcile_ws() {
  local ws="$1"                                 # NOTE: separate line — a same-line
  local mark="$ROOT/$ws/.reconcile"             # `local ws=.. mark=$ROOT/$ws/..` would
  local guard="$ROOT/$ws/.reconcile.lock" mt now # expand $ws before it's assigned (empty)
  : > "$mark"                                   # mark "activity now"
  mkdir "$guard" 2>/dev/null || return          # a watcher is already running
  ( trap '' HUP
    while :; do
      sleep "$SETTLE_SECS"
      mt="$(stat -f %m "$mark" 2>/dev/null || echo 0)"; now="$(date +%s)"
      [ $((now - mt)) -ge "$SETTLE_SECS" ] && break   # quiet → settled
    done
    push_ws "$ws"                               # re-push the settled cache state
    rmdir "$guard" 2>/dev/null
  ) >/dev/null 2>&1 &
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
case "$1" in
  running)
    # Fix B: suppress the recap phantom. If this surface just finished
    # (done/ready written within RECAP_WINDOW), a `running` arriving now is the
    # auto-recap, not real work — keep the finished state so the spinner stays
    # off. A genuine new turn arrives later (or re-asserts via a real tool call).
    cur="$(cat "$DIR/$SF" 2>/dev/null)"
    if [ "$cur" = "done" ] || [ "$cur" = "ready" ]; then
      mt="$(stat -f %m "$DIR/$SF" 2>/dev/null || echo 0)"
      [ $(( $(date +%s) - mt )) -lt "$RECAP_WINDOW" ] && exit 0
    fi
    printf 'running' > "$DIR/$SF" ;;
  busy)
    # Subagent lifecycle (SubagentStart/Stop). These keep the spinner alive
    # DURING a turn — a long subagent run has no PreToolUse to refresh the
    # watchdog — but must NEVER resurrect a finished session: a backgrounded
    # subagent can Stop long after the main turn's Stop (seen 214s later). So
    # only refresh running while already running; otherwise ignore.
    [ "$(cat "$DIR/$SF" 2>/dev/null)" = "running" ] || exit 0
    printf 'running' > "$DIR/$SF" ;;
  waiting)
    # WAITING = the agent is blocked mid-turn (permission / a question). Claude
    # Code also fires an idle-reminder notification ~60s AFTER a turn ends; that
    # must not flip a finished session to WAITING. So only honor waiting while the
    # surface is still running; otherwise it's the idle reminder — leave done/ready.
    [ "$(cat "$DIR/$SF" 2>/dev/null)" = "running" ] || exit 0
    printf 'waiting' > "$DIR/$SF" ;;
  done) printf 'done' > "$DIR/$SF" ;;
  ready)
    # ready is special: if this surface was just running (i.e. it "finished"),
    # upgrade to done (finished-needs-review red dot). This way we don't depend
    # on whether the Stop hook was mounted with ready or done — both old and new
    # sessions produce the dot.
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

# 3b) Arm the display reconciler (Fix C) so a stale spinner from an out-of-order
# push clears itself a few seconds after activity settles.
reconcile_ws "$WS"

# 4a) Arm the self-healing watchdog (Fix A) so a stuck running clears itself.
arm_watchdog

# 4b) Opportunistic global sweep (rate-limited) — catches stale running from
# other sessions whenever any event fires.
now="$(date +%s)"
stamp="$ROOT/.last-sweep"
last="$(cat "$stamp" 2>/dev/null || echo 0)"
if [ $((now - last)) -ge "$SWEEP_EVERY" ]; then
  printf '%s' "$now" > "$stamp"
  run_sweep
fi
exit 0
