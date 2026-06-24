# Orchestration & Context Budget

The original APEX skill assumed a single agent working serially. Real substantial work —
large refactors, audits, migrations, multi-subsystem reads — does not fit one context.
This file adds that missing dimension: how to decompose, when to fan out, and how to
protect the context budget.

## The core constraint

Your context window is finite and lossy. Two failure modes follow:
- **Overflow** — pulling so much into context that earlier reasoning is summarized away
  mid-task.
- **Serial drag** — doing breadth-first work (read 20 files, check 12 channels) inline,
  one item at a time, when it could fan out.

The lever against both is delegation: push breadth into subagents that return
**conclusions, not raw material**, keeping your context for synthesis and decisions.

## Decision: inline vs subagent vs workflow

| Situation | Move |
|---|---|
| Single known fact / file / symbol | Do it inline — don't delegate a one-shot lookup. |
| Broad search across many files where you need the conclusion, not the dumps | One `Agent` (Explore) call. |
| Several independent work items, results needed together | Multiple `Agent` calls in one message (parallel). |
| Multi-stage work over many items (find → verify → fix), or anything needing loops / fan-out / synthesis at scale | `Workflow` (deterministic orchestration). |
| Long task at risk of context overflow | Delegate the bulky reads; keep only distilled returns. |

**Scout, then orchestrate.** You don't need the shape before the *task* — only before the
*orchestration step*. List the files / find the call sites inline first, then fan out over
that work-list.

## Reaching for a Workflow (opt-in)

Workflows can spawn many agents and spend a lot of tokens, so they are **explicit opt-in**:
use one only when the user asked for multi-agent orchestration, ran an installed workflow,
or you are invoking a shipped script (e.g. `apex-verify`) for its stated purpose. Otherwise
describe what a workflow would do and its rough cost, and ask.

When you do orchestrate, prefer:
- **pipeline over barrier** — let each item flow through all stages independently; only
  synchronize (barrier) when a stage genuinely needs all prior results (dedup, total
  count, cross-item comparison).
- **structured returns** — give fan-out agents a schema so results come back as data, not
  prose to re-parse.
- **coverage over silence** — when a sweep bounds itself (top-N, sampling, no-retry), say
  what was dropped. Silence reads as "covered everything" when it wasn't.

## Mapping to APEX tiers

- **Tier C** — never orchestrate. Inline.
- **Tier B** — at most a search agent or a couple of parallel readers for breadth.
- **Tier A** — orchestration is often justified: parallel readers to build a system map;
  adversarial verification panels (`verification.md`); migration pipelines (discover →
  transform in isolated worktrees → verify). Decompose explicitly and record coverage in
  the matrix.

## Context hygiene during long tasks

- Externalize state to `docs/` (kernel §7) so progress survives compaction.
- Prefer reading the *part* of a file you need over the whole file.
- Don't re-read files you just edited to "confirm" — the edit tools already report success.
- When a finding matters for later, write it down (matrix / tradeoff log), don't rely on
  it staying in context.
