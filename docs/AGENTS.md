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

Settings → Agents → **Install hooks** writes the Klayer Island hooks into `~/.claude/settings.json`. The app first shows what changes in the `hooks` block, one entry per line (`-` removed, `+` added), writes only after you click **Confirm and write**, and backs the file up just before. It only touches its own entries: a command that runs its `nb-hook`, or the `~/.claude/klayer/nb-hook` of earlier builds. Your own hooks stay, even under a path that contains "klayer". **Uninstall** works the same way. The hook command is `nb-hook`, a shell wrapper around a Python relay that forwards each event to Klayer Island over a Unix domain socket and always exits 0, so Claude Code is never blocked.

Events installed: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, plus a dedicated `PreToolUse` hook for `AskUserQuestion` (`nb-hook --ask`).

Where the session runs decides how it is routed:

- VS Code or Cursor (the integrated terminal): `integration_claude`. Cursor is recognised by its bundle identifier only.
- A known terminal (Warp, Terminal, iTerm, Ghostty, kitty, and so on): `integration_claude`, with the terminal recorded on the pill. Its questions and permission requests are asked in the terminal unless you turn on **Answer questions and permissions from terminal sessions in the notch**.
- Anything else: ignored.

Permission cards (Allow, Deny, Always) and `AskUserQuestion` cards appear for Claude Code in an editor and in the Claude desktop app. For a session in a terminal they appear only when **Answer questions and permissions from terminal sessions in the notch** is on; it is off by default, and the terminal then asks itself. If the app is not running, the hook returns at once and Claude Code asks as usual.

If you talk to the socket directly, send newline-terminated JSON to `~/Library/Application Support/NotchBuddy/nb.sock`.

## Claude desktop app

Claude Code sessions started from the Claude desktop app's Code tab carry `CLAUDE_CODE_ENTRYPOINT=claude-desktop`. The relay tags them `klayer_agent: claude-desktop` on its own, so nothing extra is installed beyond the Claude Code hooks. The sessions get the `agent_claude-desktop` pill. Their permission requests and questions show in the island like the Claude Code ones. The island answers through the hook (Allow, Deny, Always), the Claude app keeps its own prompt, and the Claude Code documentation says the first answer applies. To check on a Mac (spike S1): that the app's prompt goes away when the island answers first, and that the island card closes when the app answers first (the card closes when the hook connection closes, as for Claude Code). « Répondre dans Claude » on a question hands it back to the app. A click on the session's row on the home opens the Claude app.

Since lot 6 the home has no Claude Desktop pill (nor a Claude Code one): each session is a row of the home's list, with its project, its state and its last action, and a finished session stays there in grey until midnight. The `agent_claude-desktop` id stays for routing, Klay's pose and the cards. A notification of a Claude app session that asks something (a permission, an MCP form, or the idle prompt after a finish the island could not show) opens the island on « Claude attend ta réponse » with « Ouvrir Claude ». When the island is busy (a card waits, the chat is open…), the alert is held and shows once the island frees, and the house tab of the header carries a badge meanwhile. The Chat and Cowork modes of the app send no hook: an experimental watch reads the app's buttons through macOS Accessibility. See `docs/SPEC.md` §16 and `docs/INTEGRATIONS.md` §1 and §8.

## Pill lifecycle

| Event | Effect |
|---|---|
| `SessionStart` | Creates the pill (if absent), sets state to idle |
| `UserPromptSubmit` | State → thinking; the prompt becomes the session's last action on the home |
| `PreToolUse` | State → working, or searching (binoculars) for Grep, Glob, LS, WebSearch, WebFetch and a Bash search command; the tool label becomes the session's last action on the home |
| `PostToolUse` / `PostToolUseFailure` | State → working; a search keeps the binoculars at least 1.5 s |
| `Notification` | Rate-limit or question state if applicable. For a Claude app session, a notification that asks something puts its row on « Attend ton accord » or « Te pose une question » and opens the island on « Claude attend ta réponse » (held while the island is busy); every one is logged in `nb.log` with its type, never its text |
| `Stop` | State → finished for 5 s; active declared pills (catalog + checked in Settings) reset to idle, all others are removed |
| `StopFailure` | State → error; the island opens on the error view of that session, as for `Stop` |
| `SessionEnd` | Active declared pills (catalog + checked in Settings) reset to idle, all others are removed |
| `SubagentStart` / `SubagentStop` | Step added to the pill; the session's row is unchanged |

## Declared pills

A **declared pill** is a catalog entry (`PillCatalog.swift`) that has been enabled in **Settings → Active pills**. When a session ends for a declared pill, the pill stays visible and resets to idle instead of disappearing.

A catalog pill that is not checked in Settings gets an automatic pill when a session starts, and that pill is removed when the session ends.

Claude Desktop (`agent_claude-desktop`) is in the catalog: declare it to keep it after the session ends. Editors have no pill: the sessions that run in VS Code or Cursor appear on the Claude Code pill, like terminal sessions.

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
| Hermes Agent | the folder `~/.hermes/plugins/klayer`, and the `- klayer` line under `plugins.enabled` in `~/.hermes/config.yaml`; and, if you had turned on approvals in the notch, the lines `transport: klayer` and `transport_fallback: builtin` under `security.approval` in `~/.hermes/config.yaml` |
| Muse Code | the Klayer Island entries under `hooks` in `~/.config/muse/settings.json` (`--agent muse`) |

Leave every other hook of those tools alone. In a file Klayer Island shares with the tool, delete only the entries whose command contains `nb-hook`.

## Quick test (macOS)

With Klayer Island running:

```sh
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","cwd":"/tmp/essai","prompt":"hello"}' \
  | /bin/sh ~/Library/Application\ Support/NotchBuddy/nb-hook --agent claude-desktop
```

Hover the notch to open the island: the home's list shows a row « essai » (the last folder of `cwd`), « Réfléchit », with « hello » as its last action. No pill appears: since lot 6 the home has none for Claude.
