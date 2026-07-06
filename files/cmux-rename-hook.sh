#!/bin/bash
# conductor sidebar 的通知 hook（由 notifications.hooks 调用）。
# 拦截两种内部"魔法通知"并吞掉它们本身，其余通知原样放行：
#   cmux-rename  -> 弹 macOS 输入框重命名 workspace（body=workspace-id）
#   cmux-seen    -> 点开某 tab，清除它的"完成待查"红点（body=surface-id）
# 说明：socket 授权基于进程祖先链，故输出 policy 后关 stdout 继续驻留，作为子进程的授权锚点。

INPUT=$(cat)
CMUX="${CMUX_BUNDLED_CLI_PATH:-/Applications/cmux.app/Contents/Resources/bin/cmux}"

# 定位 cmux-status.sh（本机在 ~/.claude/hooks；安装包在与本脚本同目录）
STATUS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/cmux-status.sh"
[ -x "$STATUS" ] || STATUS="$HOME/.claude/hooks/cmux-status.sh"
[ -x "$STATUS" ] || STATUS="$HOME/.config/cmux/conductor-sidebar/cmux-status.sh"

swallow() {  # 吞掉当前通知：把所有 effects 关掉
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
                       -e "text returned of (display dialog \"输入新名称：\" default answer \"$CUR\" with title \"重命名 Workspace\")" 2>/dev/null)
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
