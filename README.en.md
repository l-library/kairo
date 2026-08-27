# kairo

A ready-to-use desktop AI assistant for Hyprland: **quickshell popup (QML)** + **PI SDK (Node daemon)**.

Press `Super+A` anytime. Two modes, Chat / Command: pure conversation never touches tools; full agentic shows a diff before writes and confirms before running commands.

**Language:** English | [中文](README.md)

## Features

- **Two modes**: Chat — pure conversation (no tool calls); Command — full agentic (read/write/edit/bash/grep/find/ls, 7 built-in tools).
- **Safety confirmation gate**: writes generate a diff first, commands show the full text before approval; read-only tools are auto-approved.
- **Isolated configuration**: dedicated PI config directory `~/.config/kairo/agent` (mcp / skills / plugins / sessions are all independent of `~/.pi`).
- **Session management**: single active session + history list, with new / switch / delete.
- **Streaming Markdown rendering**: bubble replies, tool cards, approval dialogs; bilingual UI (中文 / English), Chinese input works out of the box.
- **systemd-managed**: the daemon stays resident and restores the most recent session; the panel is summoned via a Hyprland keybind.

## Screenshots

| Chat mode: conversation only | Command mode: tool calls (web_search) |
|---|---|
| ![Chat mode](assets/chat.png) | ![Command mode](assets/cmd.png) |

| Command mode: writing code | Settings panel: providers & skills |
|---|---|
| ![Writing code](assets/code_write.png) | ![Settings panel](assets/setting.png) |

## Prerequisites

| Dependency | Requirement | Notes |
|------|------|------|
| Hyprland | runtime | the popup is a layer-shell window |
| Node.js | ≥ 24 | daemon build & runtime (`install.sh` checks the version) |
| pi (PI Coding Agent) | installed & provider logged in | keys are imported from `~/.pi/agent`; install still completes without keys — run `kairoctl reimport` later |
| quickshell | ≥ 0.3 | popup rendering. `nix profile install nixpkgs#quickshell` or distro package / AUR |
| python3 | any | `kairoctl status` JSON parsing |
| fcitx5 | optional | Chinese input in the panel; handled automatically by toggle-kairo.sh under nix |
| Internationalization | — | UI language: switch with the 中/EN chip in the title bar; persisted in `~/.config/kairo/settings.json` |

The repo can live anywhere — the install script writes the actual paths into the systemd unit and the Hyprland snippet.

## Quick start

```bash
# 1. Install (build daemon → systemd unit → import keys → write Hyprland snippet)
./scripts/install.sh            # add --skip-setup if pi keys aren't configured yet; run kairoctl reimport later

# 2. Summon the panel (Super+A, or manually)
./scripts/toggle-kairo.sh

# 3. Manage
kairoctl status      # mode / session / pending approvals
kairoctl restart     # restart the daemon (restores the most recent session)
kairoctl logs        # live logs
```

## Architecture

```
Hyprland
├─ keybind Super+A ──→ scripts/toggle-kairo.sh ──→ quickshell (shell/config.qml)
│                                                     └─ IPC: quickshell ipc call kairo toggle
├─ quickshell panel (QML, top-right overlay layer)
└─ kairo-daemon (systemd --user, Node 24)
     ├─ HTTP :44811  REST control plane (Bearer token auth)
     ├─ WebSocket /ws event stream (for scripts / other clients)
     └─ panel.sock    Unix socket (panel-only, 0600 file-permission auth)
```

## Repo layout

| Path | Purpose |
|------|------|
| `daemon/` | Node + TS daemon (`npm run build` → `dist/main.js`) |
| `daemon/src/approval.ts` | Confirmation gate: edit/write produce a diff, bash shows the full command; the approval registry holds pending approval promises |
| `daemon/src/agent.ts` | AgentSession wrapper, event normalization, `setRebindSession` session rebinding |
| `daemon/src/panel-socket.ts` | Panel Unix socket (native channel since quickshell can't do TCP) |
| `daemon/src/i18n.ts` | Bilingual (zh/en) user-facing strings for the daemon |
| `shell/` | quickshell QML project (`config.qml` entry) |
| `shell/qml/` | Components: ChatPanel / MessageBubble / ToolCard / ApprovalDialog / SessionSidebar / InputBar / KairoClient / TitleBar / I18n |
| `scripts/` | setup.sh (key import) / install.sh / toggle-kairo.sh / kairoctl |
| `skills/` | Built-in skills (kairo-skills: teaches the model to install skills; synced during install) |
| `docs/` | Config reference & usage docs (incl. `docs/skills.md` manual skill install guide) |

## Host isolation

kairo uses a dedicated PI config directory `~/.config/kairo/agent` (mcp/skills/plugins/sessions are all independent of `~/.pi`);
keys are imported once by `scripts/setup.sh` and then evolve independently. The Command-mode working directory is a neutral
directory `~/.local/share/kairo/workdir` (no AGENTS.md / .pi placed there), avoiding any host project resources.

## Milestones

M0 tech validation ✅ · M1 daemon skeleton ✅ · M2 panel + chat ✅ · M3 Command mode ✅ · M4 sessions & polish ✅

Full design and decisions: see [PLAN.md](PLAN.md).

## Demo

A real Command-mode workflow: ask the AI to process a video; it offers several approaches (ffmpeg transcode / mpv·vlc playback),
a confirmation card pops up before running the command, and after approval it produces a no-audio `video_noaudio.mp4`.

[Video demo](assets/display.mp4)

## Contributing

Issues and PRs are welcome.

- `daemon/` is an npm workspace: after changes run `npm run build`, then `kairoctl restart`.
- `shell/` is quickshell QML: refresh the panel after changes.
- Full design and decisions: see [PLAN.md](PLAN.md).

## License

[LICENSE](LICENSE)