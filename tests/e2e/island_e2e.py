#!/usr/bin/env python3
"""End-to-end test of Klayer Island, run by scripts/test-e2e-island.sh on the macOS CI.

It launches the test build of the app (compiled with KLAYER_E2E, never shipped) with
KLAYER_ISLAND_TEST=1, then plays sessions of the Claude app through the REAL relay the app writes
(~/Library/Application Support/NotchBuddy/nb-hook), as Claude Code runs it: the hook command
Klayer Island puts in ~/.claude/settings.json, the hook input on stdin in Claude Code's format, and
CLAUDE_CODE_ENTRYPOINT=claude-desktop for a session of the Claude app. It reads the island with the
test-only socket command e2e_state, and answers a card with e2e_decide or e2e_answer, which call
what the card's buttons call. It never writes ~/.claude/settings.json.

Each scenario prints "  ok  <name>"; the first failure prints what was expected and the island's
state, stops the app, prints the last 200 lines of its log, and exits 1.

--expect-no-test-commands: the app must NOT answer the test commands (the shipped build, or the
test build launched without KLAYER_ISLAND_TEST=1). Python 3 standard library only (3.9+).
"""

import argparse
import json
import os
import select
import signal
import socket
import subprocess
import sys
import time
import uuid

SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/NotchBuddy")
SOCKET_PATH = os.path.join(SUPPORT_DIR, "nb.sock")
RELAY_PATH = os.path.join(SUPPORT_DIR, "nb-hook")

DESKTOP_PILL = "agent_claude-desktop"   # HookRouting.desktopPillId
PROJECTS = "/Users/klayer-e2e/projets"  # cwd of the sessions: the island titles them by the last folder

POLL = 0.1              # e2e_state polling interval (s)
EXPECT_TIMEOUT = 10.0   # longest wait for one expectation (s)
LAUNCH_TIMEOUT = 30.0   # the socket and the relay must be there by then (s)
HIDE_TIMEOUT = 150.0    # the launch greeting folds, then the compact island hides 60 s later (s)
ASK_TIMEOUT = 2.0       # an "ask" fall-through is immediate (s)
SILENCE = 3.0           # how long a request is left unanswered to show nothing approves it (s)
QUIET = 2.0             # how long a state must hold to show nothing changes it (s)

# The variables Claude Code or a terminal sets for a hook; each relay run sets its own.
HOOK_ENV_KEYS = ("CLAUDE_CODE_ENTRYPOINT", "TERM_PROGRAM", "__CFBundleIdentifier", "ITERM_SESSION_ID",
                 "TERM_SESSION_ID", "KLAYER_ISLAND_INTERNAL", "KLAYER_ISLAND_TEST")


class Failure(Exception):
    pass


class Stopped(Failure):
    """SIGTERM (the CI's timeout, a kill): the run stops as on a failure, and the app is quit."""


# MARK: - The island's socket

