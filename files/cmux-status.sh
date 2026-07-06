#!/bin/bash
# cmux 工作区状态同步（由 Claude Code / trae 的 hooks 调用）
# 用法: cmux-status.sh <running|waiting|ready|done|clear|seen <surface-id>>
#
# 状态：running(跑中) / waiting(等输入) / done(刚完成待查) / ready(空闲·已看) / clear(退出)
# 聚合优先级：任一 running -> RUNNING；否则任一 waiting -> WAITING；否则 READY。
# progress.label = "<AGG> run:<uuid> ... done:<uuid> ..."
#   run:  -> 侧栏画动画 spinner；done: -> 侧栏画红点(完成待查)。
# seen <sid>：把某 surface 的 done 清成 ready（已看，红点消失）——由侧栏点开 tab 时触发。
#
# 兜底：running 超过 STALE_SECS 没刷新视为已停(Ctrl+C 中断等)，降级为 done(仍提示一下)。
# 回滚：~/.config/cmux/rollback-20260703.sh

CMUX="${CMUX_CLAUDE_HOOK_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
[ -x "$CMUX" ] || CMUX="$(command -v cmux)" || exit 0

ROOT="$HOME/.cache/cmux-status"
STALE_SECS=180
SWEEP_EVERY=60

# 聚合某 workspace 并推送（$1 = workspace uuid）
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
  # 分隔符用空格(ASCII)；cmux 对多字节字符(如 §)有 bug 会吞前缀。
  "$CMUX" set-progress 1.0 --label "$L $ids" --workspace "$ws" 2>/dev/null
  "$CMUX" set-status claude "$L" --workspace "$ws" --icon "$I" --color "$C" --priority 1 2>/dev/null
}

# 特殊：seen <sid> —— 点开 tab，把它的 done 清成 ready，红点消失（遍历各 workspace 找）
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

# 以下是正常状态事件，需要 workspace 上下文（seen 不需要，已在上面处理并退出）
[ -n "$CMUX_WORKSPACE_ID" ] || exit 0
WS="$CMUX_WORKSPACE_ID"
SF="${CMUX_SURFACE_ID:-$WS}"
DIR="$ROOT/$WS"
mkdir -p "$DIR"

# 1) 记录本会话状态
# ready 特殊：若这个 surface 刚才还是 running（说明是"跑完了"），升级为 done（完成待查红点）。
# 这样不依赖 Stop 挂载参数是 ready 还是 done，新旧会话都能出红点。
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

# 2) 清理已关闭 surface 的残留（跑 cmux tree 较重，只在低频事件做）
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

# 3) 推送自己 workspace
push_ws "$WS"

# 4) 全局兜底：stale running 视为已停 -> done（限流）
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
