#!/usr/bin/env bash
# APEX guardrail — SessionStart
# Loads the APEX kernel into context once per session so the rules are always present,
# instead of depending on the model to remember to read them.
#
# Contract: SessionStart hook stdout is injected as additional context.
# Resolve KERNEL.md relative to this script so it works wherever the package is installed.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kernel="$here/../apex/KERNEL.md"

if [ -f "$kernel" ]; then
  echo "<apex-kernel>"
  cat "$kernel"
  echo "</apex-kernel>"
  echo
  echo "The APEX kernel above is always in effect. For substantial work, load the \`apex\` skill."
fi
exit 0