def send(message, timeout=5.0):
    """Sends one JSON line to the island's socket; returns its one-line reply, parsed (None if none)."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(SOCKET_PATH)
        s.sendall((json.dumps(message) + "\n").encode())
        data = b""
        while b"\n" not in data:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    finally:
        s.close()
    line = data.split(b"\n", 1)[0].strip()
    return json.loads(line.decode()) if line else None


def read_state():
    try:
        reply = send({"klayer_kind": "e2e_state"})
    except OSError as error:
        raise Failure("island not reachable on %s: %s" % (SOCKET_PATH, error))
    if not isinstance(reply, dict) or "mode" not in reply:
        raise Failure("state not readable: e2e_state was answered %s (a build without KLAYER_E2E, "
                      "or an app launched without KLAYER_ISLAND_TEST=1)" % json.dumps(reply))
    return reply


def command(message):
    """A test command that acts (e2e_decide, e2e_answer, e2e_shortcut): it must answer ok."""
    reply = send(message)
    if not isinstance(reply, dict) or reply.get("ok") is not True:
        raise Failure("%s was refused: %s" % (json.dumps(message), json.dumps(reply)))


def show(state):
    return json.dumps(state, indent=2, sort_keys=True, ensure_ascii=False)


def holds(predicate, state):
    try:
        return bool(predicate(state))
    except (KeyError, IndexError, TypeError, AttributeError):
        return False


def wait_until(expected, predicate, timeout=EXPECT_TIMEOUT):
    """Polls e2e_state every 100 ms until `predicate` holds; fails with the last state after `timeout`."""
    deadline = time.monotonic() + timeout
    while True:
        state = read_state()
        if holds(predicate, state):
            return state
        if time.monotonic() >= deadline:
            raise Failure("expected %s within %.0f s; the state was:\n%s" % (expected, timeout, show(state)))
        time.sleep(POLL)


def keeps(expected, predicate, seconds):
    """`predicate` must hold on every read of e2e_state for `seconds`."""
    deadline = time.monotonic() + seconds
    while True:
        state = read_state()
        if not holds(predicate, state):
            raise Failure("expected %s to stay true for %.0f s; the state became:\n%s"
                          % (expected, seconds, show(state)))
        if time.monotonic() >= deadline:
            return state
        time.sleep(POLL)


def session(state, session_id):
    return next((row for row in state["sessions"] if row["id"] == session_id), None)


def phase(state, session_id):
    row = session(state, session_id)
    return row["phase"] if row else None


def choices_since(state, started):
    """The choices recorded from the island since `started` (the history keeps the 3 newest)."""
    return [(c["kind"], c["prompt"], c["answer"], c["session"]) for c in state["choices"] if c["date"] >= started - 1]


# MARK: - The relay, as Claude Code runs it

def hook_env(**extra):
    env = {key: value for key, value in os.environ.items() if key not in HOOK_ENV_KEYS}
    env.update(extra)
    return env


def claude_app_env():
    """A hook of a session of the Claude app (its Code tab)."""
    return hook_env(CLAUDE_CODE_ENTRYPOINT="claude-desktop",
                    __CFBundleIdentifier="com.anthropic.claudefordesktop")


def terminal_env():
    """A hook of Claude Code in Apple's Terminal."""
    return hook_env(CLAUDE_CODE_ENTRYPOINT="cli", TERM_PROGRAM="Apple_Terminal",
                    __CFBundleIdentifier="com.apple.Terminal")


