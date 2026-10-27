# Terminal: Windows Terminal vs WezTerm vs our own

Measured on 2026-10-19 on the laptop (Ryzen 5 5600H, Windows 11). The prototype is in `terminal/wezterm/`.

## Options

| | Control | Notes |
|---|---|---|
| Windows Terminal | low: JSON config only, no events or scripting | comes with Windows 11; global summon (Ctrl+Alt+T); runs elevated |
| **WezTerm** | **high**: Lua config with events, panes and sizes in code, user vars from the shell, its own CLI (`wezterm cli`) | GPU; kitty/sixel/iTerm images; multiplexer and SSH domains |
| Alacritty | low: no tabs or splits | fastest, but would need tmux (not on native Windows) |
| Kitty / Ghostty | high | no stable Windows build |
| Our own | total | VT parser, ConPTY, fonts, Unicode, IME, selection... months of work to reach WT; not worth it |

## Measurements

| | Result |
|---|---|
| WezTerm: window opened → command running | 0.36 to 0.67 s (median ≈ 0.5 s) |
| WezTerm: memory of `wezterm-gui` | 125 to 180 MB depending on the renderer (Software ≈ 127, OpenGL ≈ 154, WebGpu ≈ 126 to 190) |
| Windows Terminal open at the time | ≈ 25 MB (WindowsTerminal.exe) + 27 MB (OpenConsole); the window was hidden, so maybe trimmed |
| pwsh without profile | ≈ 0.31 to 0.41 s |
| pwsh with our profile (command mode) | ≈ 0.57 to 0.80 s |

**Reading:**
- The terminal is not the bottleneck. WezTerm opens as fast as WT and uses 3 to 4 times more memory.
- **What slows down our terminal is the pwsh startup plus the profile** (+0.3 to 0.5 s on top of pwsh). That gets fixed in the profile (phase 1: modules, lazy loading), not by changing terminals.

## What WezTerm solves (tested in the prototype)

The pin goes native, without hacks. Each tab gets a header pane on top, created in Lua:
- **Height:** the header says how many rows it needs (user var `rows`), and Lua sets the pane to that, including after a window resize.
- **Focus:** the header never keeps the focus (`update-status` hands it back to the shell).
- **Splits:** `split-pane` (Ctrl+D) splits only the shell and the header stays across the full width.
- **Closing:** when the last shell closes, the header and the tab close by themselves.
- **Zoom:** done through `wezterm cli zoom-pane` (no fake keypresses).
- **Shortcuts:** the same as WT live in the config (Ctrl+T/D/W/Q/E, Ctrl+1..9, Ctrl+arrows, Ctrl+Shift+Z, smart Ctrl+C).

All of this replaces, in WT: files in `%TEMP%` to sync the panes, `keybd_event` for zoom, `wt.exe move-focus`, and the PSReadLine handler for Ctrl+D.

## What it does not have (yet)

- **Global summon** (Ctrl+Alt+T shows/hides the terminal from anywhere): WezTerm doesn't have it; it needs a helper (tray app / AutoHotkey) or stays in WT.
- **Elevation**: WT opens as admin (`elevate: true`); WezTerm doesn't.
- **Tab restore** (today based on `WT_SESSION`): would have to be redone (resurrect plugin or our own).
- **Releases**: the last stable is 2024-02-03; the repo is active (nightlies). Installing with winget needs admin; the portable zip in `~\.local\wezterm` works without it.
- More memory (see above).

## Decision (2026-10-19): WezTerm

Kev chose WezTerm. It's installed on both PCs (portable in `~\.local\wezterm`) with the gaps closed:
- **Ctrl+Alt+T**: `terminal/agent/agent.cs` (7 KB, compiled with the .NET Framework `csc` that comes with Windows). Starts with Windows from the Startup folder and opens WezTerm hidden at login (`--prelaunch`). The hotkey shows / hides it and reopens it if it was closed. Ctrl+W on the last shell only hides the window (`agent --hide`). Tested: show, hide, show, reopen after a kill.
- **Admin**: the terminal opens normally; `sudo <command>` when needed (Windows 11 built-in sudo on the laptop, gsudo on the Windows 10 desktop).
  - **Changed 2026-10-27 (Kev):** the agent starts WezTerm directly, so it gets the agent's rights. On Kev's PCs the agent runs elevated (`TerminalKeepAlive` task), so the terminal is always admin. Started from the Startup folder, it stays normal. Side effect: Windows blocks drag and drop from Explorer into an admin window.
- **Tab restore**: the prompt sends the folder (user var `cwd` + OSC 7); Lua saves the tabs every 3 s in `session.json` and reopens them on start, each with its header and its shells side by side. Tested: 2 tabs, one with 2 shells, after a kill.
- **pin** in WezTerm toggles the header pane through `wezterm cli`.
- The old `TerminalKeepAlive` task (elevated) keeps only the home tidy; on a PC with the agent it no longer opens Windows Terminal. **The switch takes effect at the next sign-in** (Windows Terminal keeps Ctrl+Alt+T until it's closed).
- Still open: memory (≈150 MB), stable release from 2024 (version pinned in the installer).

## WezTerm nightly (2026-10-19)
The 2024-02-03 stable swallows sixel images written by a script: its bundled ConPTY doesn't pass the DCS through, so the `yt` thumbnails never showed up. The **nightly 20261010-083911-e2a98e1b** shows them; that's the pinned version.
- The Windows Terminal 1.24 `OpenConsole.exe` does not work with WezTerm 2024 (resize fails, then a panic).
- chafa, when it runs inside WezTerm, puts `?80l ?8452l` before the image, and WezTerm then doesn't show it. Everything before `ESC P` is stripped.
- chafa without a terminal assumes 10x20 px cells; the WezTerm cell is ~9x24 (line height 1.25). yt reads the real cell (`wezterm cli list`: pixel_width / cols) and asks chafa for the equivalent size, in its own cache folder per cell size.
- Video page: `Get-WezGeom` finds the WezTerm window of the pane and places mpv using padding × DPI + the tab bar.

## Original recommendation

**WezTerm as the SuperTerminal terminal**, if a few days of real use confirm it. The memory cost buys control that WT will never give, and it makes the setup portable (one Lua config, no `%TEMP%` hacks). Before deciding:
1. Kev uses it a few days (`~\.local\wezterm\wezterm-gui.exe`).
2. Small global summon helper (RegisterHotKey + show/hide the window), so Ctrl+Alt+T doesn't go away.
3. Performance comes from the profile (phase 1), whichever terminal wins.

