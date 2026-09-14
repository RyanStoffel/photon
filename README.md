# Photon

<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Photon icon">
</p>

Photon is a stripped-down, macOS-only launcher. It opens instantly, stays out of the Dock, and covers the few things that actually get used: applications, clipboard history, notes, file search, and keybinds.

It is not an extension platform. There is no AI, no account, no cloud sync, and no telemetry.

## Features

- **Launcher** — `Cmd+Space` opens a floating search panel. Configurable hotkey.
- **Applications** — fuzzy search over `/Applications`, `/System/Applications`, `~/Applications`, and System Settings panes, ranked by frecency.
- **Clipboard history** — `Cmd+Shift+V`, or type `cb ` in the launcher. Text (with rich text), links, images, and files; searchable, pin, paste back or copy. Retention of 1/7/30 days or forever, an item limit, and excluded apps (password managers by default).
- **Notes** — quick floating notes with lightweight markdown (Phase 2).
- **File search** — type `/` or `f ` (or run *Search Files*) to search the whole Mac through Spotlight. Enter opens, `Cmd+Enter` reveals in Finder, Space or `Cmd+Y` toggles Quick Look, `Cmd+C` copies the path, `Cmd+I` shows size and dates. Strong file matches also appear below applications in the main list.
- **Keybinds** — Hyper key, app hotkeys, and window management (Phase 2).

## Install

```sh
brew install --cask ryanstoffel/taps/photon
```

Requires macOS 14 or later.

Photon is distributed from [RyanStoffel/homebrew-taps](https://github.com/RyanStoffel/homebrew-taps). Until a signed, notarized release exists, macOS Gatekeeper will block the first launch: open **System Settings > Privacy & Security** and click **Open Anyway**.

## Permissions

Photon is a menu-bar agent (`LSUIElement`). It does not appear in the Dock.

| Permission | When | Why |
| --- | --- | --- |
| none for the launcher itself | Phase 1 | `RegisterEventHotKey` does not require Input Monitoring. |
| Keyboard shortcuts | first launch | macOS Spotlight also defaults to `Cmd+Space`. Photon detects the conflict and tells you how to disable Spotlight's shortcut under **System Settings > Keyboard > Keyboard Shortcuts > Spotlight**. |
| Login Item | optional | "Launch at login" on the General settings tab uses `SMAppService`. |
| Accessibility | optional | Pasting a clipboard item into the frontmost app (Photon sends `Cmd+V`). Without it, Return copies the item and shows a hint. Also window management and the Hyper key (Phase 2). |
| Full Disk Access | optional | File search only sees what Spotlight indexes; folders in Spotlight Privacy stay hidden. Photon adds its own excluded-folders list under **Settings > Files**. |

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching model, commit style, and PR flow.

```sh
git clone https://github.com/RyanStoffel/photon.git
cd photon
Scripts/package_app.sh
```

Architecture: [docs/architecture.md](docs/architecture.md). Releases: [docs/releasing.md](docs/releasing.md).

## License

[MIT](LICENSE)
