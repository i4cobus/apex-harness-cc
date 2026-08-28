#!/usr/bin/env bash
# Regression harness for fs-guard.sh. Builds a throwaway git repo with one file of every
# recoverability class, then replays fs-cases.tsv against the hook from inside it.
# Each case line: WANT<TAB>TOOL<TAB>PAYLOAD
#   WANT=K -> must ask (stdout carries permissionDecision "ask"); WANT=A -> must allow silently.
#   TOOL=Bash -> PAYLOAD is the shell command; TOOL=Write -> PAYLOAD is the target file_path.
# Every case gets its own session id so the ask-once-per-session ledger never masks a case.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
G="$DIR/fs-guard.sh"
CASES="$DIR/fs-cases.tsv"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
build_fixture() {
  cd "$FIX" || exit 1
  git init -q .
  git config user.email apex@example.com
  git config user.name apex
  printf 'tracked\n' > tracked.md
  printf '*.log\nbuild/\n' > .gitignore
  git add tracked.md .gitignore
  git commit -qm init
  printf 'untracked\n' > untracked.md
  mkdir -p sub __pycache__ build
  printf 'untracked\n' > sub/untracked2.md
  printf 'junk\n'      > __pycache__/mod.pyc
  printf 'junk\n'      > .DS_Store
  printf 'ignored\n'   > ignored.log
  printf 'ignored\n'   > build/artifact.bin
}
build_fixture >/dev/null 2>&1

payload() {  # $1=tool $2=payload $3=session id
  if [ "$1" = Write ]; then
    jq -n --arg p "$2" --arg s "$3" \
      '{tool_name:"Write",session_id:$s,tool_input:{file_path:$p}}'
  else
    jq -n --arg c "$2" --arg s "$3" \
      '{tool_name:"Bash",session_id:$s,tool_input:{command:$c}}'
  fi
}

runmatrix() {
  local sh="$1" pass=0 fail=0 total=0 line=0
  echo "================= interpreter: $sh ================="
  while IFS=$'\t' read -r want tool cmd; do
    line=$((line+1))
    [ -z "${want:-}" ] && continue
    case "$want" in \#*) continue ;; esac
    total=$((total+1))
    cmd="${cmd//%FIX%/$FIX}"
    out="$(cd "$FIX" && payload "$tool" "$cmd" "t$$-$line-$RANDOM" | "$sh" "$G" 2>/dev/null)"
    got=A
    case "$out" in *'"ask"'*) got=K ;; esac
    if [ "$want" = "$got" ]; then
      pass=$((pass+1))
    else
      fail=$((fail+1)); printf '  FAIL want=%s got=%s | %s %s\n' "$want" "$got" "$tool" "$cmd"
    fi
  done < "$CASES"
  echo "  -> $pass passed, $fail failed (of $total)"
  return "$fail"
}

ledger_check() {  # asking twice for the same path in one session would be nagging
  local sh="$1" sid="ledger-$$-$RANDOM" a b
  a="$(cd "$FIX" && payload Bash "rm untracked.md" "$sid" | "$sh" "$G" 2>/dev/null)"
  b="$(cd "$FIX" && payload Bash "rm untracked.md" "$sid" | "$sh" "$G" 2>/dev/null)"
  rm -f "${TMPDIR:-/tmp}/apex-fs-guard-${sid}.seen"
  case "$a" in *'"ask"'*) ;; *) echo "  FAIL ledger: first call did not ask"; return 1 ;; esac
  case "$b" in *'"ask"'*) echo "  FAIL ledger: asked twice for the same path"; return 1 ;; esac
  echo "  -> ledger ok (asks once per path per session)"
  return 0
}

ownership_check() {  # a file this session created is not pre-existing content
  local sh="$1" sid="own-$$-$RANDOM" a b c
  rm -f "$FIX/session-made.md"
  # 1. Write to a path that does not exist yet -> silent, and the session claims it
  a="$(cd "$FIX" && payload Write "$FIX/session-made.md" "$sid" | "$sh" "$G" 2>/dev/null)"
  printf 'created\n' > "$FIX/session-made.md"
  # 2. rewriting the file we just authored must stay silent
  b="$(cd "$FIX" && payload Write "$FIX/session-made.md" "$sid" | "$sh" "$G" 2>/dev/null)"
  # 3. control: a pre-existing untracked file in the same session must still ask
  c="$(cd "$FIX" && payload Bash "rm sub/untracked2.md" "$sid" | "$sh" "$G" 2>/dev/null)"
  rm -f "${TMPDIR:-/tmp}/apex-fs-guard-${sid}.seen" "$FIX/session-made.md"
  case "$a" in *'"ask"'*) echo "  FAIL ownership: asked when creating a new file"; return 1 ;; esac
  case "$b" in *'"ask"'*) echo "  FAIL ownership: asked when rewriting a file this session created"; return 1 ;; esac
  case "$c" in *'"ask"'*) ;; *) echo "  FAIL ownership: stopped asking about pre-existing files"; return 1 ;; esac
  echo "  -> ownership ok (session-authored files never prompt; pre-existing ones still do)"
  return 0
}

f=0
for sh in /opt/homebrew/bin/bash /bin/bash; do
  [ -x "$sh" ] || continue
  runmatrix "$sh" || f=$((f+$?))
  ledger_check "$sh"    || f=$((f+1))
  ownership_check "$sh" || f=$((f+1))
done
exit "$f"