class Relay:
    """One run of nb-hook, through the shell as Claude Code runs a hook command: the script between
    double quotes (KlayerHookCommand.written), then its arguments (" --ask" for AskUserQuestion)."""

    def __init__(self, payload, env, args=()):
        self.command = '"%s"' % RELAY_PATH.replace('"', '\\"')
        for arg in args:
            self.command += " " + arg
        self.proc = subprocess.Popen(["/bin/sh", "-c", self.command], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
                                     start_new_session=True)
        try:
            self.proc.stdin.write(json.dumps(payload).encode())
            self.proc.stdin.close()
        except BrokenPipeError:
            pass   # the relay exited without reading: finish() reports it

    def waiting_silently(self):
        """Still running, and nothing printed yet."""
        if self.proc.poll() is not None:
            return False
        readable, _, _ = select.select([self.proc.stdout], [], [], 0)
        return not readable

    def finish(self, timeout, what):
        """Exit code and output once the relay ends; fails if it is still running after `timeout`."""
        try:
            code = self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.kill()
            raise Failure("%s: nb-hook (%s) still running after %.0f s" % (what, self.command, timeout))
        return code, self.proc.stdout.read().decode()

    def kill(self):
        """Ends the relay and its python3 the way a hook is torn down: the whole process group."""
        try:
            os.killpg(self.proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        self.proc.wait()


def pending(relay, what):
    """While its card is awaited, the relay must still wait: an answer before the card means the
    request was decided without the island (scenario 8)."""
    if relay.waiting_silently():
        return True
    try:
        code = relay.proc.wait(timeout=1)
        detail = "exited %d and printed %r" % (code, relay.proc.stdout.read().decode())
    except subprocess.TimeoutExpired:
        detail = "printed something and is still running"
    raise Failure("%s was answered before its card showed: nb-hook %s" % (what, detail))


def fire(payload, env, what):
    """An event hook (fire and forget): nb-hook prints nothing and exits 0 at once."""
    code, out = Relay(payload, env).finish(5, what)
    if code != 0 or out != "":
        raise Failure("%s: nb-hook exited %d and printed %r; expected exit 0 and no output" % (what, code, out))


def expect_output(relay, expected, what):
    """The relay prints exactly `expected` (one JSON line, as Claude Code reads it) and exits 0."""
    code, out = relay.finish(5, what)
    line = json.dumps(expected) + "\n"
    if code != 0 or out != line:
        raise Failure("%s: nb-hook exited %d and printed %r; expected exit 0 and %r" % (what, code, out, line))


def expect_fall_through(relay, what):
    """The answer "ask": nb-hook prints nothing and exits 0, so Claude Code asks in its own window."""
    code, out = relay.finish(ASK_TIMEOUT, what)
    if code != 0 or out != "":
        raise Failure("%s: nb-hook exited %d and printed %r; expected exit 0 and no output (ask)"
                      % (what, code, out))


def expect_raw_ask(payload, what):
    """The island's own answer to the relay's request, read on the socket: "ask", within 2 s."""
    reply = send(payload, timeout=ASK_TIMEOUT)
    if reply != {"permissionDecision": "ask"}:
        raise Failure('%s: the island answered %s; expected {"permissionDecision":"ask"}' % (what, json.dumps(reply)))


# MARK: - Claude Code's hook input

def hook_input(session_id, event, project, **fields):
    payload = {
        "session_id": session_id,
        "transcript_path": "/Users/klayer-e2e/.claude/projects/-%s/%s.jsonl" % (project, session_id),
        "cwd": "%s/%s" % (PROJECTS, project),
        "permission_mode": "default",
        "hook_event_name": event,
    }
    payload.update(fields)
    return payload


def new_session():
    return str(uuid.uuid4())


def start_turn(session_id, project, prompt):
    """SessionStart then UserPromptSubmit of a session of the Claude app, each seen by the island
    before the next is sent (a real session spaces them too)."""
    fire(hook_input(session_id, "SessionStart", project, source="startup"), claude_app_env(), "SessionStart")
    wait_until("the session %s in the list" % project, lambda s: phase(s, session_id) is not None)
    fire(hook_input(session_id, "UserPromptSubmit", project, prompt=prompt), claude_app_env(), "UserPromptSubmit")
    wait_until("the session %s thinking" % project, lambda s: phase(s, session_id) == "thinking")


def stop(session_id, project, last_message):
    fire(hook_input(session_id, "Stop", project, stop_hook_active=False, last_assistant_message=last_message),
         claude_app_env(), "Stop")


def permission_request(session_id, project, command_line, env, args=()):
    payload = hook_input(session_id, "PermissionRequest", project, tool_name="Bash",
                         tool_input={"command": command_line, "description": "Run %s" % command_line},
                         permission_suggestions=[{"type": "addRules", "behavior": "allow", "destination": "localSettings",
                                                  "rules": [{"toolName": "Bash", "ruleContent": command_line}]}])
    return payload, Relay(payload, env, args)


ALLOW_OUTPUT = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}
DENY_OUTPUT = {"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                      "decision": {"behavior": "deny", "message": "Denied from Klayer Island"}}}


# MARK: - The app

class App:
    def __init__(self, executable, log_path, test_env):
        self.executable = executable
        self.log_path = log_path
        self.test_env = test_env
        self.proc = None
        self.log = None

    def launch(self):
        if not os.access(self.executable, os.X_OK):
            raise Failure("no test build at %s: build it as .github/workflows/build.yml does" % self.executable)
        # A socket left by an island that is gone: the wait below must see the new one.
        if os.path.exists(SOCKET_PATH):
            os.remove(SOCKET_PATH)
        env = dict(os.environ)
        env.pop("KLAYER_ISLAND_TEST", None)
        if self.test_env:
            env["KLAYER_ISLAND_TEST"] = "1"
        self.log = open(self.log_path, "ab")
        self.log.write(("\n==== %s %s (KLAYER_ISLAND_TEST=%s)\n" % (time.strftime("%H:%M:%S"), self.executable,
                                                                    "1" if self.test_env else "unset")).encode())
        self.log.flush()
        launched_at = time.time()
        self.proc = subprocess.Popen([self.executable], stdout=self.log, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, env=env, start_new_session=True)
        # The socket answers, and the relay the app writes at launch is there.
        deadline = time.monotonic() + LAUNCH_TIMEOUT
        while True:
            if self.proc.poll() is not None:
                raise Failure("the app exited with code %d during launch" % self.proc.returncode)
            if self.reachable() and os.access(RELAY_PATH, os.X_OK) and os.path.getmtime(RELAY_PATH) >= launched_at - 1:
                return
            if time.monotonic() >= deadline:
                raise Failure("no socket %s and relay %s written by the app within %.0f s"
                              % (SOCKET_PATH, RELAY_PATH, LAUNCH_TIMEOUT))
            time.sleep(POLL)

    @staticmethod
    def reachable():
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1)
        try:
            s.connect(SOCKET_PATH)
            return True
        except OSError:
            return False
        finally:
            s.close()

    def quit(self):
        if self.proc is None:
            return
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.proc = None
        if self.log:
            self.log.close()
            self.log = None

    def tail(self, lines=200):
        try:
            with open(self.log_path, "rb") as f:
                return b"".join(f.readlines()[-lines:]).decode(errors="replace")
        except OSError as error:
            return "(no log: %s)" % error


