#!/usr/bin/env bash
# dedent-clipboard — herdr plugin action
# Removes the common leading whitespace from every line of the clipboard
# text. Fixes copying from TUIs (Codex etc.) that render output with a
# left margin: the copied text carries that margin on every line.
# Relative indentation (nested lists, code blocks) is preserved — only the
# shared prefix is stripped.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"

log()    { printf '%s\n' "dedent-clipboard: $*" >&2; }
notify() { "$HERDR" notification show "Dedent clipboard" --body "$1" >/dev/null 2>&1 || true; }
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

# Count the smallest leading whitespace run across all non-blank lines.
min=$(printf '%s' "$b64" | base64 -d | awk '
  NF {
    n = 0
    while (n < length($0) && substr($0, n+1, 1) ~ /[ \t]/) n++
    if (min == "" || n < min) min = n
  }
  END { print (min == "" ? 0 : min) }
')

if [[ "$min" -eq 0 ]]; then
  notify "no shared indent to strip"
  log "no shared indent found, clipboard unchanged"
  exit 0
fi

# Strip exactly `min` leading whitespace chars from each line.
ded_b64=$(printf '%s' "$b64" | base64 -d | sed "s/^[ \t]\{$min\}//" | base64 -w0)
[[ -n "$ded_b64" ]] || fail "dedent produced empty output"

set_clipboard_b64 "$ded_b64" || fail "cannot write clipboard"

notify "stripped $min leading space(s) from every line"
log "stripped min=$min leading whitespace from clipboard text"
exit 0
