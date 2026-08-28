#!/usr/bin/env bash
# APEX guardrail — Stop (OPT-IN; conservative)
# Mechanizes kernel §3 (do not bluff): if the final turn claims success with hedge words
# but shows no sign of verification, block ONCE and ask for evidence or an honest caveat.
#
# Contract: Stop hook. stdin JSON includes `stop_hook_active` (true if we already blocked
# this turn — must allow then, or we loop) and `transcript_path`.
# Exit 2 + stderr => Claude continues with the message. Exit 0 => allow stop.
#
# Deliberately biased toward allowing: a nagging completion gate gets uninstalled, and then
# the env/fs guards go with it. Two properties keep the false-positive rate down:
#   1. it reads ONLY the last assistant message — not a byte window that can straddle
#      several turns, where a hedge in one turn meets evidence from another;
#   2. hedge and evidence terms are matched on WORD boundaries — "latest" is not evidence
#      of a "test", and "brand" is not evidence that something "ran".
# Both were bugs in the first version; `test-completion-gate.sh` pins them.

set -u
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# Never loop: if we already blocked this stop, let it through.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
{ [ -z "$transcript" ] || [ ! -f "$transcript" ]; } && exit 0

# The LAST assistant message that carries text, as one string. Streamed line-by-line
# (one JSON string per message) rather than slurped, so a long transcript stays cheap.
# Sidechain entries are subagent transcripts, not this turn's reply.
enc="$(jq -r '
        select(.isSidechain != true)
      | select(.message.role == "assistant")
      | [ .message.content[]? | select(.type == "text") | .text ]
      | join("\n")
      | select(length > 0)
      | @json' "$transcript" 2>/dev/null | tail -1)"
[ -z "$enc" ] && exit 0
last="$(printf '%s' "$enc" | jq -r . 2>/dev/null)"
[ -z "$last" ] && exit 0

# A hedged success claim — the shape of "I did not check, but let us call it done".
HEDGE='should (now )?(work|be working|fix|do it)|probably (works|fixes)|likely works|ought to work|i (think|believe) (this|it) (works|fixes)|that should do it|presumably works'
printf '%s' "$last" | grep -qiE "$HEDGE" || exit 0

# Any sign that verification happened, or that the limits were stated honestly? Then allow.
EVIDENCE='\b(tested|testing|ran|running|passed|failed|observed|output|reproduced|confirmed)\b|\bverif(y|ied|ication)\b|\b(not verified|unverified|untested|could not|unable to|blocker|caveat|assumption)\b'
printf '%s' "$last" | grep -qiE "$EVIDENCE" && exit 0

>&2 cat <<'MSG'
[apex-guardrail] Completion check (kernel §3 — do not bluff):
The reply claims success with hedge words ("should work" / "probably works") but shows no
verification and no stated caveat. Before finishing, do ONE of:
  - run the relevant check (existing test, the `verify` skill, or observe the output) and
    report what you saw; or
  - if you cannot verify here, say so plainly: what is verified, what is not, and the blocker.
MSG
exit 2
