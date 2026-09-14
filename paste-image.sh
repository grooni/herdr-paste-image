#!/usr/bin/env bash
# paste-image — herdr plugin action
# Reads an image from the clipboard (Windows clipboard via powershell.exe on
# WSL, wl-paste/xclip on native Linux), saves it as a PNG file and types the
# absolute file path into the focused agent pane.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
DEFAULT_DIR="$HOME/.local/state/herdr-paste-images"

log()   { printf '%s\n' "paste-image: $*" >&2; }
notify() { "$HERDR" notification show "Paste image" --body "$1" >/dev/null 2>&1 || true; }
fail()  { log "$1"; notify "$1"; exit 1; }

# ---------------------------------------------------------------------------
# Config: storage directory.
# Priority: HERDR_PASTE_IMAGE_DIR env var > image_dir in
# $HERDR_PLUGIN_CONFIG_DIR/config.env > default.
# ---------------------------------------------------------------------------
resolve_image_dir() {
  local dir="${HERDR_PASTE_IMAGE_DIR:-}"
  if [[ -z "$dir" && -n "${HERDR_PLUGIN_CONFIG_DIR:-}" \
        && -f "$HERDR_PLUGIN_CONFIG_DIR/config.env" ]]; then
    local line
    line=$(sed -n -E 's/^[[:space:]]*image_dir[[:space:]]*=[[:space:]]*//p' \
           "$HERDR_PLUGIN_CONFIG_DIR/config.env" | tail -n 1)
    line="${line%\"*}"; line="${line#\"}"   # strip surrounding quotes
    line="${line%\'}"; line="${line#\'}"
    line="${line%%#*}"                      # strip trailing comment
    # trim whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    dir="$line"
  fi
  if [[ -z "$dir" ]]; then
    dir="$DEFAULT_DIR"
  fi
  dir="${dir/#\~/$HOME}"                    # expand leading ~
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Clipboard readers. Each writes image bytes to stdout or fails.
# ---------------------------------------------------------------------------
read_clipboard_wsl() {
  local powershell
  powershell=$(command -v powershell.exe) || return 1
  local b64
  b64=$("$powershell" -NoProfile -Command '
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $img = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $img) { exit 1 }
    $ms = New-Object System.IO.MemoryStream
    $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    [Console]::Out.Write([Convert]::ToBase64String($ms.ToArray()))
  ' 2>/dev/null | tr -d '\r\n') || return 1
  b64="${b64#*$'\xEF\xBB\xBF'}"             # strip UTF-8 BOM if present
  [[ -n "$b64" ]] || return 1
  printf '%s' "$b64" | base64 -d
}

read_clipboard_linux() {
  if command -v wl-paste >/dev/null 2>&1; then
    wl-paste --type image/png 2>/dev/null && return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -t image/png -o 2>/dev/null && return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
IMAGE_DIR=$(resolve_image_dir)

tmp=$(mktemp) || fail "mktemp failed"
trap 'rm -f "$tmp"' EXIT

read_ok=0
if command -v powershell.exe >/dev/null 2>&1; then
  read_clipboard_wsl > "$tmp" && read_ok=1
fi
if [[ "$read_ok" -ne 1 ]]; then
  read_clipboard_linux > "$tmp" && read_ok=1
fi

if [[ "$read_ok" -ne 1 ]] || [[ ! -s "$tmp" ]]; then
  fail "clipboard has no image"
fi

# Validate PNG magic bytes.
magic=$(head -c 8 "$tmp" | od -An -tx1 | tr -d ' \n')
if [[ "$magic" != "89504e470d0a1a0a" ]]; then
  fail "clipboard image is not a PNG (got: $magic)"
fi

mkdir -p "$IMAGE_DIR" || fail "cannot create directory: $IMAGE_DIR"

name="paste-$(date +%Y%m%d-%H%M%S)"
dest="$IMAGE_DIR/$name.png"
while [[ -e "$dest" ]]; do
  dest="$IMAGE_DIR/$name-$RANDOM.png"
done
mv "$tmp" "$dest" || fail "cannot write file: $dest"
trap - EXIT

# Find the focused pane to type the path into.
pane_id=$("$HERDR" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty')
if [[ -z "$pane_id" && -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]]; then
  pane_id=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" \
            | jq -r '.focused_pane_id // .focused_pane.pane_id // .pane.pane_id // empty' 2>/dev/null)
fi
[[ -z "$pane_id" ]] && pane_id="${HERDR_PANE_ID:-}"
[[ -z "$pane_id" ]] && fail "no focused pane found"

"$HERDR" pane send-text "$pane_id" "$dest" || fail "cannot send text to pane $pane_id"

notify "Image saved: $dest"
log "saved $dest -> pane $pane_id"
exit 0
