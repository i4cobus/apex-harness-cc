---
name: apex
description: Disciplined execution harness for substantial coding, refactoring, architecture, research, or ML work that needs risk-calibrated effort, evidence-closed verification, clear user decision points, and durable docs (specs, design docs, coverage matrices, tradeoff logs, handoff records). Routes verification through plan mode, the verify/code-review skills, and adversarial subagent checks. Do NOT use for trivial low-risk edits (minor UI text, comments, narrow obvious fixes).
---

# APEX Harness (Claude Code)

A Claude Code-native port of the APEX execution discipline. The portable rules live in
`KERNEL.md` (kept in context); this skill turns them into concrete Claude Code behavior
and routes to deeper procedures on demand.

Use this when the task is substantial enough to need discipline rather than ad hoc
coding: significant implementation/refactor, ML/DL algorithm work, research-oriented
coding where evaluation semantics matter, architecture-level or cross-module changes, or
work needing durable docs / coverage tracking / explicit tradeoffs / handoff.

Do **not** use it for trivial low-risk edits (minor UI text, comments-only, narrow local
fixes with obvious behavior and small blast radius).

## The kernel (always applies)

Read `KERNEL.md`. In short: calibrate effort to blast radius; close the loop with real
evidence; never bluff; never guess load-bearing facts; hold scope and surface tradeoffs;
know when to yield control; externalize state for long work; keep the workspace clean.

## How the kernel maps onto Claude Code primitives

The kernel is not just advice here — it is wired to mechanisms. Some rules are enforced
by hooks (see `../hooks/`); the rest you execute through these native moves:

| Kernel rule | Claude Code move |
|---|---|
| Calibrate effort (Tier A/B/C) | For Tier A or substantial Tier B, **enter plan mode** before implementing; present tier + success criteria + verification path, get sign-off via ExitPlanMode. |
| Close the loop with evidence | Run `verify` to drive the real app/behavior; run `code-review` on the diff. Existing tests first; a dedicated harness only when they can't localize the claim. |
| Adversarial verification (added) | For high-blast claims, fan out independent skeptics via the `apex-verify` workflow or the Agent tool — see `references/verification.md`. |
| Don't bluff / completion gate | Honor the completion rules in `references/workflow.md`; the `completion-gate` Stop hook reminds you before finishing. |
| Hold scope; surface tradeoffs | Use AskUserQuestion only at the consultation boundary (`references/workflow.md` §3). Record approved deviations via `references/tradeoff_template.md`. |
| Externalize state | Maintain `docs/` artifacts per `references/documentation_topology.md`; coverage in `docs/matrix_*.md`; handoff only when asked. |
| Keep workspace clean (env hygiene) | Enforced by the `env-guard` PreToolUse hook — deps cannot be installed into base/system/global Python. |
| Scale beyond one context | Decompose with the Agent/Workflow tools per `references/orchestration.md`. |

## Activation output

When this skill is active, state before implementing (concise — a boundary, not
ceremony):
- task tier and why
- success criteria
- verification path (which tests / `verify` / `code-review` / adversarial check)
- whether docs, coverage matrix, tradeoff log, or (only if requested) handoff updates are
  required

## Routing

- `references/workflow.md` — Tier A/B/C classification, verification policy, user
  consultation boundary, harness rules, completion rules, handoff, environment policy.
- `references/verification.md` — evidence standards and **adversarial verification**
  (independent skeptics, perspective-diverse panels, the `apex-verify` workflow).
- `references/orchestration.md` — **context budget and fan-out**: when to stay inline,
  when to spawn subagents, when to run a Workflow; pipeline vs barrier.
- `references/documentation_topology.md` — what belongs in `docs/specs/`, `docs/design/`,
  `docs/matrix_*.md`, `docs/tradeoffs.md`; update rules by tier.
- `references/matrix_template.md` — spec-to-implementation coverage matrix.
- `references/tradeoff_template.md` — `docs/tradeoffs.md` entries with stable IDs.
- `references/status_template.md` — short, user-requested handoff snapshots.

## Red flags — stop and re-check

- "I'll do the simple version first" for a requested feature/algorithm/eval/contract.
- "This probably works" with no observable evidence.
- "The shape / schema / config probably is…" without reading the source of truth.
- "Docs can be updated later" after a source-of-truth doc went stale or wrong.
- "Small enough to skip classification."
- Creating/refreshing handoff docs without the user asking for handoff.

## Repository assumptions

Unless the repo defines a stronger convention (then follow repo truth):
- `docs/specs/` active specs and leaf docs; `docs/specs/legacy/` superseded specs
- `docs/specs/status_*.md` handoff snapshots (only when requested)
- `docs/design/` global architecture / system structure
- `docs/matrix_*.md` spec-to-implementation matrices
- `docs/tradeoffs.md` repository-wide approved/unavoidable deviations

## Minimal always-on behavior

- Keep diffs proportionate to scope.
- Prefer existing reliable tests over redundant scaffolding.
- Ask before committing to material research/architecture tradeoffs.
- Do not claim completion unless scope, verification, and required docs are mutually
  consistent.