# MARK: - Scenarios

def ok(name):
    print("  ok  %s" % name, flush=True)


def scenario_1_finish_while_hidden(run):
    """A session of the Claude app ends while the island is hidden: it opens on the finished view."""
    sid, project = new_session(), "atelier-facturation"
    start_turn(sid, project, "Corrige le calcul de la TVA")
    print("  ..  waiting for the island to hide after the launch greeting (about 65 s)", flush=True)
    wait_until("the island hidden", lambda s: s["mode"] == "hidden", timeout=HIDE_TIMEOUT)
    stop(sid, project, "La TVA est corrigée et les tests passent.")
    wait_until("the island open on the finished view of %s (Claude app pill)" % project,
               lambda s: s["mode"] == "expanded" and s["view"] == "finished"
               and s["finishedSession"]["id"] == sid and s["finishedSession"]["title"] == project
               and s["finishedSession"]["pill"] == DESKTOP_PILL and phase(s, sid) == "finished")
    ok("1 a finished Claude app session opens the hidden island on its end, titled %s" % project)


def scenario_2_finish_during_prompt(run):
    """The same end while the chat is open: the chat stays, the session's row says finished."""
    command({"klayer_kind": "e2e_shortcut", "action": "openChat"})
    wait_until("the chat open", lambda s: s["mode"] == "expanded" and s["view"] == "prompt")
    sid, project = new_session(), "carnet-de-bord"
    start_turn(sid, project, "Résume les décisions de la semaine")
    stop(sid, project, "Le résumé est prêt.")
    wait_until("the row of %s finished" % project, lambda s: phase(s, sid) == "finished")
    keeps("the chat on screen", lambda s: s["mode"] == "expanded" and s["view"] == "prompt"
          and phase(s, sid) == "finished", QUIET)
    ok("2 a session that ends while the chat is open leaves the chat open, its row is finished")


