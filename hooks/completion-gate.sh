#!/usr/bin/env bash
# APEX guardrail — Stop (OPT-IN; conservative)
# Mechanizes kernel §3 (do not bluff): if the final turn claims success with hedge words
# but shows no sign of verification, block ONCE and ask for evidence or an honest caveat.
#
# Contract: Stop hook. stdin JSON includes `stop_hook_active` (true if we already blocked
# this turn — must allow then, or we loop) and `transcript_path`.
# Exit 2 + stderr => Claude continues with the message. Exit 0 => allow stop.
#
# This is intentionally narrow to avoid nagging. Remove it from settings if unwanted.

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# Never loop: if we already blocked this stop, let it through.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Last assistant text block in the transcript.
last="$(jq -r 'select(.message.role=="assistant") | .message.content[]? | select(.type=="text") | .text' "$transcript" 2>/dev/null | tail -c 4000)"
[ -z "$last" ] && exit 0
lc="$(printf '%s' "$last" | tr '[:upper:]' '[:lower:]')"

# Hedged success claim?
hedged=false
case "$lc" in
  *"should work"*|*"should now work"*|*"probably works"*|*"i think this works"*|\
  *"this should fix"*|*"that should do it"*|*"likely works"*|*"ought to work"*) hedged=true ;;
esac
$hedged || exit 0

# Any sign verification happened or limits were stated honestly? Then allow.
case "$lc" in
  *"test"*|*"verified"*|*"verify"*|*"ran "*|*"output"*|*"passed"*|*"observed"*|\
  *"not verified"*|*"unverified"*|*"could not"*|*"unable to"*|*"blocker"*|*"caveat"*) exit 0 ;;
esac

>&2 cat <<'MSG'
[apex-guardrail] Completion check (kernel §3 — do not bluff):
The reply claims success with hedge words ("should work" / "probably works") but shows no
verification and no stated caveat. Before finishing, do ONE of:
  - run the relevant check (existing test, the `verify` skill, or observe the output) and
    report what you saw; or
  - if you cannot verify here, say so plainly: what is verified, what is not, and the blocker.
MSG
exit 2
