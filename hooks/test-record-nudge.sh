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
  check "SessionStart 只记基线，不出声"       quiet "$(fire SessionStart)"
  check "没有改动 -> 静默"                     quiet "$(fire UserPromptSubmit)"
  work a b c
  check "改了 3 个（低于阈值 5）-> 静默"       quiet "$(fire UserPromptSubmit)"
  work d e
  check "改到 5 个 -> 提醒"                    nudge "$(fire UserPromptSubmit)"
  check "紧接着再问 -> 不重复唠叨"             quiet "$(fire UserPromptSubmit)"
  work f g h
  check "又多 3 个（未到 +5）-> 静默"          quiet "$(fire UserPromptSubmit)"
  work i j
  check "累计 +5 -> 再提醒"                    nudge "$(fire UserPromptSubmit)"

  # --- compaction re-arms regardless of threshold ---
  new_fixture; fire SessionStart >/dev/null; work a
  check "1 个改动，未到阈值 -> 静默"           quiet "$(fire UserPromptSubmit)"
  check "PreCompact 自己不出声"                quiet "$(fire PreCompact)"
  check "compact 后立刻提醒，不等阈值"         nudge "$(fire UserPromptSubmit)"

  # --- recording silences it ---
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  check "先提醒一次"                           nudge "$(fire UserPromptSubmit)"
  know found.md
  check "写了知识层 -> 闭嘴"                   quiet "$(fire UserPromptSubmit)"
  fire PreCompact >/dev/null
  check "写过之后 compact 也不提醒"            quiet "$(fire UserPromptSubmit)"

  # --- a commit is not a record: baseline is session start, not HEAD ---
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  ( cd "$FIX" && git add -A && git commit -qm wip ) >/dev/null 2>&1
  check "已 commit 的改动仍然算未记录"         nudge "$(fire UserPromptSubmit)"

  # --- config and kill switches ---
  new_fixture; printf 'nudge_after = 2\n' > "$FIX/.apex"
  fire SessionStart >/dev/null; work a b
  check ".apex 的 nudge_after=2 生效"          nudge "$(fire UserPromptSubmit)"
  new_fixture; printf 'knowledge = notes/\n' > "$FIX/.apex"
  fire SessionStart >/dev/null; work a b c d e
  mkdir -p "$FIX/notes" && echo n > "$FIX/notes/x.md"
  check ".apex 的 knowledge 路径覆盖默认值"    quiet "$(fire UserPromptSubmit)"
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  check "APEX_NUDGE=off -> 静默"               quiet "$(cd "$FIX" && jq -nc --arg s "$SID" \
      '{hook_event_name:"UserPromptSubmit",session_id:$s}' | APEX_NUDGE=off "$SH" "$G" 2>/dev/null)"
  check "不在 git 仓里 -> 静默"                quiet "$(cd /tmp && jq -nc \
      '{hook_event_name:"UserPromptSubmit",session_id:"x"}' | "$SH" "$G" 2>/dev/null)"
  check "未知事件 -> 静默"                     quiet "$(fire SubagentStop)"
  # scope: follows load-kernel
  new_fixture; fire SessionStart >/dev/null; work a b c d e
  check "APEX_SCOPE=marker 且无 .apex -> 静默" quiet "$(cd "$FIX" && jq -nc --arg s "$SID" \
      '{hook_event_name:"UserPromptSubmit",session_id:$s}' | APEX_SCOPE=marker "$SH" "$G" 2>/dev/null)"
  : > "$FIX/.apex"
  check "APEX_SCOPE=marker 且有 .apex -> 提醒" nudge "$(cd "$FIX" && jq -nc --arg s "$SID" \
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
