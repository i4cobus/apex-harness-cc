# APEX Harness for Claude Code

A Claude Code-native port of the APEX execution discipline (originally a Codex skill;
upstream core idea: <https://github.com/4everWZ/apex-harness>). It keeps APEX's strong
cognitive core, rewrites the platform glue for Claude Code, **sinks the mechanizable rules
into hooks**, and **adds the two dimensions the original lacked**: adversarial verification
and orchestration / context budget.

## Why this exists

The original APEX skill is a high-quality *cognitive* harness — but it enforces everything
through prompt self-discipline alone, and it assumes a single agent working serially. This
port keeps the good parts and addresses both gaps:

1. **Distilled kernel** (`apex/KERNEL.md`) — the portable, platform-neutral core, kept in
   context at all times.
2. **Claude Code port** (`apex/SKILL.md` + `apex/references/`) — the kernel mapped onto CC
   primitives: plan mode, the `verify` / `code-review` skills, the Agent / Workflow tools.
3. **Guardrails** (`hooks/`) — rules that reduce to a deterministic check become hooks, not
   admonitions: a hard env-hygiene gate, always-load-the-kernel, and a conservative
   anti-bluff completion check.
4. **Added dimensions** — `references/verification.md` (adversarial verification) and
   `references/orchestration.md` (context budget & fan-out), plus a ready-to-run
   `workflows/apex-verify.js`.

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
apex-cc-harness/
├── README.md                      # this file
├── apex/                          # ← the skill: copy into a Claude Code skills dir
│   ├── SKILL.md                   # CC-native skill (frontmatter + routing)
│   ├── KERNEL.md                  # distilled platform-neutral kernel (always in context)
│   └── references/
│       ├── workflow.md            # Tier A/B/C, verification policy, consultation boundary
│       ├── verification.md        # ADDED: adversarial verification
│       ├── orchestration.md       # ADDED: context budget & fan-out
│       ├── documentation_topology.md
│       ├── matrix_template.md
│       ├── tradeoff_template.md
│       └── status_template.md
├── hooks/                         # ← guardrails: wire into settings.json
│   ├── env-guard.sh               # PreToolUse(Bash): hard deny deps into base/system py
│   ├── load-kernel.sh             # SessionStart: inject the kernel
│   ├── completion-gate.sh         # Stop: conservative anti-bluff check (opt-in)
│   ├── settings.snippet.json      # hook wiring to merge into settings.json
│   └── README.md                  # what each hook enforces; what can't be mechanized
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
> `PreToolUse·Bash`, `SessionStart`, and `Stop`. If it's empty, the hooks aren't active.
> Note: user-level hooks apply to *every* project (`env-guard` is safe globally; the
> `SessionStart` kernel injection adds ~1.1k tokens to every session — see Cost below).

After editing settings, **restart Claude Code** (or start a new session) so the hooks
register. Requires `jq` on PATH; hooks fail open (allow) if it's missing. See
`hooks/README.md` for exactly what each hook enforces and the limits of what can be
mechanized.

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
| — (missing in original) Beyond one context | **Added**: `references/orchestration.md`. |
| — (missing in original) Adversarial checking | **Added**: `references/verification.md` + `workflows/apex-verify.js`. |

## Reusing the kernel on other agents

`apex/KERNEL.md` is deliberately platform-neutral. To put it on any other agent, drop it
into that agent's always-loaded instruction surface (system prompt / global rules /
memory) and re-implement only Layers 2–3 against that agent's own primitives (its planning
mode, its verification tools, its hook/permission system). Don't copy the hooks or
workflow verbatim — those are Claude Code-shaped.

## Cost

The harness is designed to be proportionate, but it is not free:

- **Always-on:** the `SessionStart` hook injects `KERNEL.md` (~1.1k tokens) into **every**
  session. It rides in early context, so prompt caching amortizes the per-turn cost.
- **On invoke:** `SKILL.md` (~1.4k tokens) loads only when the `apex` skill is invoked.
  `references/` load lazily — only the ones you route to.
- **Hooks:** zero token cost on the happy path; `env-guard` / `completion-gate` emit
  ~120–150 tokens only when they actually block.
- **Behavioral (the real driver):** higher tiers spend more on *verification tool calls*.
  Tier C ≈ negligible; Tier A adversarial verification (`apex-verify`) is the single most
  expensive operation. **Measured:** a trivial 5-agent smoke test cost **~114k tokens**
  (~23k/agent — opus subagents carry fixed system-prompt + reasoning overhead regardless of
  how little they read). A realistic 7-agent run with real file reading is **~160k–400k
  tokens**. By design, and opt-in — reserve it for claims where a wrong answer is costly.

To drop the only cross-project tax, remove the `SessionStart` hook and let the kernel
arrive via skill invocation instead.

## Status / what's been verified

Validated live on macOS (Claude Code, `jq` present, Python 3.11):
- `env-guard` parses each sub-command's leading program (not substring-scanning the whole
  line), so it blocks bare `pip/conda/uv pip` installs **and** chain-bypasses like
  `uv run x && pip install evil`, while allowing the documented safe workflows
  (activate-then-install, `conda run -n proj …`, `uv venv && uv pip install`, `uv add`) and
  commands that merely mention an install in a quoted string. Covered by a 36-case
  regression suite (`hooks/test-env-guard.sh`) passing on bash 3.2 and 5.3.
- `load-kernel` injects the kernel at session start.
- `completion-gate` parses the real transcript format and triggers only on hedged-without-evidence endings.
- The `apex` skill and `apex-verify` workflow load and route correctly.
- `apex-verify` **run live** (5-agent smoke test): fan-out, schema-structured returns, and
  synthesis verdict all worked; the claim survived with no dissents.

Not yet exercised: hook behavior on Linux/Windows and the `jq`-absent fail-open path have
not been tested. `apex-verify` has been smoke-tested but not run against a real Tier-A
claim with file-reading evidence.

## Credits

The APEX execution discipline — risk-calibrated tiers, evidence-closed verification, the
consultation boundary, and the docs topology — originates from the upstream APEX harness:
<https://github.com/4everWZ/apex-harness>. This project is a Claude Code-native port of
that core idea, with the mechanizable rules moved into hooks and two dimensions added
(adversarial verification, orchestration / context budget).

## License

MIT — see [`LICENSE`](./LICENSE).
