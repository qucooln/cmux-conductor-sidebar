#!/bin/bash
# cmux Conductor Sidebar —— 卸载
# 精确移除本包加入的 hooks / 配置 / 文件；不动你原有的其它配置。
# 安装时的完整备份仍保留在 ~/.config/cmux/conductor-backup-* 里，可手动完全还原。
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMUX="${CMUX_BUNDLED_CLI_PATH:-}"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="$(command -v cmux 2>/dev/null || true)"
[ -n "$CMUX" ] && [ -x "$CMUX" ] || CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"

echo "==> 1/4 从 hooks / cmux 配置移除本包条目"
python3 "$SCRIPT_DIR/merge.py" uninstall

echo "==> 2/4 删除安装的文件"
rm -f "$HOME/.config/cmux/sidebars/conductor.swift"
rm -rf "$HOME/.config/cmux/conductor-sidebar"
rm -rf "$HOME/.cache/cmux-status"
echo "   已删除侧栏、状态脚本、状态缓存"

echo "==> 3/4 切回默认侧栏"
"$CMUX" sidebar select default >/dev/null 2>&1 || echo "   ⚠ 请右键侧栏切换按钮手动选 default"

echo "==> 4/4 重载配置"
"$CMUX" reload-config >/dev/null 2>&1 || true

BAK="$(cat "$HOME/.config/cmux/.conductor-last-backup" 2>/dev/null || true)"
echo ""
echo "✅ 卸载完成。"
[ -n "$BAK" ] && echo "   安装前的完整备份仍在：$BAK"
