# APEX Harness for Claude Code

A Claude Code-native port of the APEX execution discipline (originally a Codex skill;
upstream core idea: <https://github.com/4everWZ/apex-harness>). It keeps APEX's strong
cognitive core, rewrites the platform glue for Claude Code, **sinks the mechanizable rules
into hooks**, and **adds the dimensions the original lacked**: adversarial verification,
orchestration / context budget, and empirical-claim discipline.

## Why this exists

The original APEX skill is a high-quality *cognitive* harness — but it enforces everything
through prompt self-discipline alone, and it assumes a single agent working serially. This
port keeps the good parts and addresses both gaps:

1. **Distilled kernel** (`apex/KERNEL.md`) — the portable, platform-neutral core, kept in
   context at all times.
2. **Claude Code port** (`apex/SKILL.md` + `apex/references/`) — the kernel mapped onto CC
   primitives: plan mode, the `verify` / `code-review` skills, the Agent / Workflow tools.
3. **Guardrails** (`hooks/`) — rules that reduce to a deterministic check become hooks, not
   admonitions: a hard env-hygiene gate, a recoverability gate on destructive filesystem
   operations, always-load-the-kernel, a nudge when a stretch of work has produced no
   written record, and a conservative anti-bluff completion check.
4. **Added dimensions** — `references/verification.md` (adversarial verification),
   `references/orchestration.md` (context budget & fan-out), and
   `references/empirical_claims.md` (how a measurement earns the right to be called a
   result), plus a ready-to-run `workflows/apex-verify.js`.

## The three-layer model

```
Layer 1  Kernel        apex/KERNEL.md            platform-neutral; reusable by ANY agent
Layer 2  Modules       apex/references/*         tiers, verification, docs, orchestration
Layer 3  Platform glue hooks/, workflows/, SKILL routing, plan mode, verify/code-review
```

Layer 1 is the part worth copying to any agent. Layers 2–3 are Claude Code-specific
delivery.

## Layout

```
apex-harness-cc/
├── README.md                      # this file
├── apex/                          # ← the skill: copy into a Claude Code skills dir
│   ├── SKILL.md                   # CC-native skill (frontmatter + routing)
│   ├── KERNEL.md                  # distilled platform-neutral kernel (always in context)
│   └── references/
│       ├── workflow.md            # Tier A/B/C, verification policy, consultation boundary
│       ├── verification.md        # ADDED: adversarial verification
│       ├── empirical_claims.md    # ADDED: what makes a measured claim defensible
│       ├── orchestration.md       # ADDED: context budget & fan-out
│       ├── documentation_topology.md
│       ├── matrix_template.md
│       ├── tradeoff_template.md
│       └── status_template.md
├── hooks/                         # ← guardrails: wire into settings.json
│   ├── env-guard.sh               # PreToolUse(Bash): hard deny deps into base/system py
│   ├── fs-guard.sh                # PreToolUse(Bash|Write): ask before destroying untracked files
│   ├── split-subcommands.awk      # quote-aware sub-command splitting, shared by both guards
│   ├── record-nudge.sh            # SessionStart|UserPromptSubmit|PreCompact: ask for the write-up
│   ├── load-kernel.sh             # SessionStart: inject the kernel
│   ├── completion-gate.sh         # Stop: conservative anti-bluff check (opt-in)
│   ├── settings.snippet.json      # hook wiring to merge into settings.json
│   ├── test-*.sh / *-cases.tsv    # regression suites (158 cases, bash 3.2 + 5.x)
│   └── README.md                  # what each hook enforces; what is deliberately not mechanized
└── workflows/
    └── apex-verify.js             # reusable adversarial-verification workflow
```

## Install

### 1. The skill
Copy the `apex/` folder into a Claude Code skills directory:
- Global: `~/.claude/skills/apex/`
- Project: `<repo>/.claude/skills/apex/`

```sh
cp -R apex ~/.claude/skills/apex      # global
```
Claude Code discovers the skill from `SKILL.md` frontmatter and routes to it for
substantial work. The `apex` skill then pulls in `references/` on demand.

### 2. The guardrails (recommended)
Merge the `hooks` block from `hooks/settings.snippet.json` into your `settings.json`,
replacing `APEX_HOME` with the absolute path to this folder, then `chmod +x hooks/*.sh`.

> **Install hooks at user level (`~/.claude/settings.json`).** Skills are discovered by
> walking up from the working directory, so they load from a project `.claude/`. Hooks are
> not the same: in testing, hooks placed in a *project* `.claude/settings.json` were **not
> picked up** (e.g. when the session's working dir is a subdirectory of the repo), while
> user-level hooks loaded reliably. Verify with `/hooks` after a restart — it should list
> `PreToolUse·Bash`, `PreToolUse·Write`, `SessionStart`, and `Stop`. If it's empty, the
> hooks aren't active.
> Note: user-level hooks apply to *every* project. `env-guard` and `fs-guard` are safe
> globally; the `SessionStart` kernel injection adds ~1.2k tokens to every session, which
> `APEX_SCOPE=marker` limits to projects carrying a `.apex` marker — see Cost below.

After editing settings, **restart Claude Code** (or start a new session) so the hooks
register. Requires `jq` on PATH (`fs-guard` also requires `git`); hooks fail open (allow) if
either is missing. See `hooks/README.md` for exactly what each hook enforces, what is
**deliberately not** mechanized, and how to run the regression suites.

### 3. The verification workflow (optional)
Copy `workflows/apex-verify.js` into `<repo>/.claude/workflows/` to invoke it by name, or
point the `Workflow` tool at the file path. It is **opt-in** (spawns several agents) — use
it for Tier A / correctness-critical claims:
```
Workflow apex-verify  args={ "claim": "...", "evidence": ["path:line", "test cmd"] }
```

## How each original APEX rule lands here

| APEX rule | In this port |
|---|---|
| Risk-calibrated execution (Tier A/B/C) | `references/workflow.md` §1–2; Tier A/substantial-B → **plan mode** sign-off. |
| Stronger verification for higher risk | `verify` + `code-review` skills; **adversarial** panels for high blast (`verification.md`). |
| User decision boundaries | `references/workflow.md` §3 via **AskUserQuestion**. |
| No silent simplification / scope narrowing | Kernel §5 + consultation boundary; surfaced, not gated. |
| Doc sync when source-of-truth would go stale | `references/documentation_topology.md`. |
| Structured docs (specs/matrix/tradeoffs/status) | `references/*_template.md`. |
| Env hygiene (no deps into base/system) | **Mechanized**: `hooks/env-guard.sh` (hard deny). |
| Don't fake completeness | Kernel §3 + **`hooks/completion-gate.sh`**. |
| — (missing in original) Recoverability before destroying | **Added**: kernel §8 + **`hooks/fs-guard.sh`** (asks, doesn't deny). |
| Externalize state (rule existed, nothing watched it) | **Mechanized**: `hooks/record-nudge.sh` — kernel §7 now has an observer, and recording moved from the last step to the moment of discovery. |
| — (missing in original) Beyond one context | **Added**: `references/orchestration.md`. |
| — (missing in original) Adversarial checking | **Added**: `references/verification.md` + `workflows/apex-verify.js`. |
| — (missing in original) Defensible measured claims | **Added**: `references/empirical_claims.md`. |

## Reusing the kernel on other agents

`apex/KERNEL.md` is deliberately platform-neutral. To put it on any other agent, drop it
into that agent's always-loaded instruction surface (system prompt / global rules /
memory) and re-implement only Layers 2–3 against that agent's own primitives (its planning
mode, its verification tools, its hook/permission system). Don't copy the hooks or
workflow verbatim — those are Claude Code-shaped.

## Cost

The harness is designed to be proportionate, but it is not free.

**Context**

| What | When | Size |
|---|---|---|
| `KERNEL.md` | every session, via the `SessionStart` hook | **~1.3k tokens** |
| `SKILL.md` | only when the `apex` skill is invoked | ~1.6k tokens |
| `references/workflow.md` | routed to on demand | ~2.5k |
| `references/documentation_topology.md` | routed to on demand | ~2.5k |
| `references/empirical_claims.md` | routed to on demand | ~1.8k |
| `references/orchestration.md` | routed to on demand | ~0.9k |
| `references/verification.md` | routed to on demand | ~1.1k |
| `references/*_template.md` | routed to on demand | 0.2–0.4k each |

The kernel is the only unconditional cost, and it rides in early context so prompt caching
amortizes the per-turn price. If you do not want it in unrelated projects, set
`APEX_SCOPE=marker` (see `hooks/README.md`) and let it arrive via skill invocation instead.

**Hooks** — zero tokens on the happy path; they emit ~85–200 tokens only when they fire.
Latency per tool call, measured on macOS (Apple silicon, warm), median of 5 rounds x 30
invocations; round-to-round spread was 1-6 ms:

| Hook | Path | Latency |
|---|---|---|
| `env-guard` | any Bash call | ~17 ms |
| `record-nudge` | any user prompt (once per prompt, not per tool call) | ~48 ms |
| `fs-guard` | nothing destructive in the command (pre-filter, no `git` call) | ~19 ms |
| `fs-guard` | destructive verb, or `Write` to an existing file → one `git status` per target | ~36–41 ms |
| `fs-guard` | worst case: `rm -rf` a tracked directory holding thousands of untracked files | ~490 ms |

**Behavioral (the real driver)** — higher tiers spend more on *verification tool calls*.
Tier C ≈ negligible; Tier A adversarial verification (`apex-verify`) is the single most
expensive operation. **Measured:** a trivial 5-agent smoke test cost **~114k tokens**
(~23k/agent — opus subagents carry fixed system-prompt + reasoning overhead regardless of
how little they read). A realistic 7-agent run with real file reading is **~160k–400k
tokens**. By design, and opt-in — reserve it for claims where a wrong answer is costly.

## Status / what's been verified

Validated live on macOS (Claude Code, `jq` + `git` present, bash 3.2.57 and 5.3.15,
Python 3.11). Regression suites: **158 cases**, every matrix run under both interpreters.

**Hooks**

- `env-guard` parses each sub-command's leading program (not substring-scanning the whole
  line), so it blocks bare `pip`/`conda` installs **and** chain-bypasses like
  `uv run x && pip install evil`, while allowing the documented safe workflows
  (activate-then-install, `conda run -n proj …`, `uv pip install`, `uv add`) and
  commands that merely mention an install inside quotes — including when the quoted text
  contains shell separators, which an earlier version got wrong. A quoted command
  substitution still splits, so `echo "$(pip install evil)"` is not a bypass. 46 cases,
  `hooks/test-env-guard.sh`.
