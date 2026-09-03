#!/usr/bin/env bash
# Temp test harness for env-guard.sh. Reads cases from test-cases.tsv so this file (and the
# invoking command line) contain no install-like substrings the LIVE hook would intercept.
# Each case line: WANT<TAB>COMMAND   where WANT is B (must block, exit 2) or A (must allow, 0).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
G="$DIR/env-guard.sh"
CASES="$DIR/test-cases.tsv"

runmatrix() {
  local sh="$1" pass=0 fail=0 total=0 xfail=0 xpass=0
  echo "================= interpreter: $sh ================="
  while IFS=$'\t' read -r want cmd; do
    [ -z "${want:-}" ] && continue
    case "$want" in \#*) continue ;; esac
    total=$((total+1))
    # `\n` in a case becomes a real newline, so a case can be a multi-line command.
    # No case uses any other backslash escape.
    cmd="$(printf '%b' "$cmd")"
    printf '%s' "$cmd" | jq -Rs '{tool_input:{command:.}}' | "$sh" "$G" >/dev/null 2>&1
    rc=$?
    # X = known-fail: the guard SHOULD allow this but currently blocks it. Tracked here
    # rather than as a plain A so one open bug does not mask a real regression.
    if [ "$want" = X ]; then
      if [ "$rc" -eq 0 ]; then
        xpass=$((xpass+1)); printf '  XPASS (now fixed — flip this case to A) | %s\n' "$cmd"
      else
        xfail=$((xfail+1))
      fi
      continue
    fi
    if { [ "$want" = B ] && [ "$rc" -eq 2 ]; } || { [ "$want" = A ] && [ "$rc" -eq 0 ]; }; then
      pass=$((pass+1))
    else
      fail=$((fail+1)); printf '  FAIL want=%s got_exit=%s | %s\n' "$want" "$rc" "$cmd"
    fi
  done < "$CASES"
  printf '  -> %s passed, %s failed (of %s)' "$pass" "$fail" "$((total-xfail-xpass))"
  [ "$xfail" -gt 0 ] && printf ' + %s known-fail' "$xfail"
  [ "$xpass" -gt 0 ] && printf ' + %s unexpectedly passing' "$xpass"
  echo
  return "$fail"
}

f=0
runmatrix /opt/homebrew/bin/bash || f=$((f+$?))
runmatrix /bin/bash || f=$((f+$?))
exit "$f"
