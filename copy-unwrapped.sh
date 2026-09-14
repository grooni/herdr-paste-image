#!/usr/bin/env bash
# copy-unwrapped — herdr plugin action (F10)
# Copies the recent output of the focused pane to the clipboard with
# soft line-wraps undone (herdr rejoins lines split by terminal width),
# TUI chrome (borders, spinner lines) removed, and the shared left
# margin stripped. See clean-text.sh for the cleanup details.
#
# Optional config: in $HERDR_PLUGIN_CONFIG_DIR/config.env set
#   copy_lines=60
# to change how many recent lines are copied (default 40).
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

log()    { printf '%s\n' "copy-unwrapped: $*" >&2; }
notify() { "$HERDR" notification show "Copy unwrapped" --body "$1" >/dev/null 2>&1 || true; }
fail()   { log "$1"; notify "$1"; exit 1; }

lines="${HERDR_COPY_LINES:-40}"
if [[ -z "${HERDR_COPY_LINES:-}" && -n "${HERDR_PLUGIN_CONFIG_DIR:-}" \
      && -f "$HERDR_PLUGIN_CONFIG_DIR/config.env" ]]; then
  cfg=$(sed -n -E 's/^[[:space:]]*copy_lines[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' \
        "$HERDR_PLUGIN_CONFIG_DIR/config.env" | tail -n 1)
  [[ -n "$cfg" ]] && lines="$cfg"
fi

pane_id=$("$HERDR" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty')
if [[ -z "$pane_id" && -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]]; then
  pane_id=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" \
            | jq -r '.focused_pane_id // empty' 2>/dev/null)
fi
[[ -z "$pane_id" ]] && pane_id="${HERDR_PANE_ID:-}"
[[ -z "$pane_id" ]] && fail "no focused pane found"

text=$("$HERDR" pane read "$pane_id" --source recent-unwrapped \
       --lines "$lines" --format text 2>/dev/null) || fail "cannot read pane $pane_id"
[[ -n "$text" ]] || fail "pane returned no text"

# Drop TUI chrome: lines made only of box-drawing characters, border
# rules, or braille spinner fragments never carry code or prose.
# Short code lines like "}" or ")" are NOT matched and are kept.
text=$(printf '%s' "$text" | grep -v -E \
  '^[[:space:]─│┌┐└┘├┤┬┴┼═║╔╗╚╝=─┄┅┈┉·⁃]*$|^[[:space:]⠀-⣿]*$' \
  2>/dev/null || true)
[[ -n "$text" ]] || fail "nothing left after filtering TUI chrome"

summary=$(printf '%s' "$text" | "$ROOT/clean-text.sh" 2>&1 >/tmp/.herdr_cu_out)
result_b64=$(base64 -w0 /tmp/.herdr_cu_out); rm -f /tmp/.herdr_cu_out
[[ -n "$result_b64" ]] || fail "cleanup produced empty output"

# Write to clipboard via base64 so non-ASCII survives the Windows boundary.
if command -v powershell.exe >/dev/null 2>&1; then
  printf '%s' "$result_b64" | powershell.exe -NoProfile -Command '
    Add-Type -AssemblyName System.Windows.Forms
    $b = [Console]::In.ReadToEnd()
    $t = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b))
    [System.Windows.Forms.Clipboard]::SetText($t)
  ' >/dev/null 2>&1 || fail "cannot write clipboard"
elif command -v wl-copy >/dev/null 2>&1; then
  printf '%s' "$result_b64" | base64 -d | wl-copy 2>/dev/null || fail "cannot write clipboard"
elif command -v xclip >/dev/null 2>&1; then
  printf '%s' "$result_b64" | base64 -d | xclip -selection clipboard -i 2>/dev/null || fail "cannot write clipboard"
else
  fail "no clipboard tool available"
fi

summary="${summary#clean-text: }"
notify "copied $lines lines from $pane_id, $summary"
log "copied $lines lines from pane $pane_id, $summary"
exit 0