def scenario_3_permission_allowed(run):
    """A permission of the Claude app: the card shows the command, e2e_decide allow answers it; a
    second one, denied, gives the deny output."""
    # Nothing to decide yet: a decision without a card on screen is refused.
    reply = send({"klayer_kind": "e2e_decide", "decision": "allow"})
    if not isinstance(reply, dict) or reply.get("ok") is not False:
        raise Failure("e2e_decide with no card on screen was answered %s; expected a refusal" % json.dumps(reply))
    sid, project = new_session(), "pipeline-donnees"
    start_turn(sid, project, "Lance les tests")
    choices_before = read_state()["choices"]
    _, relay = permission_request(sid, project, "npm test", claude_app_env())
    wait_until("the permission card of %s showing npm test" % project,
               lambda s: pending(relay, "the permission of %s" % project)
               and s["mode"] == "expanded" and s["view"] == "approval"
               and s["pendingApproval"]["pill"] == DESKTOP_PILL and s["pendingApproval"]["command"] == "npm test"
               and s["pendingApproval"]["session"] == sid and phase(s, sid) == "approval")
    # Scenario 8: left alone, the request is not approved.
    unanswered(relay, "the permission of %s" % project, lambda s: s["pendingApproval"]["session"] == sid
               and s["choices"] == choices_before)
    command({"klayer_kind": "e2e_decide", "decision": "allow"})
    expect_output(relay, ALLOW_OUTPUT, "PermissionRequest allowed")
    wait_until("the permission card closed and « Autorisé » recorded for npm test",
               lambda s: s["pendingApproval"] is None and s["view"] != "approval"
               and choices_since(s, run["started"]) == [("permission", "npm test", "Autorisé", project)])
    # Deny: the second button of the card, the same path.
    _, relay = permission_request(sid, project, "git push --force", claude_app_env())
    wait_until("the permission card of %s showing git push --force" % project,
               lambda s: pending(relay, "the second permission of %s" % project)
               and s["mode"] == "expanded" and s["view"] == "approval"
               and s["pendingApproval"]["command"] == "git push --force" and s["pendingApproval"]["session"] == sid)
    command({"klayer_kind": "e2e_decide", "decision": "deny"})
    expect_output(relay, DENY_OUTPUT, "PermissionRequest denied")
    wait_until("the permission card closed and « Refusé » recorded for git push --force",
               lambda s: s["pendingApproval"] is None and s["view"] != "approval"
               and choices_since(s, run["started"]) == [("permission", "git push --force", "Refusé", project),
                                                        ("permission", "npm test", "Autorisé", project)])
    ok("3 a Claude app permission shows npm test; allowed from the island, nb-hook prints the allow output; "
       "a second one denied prints the deny output")


def scenario_4_question_answered(run):
    """A question (AskUserQuestion, --ask hook) with 2 options: e2e_answer answers it."""
    sid, project = new_session(), "prototype-crm"
    start_turn(sid, project, "Monte le prototype")
    question = "Quelle base de données pour le prototype ?"
    questions = [{"question": question, "header": "Base", "multiSelect": False, "options": [
        {"label": "PostgreSQL", "description": "Robuste, déjà en production"},
        {"label": "SQLite", "description": "Un fichier, rien à installer"}]}]
    payload = hook_input(sid, "PreToolUse", project, tool_name="AskUserQuestion",
                         tool_input={"questions": questions}, tool_use_id="toolu_e2e_%s" % sid[:8])
    relay = Relay(payload, claude_app_env(), args=("--ask",))
    wait_until("the question card of %s with its 2 options" % project,
               lambda s: pending(relay, "the question of %s" % project)
               and s["mode"] == "expanded" and s["view"] == "question"
               and s["pendingQuestion"]["pill"] == DESKTOP_PILL
               and s["pendingQuestion"]["questions"] == [{"question": question, "options": ["PostgreSQL", "SQLite"],
                                                          "multiSelect": False}]
               and phase(s, sid) == "question")
    pending(relay, "the question of %s" % project)
    command({"klayer_kind": "e2e_answer", "answers": {question: "SQLite"}})
    expect_output(relay, {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
                                                 "updatedInput": {"questions": questions,
                                                                  "answers": {question: "SQLite"}}}},
                  "AskUserQuestion answered")
    wait_until("the question card closed and SQLite recorded",
               lambda s: s["pendingQuestion"] is None and s["view"] != "question"
               and choices_since(s, run["started"])[0] == ("question", question, "SQLite", project))
    ok("4 a Claude app question shows its 2 options; answered from the island, nb-hook prints updatedInput")


