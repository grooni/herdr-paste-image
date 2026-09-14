# herdr-paste-image

A [Herdr](https://herdr.dev) plugin that lets you **paste images into your AI
agent's prompt with one hotkey** — the same way you paste images into Claude
Code or ChatGPT.

Press a key → the plugin grabs the image from your clipboard, saves it as a
PNG file, and types the absolute file path into the focused agent pane
(Claude Code, Codex, Gemini CLI, …). No more manually saving screenshots and
typing paths.

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

## Keybinding

Add to `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+i"
type = "plugin_action"
command = "paste-image.paste"
description = "paste clipboard image as path"
```

`prefix` is your configured Herdr prefix (`ctrl+b` by default), so the default
binding is `Ctrl+b` then `i`. Pick any key you like. Reload the config with
`prefix+shift+r` (or restart Herdr) after editing.

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

Плагин для [Herdr](https://herdr.dev): вставка картинок в промпт агента одной
клавишей, как в Claude Code.

Нажатие хоткея → картинка из буфера обмена сохраняется в PNG-файл → абсолютный
путь автоматически печатается в поле ввода активного агента (Claude Code,
Codex, Gemini…). Больше не нужно сохранять скриншот руками и писать путь.

**Поддержка:** WSL (буфер Windows через `powershell.exe`) и Linux
(`wl-paste`/`xclip`). Требуется Herdr 0.7.4+, `jq` и `base64`.

**Установка:** `herdr plugin link <путь к папке плагина>` (локально) или
`herdr plugin install <owner>/herdr-paste-image` (с GitHub).

**Хоткей** — добавить в `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+i"
type = "plugin_action"
command = "paste-image.paste"
description = "paste clipboard image as path"
```

По умолчанию это `Ctrl+b`, затем `i`. После правки конфига — `prefix+shift+r`
или перезапуск Herdr.

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
