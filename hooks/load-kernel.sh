#!/usr/bin/env bash
# APEX guardrail — SessionStart
# Loads the APEX kernel into context once per session so the rules are always present,
# instead of depending on the model to remember to read them.
#
# Contract: SessionStart hook stdout is injected as additional context.
# Resolve KERNEL.md relative to this script so it works wherever the package is installed.
#
# Scope (APEX_SCOPE): hooks must be installed at USER level to load reliably, so this one
# fires in every project — and it is the harness's only unconditional token cost (~1.1k per
# session). A hook that charges projects that never asked for it is a hook people uninstall,
# taking the free guards (env-guard, fs-guard) with it. So the scope is selectable:
#   always  (default) — inject everywhere. Backward compatible.
#   marker            — inject only where a `.apex` marker file/dir exists at or above the
#                       working directory. Silent elsewhere; the kernel still arrives via
#                       the `apex` skill when a session actually needs it.
# Set it in settings.json `env`, or export it in your shell profile.

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kernel="$here/../apex/KERNEL.md"
[ -f "$kernel" ] || exit 0

if [ "${APEX_SCOPE:-always}" = "marker" ]; then
  d="$PWD"; found=false
  while :; do
    [ -e "$d/.apex" ] && { found=true; break; }
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
  $found || exit 0
fi

echo "<apex-kernel>"
cat "$kernel"
echo "</apex-kernel>"
echo
echo "The APEX kernel above is always in effect. For substantial work, load the \`apex\` skill."
exit 0