- `fs-guard` asks on the untracked-and-not-ignored class only, and stays silent for tracked
  files, ignored files, cache/junk paths, paths outside the repo, `>>` appends, `tee -a`,
  `git clean -n`, and `mv`/`cp` whose *source* is untracked. It follows chains
  (`ls && rm x`), does not fire on commands that merely mention a deletion, and asks about
  a given path at most once per session, and never about a file this session itself created.
  Absolute paths (the shape Claude Code actually sends) are covered, including the macOS
  `/var` → `/private/var` symlink case that a textual prefix match gets wrong. Each path
  is judged by the repo that owns it, not by the repo the shell stands in: a clone nested
  under a directory the outer repo ignores, and a repo reached from a cwd no repo owns, are
  both covered, and `rm -r` over a directory also asks about repos nested inside it (depth
  3). 65 cases plus ledger, ownership and elsewhere checks, `hooks/test-fs-guard.sh`. The emitted JSON was checked
  against the documented `permissionDecision` shape.
- `completion-gate` reads **only the last assistant message** (verified against a real
  transcript) and matches hedge/evidence terms on word boundaries. 13 cases,
  `hooks/test-completion-gate.sh`. The previous version fails 4 of those 13 — all in the
  permissive direction (evidence from an earlier turn excusing this one; `latest` and
  `testimonial` counting as a `test`; a subagent reply counting as this turn's).
- `load-kernel` injects the kernel at session start; `APEX_SCOPE=marker` correctly stays
  silent outside marked trees and fires inside them.
- `record-nudge` speaks only when work has changed files and nothing has reached `docs/`,
  re-arms on growth and after a compaction, goes quiet the moment something is recorded, and
  is not satisfied by a commit (its baseline is session start, not `HEAD`). 21 cases,
  `hooks/test-record-nudge.sh`, which walks a whole session through a throwaway repo.
- **Fail-open paths tested**: with `jq` removed from `PATH`, all three hooks exit 0 silently
  on input that otherwise blocks; `fs-guard` also allows when `git` is absent.
- **End-to-end in a live session**: with the hooks wired into `~/.claude/settings.json`,
  deleting an untracked scratch file produced a real permission prompt — `permissionDecision:
  "ask"` renders as a dialog, it is not advisory. Confirmed against the session's own ledger
  file, whose name matches the session id, so the trigger was the installed hook rather than
  a manual script run. `env-guard` also blocked two real commands during that install, both
  of them false positives, which is how the quoted-separator bug was found.

**Skill and workflow**

- The `apex` skill and the `apex-verify` workflow load and route correctly.
- `apex-verify` **run live** (5-agent smoke test): fan-out, schema-structured returns, and
  synthesis verdict all worked; the claim survived with no dissents.

**Out of scope**

- Linux and Windows. The hooks are written for macOS + bash 3.2/5.x and have never run
  elsewhere; nothing here claims they do.

**Not yet exercised**

- `apex-verify` against a real Tier-A claim with file-reading evidence.
- `references/empirical_claims.md` is distilled from a real multi-week experiment log, but
  has not yet been used to gate a live experiment in this harness.
- Whether `record-nudge` actually changes behaviour — that it fires correctly is covered by
  the suite, but whether being told makes the write-up happen is the claim that matters, and
  it needs live use to judge.

## Credits

The APEX execution discipline — risk-calibrated tiers, evidence-closed verification, the
consultation boundary, and the docs topology — originates from the upstream APEX harness:
<https://github.com/4everWZ/apex-harness>. This project is a Claude Code-native port of
that core idea, with the mechanizable rules moved into hooks and two dimensions added
(adversarial verification, orchestration / context budget).

## License

MIT — see [`LICENSE`](./LICENSE).
