#!/usr/bin/env bash
# APEX guardrail — PreToolUse(Bash)
# Mechanizes kernel §8 (env hygiene): deny installing project deps into a shared/base/
# system/global Python. This is a hard gate, not an admonition.
#
# Contract: receives the PreToolUse JSON on stdin. Exit 2 => deny + show stderr to Claude.
# Exit 0 => allow. Requires `jq` (falls back to allow if absent, so it can never wedge you).
#
# Design — why this is not substring matching:
#   The command is split into sub-commands on shell separators, and EACH is judged by its
#   parsed leading program (after env-assignments / sudo / wrappers), not by scanning the
#   whole string for "pip install" or "uv run". That kills two failure modes the naive
#   version had:
#     * false-negative: a "safe" token (uv run, ` -n `, --target) appearing in ONE part of
#       a chain whitelisted a bare global install in ANOTHER part
#       (e.g. `uv run x && pip install evil`, `echo -n x && pip install evil`).
#     * false-positive: a command that merely MENTIONS an install in a quoted string got
#       blocked (e.g. `echo "pip install"`, `git commit -m "...pip install..."`).
#   Cross-sub-command venv activation is tracked so the documented safe workflows
#   (activate-then-install, `uv venv && uv pip install`, `conda run -n proj pip install`)
#   keep working.
# Note: kept bash-3.2 compatible (macOS /bin/bash) — no mapfile/${,,}.

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Treat empty / "base" / "root" as the shared environment.
is_base() { case "$1" in ""|base|root) return 0 ;; *) return 1 ;; esac; }

# Split into sub-commands on  && || | ; &  ( ) { } `  and newlines. Over-splitting is
# safe here: a fragment whose leading token is not a package manager simply won't match,
# so it can only ever drop a false trigger, never create one. Under-splitting would be
# dangerous, so we err toward splitting on everything separator-like.
seps=$'&|;(){}`\n'

ctx_targeted=false   # a non-shared env has been established earlier in this chain
block=false
offender=""

