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

# Analyze indentation of all lines except the first (a mouse selection
# starts mid-line, so the first copied line has no leading margin).
#   min  — smallest indent among non-blank lines 2..N
#   n2   — lines (any position) with at least 2 leading spaces
#   nbl  — non-blank lines (any position)
stats=$(printf '%s' "$b64" | base64 -d | awk '
  NR > 1 && NF {
    n = 0
    while (n < length($0) && substr($0, n+1, 1) ~ /[ \t]/) n++
    if (min == "" || n < min) min = n
  }
  {
    if (NF) nbl++
    ind = 0
    while (ind < length($0) && substr($0, ind+1, 1) ~ /[ \t]/) ind++
    if (ind >= 2) n2++
  }
  END { printf "%d %d %d\n", (min == "" ? 0 : min), n2 + 0, nbl + 0 }
')
read -r min n2 nbl <<<"$stats"

amount=0
if [[ "$min" -gt 0 ]]; then
  # Uniform margin on every line: strip it.
  amount="$min"
elif [[ "$nbl" -gt 0 && $((n2 * 2)) -ge "$nbl" ]]; then
  # Mixed content (bullets flush-left, paragraphs with a 2-space margin,
  # typical for TUI chat renders): strip the 2-space margin where present.
  amount=2
fi

if [[ "$amount" -eq 0 ]]; then
  notify "no shared indent to strip"
  log "no shared indent found, clipboard unchanged"
  exit 0
fi

# Strip exactly `amount` leading whitespace chars where present; also drop
# BEL control characters that TUI renderers leave in copied text.
printf '%s' "$b64" | base64 -d | tr -d '\007' | sed "s/^[ \t]\{$amount\}//" | base64 -w0 > /tmp/.herdr_dedent_b64
ded_b64=$(cat /tmp/.herdr_dedent_b64); rm -f /tmp/.herdr_dedent_b64
[[ -n "$ded_b64" ]] || fail "dedent produced empty output"

set_clipboard_b64 "$ded_b64" || fail "cannot write clipboard"

notify "stripped $min leading space(s) from every line"
log "stripped min=$min leading whitespace from clipboard text"
exit 0
