# APEX Guardrails (hooks)

These turn kernel rules from *admonitions* into *mechanisms*. A rule the model is merely
told to follow can be skipped under load; a hook cannot.

| Hook | Event | Kernel rule | What it does | Hard or soft |
|---|---|---|---|---|
| `env-guard.sh` | PreToolUse(Bash) | §8 env hygiene | **Denies** `pip/conda/uv/poetry` installs that target base/system/global Python with no explicit non-shared env. | Hard gate (exit 2). |
| `fs-guard.sh` | PreToolUse(Bash, Write) | §8 recoverability | On `rm` / truncating `>` / `mv`·`cp` onto an existing file / `tee` / `git clean -f` / `Write`, **asks the user** when the target holds files git has never seen and does not ignore. | Soft gate (`permissionDecision: "ask"`). |
| `load-kernel.sh` | SessionStart | §1–§8 (all) | Injects `KERNEL.md` into context every session so the rules are always present, not memory-dependent. Scope selectable (see below). | Always-on context. |
| `completion-gate.sh` | Stop | §3 do not bluff | If the final turn claims success with hedge words but shows no verification/caveat, blocks **once** and asks for evidence. | Soft, opt-in, non-looping. |

## Why `fs-guard` asks instead of denying

The class it protects is narrow and provable: a path that is **untracked and not ignored**
has no recovery route at all — no git history, no archive copy, and the session transcript
expires. Tracked paths are recoverable; ignored paths are declared products.

But deleting such a file is *usually legitimate*, and only the user knows whether this one
matters. A hard block would be wrong most of the times it fires — and a guard that is wrong
often gets uninstalled, taking the guards that were right with it. Asking costs one
keystroke; it also puts the decision exactly where the kernel says it belongs (§6).

Three further concessions to the same concern:

- cache/junk paths (`__pycache__`, `*.pyc`, `.DS_Store`, `node_modules`, `.pytest_cache`, …)
  never prompt even when untracked;
- each path is asked about **once per session** — approving one and then editing it
  repeatedly does not re-prompt;
- **a file this session created is this session's own.** A `Write` to a path that does not
  exist yet claims it, so rewriting a file you just authored never prompts. The guard is
  protecting content that predates your involvement, not your own drafts.

Set `APEX_FS_GUARD=off` to disable it without touching settings.

## `load-kernel` scope

`load-kernel` is the harness's only unconditional cost: ~1.2k tokens in **every** session of
**every** project, because hooks have to be installed at user level to load reliably. If
that tax is unwanted in unrelated projects, set `APEX_SCOPE=marker` — the kernel is then
injected only where a `.apex` marker file or directory exists at or above the working
directory, and the `apex` skill still delivers it on demand elsewhere. Default is `always`
(unchanged behavior).

## What can and cannot be mechanized

Hooks are deterministic shell — they enforce rules that reduce to a string/JSON/filesystem
check.
- **Mechanizable → hooks** (here): env hygiene; recoverability of a delete/overwrite;
  always-load the kernel; a narrow anti-bluff completion check.
- **Cognitive → routed, not gated** (the skill + `references/`): tier classification,
  "verification covers the changed claim," experimental design, scope-holding, the
  consultation boundary. These are enforced through plan-mode sign-off, the
  `verify`/`code-review` skills, and adversarial subagent checks — judgment the model must
  exercise, with the skill as the rail.

### Deliberately not mechanized

Recording these matters as much as the hooks themselves: each one was considered and
rejected, so the next person does not re-litigate it.

| Not done | Why |
|---|---|
| A **Stop hook for the documentation/close-out checklist** | Only one item ("no doc was touched at all") is decidable; the rest are semantic. Mis-firing on the undecidable ones would train the user to disable the whole set. |
| Blocking **global `npm`/`cargo`/`gem` installs** | Unlike Python's base env, a global CLI install is routinely legitimate. The false-positive rate would exceed the harm prevented. |
| `fs-guard` on the **Edit tool** | Edit is surgical and requires a prior Read. It would fire on every revision of a brand-new file — the exact nagging pattern that gets guards uninstalled. |
| `fs-guard` for **`dd` / `truncate` / `shred` / `sed -i`** | Rare in agent work; each needs its own parser. Added only if one is actually observed. |
| Parsing **shell variables and `cd` chains** in `fs-guard` | `cd /elsewhere && rm "$f"` cannot be resolved without executing the command. Fails open, and it is documented rather than half-guessed. |
| `fs-guard` **outside a git work tree** | With no version control there is nothing to prove and everything would prompt. Kernel §8 and `references/workflow.md` §8 still apply by judgment there. |