while IFS= read -r seg || [ -n "$seg" ]; do
  # tokenize on whitespace (quotes aren't honored, but we only inspect leading program
  # tokens + flags, where that is fine and cannot manufacture a false install match)
  read -ra T <<<"$seg"
  [ "${#T[@]}" -eq 0 ] && continue

  sudo=false
  i=0
  # skip leading env-var assignments and harmless wrappers; note sudo; track inline env
  while [ $i -lt ${#T[@]} ]; do
    tok="${T[$i]}"
    case "$tok" in
      VIRTUAL_ENV=*|CONDA_PREFIX=*) ctx_targeted=true; i=$((i+1)) ;;
      CONDA_DEFAULT_ENV=*)
        if is_base "${tok#*=}"; then ctx_targeted=false; else ctx_targeted=true; fi
        i=$((i+1)) ;;
      *=*)        i=$((i+1)) ;;            # other VAR=value assignment
      sudo)       sudo=true; i=$((i+1)) ;;
      env|command|exec|time|nice|nohup|builtin|\\) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ $i -ge ${#T[@]} ] && continue

  prog="${T[$i]}"
  base_prog="${prog##*/}"
  a1="${T[$((i+1))]:-}"; a2="${T[$((i+2))]:-}"; a3="${T[$((i+3))]:-}"

  prog_is_system_py=false
  case "$prog" in
    /usr/bin/python*|/usr/local/bin/python*|/usr/bin/pip*|/usr/local/bin/pip*) prog_is_system_py=true ;;
  esac

  # ---- environment-context updates (activation / creation / deactivation) ----
  case "$base_prog" in
    source|.)
      case "$seg" in
        *"activate base"*) ctx_targeted=false ;;
        *activate*)        ctx_targeted=true ;;
      esac ;;
    conda|mamba)
      if [ "$a1" = activate ];   then is_base "$a2" && ctx_targeted=false || ctx_targeted=true; continue; fi
      if [ "$a1" = deactivate ]; then ctx_targeted=false; continue; fi ;;
    uv)
      [ "$a1" = venv ] && ctx_targeted=true ;;
    python|python3)
      { [ "$a1" = -m ] && [ "$a2" = venv ]; } && ctx_targeted=true ;;
  esac

  # ---- unwrap `conda run [-n NAME|--name NAME|-p PREFIX] ...` so the real install shows ----
  if { [ "$base_prog" = conda ] || [ "$base_prog" = mamba ]; } && [ "$a1" = run ]; then
    i=$((i+2))
    while [ $i -lt ${#T[@]} ]; do
      case "${T[$i]}" in
        -n|--name)   is_base "${T[$((i+1))]:-}" && ctx_targeted=false || ctx_targeted=true; i=$((i+2)) ;;
        --name=*)    is_base "${T[$i]#--name=}" && ctx_targeted=false || ctx_targeted=true; i=$((i+1)) ;;
        -n*)         is_base "${T[$i]#-n}"      && ctx_targeted=false || ctx_targeted=true; i=$((i+1)) ;;
        -p|--prefix) ctx_targeted=true; i=$((i+2)) ;;
        --prefix=*)  ctx_targeted=true; i=$((i+1)) ;;
        --no-capture-output|--live-stream) i=$((i+1)) ;;
        *) break ;;
      esac
    done
    [ $i -ge ${#T[@]} ] && continue
    prog="${T[$i]}"; base_prog="${prog##*/}"
    a1="${T[$((i+1))]:-}"; a2="${T[$((i+2))]:-}"; a3="${T[$((i+3))]:-}"
    case "$prog" in
      /usr/bin/python*|/usr/local/bin/python*|/usr/bin/pip*|/usr/local/bin/pip*) prog_is_system_py=true ;;
    esac
  fi

  # ---- is THIS sub-command a dependency install? ----
  kind=""   # pip | conda | manifest | ""
  case "$base_prog" in
    pip|pip3)
      case "$a1" in install|uninstall) kind=pip ;; esac ;;
    python|python3)
      if [ "$a1" = -m ] && [ "$a2" = pip ]; then
        case "$a3" in install|uninstall) kind=pip ;; esac
      fi ;;
    uv)
      if   [ "$a1" = pip ]; then case "$a2" in install) kind=pip ;; esac
      elif [ "$a1" = add ]; then kind=manifest
      fi ;;
    conda|mamba)
      case "$a1" in install) kind=conda ;; esac ;;
    poetry)
      case "$a1" in add|install) kind=manifest ;; esac ;;
  esac
  [ -z "$kind" ] && continue

  # manifest-scoped installs (uv add / poetry add / poetry install) act on the project's
  # managed env, never a shared/base interpreter — always safe.
  [ "$kind" = manifest ] && continue

  # ---- safety of this install sub-command ----
  local_safe=false
  never_safe=false
  $sudo && never_safe=true
  $prog_is_system_py && never_safe=true

  for ((j=i; j<${#T[@]}; j++)); do
    case "${T[$j]}" in
      --target|--target=*|--prefix|--prefix=*|--python|--python=*) local_safe=true ;;
      *".venv/bin/"*|*"venv/bin/pip"*)                              local_safe=true ;;
      --system|--break-system-packages)                            never_safe=true ;;
    esac
  done

  if [ "$kind" = conda ]; then
    for ((j=i; j<${#T[@]}; j++)); do
      case "${T[$j]}" in
        -n|--name) is_base "${T[$((j+1))]:-}" && never_safe=true || local_safe=true ;;
        -n*)       is_base "${T[$j]#-n}"      && never_safe=true || local_safe=true ;;
        --name=*)  is_base "${T[$j]#--name=}" && never_safe=true || local_safe=true ;;
      esac
    done
  fi

  safe=false
  if ! $never_safe && { $local_safe || $ctx_targeted; }; then safe=true; fi

  if ! $safe; then
    block=true
    # trim leading whitespace for the report
    offender="${seg#"${seg%%[![:space:]]*}"}"
    break
  fi
done < <(printf '%s' "$cmd" | tr "$seps" '\n')

$block || exit 0

>&2 cat <<MSG
[apex-guardrail] BLOCKED: dependency install with no explicit, non-shared target environment.

Kernel §8: never install project deps into conda \`base\`, system Python, global Python, or
any shared interpreter.

Offending sub-command:
  $offender

Retry with an explicit target, e.g.:
  python -m venv .venv && source .venv/bin/activate && pip install ...
  conda create -n <proj> python=3.x && conda run -n <proj> pip install ...
  uv venv && uv pip install ...        # or: uv add <pkg>
  pip install --target ./.deps ...

If a shared/base install is genuinely intended, the USER must request it explicitly; then
they can approve this command directly.
MSG
exit 2
