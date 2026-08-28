#!/usr/bin/env bash
# APEX guardrail — PreToolUse(Bash | Write)
# Mechanizes kernel §8 (recoverability): before deleting or overwriting a file, confirm it
# is recoverable. A file version control has never seen — and that is not ignored — leaves
# NO trace when removed or truncated: git has no record, there is no archive copy, and the
# session transcript expires. Every other class is recoverable (tracked -> `git checkout`;
# ignored -> a build product by declaration).
#
# Contract: PreToolUse JSON on stdin.
#   exit 0, no stdout                  -> allow silently
#   exit 0, {permissionDecision:"ask"} -> hand the decision to the user
# It never denies on its own. The operation is usually legitimate and only the user knows
# whether the target matters; asking costs one keystroke, while a false hard-block costs
# the whole hook — people uninstall guards that nag.
#
# Fail-open by design: no jq, no git, not inside a work tree, path outside the repo, or an
# unexpanded variable/glob it cannot resolve -> allow. It protects exactly the class it can
# *prove* is at risk, and can never wedge a session.
#
# Deliberately NOT covered (see hooks/README.md "What is deliberately not mechanized"):
#   files outside any git work tree; `dd`/`truncate`/`shred`; in-place editors (`sed -i`);
#   the Edit tool (surgical, requires a prior Read, and would fire on every revision of a
#   brand-new file).
#
# Note: kept bash-3.2 compatible (macOS /bin/bash) — no mapfile / ${,,} / assoc arrays.

set -u
input="$(cat)"

[ "${APEX_FS_GUARD:-on}" = "off" ] && exit 0
command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "nosid"' 2>/dev/null)"
ledger="${TMPDIR:-/tmp}/apex-fs-guard-${sid//\//_}.seen"

