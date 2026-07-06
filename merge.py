#!/usr/bin/env python3
# Conductor Sidebar package — config merge / removal
# Usage: merge.py <install|uninstall>
# Idempotently edits three configs: Claude settings.json, trae hooks.json, cmux.json.
import json, os, re, sys

HOME = os.path.expanduser("~")
DIR = f"{HOME}/.config/cmux/conductor-sidebar"
STATUS = f"{DIR}/cmux-status.sh"
RENAME = f"{DIR}/cmux-rename-hook.sh"
MARK = "conductor-sidebar/cmux-status.sh"          # idempotency / removal marker

MODE = sys.argv[1] if len(sys.argv) > 1 else "install"

# Per-agent hook events -> (status argument, matcher)
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
    raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)   # whole-line comments
    raw = re.sub(r',(\s*[}\]])', r'\1', raw)          # trailing commas
    return json.loads(raw)

# These events run synchronously: end-of-turn / low-frequency, must fire reliably.
# (An async Stop often gets dropped before it can spawn, leaving "running"
# never cleared and the spinner stuck.)
SYNC_EVENTS = {"Stop", "Notification", "SessionEnd"}

def hook_cmd(arg, timeout=True, is_async=True):
    # High-frequency events are async (don't block tool calls);
    # end-of-turn / low-frequency events are sync (guaranteed to run).
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
        return f"  skip {path} (not found)"
    try:
        data = loader(path)
    except Exception as e:
        # A parse failure must fail the whole run (instead of moving on to the
        # other files) so install.sh can catch it and point at the backup —
        # never leave a half-installed state.
        print(f"✗ Failed to parse {path}: {e}", file=sys.stderr)
        sys.exit(1)
    hlist = data.setdefault("hooks", {})
    # install strips first too: removes mounts left by older versions of this
    # package (e.g. an old Stop->ready) before adding the new ones, so
    # "re-run install" is a safe update with no stale arguments left behind.
    strip_hooks(hlist)
    if MODE == "install":
        add_hooks(hlist, spec, timeout)
    data.setdefault("version", data.get("version", 1)) if "trae" in path else None
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    return f"  {'merged' if MODE=='install' else 'removed'} hooks -> {path}"

def process_cmux():
    p = f"{HOME}/.config/cmux/cmux.json"
    if not os.path.exists(p):
        if MODE == "uninstall":
            return "  skip cmux.json (not found)"
        data = {"$schema": "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json",
                "schemaVersion": 1}
    else:
        try:
            data = load_jsonc(p)
        except Exception as e:
            return f"  ⚠ Failed to parse cmux.json, skipped (add reorderOnNotification/notifications.hooks manually): {e}"
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
    return f"  {'merged' if MODE=='install' else 'removed'} config -> {p}"

if __name__ == "__main__":
    if MODE not in ("install", "uninstall"):
        # An unknown argument must never fall through to the uninstall branch
        # (strip without add = silent hook removal).
        print(f"usage: merge.py <install|uninstall> (got: {MODE!r})", file=sys.stderr)
        sys.exit(2)
    # All three configs use JSONC-tolerant parsing (comments / trailing
    # commas): hand-edited configs often contain these, and a strict
    # json.load would blow up mid-install.
    print(process_agent(f"{HOME}/.claude/settings.json", CLAUDE_HOOKS, True, load_jsonc))
    print(process_agent(f"{HOME}/.trae/hooks.json", TRAE_HOOKS, False, load_jsonc))
    print(process_cmux())