def scenario_5_answered_in_the_app(run):
    """A permission answered in the Claude app: its hook is killed, the card closes, no decision."""
    sid, project = new_session(), "site-vitrine"
    start_turn(sid, project, "Nettoie le dossier de build")
    _, relay = permission_request(sid, project, "rm -rf build", claude_app_env())
    state = wait_until("the permission card of %s" % project,
                       lambda s: pending(relay, "the permission of %s" % project)
                       and s["view"] == "approval" and s["pendingApproval"]["session"] == sid)
    choices_before = state["choices"]
    unanswered(relay, "the permission of %s" % project, lambda s: s["pendingApproval"]["session"] == sid
               and s["choices"] == choices_before)
    relay.kill()
    leftover = relay.proc.stdout.read().decode()
    if leftover:
        raise Failure("the killed nb-hook had printed %r" % leftover)
    wait_until("the card closed with « Handled in Claude. » and no choice recorded",
               lambda s: s["pendingApproval"] is None and s["view"] == "note" and s["note"] == "Handled in Claude."
               and s["choices"] == choices_before)
    keeps("no decision recorded", lambda s: s["pendingApproval"] is None and s["choices"] == choices_before, QUIET)
    ok("5 a permission answered in the Claude app (nb-hook killed) closes the card, no decision sent")


def scenario_6_notification_without_card(run):
    """A permission notification of the Claude app with no card: the island says Claude waits."""
    sid, project = new_session(), "revue-contrats"
    start_turn(sid, project, "Relis les clauses de résiliation")
    fire(hook_input(sid, "Notification", project, message="Claude needs your permission to use Bash",
                    notification_type="permission_prompt"), claude_app_env(), "Notification")
    wait_until("the note « Claude attend ta réponse » for %s" % project,
               lambda s: s["mode"] == "expanded" and s["view"] == "note"
               and s["claudeAppAlert"] == {"title": "Claude attend ta réponse",
                                           "message": "Une autorisation t'attend dans l'app Claude : %s" % project}
               and s["pendingApproval"] is None and phase(s, sid) == "approval")
    ok("6 a Claude app permission notification with no card opens « Claude attend ta réponse »")


def scenario_7_fall_through(run):
    """Requests the island does not show are answered "ask" at once."""
    # An agent Klayer Island does not follow: a hook an earlier build wired with --agent.
    sid, project = new_session(), "outil-tiers"
    payload, relay = permission_request(sid, project, "make deploy", hook_env(), args=("--agent", "codex"))
    expect_fall_through(relay, "unknown klayer_agent")
    raw = dict(payload, klayer_agent="codex", term_program="", bundle_id="")
    expect_raw_ask(raw, "unknown klayer_agent")
    # Claude Code in a terminal while terminal cards are off (the default).
    state = read_state()
    if state["terminalCards"] is not False:
        raise Failure("terminal cards are on in this account's preferences: scenario 7 needs them off")
    sid, project = new_session(), "scripts-terminal"
    payload, relay = permission_request(sid, project, "git push", terminal_env())
    expect_fall_through(relay, "terminal session, terminal cards off")
    raw = dict(payload, term_program="Apple_Terminal", bundle_id="com.apple.Terminal")
    expect_raw_ask(raw, "terminal session, terminal cards off")
    keeps("no card for them", lambda s: s["pendingApproval"] is None and s["view"] != "approval", QUIET)
    ok("7 an unknown klayer_agent and a terminal session (cards off) get ask at once")


