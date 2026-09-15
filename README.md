# herdr-paste-image

A [Herdr](https://herdr.dev) plugin with two clipboard helpers for AI agent
panes:

1. **Paste image** — gives **every AI agent in Herdr the image-paste
   experience of Claude Code**. Press a key → the plugin grabs the image from
   your clipboard, saves it as a PNG file, and types
   `[Image #N] /absolute/path.png` into the focused agent pane (Codex, Gemini
   CLI). The agent reads the file and sees the actual image —
   the same result as Claude Code's native clipboard paste, which other
   agent CLIs don't have. If the clipboard contains text instead of an
   image, the plugin pastes the text, so binding it to a direct key does not
   break normal pasting.

2. **Dedent clipboard** — TUI agents (Codex, …) render output with a left
   margin, so mouse-copied text carries extra leading spaces on every line.
   The dedent action strips the shared leading whitespace from all clipboard
   lines while preserving relative indentation (nested lists, code).

## How it works

1. Reads an image from the clipboard:
   - **WSL** (Windows clipboard) via `powershell.exe`
   - **Linux** via `wl-paste` (Wayland) or `xclip` (X11)
2. Saves it as `paste-YYYYMMDD-HHMMSS.png` into a configurable directory
   (default: `~/.local/state/herdr-paste-images/`)
3. Types the absolute path into the focused pane with
   `herdr pane send-text`
4. Shows a Herdr notification with the saved path

## Requirements

- Herdr **0.7.4+**
- WSL with `powershell.exe` on PATH, **or** Linux with `wl-paste` / `xclip`
- `jq` and `base64`

## Install

From GitHub (after publishing):

```bash
herdr plugin install <owner>/herdr-paste-image
```

Local development:

```bash
git clone https://github.com/<owner>/herdr-paste-image
herdr plugin link /path/to/herdr-paste-image
```

## Keybindings

Add to `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "f9"
type = "shell"
command = "/home/qo0d/.local/bin/herdr plugin action invoke paste-image.dedent"
description = "strip shared indent from clipboard text"

[[keys.command]]
key = "f8"
type = "shell"
command = "/home/qo0d/.local/bin/herdr plugin action invoke paste-image.paste"
description = "paste clipboard image as path"
```

Reload the config with `prefix+shift+r` (or restart Herdr) after editing.
Use the absolute path of your `herdr` binary in `command`.

Version notes (tested on Herdr 0.7.4 / WSL2 / Windows Terminal):

- `type = "plugin_action"` with `command = "paste-image.paste"` is the
  documented form, but it did not fire on 0.7.4 — use `type = "shell"` as
  above. On newer Herdr versions, try `plugin_action` first.
- Direct `ctrl+v` never reaches Herdr: Windows Terminal intercepts it as
  text paste. `alt+v` arrives as `ESC`+`v` and 0.7.4 does not reassemble it
  into a chord. Function keys (e.g. `f8`) and `prefix` bindings are reliable.
- Claude Code has native clipboard image paste of its own (Alt+V on
  Windows/WSL); other agents (Codex, …) do not — that is exactly the gap
  this plugin fills.

## Configuration: where images are stored

Find the plugin config directory:

```bash
herdr plugin config-dir paste-image
```

Create a `config.env` file there:

```bash
image_dir=~/pictures/agent-pastes     # absolute path, ~ is expanded
```

Priority: `HERDR_PASTE_IMAGE_DIR` env var → `image_dir` in `config.env` →
default `~/.local/state/herdr-paste-images/`.

## Test without the hotkey

```bash
# put an image in your clipboard (e.g. Win+Shift+S on Windows),
# then:
herdr plugin action invoke paste-image.paste
# copy text with extra indentation, then:
herdr plugin action invoke paste-image.dedent
```

A notification should appear and the path should be typed into the focused
pane. Plugin logs: `herdr plugin log list --plugin paste-image`.

## Publishing your own plugins

Herdr's marketplace indexes public GitHub repositories tagged
[`herdr-plugin`](https://herdr.dev/plugins/) that contain a valid
`herdr-plugin.toml`. Push this repo, add the topic `herdr-plugin`, and anyone
can install it with `herdr plugin install <owner>/herdr-paste-image`.

## License

MIT — see [LICENSE](LICENSE).

---

## По-русски

Плагин для [Herdr](https://herdr.dev): вставка картинок в промпт **любого
агента** (Codex, Gemini, Claude Code…) — как встроенная вставка Claude Code,
которой у других агентов нет.

Нажал **Ctrl+V** → картинка из буфера сохранилась в PNG → в поле ввода
активного агента вставилось `[Image #N] /абсолютный/путь.png` → агент читает
файл и видит изображение. Если в буфере текст, а не картинка — вставится
текст, так что обычная вставка не ломается.

**Поддержка:** WSL (буфер Windows через `powershell.exe`) и Linux
(`wl-paste`/`xclip`). Требуется Herdr 0.7.4+, `jq` и `base64`.

**Установка:** `herdr plugin link <путь к папке плагина>` (локально) или
`herdr plugin install <owner>/herdr-paste-image` (с GitHub).

**Хоткеи** — добавить в `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "f9"
type = "shell"
command = "/home/qo0d/.local/bin/herdr plugin action invoke paste-image.dedent"
description = "strip shared indent from clipboard text"

[[keys.command]]
key = "f8"
type = "shell"
command = "/home/qo0d/.local/bin/herdr plugin action invoke paste-image.paste"
description = "paste clipboard image as path"
```

**F8** — вставить картинку из буфера как путь в активного агента.
**F9** — убрать лишние отступы слева из текста в буфере (после копирования
мышкой из Codex и других TUI, которые рисуют вывод с полем слева).
Вложенность списков и отступы кода сохраняются — срезается только общий
лишний префикс.

После правки конфига — `prefix+shift+r` или перезапуск Herdr. В `command`
укажи полный путь к своему бинарнику herdr.

Проверено на Herdr 0.7.4 / WSL2 / Windows Terminal:

- `type = "plugin_action"` в доках есть, но на 0.7.4 не срабатывал —
  используй `type = "shell"` как выше; на новых версиях herdr попробуй
  `plugin_action`
- `ctrl+v` до herdr не долетает (Windows Terminal перехватывает под вставку
  текста), `alt+v` приходит как ESC+v и 0.7.4 не собирает его в аккорд —
  надёжно работают функциональные клавиши (`f8`) и префикс (`prefix+i`)
- У Claude Code есть своя родная вставка картинок (Alt+V на Windows/WSL);
  у Codex и других агентов её нет — именно эту дыру плагин и закрывает

**Где хранить картинки** (настраивается):

```bash
herdr plugin config-dir paste-image   # узнать папку конфига плагина
# создать там файл config.env со строкой:
image_dir=~/my/screenshots
```

Приоритет: переменная `HERDR_PASTE_IMAGE_DIR` → `image_dir` из `config.env` →
по умолчанию `~/.local/state/herdr-paste-images/`.

**Тест без хоткея:** положи картинку в буфер (Win+Shift+S), затем
`herdr plugin action invoke paste-image.paste`. Логи:
`herdr plugin log list --plugin paste-image`.

**Публикация:** push на GitHub + топик `herdr-plugin` — плагин попадёт в
маркетплейс Herdr.

Лицензия MIT.