Honest framing: this is defense in depth, not a sandbox. `env-guard` is a real gate;
`fs-guard` narrows a whole class of unrecoverable mistakes down to one user decision;
`completion-gate` is a conservative nudge tuned to avoid nagging (delete it if unwanted);
`load-kernel` just guarantees the rules are in context.

## Install

1. **Use user-level `~/.claude/settings.json`.** In testing, hooks in a *project*
   `.claude/settings.json` were not picked up (unlike skills, which load from a project
   `.claude/`); user-level hooks loaded reliably. User-level means these apply to every
   project — fine for `env-guard` and `fs-guard` (both safe globally), and see the scope
   note above for `load-kernel`.
2. Merge the `hooks` block from `settings.snippet.json` into that file, replacing
   `APEX_HOME` with the absolute path to the `apex-harness-cc` folder.
3. Ensure the scripts are executable: `chmod +x apex-harness-cc/hooks/*.sh`.
4. **Restart Claude Code** (or start a new session), then run `/hooks` to confirm
   `PreToolUse·Bash`, `PreToolUse·Write`, `SessionStart`, and `Stop` are listed. Empty list
   = not active.
5. Requires `jq` on PATH (`fs-guard` also requires `git`). If either is absent the hooks
   fail open (allow) so they can never wedge your session.

Verify manually:
```sh
echo '{"tool_input":{"command":"pip install requests"}}' | hooks/env-guard.sh; echo "exit=$?"   # -> exit=2 (blocked)
echo '{"tool_name":"Bash","tool_input":{"command":"rm some-untracked-file"}}' | hooks/fs-guard.sh   # -> JSON with permissionDecision "ask"
```

## Cost per tool call

Measured on macOS (Apple silicon, warm cache, 40 iterations):

| Hook | Path | Latency |
|---|---|---|
| `fs-guard` | command cannot destroy anything (pre-filter exits before any `git` call) | **~15 ms** |
| `fs-guard` | destructive verb, or `Write` to an existing file → one pathspec-limited `git status` per target | **~36 ms** |
| `fs-guard` | `Write` to a new path (claims it, exits) | **~29 ms** |
| `fs-guard` | `rm -rf` on a wholly-untracked 2000-file directory | **~77 ms** |
| `fs-guard` | worst case: a *tracked* directory holding 2000 untracked files (hits `RISK_CAP`) | **~490 ms** |
| `env-guard` | any Bash call | **~30 ms** |

`git status` itself costs ~30 ms in all of these; the rest is this shell. The default
untracked mode (not `-uall`) is what keeps the first large-directory case cheap — it
collapses a wholly-untracked directory to one line instead of two thousand.

`fs-guard`'s pre-filter is what keeps the common case cheaper than `env-guard`: most
commands contain no `rm`/`mv`/`cp`/`tee`/`clean`/`>` at all and exit before touching git.

## Tests

```sh
hooks/test-env-guard.sh          # 36 cases — env-guard
hooks/test-fs-guard.sh           # 50 cases + ledger + ownership — fs-guard (builds a throwaway git repo)
hooks/test-completion-gate.sh    # 13 cases — completion-gate (synthetic transcripts)
```

Each runs the matrix under both `/bin/bash` (3.2, macOS system) and a modern bash.
**Changing a hook requires adding cases here** — that is the only thing keeping "it still
works" from being a guess.

## Tuning

- Add safe patterns (e.g. an in-house env manager) to the `safe=true` cases in
  `env-guard.sh`.
- Extend `fs-guard.sh`'s `is_junk()` if your workflow generates another never-tracked class
  that should not prompt.
- `completion-gate.sh` only triggers on a small hedge-phrase list and stays silent when any
  verification/caveat language is present. Widen or remove to taste.
