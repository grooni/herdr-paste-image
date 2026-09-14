#!/usr/bin/env bash
# clean-text.sh — shared cleanup for herdr paste-image plugin.
# Reads text on stdin, writes cleaned text to stdout:
#   1. Strips the shared leading whitespace margin TUI agents render.
#   2. Unwraps soft line breaks: after the margin is stripped, a copied
#      line that fills the wrap width was split by the terminal — rejoin
#      it with the next line, restoring the original long line.
# Relative indentation (nested lists, code blocks) is preserved.
# Prints a short summary to stderr.
set -uo pipefail

tmpf=$(mktemp) || exit 1
trap 'rm -f "$tmpf"' EXIT
cat | tr -d '\007' > "$tmpf"

# --- 1. Strip shared leading whitespace ------------------------------------
# amount = smallest indent among ALL non-blank lines (a uniform TUI margin,
# or a uniformly indented code block — stripping it preserves relative
# structure). When indents are mixed (bullets flush-left, paragraphs with
# a 2-space TUI render margin), strip the 2-space margin where present.
stats=$(awk '
  NF {
    n = 0
    while (n < length($0) && substr($0, n+1, 1) ~ /[ \t]/) n++
    if (min == "" || n < min) min = n
    nbl++
  }
  {
    ind = 0
    while (ind < length($0) && substr($0, ind+1, 1) ~ /[ \t]/) ind++
    if (ind >= 2) n2++
  }
  END { printf "%d %d %d\n", (min == "" ? 0 : min), n2 + 0, nbl + 0 }
' "$tmpf")
read -r min n2 nbl <<<"$stats"

amount=0
if [[ "$min" -gt 0 ]]; then
  amount="$min"
elif [[ "$nbl" -gt 0 && $((n2 * 2)) -ge "$nbl" ]]; then
  amount=2
fi

if [[ "$amount" -gt 0 ]]; then
  sed -i "s/^[ \t]\{$amount\}//" "$tmpf"
fi

# --- 2. Unwrap soft line breaks --------------------------------------------
# After the margin strip, every piece of a terminal-wrapped line fills
# the wrap width exactly; only the last piece is shorter. Rejoin each
# full-width line with the next one. Only apply when the wrap width
# looks like a terminal (>= 40 chars), so short text is never touched.
max=$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$tmpf")
joined=0
if [[ "$max" -ge 40 ]]; then
  awk -v w="$max" '
    length($0) == w { buf = buf $0; next }
    { print buf $0; buf = "" }
    END { if (buf != "") print buf }
  ' "$tmpf" > "$tmpf.u" && mv "$tmpf.u" "$tmpf"
  joined=1
fi

cat "$tmpf"

what=""
[[ "$joined" -eq 1 ]] && what="unwrapped long lines"
if [[ "$amount" -gt 0 ]]; then
  [[ -n "$what" ]] && what="$what, "
  what="${what}stripped $amount leading space(s) per line"
fi
[[ -z "$what" ]] && what="already clean"
printf '%s\n' "clean-text: $what" >&2
