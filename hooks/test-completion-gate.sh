#!/usr/bin/env bash
# Regression harness for completion-gate.sh. Builds synthetic transcripts in the real
# Claude Code JSONL shape (one entry per assistant block; `isSidechain` on subagent lines)
# and asserts block (exit 2) vs allow (exit 0).
# Cases live here rather than in a .tsv because each one needs a multi-message transcript.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
G="$DIR/completion-gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# msg <file> <role> <text> [sidechain]
msg() { jq -nc --arg r "$2" --arg t "$3" --argjson s "${4:-false}" \
        '{type:$r,isSidechain:$s,message:{role:$r,content:[{type:"text",text:$t}]}}' >> "$1"; }
thinking() { jq -nc --arg t "$2" \
        '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"thinking",thinking:$t}]}}' >> "$1"; }

check() {  # check <name> <want B|A> <transcript> [stop_hook_active]
  local name="$1" want="$2" tr="$3" active="${4:-false}" rc
  jq -nc --arg p "$tr" --argjson a "$active" '{transcript_path:$p,stop_hook_active:$a}' \
    | "$SH" "$G" >/dev/null 2>&1; rc=$?
  local got=A; [ "$rc" -eq 2 ] && got=B
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s | %s\n' "$want" "$got" "$name"; fi
}

run_all() {
  local t
  # --- the case the gate exists for ---
  t="$TMP/1.jsonl"; : > "$t"
  msg "$t" user "fix the parser"; msg "$t" assistant "Updated the regex. This should work now."
  check "bare hedge, no evidence -> block" B "$t"

  # --- honest endings must pass ---
  t="$TMP/2.jsonl"; : > "$t"
  msg "$t" assistant "This should work now. I ran the suite: 45 passed, 0 failed."
  check "hedge + evidence -> allow" A "$t"
  t="$TMP/3.jsonl"; : > "$t"
  msg "$t" assistant "This should work, but I could not verify it here: no GPU on this box."
  check "hedge + stated blocker -> allow" A "$t"
  t="$TMP/4.jsonl"; : > "$t"
  msg "$t" assistant "Renamed the field in three call sites."
  check "no hedge at all -> allow" A "$t"

  # --- BUG 1 (fixed): a byte window over ALL assistant text straddles turns ---
  t="$TMP/5.jsonl"; : > "$t"
  msg "$t" assistant "I ran the full test suite and every case passed, output attached."
  msg "$t" user "now do the other module"
  msg "$t" assistant "Applied the same change there. That should do it."
  check "evidence in an EARLIER turn must not excuse this one" B "$t"
  t="$TMP/6.jsonl"; : > "$t"
  msg "$t" assistant "Not sure this should work at all, I never ran it."
  msg "$t" user "ok"
  msg "$t" assistant "Removed the dead import. Nothing else touched."
  check "hedge in an EARLIER turn must not trigger on this one" A "$t"

  # --- BUG 2 (fixed): bare-substring evidence matching ---
  t="$TMP/7.jsonl"; : > "$t"
  msg "$t" assistant "Pointed it at the latest tag. This should work."
  check "'latest' is not a 'test'" B "$t"
  t="$TMP/8.jsonl"; : > "$t"
  msg "$t" assistant "Renamed it to brand_id everywhere. That should do it."
  check "'brand' is not evidence something 'ran'" B "$t"
  t="$TMP/9.jsonl"; : > "$t"
  msg "$t" assistant "Added a testimonial fixture. This should work."
  check "'testimonial' is not a 'test'" B "$t"

  # --- transcript-shape robustness ---
  t="$TMP/10.jsonl"; : > "$t"
  msg "$t" assistant "This should work now."
  thinking "$t" "internal reasoning that mentions tests and verified output"
  check "a trailing thinking block must not mask the text" B "$t"
  t="$TMP/11.jsonl"; : > "$t"
  msg "$t" assistant "This should work now."
  msg "$t" assistant "subagent says it ran and passed" true
  check "a sidechain (subagent) reply is not this turn's reply" B "$t"
  t="$TMP/12.jsonl"; : > "$t"
  msg "$t" assistant "This should work now."
  check "stop_hook_active -> never loop" A "$t" true
  check "missing transcript -> fail open" A "$TMP/does-not-exist.jsonl"
}

f=0
for SH in /opt/homebrew/bin/bash /bin/bash; do
  [ -x "$SH" ] || continue
  echo "================= interpreter: $SH ================="
  pass=0; fail=0; run_all
  echo "  -> $pass passed, $fail failed (of $((pass+fail)))"
  f=$((f+fail))
done
exit "$f"
