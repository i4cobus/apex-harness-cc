#!/usr/bin/env bash
# Temp test harness for env-guard.sh. Reads cases from test-cases.tsv so this file (and the
# invoking command line) contain no install-like substrings the LIVE hook would intercept.
# Each case line: WANT<TAB>COMMAND   where WANT is B (must block, exit 2) or A (must allow, 0).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
G="$DIR/env-guard.sh"
CASES="$DIR/test-cases.tsv"

runmatrix() {
  local sh="$1" pass=0 fail=0 total=0
  echo "================= interpreter: $sh ================="
  while IFS=$'\t' read -r want cmd; do
    [ -z "${want:-}" ] && continue
    case "$want" in \#*) continue ;; esac
    total=$((total+1))
    printf '%s' "$cmd" | jq -Rs '{tool_input:{command:.}}' | "$sh" "$G" >/dev/null 2>&1
    rc=$?
    if { [ "$want" = B ] && [ "$rc" -eq 2 ]; } || { [ "$want" = A ] && [ "$rc" -eq 0 ]; }; then
      pass=$((pass+1))
    else
      fail=$((fail+1)); printf '  FAIL want=%s got_exit=%s | %s\n' "$want" "$rc" "$cmd"
    fi
  done < "$CASES"
  echo "  -> $pass passed, $fail failed (of $total)"
  return "$fail"
}

f=0
runmatrix /opt/homebrew/bin/bash || f=$((f+$?))
runmatrix /bin/bash || f=$((f+$?))
exit "$f"
