# APEX Guardrails (hooks)

These turn kernel rules from *admonitions* into *mechanisms*. A rule the model is merely
told to follow can be skipped under load; a hook cannot.

| Hook | Event | Kernel rule | What it does | Hard or soft |
|---|---|---|---|---|
| `env-guard.sh` | PreToolUse(Bash) | §8 env hygiene | **Denies** `pip/conda/uv/poetry` installs that target base/system/global Python with no explicit non-shared env. | Hard gate (exit 2). |
| `load-kernel.sh` | SessionStart | §1–§8 (all) | Injects `KERNEL.md` into context every session so the rules are always present, not memory-dependent. | Always-on context. |
| `completion-gate.sh` | Stop | §3 do not bluff | If the final turn claims success with hedge words but shows no verification/caveat, blocks **once** and asks for evidence. | Soft, opt-in, non-looping. |

## What can and cannot be mechanized

Hooks are deterministic shell — they enforce rules that reduce to a string/JSON check.
- **Mechanizable → hooks** (here): env hygiene; always-load the kernel; a narrow
  anti-bluff completion check.
- **Cognitive → routed, not gated** (the skill + `references/`): tier classification,
  "verification covers the changed claim," scope-holding, the consultation boundary.
  These are enforced through plan-mode sign-off, the `verify`/`code-review` skills, and
  adversarial subagent checks — judgment the model must exercise, with the skill as the
  rail.

Honest framing: this is defense in depth, not a sandbox. `env-guard` is a real gate;
`completion-gate` is a conservative nudge tuned to avoid nagging (delete it if unwanted);
`load-kernel` just guarantees the rules are in context.

## Install

1. **Use user-level `~/.claude/settings.json`.** In testing, hooks in a *project*
   `.claude/settings.json` were not picked up (unlike skills, which load from a project
   `.claude/`); user-level hooks loaded reliably. User-level means these apply to every
   project — fine for `env-guard` (safe globally) and `load-kernel` (always-on kernel).
2. Merge the `hooks` block from `settings.snippet.json` into that file, replacing
   `APEX_HOME` with the absolute path to the `apex-cc-harness` folder.
3. Ensure the scripts are executable: `chmod +x apex-cc-harness/hooks/*.sh`.
4. **Restart Claude Code** (or start a new session), then run `/hooks` to confirm
   `PreToolUse·Bash`, `SessionStart`, and `Stop` are listed. Empty list = not active.
5. Requires `jq` on PATH. If `jq` is absent, `env-guard` and `completion-gate` fail open
   (allow) so they can never wedge your session.

Verify a hook manually:
```sh
echo '{"tool_input":{"command":"pip install requests"}}' | apex-cc-harness/hooks/env-guard.sh; echo "exit=$?"   # -> exit=2 (blocked)
```

## Tuning

- Add safe patterns (e.g. an in-house env manager) to the `safe=true` cases in
  `env-guard.sh`.
- `completion-gate.sh` only triggers on a small hedge-phrase list and stays silent when
  any verification/caveat language is present. Widen or remove to taste.
