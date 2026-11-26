# APEX Guardrails (hooks)

These turn kernel rules from *admonitions* into *mechanisms*. A rule the model is merely
told to follow can be skipped under load; a hook cannot.

| Hook | Event | Kernel rule | What it does | Hard or soft |
|---|---|---|---|---|
| `env-guard.sh` | PreToolUse(Bash) | §8 env hygiene | **Denies** `pip`/`conda` installs that target base/system/global Python with no explicit non-shared env. | Hard gate (exit 2). |
| `fs-guard.sh` | PreToolUse(Bash, Write) | §8 recoverability | On `rm` / truncating `>` / `mv`·`cp` onto an existing file / `tee` / `git clean -f` / `Write`, **asks the user** when the target holds files git has never seen and does not ignore. | Soft gate (`permissionDecision: "ask"`). |
| `load-kernel.sh` | SessionStart | §1–§8 (all) | Injects `KERNEL.md` into context every session so the rules are always present, not memory-dependent. Scope selectable (see below). | Always-on context. |
| `record-nudge.sh` | SessionStart, UserPromptSubmit, PreCompact | §7 externalize state | When N files have changed and **nothing** has been written to `docs/`, injects one line asking for the findings. Re-arms by growth and after every compaction. | Soft, non-blocking (`additionalContext`). |
| `completion-gate.sh` | Stop | §3 do not bluff | If the final turn claims success with hedge words but shows no verification/caveat, blocks **once** and asks for evidence. | Soft, opt-in, non-looping. |

## Why `fs-guard` asks instead of denying

The class it protects is narrow and provable: a path that is **untracked and not ignored**
has no recovery route at all — no git history, no archive copy, and the session transcript
expires. Tracked paths are recoverable; ignored paths are declared products.

"Untracked" and "ignored" are answered by **the repo that owns the path**, not by the repo
the shell happens to stand in. The difference is not cosmetic: an outer repo that ignores
a directory of nested clones reports every file inside them as ignored, so judged from the
outer repo any deletion inside a clone passes silently. For the same reason `rm -r` over a
directory also asks about repos nested inside it (three levels deep; a deeper one is
missed), and a path inside a repo is still checked when the cwd is in no repo at all.

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

Set `APEX_FS_GUARD=off` to disable it without touching settings; `env-guard` has the same
switch as `APEX_ENV_GUARD=off`. You want these exactly when a guard is wrong about your
case, which is the moment editing `settings.json` is most annoying.

## What `env-guard` trusts

`uv pip install` is allowed without an explicit target. uv enforces this hook's own
invariant itself: with no virtual environment it refuses outright and tells you to pass
`--system` (verified against uv 0.10.8), so it cannot reach a shared interpreter by
accident. `--system`, `--break-system-packages` and `sudo` are still blocked, and
regression cases pin each of them.

This is a deliberate trade, recorded because it is the kind of thing that looks like an
oversight later: the hook gives up an explicit-target requirement in exchange for trusting
a third-party tool's guarantee. If uv ever changes that default, this stops holding.
The alternative was a false positive on every uv project, and guards that are wrong on
ordinary commands get uninstalled.

## Heredoc bodies are data unless a shell owns them

A heredoc body is shell to be executed only when the heredoc feeds a shell. Fed to anything
else it is inert data: a file being written, a script in another language. Before this was
handled, the splitter parsed every body as shell and blocked

    cat > notes.md << 'EOF'
    pip install requests
    EOF

which writes a file and installs nothing. Hit live on 2026-09-03 while authoring a document
whose *content* was install instructions. It only misfired when a body line's leading token
was itself an install command — `text = "pip install x"` was always fine, because the
leading token is `text`.

`split-subcommands.awk` now consumes a heredoc body at the end of the opening line and drops
it, unless the owning fragment's leading program is a shell, in which case the body is kept
and split as usual. The owner is resolved past `sudo` / `env` / `command` / `exec` / `nohup`
wrappers and `VAR=val` prefixes, and by basename, so `/bin/bash` and `sudo bash` both count.
Quoting the delimiter changes expansion, not who executes it, so it does not enter into this.
`<<<` is a herestring, not a heredoc, and is untouched.

Loosening a guard needs its opposite direction pinned harder than the fix itself. Regression
cases cover `bash`, `sudo bash`, `/bin/bash`, `env bash`, the `<<-` tab form, an unterminated
shell heredoc, and a real install chained after the opener on the same line — all still
blocked.

Residual gap, accepted: a command outside the shell list that runs its own stdin as shell
hides its body from the scan. Nothing common does this, and the previous behaviour bought
coverage of that case at the price of blocking ordinary document authoring.

## Why `record-nudge` nudges on a growth curve

The pain it addresses is having to remind the agent to write things down. The rule already
existed (kernel §7); nothing was watching whether it was followed.

Blocking was rejected for the reason recorded below: of a close-out checklist, only one item
is decidable. But that one item — *nothing at all was written down* — is worth saying out
loud, and `UserPromptSubmit` is the only event that can inject context and be trusted to
(`PreCompact` can block but cannot speak, so it re-arms the next prompt instead).

