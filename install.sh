#!/bin/bash
# cmux Conductor Sidebar —— 一键安装
# 装什么：Conductor 风格侧栏 + 每个 tab 的运行状态 spinner（Claude Code & trae）。
# 安装前会把你现有的 settings.json / cmux.json / trae hooks / 同名侧栏备份到时间戳目录。
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/files"
CMUX="${CMUX_BUNDLED_CLI_PATH:-}"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="$(command -v cmux 2>/dev/null || true)"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
if [ ! -x "$CMUX" ]; then
  echo "✗ 找不到 cmux CLI。请先安装 cmux（https://cmux.com）后重试。"; exit 1
fi

DEST="$HOME/.config/cmux/conductor-sidebar"
SIDEBARS="$HOME/.config/cmux/sidebars"
TS="$(date +%Y%m%d%H%M%S)"
BAK="$HOME/.config/cmux/conductor-backup-$TS"

echo "==> 1/5 备份现有配置到 $BAK"
mkdir -p "$BAK"
for f in "$HOME/.claude/settings.json" "$HOME/.config/cmux/cmux.json" \
         "$HOME/.trae/hooks.json" "$SIDEBARS/conductor.swift"; do
  [ -e "$f" ] && cp "$f" "$BAK/$(echo "$f" | sed "s#$HOME/##; s#/#__#g")" && echo "   备份 $f"
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
python3 "$SCRIPT_DIR/merge.py" install

echo "==> 4/5 校验 cmux.json"
if "$CMUX" config check >/dev/null 2>&1; then
  echo "   cmux.json 合法 ✓"
else
  echo "   ⚠ cmux.json 校验未通过，从备份还原该文件"
  [ -e "$BAK/.config__cmux__cmux.json" ] && cp "$BAK/.config__cmux__cmux.json" "$HOME/.config/cmux/cmux.json"
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

cat <<EOF

✅ 安装完成。

用法：
  • 侧栏已切到 Conductor。若没生效：右键左下角侧栏切换按钮 → 选 "conductor"。
  • 每个 tab 里跑 Claude Code / trae 时，那一行会显示蓝色运行 spinner；
    workspace 名字右边显示 RUNNING / WAITING / READY 状态 pill。
  • 状态上报的 hook 对新会话立即生效；已在跑的老会话可能需重启一次。

回滚：
  bash "$SCRIPT_DIR/uninstall.sh"
  完整备份在 ${BAK} —— 可手动完全还原
EOF
