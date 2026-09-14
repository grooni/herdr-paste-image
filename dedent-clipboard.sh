#!/usr/bin/env bash
# dedent-clipboard — herdr plugin action (F9)
# Cleans text copied by mouse from a TUI pane: unwraps soft line breaks
# (wrapped long lines are rejoined) and strips the shared leading
# whitespace margin. See clean-text.sh for the cleanup details.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

log()    { printf '%s\n' "dedent-clipboard: $*" >&2; }
notify() { "$HERDR" notification show "Clean clipboard" --body "$1" >/dev/null 2>&1 || true; }
fail()   { log "$1"; notify "$1"; exit 1; }

get_clipboard_b64() {
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command '
      Add-Type -AssemblyName System.Windows.Forms
      $t = [System.Windows.Forms.Clipboard]::GetText()
      if ($null -eq $t -or $t.Length -eq 0) { exit 1 }
      [Console]::Out.Write([Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes($t)))
    ' 2>/dev/null | tr -d '\r\n'
  elif command -v wl-paste >/dev/null 2>&1; then
    wl-paste --no-newline 2>/dev/null | base64 -w0
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -o 2>/dev/null | base64 -w0
  else
    return 1
  fi
}

set_clipboard_b64() {
  local b64="$1"
  if command -v powershell.exe >/dev/null 2>&1; then
    printf '%s' "$b64" | powershell.exe -NoProfile -Command '
      Add-Type -AssemblyName System.Windows.Forms
      $b = [Console]::In.ReadToEnd()
      $t = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b))
      [System.Windows.Forms.Clipboard]::SetText($t)
    ' >/dev/null 2>&1
  elif command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$b64" | base64 -d | wl-copy 2>/dev/null
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$b64" | base64 -d | xclip -selection clipboard -i 2>/dev/null
  else
    return 1
  fi
}

b64=$(get_clipboard_b64) || fail "clipboard has no text"
[[ -n "$b64" ]] || fail "clipboard has no text"

summary=$(printf '%s' "$b64" | base64 -d | tr -d '\007' | "$ROOT/clean-text.sh" 2>&1 >/tmp/.herdr_clean_out)
result_b64=$(base64 -w0 /tmp/.herdr_clean_out); rm -f /tmp/.herdr_clean_out
[[ -n "$result_b64" ]] || fail "cleanup produced empty output"

set_clipboard_b64 "$result_b64" || fail "cannot write clipboard"

summary="${summary#clean-text: }"
notify "$summary"
log "$summary"
exit 0