def scenario_8_nothing_approves_alone(run):
    """Checked along the way (3 and 5); here, the run's history: the one allow and the one deny are
    e2e_decide's."""
    state = read_state()
    permissions = [c for c in choices_since(state, run["started"]) if c[0] == "permission"]
    if permissions != [("permission", "git push --force", "Refusé", "pipeline-donnees"),
                       ("permission", "npm test", "Autorisé", "pipeline-donnees")]:
        raise Failure("expected two permissions decided in this run by e2e_decide, npm test allowed and git push "
                      "--force denied; choices:\n%s" % show(state["choices"]))
    ok("8 nothing is allowed without e2e_decide (3 s unanswered in 3 and 5, the killed hook printed nothing)")


def status_line(session_id, project, env, **fields):
    """One run of the status line relay (nb-hook --statusline), with Claude Code's status line input:
    it forwards to the island and exits 0; no previous status line here, so it prints nothing."""
    payload = {
        "hook_event_name": "Status",
        "session_id": session_id,
        "transcript_path": "/Users/klayer-e2e/.claude/projects/-%s/%s.jsonl" % (project, session_id),
        "cwd": "%s/%s" % (PROJECTS, project),
        "model": {"id": "claude-opus-4-1", "display_name": "Opus"},
        "workspace": {"current_dir": "%s/%s" % (PROJECTS, project), "project_dir": "%s/%s" % (PROJECTS, project)},
        "version": "2.1.233",
    }
    payload.update(fields)
    code, out = Relay(payload, env, args=("--statusline",)).finish(5, "nb-hook --statusline")
    if code != 0 or out != "":
        raise Failure("nb-hook --statusline exited %d and printed %r; expected exit 0 and no output" % (code, out))


def title(state, session_id):
    row = session(state, session_id)
    return row["title"] if row else None


def scenario_9_session_name(run):
    """The name of a session titles its row and its finished view instead of its folder. The latest
    non-empty name wins, whatever its source: the status line's session_name, a custom title from a
    hook (session_title), then a newer status line name, then a newer hook title. The Code tab note
    names the session by the last one."""
    sid, project = new_session(), "refonte-onboarding"
    start_turn(sid, project, "Prépare la refonte de l'onboarding")
    name = "Refonte de l'onboarding client"
    status_line(sid, project, claude_app_env(), session_name="  %s  " % name)
    wait_until("the row of %s titled « %s »" % (project, name), lambda s: title(s, sid) == name)
    stop(sid, project, "Le plan de la refonte est prêt.")
    wait_until("the finished view of %s titled « %s »" % (project, name),
               lambda s: s["mode"] == "expanded" and s["view"] == "finished"
               and s["finishedSession"]["id"] == sid and s["finishedSession"]["title"] == name
               and phase(s, sid) == "finished" and title(s, sid) == name)
    # Renamed in the Claude app: the next prompt carries the custom title, which replaces the AI title.
    custom = "Onboarding v2"
    fire(hook_input(sid, "UserPromptSubmit", project, prompt="Ajoute l'étape de bienvenue", session_title=custom),
         claude_app_env(), "UserPromptSubmit with session_title")
    wait_until("the row of %s titled « %s »" % (project, custom),
               lambda s: phase(s, sid) == "thinking" and title(s, sid) == custom)
    # Renamed again: the status line carries the new name before any hook. It replaces the custom title.
    renamed = "Onboarding v3"
    status_line(sid, project, claude_app_env(), session_name=renamed)
    wait_until("the row of %s titled « %s » after a custom title" % (project, renamed),
               lambda s: title(s, sid) == renamed)
    # And a newer hook title wins again.
    latest = "Onboarding v4"
    fire(hook_input(sid, "UserPromptSubmit", project, prompt="Ajoute l'étape de fin", session_title=latest),
         claude_app_env(), "UserPromptSubmit with a newer session_title")
    wait_until("the row of %s titled « %s »" % (project, latest),
               lambda s: phase(s, sid) == "thinking" and title(s, sid) == latest)
    fire(hook_input(sid, "Notification", project, message="Claude needs your permission to use Bash",
                    notification_type="permission_prompt"), claude_app_env(), "Notification")
    wait_until("the note « Claude attend ta réponse » naming « %s »" % latest,
               lambda s: s["mode"] == "expanded" and s["view"] == "note"
               and s["claudeAppAlert"] == {"title": "Claude attend ta réponse",
                                           "message": "Une autorisation t'attend dans l'app Claude : %s" % latest})
    ok("9 a session goes by its latest name, whatever its source: the status line's titles its row and its "
       "finished view, a hook title replaces it, a newer status line name replaces that, a newer hook title "
       "wins again, and the Code tab note names the last one")


