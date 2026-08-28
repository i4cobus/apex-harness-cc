#!/usr/bin/env bash
# Regression harness for record-nudge.sh. Walks a session through a throwaway repo:
# baseline, growth, recording, compaction, commits. Cases live here rather than in a .tsv
# because each depends on the state the previous step left — that sequencing IS the thing
# under test.
#
# Each scenario gets a FRESH repo. An earlier version reused one, and files committed by a
# late scenario became the next scenario's baseline, so rewriting them produced no diff and
# the suite passed for the wrong reason under one interpreter and failed under the other.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
G="$DIR/record-nudge.sh"
pass=0; fail=0; FIX=""; SID=""; SEQ=0

new_fixture() {
  [ -n "$FIX" ] && rm -rf "$FIX"
  FIX="$(mktemp -d)"
  ( cd "$FIX" && git init -q . && git config user.email a@b.c && git config user.name a \
    && echo seed > seed.txt && git add -A && git commit -qm init ) >/dev/null 2>&1
  SID="rn-$$-$RANDOM"
  SEQ=0
}
cleanup() { [ -n "$FIX" ] && rm -rf "$FIX"; rm -f "${TMPDIR:-/tmp}"/apex-record-rn-*.state; }
trap cleanup EXIT

fire() { ( cd "$FIX" && jq -nc --arg e "$1" --arg s "$SID" \
             '{hook_event_name:$e,session_id:$s}' | "$SH" "$G" 2>/dev/null ); }
# unique content each time, or rewriting a committed file is a no-op diff
work() { local x; mkdir -p "$FIX/src"; for x in "$@"; do
           SEQ=$((SEQ+1)); echo "change $SEQ" > "$FIX/src/$x"; done; }
know() { mkdir -p "$FIX/docs"; echo note > "$FIX/docs/$1"; }
check() { local got=quiet; case "$3" in *additionalContext*) got=nudge ;; esac
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s | %s\n' "$2" "$got" "$1"; fi; }

run_all() {
  # --- growth-based re-arming ---
  new_fixture
  check "SessionStart records a baseline, says nothing"                  quiet "$(fire SessionStart)"
  check "nothing changed -> silent"                                      quiet "$(fire UserPromptSubmit)"
  work a b c
  check "3 files, below the threshold of 5 -> silent"                    quiet "$(fire UserPromptSubmit)"
  work d e
  check "5 files -> speaks"                                              nudge "$(fire UserPromptSubmit)"
  check "asked again immediately -> does not repeat itself"              quiet "$(fire UserPromptSubmit)"
  work f g h
  check "3 more, short of +5 -> silent"                                  quiet "$(fire UserPromptSubmit)"
  work i j
  check "+5 since last time -> speaks again"                             nudge "$(fire UserPromptSubmit)"

  # --- compaction re-arms regardless of threshold ---
  new_fixture; fire SessionStart >/dev/null; work a
  check "1 file, below threshold -> silent"                              quiet "$(fire UserPromptSubmit)"
  check "PreCompact itself says nothing"                                 quiet "$(fire PreCompact)"
  check "after a compaction it speaks without waiting for the threshold" nudge "$(fire UserPromptSubmit)"

  # --- recording silences it ---
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  check "speaks once first"                                              nudge "$(fire UserPromptSubmit)"
  know found.md
  check "something was recorded -> goes quiet"                           quiet "$(fire UserPromptSubmit)"
  fire PreCompact >/dev/null
  check "still quiet through a compaction once recorded"                 quiet "$(fire UserPromptSubmit)"

  # --- a commit is not a record: baseline is session start, not HEAD ---
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  ( cd "$FIX" && git add -A && git commit -qm wip ) >/dev/null 2>&1
  check "committing the work does not clear the debt"                    nudge "$(fire UserPromptSubmit)"

  # --- config and kill switches ---
  new_fixture; printf 'nudge_after = 2\n' > "$FIX/.apex"
  fire SessionStart >/dev/null; work a b
  check "nudge_after=2 from .apex is honoured"                           nudge "$(fire UserPromptSubmit)"
  new_fixture; printf 'knowledge = notes/\n' > "$FIX/.apex"
  fire SessionStart >/dev/null; work a b c d e
  mkdir -p "$FIX/notes" && echo n > "$FIX/notes/x.md"
  check "knowledge paths from .apex override the defaults"               quiet "$(fire UserPromptSubmit)"
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  check "APEX_NUDGE=off -> silent"                                       quiet "$(cd "$FIX" && jq -nc --arg s "$SID" \
      '{hook_event_name:"UserPromptSubmit",session_id:$s}' | APEX_NUDGE=off "$SH" "$G" 2>/dev/null)"
  check "outside a git work tree -> silent"                              quiet "$(cd /tmp && jq -nc \
      '{hook_event_name:"UserPromptSubmit",session_id:"x"}' | "$SH" "$G" 2>/dev/null)"
  check "an event it does not handle -> silent"                          quiet "$(fire SubagentStop)"
  # scope: follows load-kernel
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  check "APEX_SCOPE=marker with no .apex -> silent"                      quiet "$(cd "$FIX" && jq -nc --arg s "$SID" \
      '{hook_event_name:"UserPromptSubmit",session_id:$s}' | APEX_SCOPE=marker "$SH" "$G" 2>/dev/null)"
  : > "$FIX/.apex"
  check "APEX_SCOPE=marker with a .apex -> speaks"                       nudge "$(cd "$FIX" && jq -nc --arg s "$SID" \
      '{hook_event_name:"UserPromptSubmit",session_id:$s}' | APEX_SCOPE=marker "$SH" "$G" 2>/dev/null)"
}

rc=0
for SH in /opt/homebrew/bin/bash /bin/bash; do
  [ -x "$SH" ] || continue
  echo "================= interpreter: $SH ================="
  pass=0; fail=0; run_all
  echo "  -> $pass passed, $fail failed (of $((pass+fail)))"
  rc=$((rc+fail))
done
exit "$rc"