# Repo-root-relative form of a path, matching what `git status --porcelain` prints.
# Both sides are resolved to physical paths: on macOS the same repo is reachable as both
# /var/... and /private/var/..., and a textual prefix match silently fails on one of them.
relpath() {
  local top dir abs
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  top="$(cd "$top" 2>/dev/null && pwd -P)" || return 1
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  abs="$dir/$(basename "$1")"
  case "$abs" in "$top"/*) printf '%s' "${abs#"$top"/}" ;; *) return 1 ;; esac
}

# ---- collect candidate paths that this call could destroy -------------------------------
CAND=""
add() { [ -n "${1:-}" ] && [ "${1:-}" != "-" ] && CAND="$CAND$1"$'\n'; return 0; }

clean_x=false   # `git clean -x` also removes ignored files, which our probe cannot list

case "$tool" in
  Write)
    wpath="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    [ -z "$wpath" ] && exit 0
    if [ ! -e "$wpath" ]; then
      rel="$(relpath "$wpath" 2>/dev/null)" && [ -n "$rel" ] && \
        printf '%s\n' "$rel" >> "$ledger" 2>/dev/null
      exit 0
    fi
    add "$wpath"
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [ -z "$cmd" ] && exit 0
    # Cheap pre-filter: the overwhelming majority of commands cannot destroy anything.
    # Skip them before paying for a single git call.
    case "$cmd" in
      *rm*|*mv*|*cp*|*tee*|*clean*|*'>'*) ;;
      *) exit 0 ;;
    esac

    seps=$'&|;(){}`\n'
    while IFS= read -r seg || [ -n "$seg" ]; do
      read -ra T <<<"$seg"
      [ "${#T[@]}" -eq 0 ] && continue

      # ---- redirect scan: applies to every sub-command, whatever the program is ----
      # `>` and `N>` truncate. `>>` appends and `>&` dups — both harmless here.
      j=0
      while [ $j -lt ${#T[@]} ]; do
        case "${T[$j]}" in
          *'>>'*|*'>&'*) ;;
          [0-9]'>'|'>')     add "${T[$((j+1))]:-}" ;;
          [0-9]'>'*|'>'*)   add "${T[$j]#*>}" ;;
        esac
        j=$((j+1))
      done

      # ---- leading env-assignments / sudo / harmless wrappers ----
      i=0
      while [ $i -lt ${#T[@]} ]; do
        case "${T[$i]}" in
          *=*) i=$((i+1)) ;;
          sudo|env|command|exec|time|nice|nohup|builtin|\\) i=$((i+1)) ;;
          *) break ;;
        esac
      done
      [ $i -ge ${#T[@]} ] && continue

      prog="${T[$i]}"; base_prog="${prog##*/}"
      a1="${T[$((i+1))]:-}"

      case "$base_prog" in
        rm)
          endflags=false
          for ((j=i+1; j<${#T[@]}; j++)); do
            tok="${T[$j]}"
            if ! $endflags; then
              [ "$tok" = "--" ] && { endflags=true; continue; }
              case "$tok" in -?*) continue ;; esac
            fi
            add "$tok"
          done ;;
        mv|cp)
          # Only the DESTINATION can lose data: mv/cp preserve the source content.
          last=""
          endflags=false
          for ((j=i+1; j<${#T[@]}; j++)); do
            tok="${T[$j]}"
            if ! $endflags; then
              [ "$tok" = "--" ] && { endflags=true; continue; }
              case "$tok" in -?*) continue ;; esac
            fi
            last="$tok"
          done
          add "$last" ;;
        tee)
          # `tee -a` appends; bare `tee` truncates.
          appends=false
          for ((j=i+1; j<${#T[@]}; j++)); do
            case "${T[$j]}" in -a|--append|-*a*) appends=true ;; esac
          done
          if ! $appends; then
            for ((j=i+1; j<${#T[@]}; j++)); do
              case "${T[$j]}" in -?*) continue ;; esac
              add "${T[$j]}"
            done
          fi ;;
        git)
          # `git clean -f` deletes precisely the untracked class this hook exists for.
          if [ "$a1" = clean ]; then
            forced=false; dry=false
            for ((j=i+2; j<${#T[@]}; j++)); do
              case "${T[$j]}" in
                --dry-run) dry=true ;;
                --force)   forced=true ;;
                -*n*)      dry=true ;;
              esac
              case "${T[$j]}" in -*f*) forced=true ;; esac
              case "${T[$j]}" in -*x*) clean_x=true ;; esac
            done
            $forced && ! $dry && add "."
          fi ;;
      esac
    done < <(printf '%s' "$cmd" | tr "$seps" '\n')
    ;;
  *) exit 0 ;;
esac

[ -z "$CAND" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# ---- classify: which candidates hold files git has never seen? --------------------------
# `git status --porcelain -uall -- <path>` prints `?? p` for exactly the unrecoverable
# class. Tracked paths (recoverable via git) and ignored paths (declared products) do not
# appear. A path outside the repo makes git error out -> nothing found -> allow.
is_junk() {
  case "${1##*/}" in
    .DS_Store|Thumbs.db|*.pyc|*.pyo) return 0 ;;
  esac
  case "/$1/" in
    */__pycache__/*|*/.pytest_cache/*|*/.ruff_cache/*|*/.mypy_cache/*|\
    */.ipynb_checkpoints/*|*/node_modules/*) return 0 ;;
  esac
  return 1
}

AT_RISK=$'\n'; n_risk=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  while IFS= read -r u; do
    [ -z "$u" ] && continue
    is_junk "$u" && continue
    case "$AT_RISK" in *$'\n'"$u"$'\n'*) continue ;; esac
    AT_RISK="$AT_RISK$u"$'\n'; n_risk=$((n_risk+1))
  done < <(git -c core.quotepath=false status --porcelain -uall -- "$p" 2>/dev/null \
             | awk '/^\?\? /{sub(/^\?\? /,""); gsub(/^"|"$/,""); print}')
done < <(printf '%s' "$CAND")

[ "$n_risk" -eq 0 ] && exit 0

# ---- ask at most once per path per session ----------------------------------------------
# The ledger also carries paths this session created (see the Write branch): a file we
# authored ourselves is not the pre-existing content this guard is protecting.
FRESH=""; n_fresh=0
while IFS= read -r u; do
  [ -z "$u" ] && continue
  if [ -f "$ledger" ] && grep -qxF "$u" "$ledger" 2>/dev/null; then continue; fi
  printf '%s\n' "$u" >> "$ledger" 2>/dev/null
  FRESH="$FRESH  $u"$'\n'; n_fresh=$((n_fresh+1))
done < <(printf '%s' "$AT_RISK")

[ "$n_fresh" -eq 0 ] && exit 0

shown="$(printf '%s' "$FRESH" | head -8)"
[ "$n_fresh" -gt 8 ] && shown="$shown"$'\n'"  … and $((n_fresh-8)) more"

reason="[apex-guardrail] kernel §8 — this would destroy files version control has never seen.

Not tracked by git, not ignored — once removed or truncated there is no record anywhere:
no git history, no archive copy, and the session transcript expires.

$shown"
$clean_x && reason="$reason
(\`git clean -x\` additionally removes ignored files, which are not listed above.)"
reason="$reason

If this is intended, approve. Otherwise snapshot first:
  git add -A && git commit -m 'snapshot'
…or move it aside (\`mv <path> _archive/\`) instead of deleting.
\"Looks like a temp file / looks like something I generated\" is not a reason."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
exit 0
