#!/usr/bin/env bash
# APEX guardrail — SessionStart | UserPromptSubmit | PreCompact
# Mechanizes kernel §7 (externalize state). The kernel says working memory is lossy and
# findings must land in files; nothing was watching whether they did. This watches.
#
# It is a NUDGE, never a gate: it can only add a line of context. Blocking here was
# considered and rejected — of a close-out checklist only one item ("nothing was written
# down at all") is decidable, and a gate that misfires on the rest teaches people to
# uninstall the whole set, guards included.
#
# Contract, by event (read from .hook_event_name):
#   SessionStart      record the baseline commit; emit nothing
#   PreCompact        re-arm; emit nothing (PreCompact cannot inject context, only block)
#   UserPromptSubmit  if the condition holds, inject one line via additionalContext
#
# The condition, the only decidable one:
#   N files changed since the baseline, and NOT ONE of them is in the knowledge layer.
#
# Re-arming is by growth, not by session. A session that runs all day through repeated
# compactions would otherwise be reminded once, at the start, about nothing. It speaks again
# after another APEX_NUDGE_AFTER files have changed with still nothing recorded, and once
# more immediately after a compaction — the moment unwritten findings actually die.
#
# Config: a `knowledge = <prefixes>` or `nudge_after = <n>` line in the `.apex` marker file,
# or APEX_NUDGE_AFTER in the environment. APEX_NUDGE=off disables it.
# Fail-open everywhere: no jq, no git, not a work tree, no baseline -> silent.
#
# Note: kept bash-3.2 compatible (macOS /bin/bash).

set -u
input="$(cat)"
[ "${APEX_NUDGE:-on}" = "off" ] && exit 0
command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"
sid="$(printf '%s' "$input"   | jq -r '.session_id // "nosid"' 2>/dev/null)"
state="${TMPDIR:-/tmp}/apex-record-${sid//\//_}.state"

# ---- config -----------------------------------------------------------------------------
# Defaults describe where durable knowledge conventionally lives. Anything matching these is
# "the knowledge layer"; everything else is work that may need recording.
# The convention is `docs/` in the working repository (documentation_topology.md §6); the
# agent's own memory store is deliberately not part of it — unversioned, unreviewable, and
# invisible to everyone else. `knowledge/` is tolerated because some repos name it that.
# Detection is deliberately generous while the doctrine is narrow: a missed nudge costs one
# reminder, a false nudge costs the hook.
# NB: `.apex` is absent on purpose — it is configuration, not a finding, and listing it
# would let editing the config count as having recorded something. So is `README.md`, which
# gets edited for reasons that have nothing to do with recording a finding.
KNOWLEDGE="docs/ knowledge/ CLAUDE.md AGENTS.md"
THRESHOLD="${APEX_NUDGE_AFTER:-5}"
marker=""
d="$PWD"
while :; do
  [ -e "$d/.apex" ] && { marker="$d/.apex"; break; }
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
# Scope follows load-kernel: where the kernel applies, so does its §7. With
# APEX_SCOPE=marker and no `.apex` above the working directory, stay silent — a nudge in a
# repo that never opted in is exactly the noise that gets hooks removed.
if [ "${APEX_SCOPE:-always}" = "marker" ] && [ -z "$marker" ]; then exit 0; fi

if [ -n "$marker" ] && [ -f "$marker" ]; then
  v="$(sed -n 's/^[[:space:]]*knowledge[[:space:]]*=[[:space:]]*//p' "$marker" | head -1)"
  [ -n "$v" ] && KNOWLEDGE="$v"
  v="$(sed -n 's/^[[:space:]]*nudge_after[[:space:]]*=[[:space:]]*//p' "$marker" | head -1)"
  case "$v" in ''|*[!0-9]*) ;; *) THRESHOLD="$v" ;; esac
fi

get() { sed -n "s/^$1=//p" "$state" 2>/dev/null | tail -1; }
put() {  # put KEY VALUE — rewrite the one line
  local k="$1" v="$2" tmp="$state.$$"
  { grep -v "^$k=" "$state" 2>/dev/null; printf '%s=%s\n' "$k" "$v"; } > "$tmp" 2>/dev/null \
    && mv "$tmp" "$state" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  return 0
}

case "$event" in
  SessionStart)
    # Baseline = where the repo stood when the session opened, so work that has since been
    # committed still counts as unrecorded. Without it we could only see the dirty tree.
    base="$(git rev-parse HEAD 2>/dev/null)" || exit 0
    : > "$state" 2>/dev/null
    put base "$base"; put nudged 0
    exit 0 ;;
  PreCompact)
    # Cannot speak here (PreCompact has no additionalContext), so arm the next prompt.
    put rearm 1
    exit 0 ;;
  UserPromptSubmit) ;;
  *) exit 0 ;;
esac

# ---- what has changed since the baseline? -----------------------------------------------
base="$(get base)"
if [ -z "$base" ]; then                       # no SessionStart seen (hook added mid-session)
  base="$(git rev-parse HEAD 2>/dev/null)" || exit 0
  put base "$base"; put nudged 0
fi

# -uall matters here and is the opposite of fs-guard's choice: this counts files, and the
# default mode collapses a wholly-untracked directory to one `?? dir/` line, so ten new
# files in a new directory would read as one change and never reach the threshold.
changed="$(
  { git diff --name-only "$base" 2>/dev/null
    git -c core.quotepath=false status --porcelain -uall 2>/dev/null \
      | awk '/^\?\? /{sub(/^\?\? /,""); gsub(/^"|"$/,""); print}'
  } | sort -u
)"
[ -z "$changed" ] && exit 0

is_knowledge() {
  local p="$1" k
  for k in $KNOWLEDGE; do
    case "$k" in
      */) case "$p" in "$k"*|*/"$k"*) return 0 ;; esac ;;
      *)  case "$p" in "$k"|*/"$k") return 0 ;; esac ;;
    esac
  done
  return 1
}

n_work=0; n_know=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if is_knowledge "$f"; then n_know=$((n_know+1)); else n_work=$((n_work+1)); fi
done <<EOF
$changed
EOF

# Something was recorded — the condition no longer holds. Reset so that a later stretch of
# unrecorded work can trigger again on its own merits.
if [ "$n_know" -gt 0 ]; then put nudged "$n_work"; put rearm 0; exit 0; fi

nudged="$(get nudged)"; case "$nudged" in ''|*[!0-9]*) nudged=0 ;; esac
rearm="$(get rearm)"

if [ "${rearm:-0}" = "1" ]; then
  [ "$n_work" -lt 1 ] && exit 0
  why="a compaction just discarded working context"
elif [ "$n_work" -lt "$THRESHOLD" ] || [ "$n_work" -lt $((nudged + THRESHOLD)) ]; then
  exit 0
else
  why="$n_work files have changed"
fi

put nudged "$n_work"; put rearm 0

msg="[apex] $why and nothing has been written to the knowledge layer ($KNOWLEDGE).

Kernel §7: findings, decisions, changed definitions and negative results survive only in
files. Record what this session learned — not what it did — or say in one line why this
work needs no record."

jq -n --arg m "$msg" '{
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: $m }
}'
exit 0
