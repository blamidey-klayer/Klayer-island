# Klayer Island: session sources

Klayer Island follows two kinds of session: Claude Code, and Claude Code sessions started from the Claude desktop app. Every other agent is out of scope: no pill, no approval card.

## The `klayer_agent` field

The relay adds the optional field `klayer_agent` to the hook JSON it forwards. Klayer Island reads it to decide where a session belongs.

| `klayer_agent` | Session | Pill |
|---|---|---|
| absent or empty | Claude Code | `integration_claude` |
| `claude-desktop` | Claude Code started from the Claude desktop app | `agent_claude-desktop` |
| any other value | not followed | none |

An event with any other value is dropped. A `PermissionRequest` carrying one is answered `{"permissionDecision":"ask"}`, so that tool asks in its own window.

## Claude Code

Settings → Agents → **Install hooks** writes the Klayer Island hooks into `~/.claude/settings.json`. The app backs the file up, merges its hooks, shows the diff and writes only after you confirm. The hook command is `nb-hook`, a shell wrapper around a Python relay that forwards each event to Klayer Island over a Unix domain socket and always exits 0, so Claude Code is never blocked.

Events installed: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, plus a dedicated `PreToolUse` hook for `AskUserQuestion` (`nb-hook --ask`).

Where the session runs decides how it is routed:

- VS Code or Cursor (the integrated terminal): `integration_claude`. Cursor is recognised by its bundle identifier only.
- A known terminal (Warp, Terminal, iTerm, Ghostty, kitty, and so on): `integration_claude`, with the terminal recorded on the pill. Its questions and permission requests are asked in the terminal unless you turn on **Answer questions and permissions from terminal sessions in the notch**.
- Anything else: ignored.

Permission cards (Allow, Deny, Always) and `AskUserQuestion` cards appear for Claude Code only. If the app is not running, the hook returns at once and Claude Code asks as usual.

If you talk to the socket directly, send newline-terminated JSON to `~/Library/Application Support/NotchBuddy/nb.sock`.

## Claude desktop app

Claude Code sessions started from the Claude desktop app's Code tab carry `CLAUDE_CODE_ENTRYPOINT=claude-desktop`. The relay tags them `klayer_agent: claude-desktop` on its own, so nothing extra is installed beyond the Claude Code hooks. The sessions get the `agent_claude-desktop` pill. Their permission requests and questions show in the island like the Claude Code ones: the first answer wins, the island's (Allow, Deny, Always) or the Claude app's own prompt, and the island card closes when the app answers first. « Répondre dans Claude » on a question hands it back to the app. The ↗ button on the pill opens the Claude app.

## Pill lifecycle

| Event | Effect |
|---|---|
| `SessionStart` | Creates the pill (if absent), sets state to idle |
| `UserPromptSubmit` | State → thinking; prompt shown in ticker |
| `PreToolUse` | State → working; tool label shown in ticker |
| `PostToolUse` / `PostToolUseFailure` | State → working |
| `Notification` | Rate-limit or question state if applicable |
| `Stop` | State → finished for 5 s; active declared pills (catalog + checked in Settings) reset to idle, all others are removed |
| `StopFailure` | State → error |
| `SessionEnd` | Active declared pills (catalog + checked in Settings) reset to idle, all others are removed |
| `SubagentStart` / `SubagentStop` | Step added to ticker |

## Declared pills

A **declared pill** is a catalog entry (`PillCatalog.swift`) that has been enabled in **Settings → Active pills**. When a session ends for a declared pill, the pill stays visible and resets to idle instead of disappearing.

A catalog pill that is not checked in Settings gets an automatic pill when a session starts, and that pill is removed when the session ends.

Claude Desktop (`agent_claude-desktop`) is in the catalog: declare it to keep it after the session ends. Cursor (`agent_cursor`) is there as a workspace pill that can be declared and set as the main pill; the sessions that run in Cursor appear on the Claude Code pill.

## Other tools

Klayer Island no longer installs hooks or plugins for other agents, and the relay no longer translates their event names. If an earlier version wired a hook for another tool, it keeps calling `nb-hook --agent <name>`: the app ignores it and answers `ask` to its permission requests. A leftover entry does nothing useful and can get in the way of that tool's own tool calls, so remove it by hand.

Where an earlier version wrote them (each entry runs `nb-hook` with `--agent <name>`):

| Tool | What to delete |
|---|---|
| Codex | the Klayer Island entries in `~/.codex/hooks.json` (`--agent codex`) |
| GitHub Copilot CLI | the file `~/.copilot/hooks/klayer.json`, which Klayer Island wrote on its own |
| Gemini CLI | the Klayer Island entries under `hooks` in `~/.gemini/settings.json` (`--agent gemini`) |
| Antigravity | the Klayer Island entries in `~/.gemini/config/hooks.json` (`--agent antigravity`) |
| OpenCode | the file `~/.config/opencode/plugins/klayer.js` |
| Amp | the file `~/.config/amp/plugins/klayer.ts` |
| Hermes Agent | the folder `~/.hermes/plugins/klayer`; and, if you had turned on approvals in the notch, the lines `transport: klayer` and `transport_fallback: builtin` under `security.approval` in `~/.hermes/config.yaml` |
| Muse Code | the Klayer Island entries under `hooks` in `~/.config/muse/settings.json` (`--agent muse`) |

Leave every other hook of those tools alone. In a file Klayer Island shares with the tool, delete only the entries whose command contains `nb-hook`.

## Quick test (macOS)

With Klayer Island running:

```sh
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","prompt":"hello"}' \
  | /bin/sh ~/Library/Application\ Support/NotchBuddy/nb-hook --agent claude-desktop
```

A "claude-desktop" pill should appear in the island.