def unanswered(relay, what, still):
    """Scenario 8: a request nobody answers stays pending; nb-hook prints nothing and keeps waiting."""
    deadline = time.monotonic() + SILENCE
    while time.monotonic() < deadline:
        if not relay.waiting_silently():
            code = relay.proc.poll()
            raise Failure("%s was answered without e2e_decide: nb-hook %s" % (
                what, "printed something" if code is None else "exited %d" % code))
        state = read_state()
        if not holds(still, state):
            raise Failure("%s changed without e2e_decide; the state became:\n%s" % (what, show(state)))
        time.sleep(POLL)


SCENARIOS = [
    scenario_1_finish_while_hidden,
    scenario_2_finish_during_prompt,
    scenario_3_permission_allowed,
    scenario_4_question_answered,
    scenario_5_answered_in_the_app,
    scenario_6_notification_without_card,
    scenario_7_fall_through,
    scenario_8_nothing_approves_alone,
    scenario_9_session_name,
]


def check_no_test_commands():
    """The app answers the test commands like any unknown event: no state, no decision."""
    for message in ({"klayer_kind": "e2e_state"}, {"klayer_kind": "e2e_decide", "decision": "allow"},
                    {"klayer_kind": "e2e_answer", "answers": {}}, {"klayer_kind": "e2e_shortcut", "action": "openChat"}):
        reply = send(message)
        if reply != {"ok": True}:
            raise Failure("%s was answered %s; expected the plain {\"ok\":true} of an ignored event"
                          % (json.dumps(message), json.dumps(reply)))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", required=True, help="Contents/MacOS/KlayerIsland of the build to launch")
    parser.add_argument("--log", required=True, help="file that receives the app's stdout and stderr")
    parser.add_argument("--expect-no-test-commands", action="store_true",
                        help="the app must not answer the test commands")
    parser.add_argument("--without-test-env", action="store_true", help="launch without KLAYER_ISLAND_TEST=1")
    args = parser.parse_args()

    app = App(args.app, args.log, test_env=not args.without_test_env)

    def stop_on_sigterm(signum, frame):
        raise Stopped("stopped by SIGTERM")

    # A kill or the CI's timeout quits the app too, as a failure does (the finally below).
    signal.signal(signal.SIGTERM, stop_on_sigterm)
    failed = None
    try:
        app.launch()
        if args.expect_no_test_commands:
            check_no_test_commands()
            ok("%s (KLAYER_ISLAND_TEST=%s) answers no test command"
               % (args.app, "unset" if args.without_test_env else "1"))
        else:
            read_state()   # RED shape: a build without the test commands fails here
            run = {"started": time.time()}
            for scenario in SCENARIOS:
                try:
                    scenario(run)
                except Failure as error:
                    raise Failure("%s: %s" % (scenario.__name__, error))
            print("e2e: %d scenarios ok" % len(SCENARIOS), flush=True)
    except Failure as error:
        failed = error
    except Exception as error:   # a harness error is a failure too, with the app's log
        failed = Failure("%s: %s" % (type(error).__name__, error))
    finally:
        app.quit()
    if failed is not None:
        print("FAIL %s" % failed, flush=True)
        if os.path.exists(args.log):
            print("---- last 200 lines of %s ----" % args.log)
            print(app.tail(), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
