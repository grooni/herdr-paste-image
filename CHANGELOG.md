# Changelog

## 0.2.0 — 2026-09-21

### Fixed

- **Paste no longer hangs on large images.** Stripping the UTF-8 BOM used a
  leading-`*` pattern removal, which is O(n²) in bash — a full-screen
  screenshot (hundreds of KB of base64) spun at 99% CPU for minutes, so F8
  looked dead. A BOM can only occur at the very start of the string, so the
  first three bytes are now checked and sliced off in constant time.

- **Claude Code panes now actually receive the image.** The `[Image #N]`
  counter was computed but never sent — Claude Code treats a bare pasted
  path as plain text and ignores it. The label is now included in the typed
  text.

### Changed

- **Per-agent paste text.** Codex, Gemini CLI and other agents that read
  plain paths get the bare path (no extra noise); Claude Code gets the
  `[Image #N] <path>` format, matching its own native image paste. The
  focused pane's agent is detected via `herdr pane current`.

- **Single image-counter storage.** The `[Image #N]` counter no longer
  resets when the script is invoked manually instead of through Herdr.

## 0.1.0 — 2026-09-16

Initial release.

- **paste** — save a clipboard image as a PNG (WSL via `powershell.exe`,
  Linux via `wl-paste`/`xclip`) and type its absolute path into the focused
  agent pane; falls back to pasting clipboard text so a direct-key binding
  does not break normal pasting.
- **dedent** — strip the shared leading whitespace from mouse-copied TUI
  text while preserving relative indentation.
- **copy-unwrapped** — copy recent pane output with soft line wraps undone
  (rejoins mid-word breaks from narrow panes, filters TUI chrome).
