#!/usr/bin/env python3
"""The nb-hook relay (nbHookPython in NotchBuddy/Sources/App/HookServer.swift), run by
scripts/test-hook-relay.sh on Linux and on the macOS CI.

It takes the relay out of HookServer.swift as the app writes it (nb-hook.py), runs it the way Claude
Code does (the hook input on stdin, --statusline for the status line) against a stub of the island's
Unix socket, and checks what it forwards, prints and exits with: the session's name in --statusline
mode (trimmed, 120 characters at most, nothing for a blank or non-string name), the previous status
line's output passed through unchanged, exit 0 at once when the island does not answer, and the hook
payload forwarded whole (session_title included).

Usage: hook_relay_test.py <repository root> <empty work directory>. HOME is set to a path relative
to the work directory, so the socket path stays under the 104 bytes of sun_path. Python 3 standard
library only.
"""

import json
import os
import socket
import subprocess
import sys
import threading
import time

REPO, WORK = sys.argv[1], sys.argv[2]
os.chdir(WORK)
HOME = "h"
SUPPORT = os.path.join(HOME, "Library", "Application Support", "NotchBuddy")
SOCK = os.path.join(SUPPORT, "nb.sock")
PREVIOUS = os.path.join(SUPPORT, "statusline-previous.json")
RELAY = os.path.abspath(os.path.join(SUPPORT, "nb-hook.py"))
# The previous status line of these checks: it saves its stdin, then prints colours and a UTF-8 mark.
PREVIOUS_COMMAND = "cat > previous-stdin.json; printf '\\033[32mma ligne\\033[0m \\342\\234\\223'"
PREVIOUS_OUTPUT = b"\x1b[32mma ligne\x1b[0m \xe2\x9c\x93"


def relay_source():
    """nbHookPython as the app writes it: the Swift literal with its one escape (\\\\n) undone."""
    swift = open(os.path.join(REPO, "NotchBuddy/Sources/App/HookServer.swift"), encoding="utf-8").read()
    start_marker = 'private let nbHookPython = """\n'
    start = swift.index(start_marker) + len(start_marker)
    end = swift.index('\n"""', start)
    return swift[start:end].replace("\\\\", "\\") + "\n"


class Island:
    """A stub of the island's socket: it keeps each JSON line it receives and answers {"ok":true}."""

    def __init__(self):
        self.lines = []
        self.lock = threading.Lock()
        if os.path.exists(SOCK):
            os.remove(SOCK)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(SOCK)
        self.server.listen(8)
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            data = b""
            while b"\n" not in data:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data += chunk
            line = data.split(b"\n", 1)[0]
            if line:
                with self.lock:
                    self.lines.append(json.loads(line.decode()))
            try:
                conn.sendall(b'{"ok":true}\n')
            except OSError:
                pass
            conn.close()

    def received(self):
        with self.lock:
            got, self.lines = self.lines, []
        return got

    def close(self):
        self.server.close()
        if os.path.exists(SOCK):
            os.remove(SOCK)


def run(stdin_bytes, args=(), env_extra=None):
    """One run of nb-hook.py: exit code, stdout, seconds it took."""
    env = {k: v for k, v in os.environ.items()
           if k not in ("KLAYER_ISLAND_INTERNAL", "CLAUDE_CODE_ENTRYPOINT", "TERM_PROGRAM")}
    env["HOME"] = HOME
    env.update(env_extra or {})
    started = time.monotonic()
    proc = subprocess.run([sys.executable, RELAY] + list(args), input=stdin_bytes, capture_output=True,
                          env=env, cwd=WORK, timeout=15)
    time.sleep(0.05)   # the stub's thread has read the line by then
    return proc.returncode, proc.stdout, time.monotonic() - started


passed = 0


def check(name, condition, detail):
    global passed
    if not condition:
        print("FAIL %s: %s" % (name, detail), flush=True)
        sys.exit(1)
    passed += 1
    print("  ok  %s" % name, flush=True)


