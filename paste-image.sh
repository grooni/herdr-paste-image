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
    function Emit-B64([System.Drawing.Image]$img) {
      $ms = New-Object System.IO.MemoryStream
      $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
      [Console]::Out.Write([Convert]::ToBase64String($ms.ToArray()))
      exit 0
    }
    # 1) plain bitmap/screenshot (Win+Shift+S, PrintScreen, browser "copy image")
    $img = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -ne $img) { Emit-B64 $img }
    # 2) explicit PNG stream placed by some apps
    $png = [System.Windows.Forms.Clipboard]::GetData("PNG")
    if ($png -is [byte[]] -and $png.Length -gt 0) {
      [Console]::Out.Write([Convert]::ToBase64String($png))
      exit 0
    }
    # 3) Office/EMF vector image (e.g. copied from Word/Excel)
    $mf = [System.Windows.Forms.Clipboard]::GetData("EnhancedMetafile")
    if ($mf -is [System.Drawing.Imaging.Metafile]) {
      $w = 1; $h = 1
      try { $w = [int]$mf.Width; $h = [int]$mf.Height } catch {}
      if ($w -lt 1) { $w = 800 }
      if ($h -lt 1) { $h = 600 }
      $bmp = New-Object System.Drawing.Bitmap($w, $h)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.Clear([System.Drawing.Color]::White)
      $g.DrawImage($mf, 0, 0, $w, $h)
      $g.Dispose()
      Emit-B64 $bmp
    }
    exit 1
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

# --- No image: fall back to pasting clipboard text, so binding this action
# --- to ctrl+v does not break normal text paste.
if [[ "$read_ok" -ne 1 ]] || [[ ! -s "$tmp" ]]; then
  clip_text=""
  if command -v powershell.exe >/dev/null 2>&1; then
    clip_text=$(powershell.exe -NoProfile -Command \
      '[Console]::Out.Write([System.Windows.Forms.Clipboard]::GetText())' 2>/dev/null \
      | tr -d '\r' | head -c 100000) || clip_text=""
  elif command -v wl-paste >/dev/null 2>&1; then
    clip_text=$(wl-paste --no-newline 2>/dev/null | head -c 100000) || clip_text=""
  elif command -v xclip >/dev/null 2>&1; then
    clip_text=$(xclip -selection clipboard -o 2>/dev/null | head -c 100000) || clip_text=""
  fi
  if [[ -n "$clip_text" ]]; then
    # Focus target pane.
    pane_id=$("$HERDR" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty')
    [[ -z "$pane_id" ]] && pane_id="${HERDR_PANE_ID:-}"
    [[ -z "$pane_id" ]] && fail "no focused pane found"
    if [[ "$clip_text" == *$'\n'* ]]; then
      # Multiline: wrap in bracketed-paste escapes so TUIs (Claude Code,
      # Codex) treat it as one paste instead of submitting per line.
      printf '\x1b[200~%s\x1b[201~' "$clip_text" > "$tmp"
    else
      printf '%s' "$clip_text" > "$tmp"
    fi
    "$HERDR" pane send-text "$pane_id" "$(cat "$tmp")" \
      || fail "cannot send text to pane $pane_id"
    log "pasted clipboard text into pane $pane_id"
    exit 0
  fi
  fail "clipboard is empty"
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

# Image counter for the "[Image #N]" label, one per machine.
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr-paste-image}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
img_n=$(cat "$STATE_DIR/counter" 2>/dev/null || echo 0)
img_n=$((img_n + 1))
echo "$img_n" > "$STATE_DIR/counter" 2>/dev/null || true

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