Frequency is the part that is easy to get wrong. Once per session is useless to anyone who
runs long sessions through repeated compactions: the one reminder lands at the start, about
nothing. So it re-arms on **growth** — another `nudge_after` files changed with still
nothing recorded — and **immediately after a compaction**, which is the moment unwritten
findings actually die. Writing anything to the knowledge layer resets it.

The baseline is where the repo stood at session start, not `HEAD`, so committing the work
does not clear the debt: a commit records what you did, not what you learned.

Config, in the `.apex` marker file:

```
nudge_after = 5          # files changed before it speaks again (default 5)
knowledge   = docs/      # what counts as having recorded something
```

`APEX_NUDGE=off` disables it; `APEX_NUDGE_AFTER` overrides the threshold from the
environment.

## Sub-command splitting

Both `PreToolUse(Bash)` hooks judge each sub-command by its leading program, so where the
fragment boundaries fall decides the verdict. `split-subcommands.awk` places them the way
a shell would: separators inside quotes are text, but `$(` and backticks still split,
because a command substitution runs even when it is double-quoted (so `echo "$(pip install evil)"`
is not a bypass).

The earlier version split on every separator regardless of quoting, reasoning that
over-splitting could only drop a trigger and never create one. That is false - it promotes
a quoted word to the front of a fragment, so a commit message that mentioned an install
inside parentheses was blocked as a dependency install. It fired twice within minutes of
the hooks first being installed for real use.

The same file also decides what to do with a heredoc body, on the same principle — see
[Heredoc bodies are data unless a shell owns them](#heredoc-bodies-are-data-unless-a-shell-owns-them).
Both are the same lesson: a fragment is only a command if a shell would actually run it.

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
| A **Stop hook for the documentation/close-out checklist** | Only one item ("no doc was touched at all") is decidable; the rest are semantic. Mis-firing on the undecidable ones would train the user to disable the whole set. That one decidable item is now handled by `record-nudge`, which injects a line instead of blocking. |
| Blocking **global `npm`/`cargo`/`gem` installs** | Unlike Python's base env, a global CLI install is routinely legitimate. The false-positive rate would exceed the harm prevented. |
| `fs-guard` on the **Edit tool** | Edit is surgical and requires a prior Read. It would fire on every revision of a brand-new file — the exact nagging pattern that gets guards uninstalled. |
| `fs-guard` for **`dd` / `truncate` / `shred` / `sed -i`** | Rare in agent work; each needs its own parser. Added only if one is actually observed. |
| Parsing **shell variables and `cd` chains** in `fs-guard` | `cd /elsewhere && rm "$f"` cannot be resolved without executing the command. Fails open, and it is documented rather than half-guessed. |
| `fs-guard` on a path **no git work tree owns** | With no version control there is nothing to prove and everything would prompt. Kernel §8 and `references/workflow.md` §8 still apply by judgment there. |

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
   `PreToolUse·Bash`, `PreToolUse·Write`, `SessionStart`, `UserPromptSubmit`, `PreCompact`
   and `Stop` are listed. Empty list = not active.
5. Requires `jq` on PATH (`fs-guard` also requires `git`). If either is absent the hooks
   fail open (allow) so they can never wedge your session.

Verify manually:
```sh
echo '{"tool_input":{"command":"pip install requests"}}' | hooks/env-guard.sh; echo "exit=$?"   # -> exit=2 (blocked)
echo '{"tool_name":"Bash","tool_input":{"command":"rm some-untracked-file"}}' | hooks/fs-guard.sh   # -> JSON with permissionDecision "ask"
```

## Cost per tool call

Measured on macOS (Apple silicon, warm), median of 5 rounds x 30 invocations. Round-to-round
spread was 1-6 ms, so treat smaller differences as noise.

| Hook | Path | Latency |
|---|---|---|
| `env-guard` | any Bash call | **~17 ms** |
| `record-nudge` | any user prompt (once per prompt, not per tool call) | **~48 ms** |
| `fs-guard` | command cannot destroy anything (pre-filter exits before splitting or calling `git`) | **~19 ms** |
| `fs-guard` | `Write` to an existing file | **~36 ms** |
| `fs-guard` | destructive verb -> quote-aware split + one pathspec-limited `git status` per target | **~41 ms** |
| `fs-guard` | `rm -rf` on a wholly-untracked 2000-file directory | **~77 ms** |
| `fs-guard` | worst case: a *tracked* directory holding 2000 untracked files (hits `RISK_CAP`) | **~490 ms** |

`git status` itself is ~30 ms of the last three; the rest is this shell. Two things keep the
common cases cheap: `fs-guard`'s pre-filter (most commands contain no destructive verb and
exit before any work), and the default untracked mode rather than `-uall`, which collapses a
wholly-untracked directory to one line instead of two thousand.

## Tests

```sh
hooks/test-env-guard.sh          # 59 cases — env-guard
hooks/test-fs-guard.sh           # 50 cases + ledger + ownership — fs-guard (builds a throwaway git repo)
hooks/test-completion-gate.sh    # 13 cases — completion-gate (synthetic transcripts)
hooks/test-record-nudge.sh       # 21 cases — record-nudge (a session walked through a repo)
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
