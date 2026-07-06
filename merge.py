#!/usr/bin/env python3
# Conductor Sidebar 安装包 —— 配置合并/移除
# 用法: merge.py <install|uninstall>
# 幂等处理三处配置：Claude settings.json、trae hooks.json、cmux.json。
import json, os, re, sys

HOME = os.path.expanduser("~")
DIR = f"{HOME}/.config/cmux/conductor-sidebar"
STATUS = f"{DIR}/cmux-status.sh"
RENAME = f"{DIR}/cmux-rename-hook.sh"
MARK = "conductor-sidebar/cmux-status.sh"          # 幂等/移除识别标记

MODE = sys.argv[1] if len(sys.argv) > 1 else "install"

# 每个 agent 的 hook 事件 -> (状态参数, matcher)
CLAUDE_HOOKS = [
    ("UserPromptSubmit", "running", None),
    ("PreToolUse",       "running", "Bash|Task"),
    ("SubagentStart",    "running", None),
    ("SubagentStop",     "running", None),
    ("Notification",     "waiting", None),
    ("Stop",             "ready",   None),
    ("SessionEnd",       "clear",   None),
]
TRAE_HOOKS = [
    ("UserPromptSubmit", "running", None),
    ("PreToolUse",       "running", "*"),
    ("Stop",             "ready",   None),
    ("Notification",     "waiting", None),
]

def load_jsonc(p):
    raw = open(p).read()
    raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)   # 整行注释
    raw = re.sub(r',(\s*[}\]])', r'\1', raw)          # 尾逗号
    return json.loads(raw)

# 这些事件同步执行：回合末/低频，必须可靠触发。
# （async 的 Stop 经常来不及 spawn 就被丢，导致 running 永不清、spinner 一直转。）
SYNC_EVENTS = {"Stop", "Notification", "SessionEnd"}

def hook_cmd(arg, timeout=True, is_async=True):
    # 高频事件 async（不阻塞工具调用）；回合末/低频事件同步（确保执行）
    e = {"type": "command", "command": f'bash "{STATUS}" {arg}'}
    if timeout: e["timeout"] = 5
    if is_async: e["async"] = True
    return e

def has_hook(hlist, ev, arg):
    for e in hlist.get(ev, []):
        for hk in e.get("hooks", []):
            c = hk.get("command", "")
            if MARK in c and c.strip().endswith(" " + arg):
                return True
    return False

def add_hooks(hlist, spec, timeout):
    for ev, arg, matcher in spec:
        if has_hook(hlist, ev, arg):
            continue
        entry = {"hooks": [hook_cmd(arg, timeout, ev not in SYNC_EVENTS)]}
        if matcher:
            entry["matcher"] = matcher
        hlist.setdefault(ev, []).append(entry)

def strip_hooks(hlist):
    for ev in list(hlist.keys()):
        kept = []
        for e in hlist[ev]:
            e["hooks"] = [hk for hk in e.get("hooks", []) if MARK not in hk.get("command", "")]
            if e["hooks"]:
                kept.append(e)
        if kept:
            hlist[ev] = kept
        else:
            del hlist[ev]

def process_agent(path, spec, timeout, loader):
    if not os.path.exists(path):
        return f"  skip {path}（不存在）"
    try:
        data = loader(path)
    except Exception as e:
        # 解析失败必须整体失败退出（而不是继续写别的文件），
        # 让 install.sh 捕获后指引用户回滚，避免半装状态。
        print(f"✗ 解析 {path} 失败：{e}", file=sys.stderr)
        sys.exit(1)
    hlist = data.setdefault("hooks", {})
    # install 也先 strip：清掉本包旧版留下的挂载（比如旧的 Stop->ready），再装新的，
    # 这样"重跑 install = 安全更新"，不会残留旧参数。
    strip_hooks(hlist)
    if MODE == "install":
        add_hooks(hlist, spec, timeout)
    data.setdefault("version", data.get("version", 1)) if "trae" in path else None
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    return f"  {'合并' if MODE=='install' else '移除'} hooks -> {path}"

def process_cmux():
    p = f"{HOME}/.config/cmux/cmux.json"
    if not os.path.exists(p):
        if MODE == "uninstall":
            return "  skip cmux.json（不存在）"
        data = {"$schema": "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json",
                "schemaVersion": 1}
    else:
        try:
            data = load_jsonc(p)
        except Exception as e:
            return f"  ⚠ cmux.json 解析失败，已跳过（请手动加 reorderOnNotification/notifications.hooks）：{e}"
    if MODE == "install":
        data.setdefault("app", {})["reorderOnNotification"] = False
        nh = data.setdefault("notifications", {}).setdefault("hooks", [])
        if not any(isinstance(x, dict) and x.get("id") == "conductor-rename" for x in nh):
            nh.append({"id": "conductor-rename",
                       "command": f'bash "{RENAME}"',
                       "timeoutSeconds": 180})
        data.setdefault("schemaVersion", 1)
    else:
        if "app" in data:
            data["app"].pop("reorderOnNotification", None)
            if not data["app"]:
                del data["app"]
        nf = data.get("notifications")
        if isinstance(nf, dict) and isinstance(nf.get("hooks"), list):
            nf["hooks"] = [x for x in nf["hooks"]
                           if not (isinstance(x, dict) and x.get("id") == "conductor-rename")]
            if not nf["hooks"]:
                del nf["hooks"]
            if not nf:
                del data["notifications"]
    with open(p, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    return f"  {'合并' if MODE=='install' else '移除'} 配置 -> {p}"

if __name__ == "__main__":
    if MODE not in ("install", "uninstall"):
        # 未知参数绝不能落进 uninstall 分支（strip 不 add = 静默卸载）
        print(f"用法: merge.py <install|uninstall>（收到: {MODE!r}）", file=sys.stderr)
        sys.exit(2)
    # 三处都用 JSONC 容错解析（注释/尾逗号）：用户手编的配置常有这类写法，
    # 严格 json.load 会在这里炸掉导致半装。
    print(process_agent(f"{HOME}/.claude/settings.json", CLAUDE_HOOKS, True, load_jsonc))
    print(process_agent(f"{HOME}/.trae/hooks.json", TRAE_HOOKS, False, load_jsonc))
    print(process_cmux())
