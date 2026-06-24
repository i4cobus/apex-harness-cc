#!/usr/bin/env bash
# APEX guardrail — PreToolUse(Bash)
# Mechanizes kernel §8 (env hygiene): deny installing project deps into a shared/base/
# system/global Python. This is a hard gate, not an admonition.
#
# Contract: receives the PreToolUse JSON on stdin. Exit 2 => deny + show stderr to Claude.
# Exit 0 => allow. Requires `jq` (falls back to allow if absent, so it can never wedge you).

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

# 1) Is this a dependency-install command at all?
is_install=false
case "$lc" in
  *"pip install"*|*"pip3 install"*|*"pip uninstall"*|*"python -m pip install"*|\
  *"uv pip install"*|*"uv add"*|*"conda install"*|*"mamba install"*|*"poetry add"*) is_install=true ;;
esac
$is_install || exit 0

# 2) An explicit, non-shared target makes it safe.
safe=false
case "$cmd" in
  *"--target"*|*"--prefix"*|*".venv/bin/"*|*"venv/bin/pip"*|*"source .venv/"*|\
  *". .venv/"*|*"VIRTUAL_ENV="*|*"conda run -n "*|*"poetry run"*|*"uv run"*|*"--python"*|\
  *"uv add"*|*"poetry add"*)
    safe=true ;;
esac
# Named conda env via -n / --name, but NOT base.
case "$lc" in
  *" -n "*|*"--name "*) safe=true ;;
esac

# 3) Explicit shared/base targets are never safe, even with a flag.
case "$lc" in
  *"-n base"*|*"--name base"*|*"activate base"*|*"/usr/bin/python"*|*"/usr/local/bin/python"*|\
  *"sudo pip"*|*"sudo -h"*) safe=false ;;
esac

$safe && exit 0

>&2 cat <<'MSG'
[apex-guardrail] BLOCKED: dependency install with no explicit, non-shared target environment.

Kernel §8: never install project deps into conda `base`, system Python, global Python, or
any shared interpreter.

Retry with an explicit target, e.g.:
  python -m venv .venv && source .venv/bin/activate && pip install ...
  conda create -n <proj> python=3.x && conda run -n <proj> pip install ...
  uv venv && uv pip install ...        # or: uv add <pkg>
  pip install --target ./.deps ...

If a shared/base install is genuinely intended, the USER must request it explicitly; then
they can approve this command directly.
MSG
exit 2
