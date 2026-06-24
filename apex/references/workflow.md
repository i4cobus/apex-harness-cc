# Workflow (Claude Code)

Procedures behind the kernel. Apply at the intensity the tier demands.

## 1. Task classification

Classify before implementing.

### Tier A — Heavyweight
Changes that affect:
- research logic, algorithms, math, losses, evaluation, baselines, or ablations
- training or inference semantics
- data preprocessing, dataset contracts, or label meaning
- architecture or cross-module contracts
- public APIs, storage schemas, or correctness-critical infrastructure
- anything that could materially alter scope, capability, claims, or downstream trust

### Tier B — Standard
Changes that affect:
- internal backend logic, medium bugfixes, config behavior, scripts
- moderate refactors, local but behavior-changing code

Treat Tier B as **substantial** when any hold: ≥3 files or >1 module boundary; changes
config semantics, CLI, user-visible behavior, or documented usage; changes behavior
future work will depend on; user asks for handoff; needs a coverage matrix to avoid
losing track of partial scope.

### Tier C — Lightweight
Low-risk and local: UI text/styling, logging, comments/docstrings, narrow parameter
plumbing, non-behavioral renames, highly localized fixes.

### Classification rules
- Default to the lowest truthful tier.
- Escalate the instant the task is found to touch a higher-risk boundary.
- If uncertain, escalate one tier.

## 2. Verification policy

Verification intensity matches task intensity. In Claude Code, verification is concrete:
existing tests, the `verify` skill (drives the real app/behavior), the `code-review`
skill (reviews the diff), and — for high-blast claims — adversarial subagent checks
(`references/verification.md`).

### Tier A — must include
- explicit success criteria (stated in plan mode before implementing)
- observability check (output of the changed claim is actually seen)
- critical review of assumptions and risk — run `code-review` on the diff
- **adversarial verification** of the central claim (`apex-verify` workflow or Agent fan-out)
- a dedicated harness only when existing tests cannot isolate the claim
- an autonomous verify→fix loop until criteria are met or a hard boundary is hit
- documentation sync where source-of-truth docs exist/are needed
- tradeoff logging for material deviation

### Tier B — must include
- concrete success criteria
- existing tests first; minimal targeted checks if coverage is insufficient
- `verify` and/or `code-review` where behavior changed
- docs updates only when relevant docs exist/are needed and behavior, usage, contracts,
  architecture, eval semantics, or non-obvious constraints materially change
- tradeoff logging only for material deviation

### Tier C — must include
- confirmation the edit is truly low-risk and local
- lightweight validation: smoke check, lint, visual confirmation, or a narrow test run
- no dedicated harness unless no cheaper credible check exists
- no heavy doc routing unless a behavior/architecture/contract boundary is crossed

### Global verification rules
- Existing reliable tests beat redundant new harnesses.
- Irrelevant green checks are not verification.
- Verification must cover the **changed claim**, not merely run some part of the repo.
- If outputs can't be observed locally, narrow the claim accordingly.
- For Tier A / substantial Tier B, state tier + success criteria + verification path
  before implementing — use plan mode and get sign-off via ExitPlanMode.

## 3. User consultation boundary

Risk escalation means stricter verification and docs, **not** automatic interruption.

Do **not** ask for confirmation for: routine debugging, routine tier escalation, local
refactors, or details resolvable mechanically from repo code and active specs.

Ask (via AskUserQuestion) only when:
- the change conflicts with the active spec, a repo contract, or a prior explicit instruction
- multiple materially different implementations satisfy the request but imply different
  product/research/maintenance/evaluation tradeoffs that can't be resolved mechanically
- proceeding would change scope, public behavior, evaluation/data semantics, or external
  contracts beyond what was requested
- a required external input, credential, approval, or product decision is missing

For Tier A research tasks, ask before committing to materially different choices in
objectives, baselines, evaluation protocols, ablation scope, data semantics, or
architectural interpretation.

Never silently simplify/omit/downgrade/narrow a requested feature, algorithm, evaluation,
or spec requirement just because a cheaper version is easier. If a reduction would change
scope/capability/claim/interpretation, surface the tradeoffs and ask.

If none of the above applies, choose the most defensible implementation and continue.

## 4. Execution flow

1. Read relevant repository context.
2. Classify the task.
3. Define tier-appropriate success criteria.
4. Ensure outputs are observable locally.
5. Critically review assumptions and risk.
6. For Tier A / substantial Tier B: enter plan mode, present tier + criteria + verification
   path, get sign-off (ExitPlanMode).
7. Implement the most defensible version.
8. Verify (existing tests → `verify` → `code-review` → adversarial for high blast) and
   iterate until criteria are met or a hard boundary is reached.
9. Sync documentation if scope requires (`documentation_topology.md`).
10. Update the handoff snapshot only if the user explicitly asked for handoff.

## 5. Harness rules

A dedicated harness is a tool, not a ritual.

**Build one when:** Tier A; risky boundaries aren't covered by existing tests; shapes /
interfaces / data contracts / eval semantics must be validated in isolation; repo tests
are too coarse to localize the claim.

**Don't when:** narrow Tier C; existing tests already verify the behavior credibly; the
harness would be heavier than the change; a smaller targeted check gives equal confidence.

**A valid harness:** stays minimal; uses deterministic fixtures; asserts the critical
claim directly; exposes observable outputs; avoids fake confidence from unrelated mocks.

## 6. Completion rules

Complete only when, at the required tier:
- implementation matches the claimed scope
- relevant verification passed, or the failure boundary is explicitly documented
- behavior-changing claims are backed by observed evidence
- required doc updates are done
- no known critical contradiction remains across code, tests, docs, and the matrix

If blocked by a hard boundary (missing creds, hardware, datasets, external failure,
unrecoverable env limit): do not bluff — state what was verified, what remains
unverified, and the precise blocker. (The `completion-gate` Stop hook reminds you of this.)

## 7. Handoff

Handoff is user-requested. When asked: create/refresh the status snapshot
(`status_template.md`) — objective, high-level state, verification summary,
blockers/risks, next steps, references. Keep it a current-state snapshot, not a diary;
link to the matrix for requirement-level status.

## 8. Environment policy

Repository-native tooling first.

- Identify the intended target environment before any interpreter, package manager, or
  dependency-changing command.
- If the repo standardizes a toolchain/execution path, follow it.
- Otherwise prefer the active local environment.
- Never install project deps into conda `base`, system Python, global Python, or shared
  environments unless the user explicitly asks. (Mechanically enforced by the `env-guard`
  PreToolUse hook — see `../hooks/`.)
- Don't introduce a new environment manager unless the repo already uses it, the task
  requires it, or the current env is provably insufficient and the change is documented.

## 9. Priority order

1. Correctness / scientific defensibility
2. Implementation viability
3. Clear evaluation semantics
4. Contract correctness
5. Maintainability
6. Surface fidelity
7. Integration elegance

When uncertain: narrow the claim, raise verification, or state the uncertainty.