def main():
    os.makedirs(SUPPORT, exist_ok=True)
    open(RELAY, "w", encoding="utf-8").write(relay_source())
    if os.path.exists(PREVIOUS):
        os.remove(PREVIOUS)

    status = {
        "hook_event_name": "Status", "session_id": "sess-1234-abcd", "cwd": "/Users/me/projets/site",
        "model": {"id": "claude-opus-4-1", "display_name": "Opus"},
        "workspace": {"current_dir": "/Users/me/projets/site"},
        "rate_limits": {"five_hour": {"used_percentage": 42, "resets_at": 1800000000}},
        "session_name": "  Refonte de l'onboarding  ",
    }
    raw = json.dumps(status).encode()
    base = {"klayer_kind": "statusline", "session_id": "sess-1234-abcd", "rate_limits": status["rate_limits"]}

    island = Island()
    code, out, _ = run(raw, ["--statusline"])
    got = island.received()
    check("statusline_forwards_the_session_name_trimmed",
          code == 0 and out == b"" and got == [dict(base, session_name="Refonte de l'onboarding")],
          "exit %r, printed %r, forwarded %r" % (code, out, got))

    without = dict(status)
    del without["session_name"]
    code, out, _ = run(json.dumps(without).encode(), ["--statusline"])
    got = island.received()
    check("statusline_without_a_name_forwards_none", code == 0 and out == b"" and got == [base],
          "exit %r, printed %r, forwarded %r" % (code, out, got))

    for label, value in (("empty", ""), ("blank", " \n\t "), ("number", 42), ("null", None),
                         ("list", ["Nom"]), ("object", {"name": "Nom"})):
        code, out, _ = run(json.dumps(dict(status, session_name=value)).encode(), ["--statusline"])
        got = island.received()
        check("statusline_%s_name_is_not_forwarded" % label,
              code == 0 and out == b"" and got == [base], "exit %r, printed %r, forwarded %r" % (code, out, got))

    code, out, _ = run(json.dumps(dict(status, session_name="é" * 130)).encode(), ["--statusline"])
    got = island.received()
    check("statusline_name_cut_to_120_characters",
          code == 0 and len(got) == 1 and got[0].get("session_name") == "é" * 120, "forwarded %r" % got)
    code, out, _ = run(json.dumps(dict(status, session_name="a" * 119 + " b")).encode(), ["--statusline"])
    got = island.received()
    check("statusline_name_has_no_trailing_space_after_the_cut",
          len(got) == 1 and got[0].get("session_name") == "a" * 119, "forwarded %r" % got)

    # The previous status line runs with the same stdin and its output comes back byte for byte.
    with open(PREVIOUS, "w") as f:
        json.dump({"command": PREVIOUS_COMMAND}, f)
    code, out, _ = run(raw, ["--statusline"])
    got = island.received()
    with open(os.path.join(WORK, "previous-stdin.json"), "rb") as f:
        passed_stdin = f.read()
    check("previous_status_line_output_unchanged",
          code == 0 and out == PREVIOUS_OUTPUT and passed_stdin == raw
          and got == [dict(base, session_name="Refonte de l'onboarding")],
          "exit %r, printed %r, same stdin %r, forwarded %r" % (code, out, passed_stdin == raw, got))

    code, out, _ = run(b"{not json", ["--statusline"])
    check("invalid_json_still_runs_the_previous_line_and_exits_0", code == 0 and out == PREVIOUS_OUTPUT,
          "exit %r, printed %r" % (code, out))

    # The island does not answer: exit 0 at once, the previous status line still prints.
    island.close()
    code, out, elapsed = run(raw, ["--statusline"])
    check("island_away_exits_0_at_once_and_prints_the_previous_line",
          code == 0 and out == PREVIOUS_OUTPUT and elapsed < 2.0,
          "exit %r, printed %r, %.2f s" % (code, out, elapsed))
    os.remove(PREVIOUS)
    code, out, elapsed = run(raw, ["--statusline"])
    check("island_away_without_a_previous_line_prints_nothing", code == 0 and out == b"" and elapsed < 2.0,
          "exit %r, printed %r, %.2f s" % (code, out, elapsed))

    # Hook events go on whole: session_title reaches the island untouched.
    island = Island()
    for event, extra in (("SessionStart", {"source": "startup"}), ("UserPromptSubmit", {"prompt": "Corrige"})):
        payload = dict({"session_id": "sess-1234-abcd", "cwd": "/Users/me/projets/site", "hook_event_name": event,
                        "session_title": "Formulaire de contact"}, **extra)
        code, out, _ = run(json.dumps(payload).encode(), [], {"CLAUDE_CODE_ENTRYPOINT": "claude-desktop"})
        got = island.received()
        check("%s_keeps_session_title" % event,
              code == 0 and out == b"" and len(got) == 1 and got[0].get("session_title") == "Formulaire de contact"
              and got[0].get("hook_event_name") == event and got[0].get("klayer_agent") == "claude-desktop",
              "exit %r, printed %r, forwarded %r" % (code, out, got))

    # Klayer Island's own Claude Code processes relay nothing, the status line included.
    code, out, _ = run(raw, ["--statusline"], {"KLAYER_ISLAND_INTERNAL": "1"})
    got = island.received()
    check("internal_processes_relay_nothing", code == 0 and out == b"" and got == [],
          "exit %r, printed %r, forwarded %r" % (code, out, got))
    island.close()
    print("Hook relay: %d checks passed" % passed, flush=True)


if __name__ == "__main__":
    main()
