#!/bin/bash
# cmux Conductor Sidebar —— 一键安装
# 装什么：Conductor 风格侧栏 + 每个 tab 的运行状态 spinner（Claude Code & trae）。
# 安装前会把你现有的 settings.json / cmux.json / trae hooks / 同名侧栏备份到时间戳目录。
set -e

die() { echo "✗ $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/files"
CMUX="${CMUX_BUNDLED_CLI_PATH:-}"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="$(command -v cmux 2>/dev/null || true)"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
if [ ! -x "$CMUX" ]; then
  die "找不到 cmux CLI。请先安装 cmux（https://cmux.com）后重试。"
fi
command -v python3 >/dev/null 2>&1 || die "找不到 python3（macOS 自带；请确认 PATH）。"

DEST="$HOME/.config/cmux/conductor-sidebar"
SIDEBARS="$HOME/.config/cmux/sidebars"
TS="$(date +%Y%m%d%H%M%S)"
BAK="$HOME/.config/cmux/conductor-backup-$TS"

echo "==> 1/5 备份现有配置到 $BAK"
mkdir -p "$BAK"
for f in "$HOME/.claude/settings.json" "$HOME/.config/cmux/cmux.json" \
         "$HOME/.trae/hooks.json" "$SIDEBARS/conductor.swift"; do
  if [ -e "$f" ]; then
    cp "$f" "$BAK/$(echo "$f" | sed "s#$HOME/##; s#/#__#g")" \
      || die "备份 $f 失败，中止安装（尚未修改任何文件）。"
    echo "   备份 $f"
  fi
done
echo "$BAK" > "$HOME/.config/cmux/.conductor-last-backup"

echo "==> 2/5 安装脚本与侧栏文件"
mkdir -p "$DEST" "$SIDEBARS"
install -m 0755 "$FILES/cmux-status.sh"       "$DEST/cmux-status.sh"
install -m 0755 "$FILES/cmux-rename-hook.sh"  "$DEST/cmux-rename-hook.sh"
install -m 0644 "$FILES/conductor.swift"      "$SIDEBARS/conductor.swift"
echo "   -> $DEST/{cmux-status.sh,cmux-rename-hook.sh}"
echo "   -> $SIDEBARS/conductor.swift"

echo "==> 3/5 合并 hooks 与 cmux 配置（幂等）"
if ! python3 "$SCRIPT_DIR/merge.py" install; then
  echo "✗ 配置合并失败。你的原配置完整备份在：$BAK" >&2
  echo "  手动回滚：把备份文件复制回原位即可（文件名中 __ 代表 /），" >&2
  echo "  或运行 bash \"$SCRIPT_DIR/uninstall.sh\" 清理本包已装入的文件。" >&2
  exit 1
fi

echo "==> 4/5 校验 cmux.json"
WARN=0
if "$CMUX" config check >/dev/null 2>&1; then
  echo "   cmux.json 合法 ✓"
else
  echo "   ⚠ cmux.json 校验未通过，还原该文件"
  CMUX_JSON_BAK="$BAK/.config__cmux__cmux.json"
  if [ -e "$CMUX_JSON_BAK" ]; then
    cp "$CMUX_JSON_BAK" "$HOME/.config/cmux/cmux.json" \
      || die "还原 cmux.json 失败！请手动复制：$CMUX_JSON_BAK -> ~/.config/cmux/cmux.json"
  else
    # 安装前本就没有 cmux.json：忠实还原为「不存在」，不留下坏文件
    rm -f "$HOME/.config/cmux/cmux.json"
  fi
  WARN=1
fi

echo "==> 5/5 加载并激活侧栏"
"$CMUX" sidebar validate conductor >/dev/null 2>&1 || echo "   ⚠ 侧栏校验未过（cmux 可能未运行）"
# 关键：必须先 reload-config，让 cmux 把刚装的 conductor.swift 加进可选侧栏列表，
# 否则紧接着的 select 会因为 cmux 还没发现这个文件而失败。
"$CMUX" reload-config >/dev/null 2>&1 || true
ACTIVATED=0
for _ in 1 2 3; do
  if "$CMUX" sidebar select conductor >/dev/null 2>&1; then ACTIVATED=1; break; fi
  sleep 1
done
if [ "$ACTIVATED" = 1 ]; then
  echo "   已激活 Conductor 侧栏 ✓"
else
  echo "   ⚠ 未能自动激活（cmux 可能未运行）。请在 cmux 的任意终端里运行一次："
  echo "        cmux sidebar select conductor"
fi

if [ "$WARN" = 1 ]; then
  DONE_MSG="⚠ 安装完成（有警告）：cmux.json 未能合并，已还原原文件。
   影响：右键重命名菜单、通知排序两项辅助功能不可用；核心侧栏与状态灯不受影响。
   可稍后手动重跑：python3 \"$SCRIPT_DIR/merge.py\" install"
else
  DONE_MSG="✅ 安装完成。"
fi

cat <<EOF

$DONE_MSG

用法：
  • 侧栏已切到 Conductor。若没生效：右键左下角侧栏切换按钮 → 选 "conductor"。
  • 每个 tab 里跑 Claude Code / trae 时，那一行会显示蓝色运行 spinner；
    workspace 名字右边显示 RUNNING / WAITING / READY 状态 pill。
  • 状态上报的 hook 对新会话立即生效；已在跑的老会话可能需重启一次。

回滚：
  bash "$SCRIPT_DIR/uninstall.sh"
  完整备份在 ${BAK} —— 可手动完全还原
EOF
