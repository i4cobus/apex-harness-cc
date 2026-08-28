# Documentation Topology

Keep source-of-truth docs aligned with changed behavior. Do **not** manufacture heavy
docs just because a small edit happened. This is state externalization (kernel §7), not
paperwork.

## 1. When documentation updates are required

Both must be true:
- a relevant source-of-truth doc (spec, design doc, matrix, README, handoff) exists or is
  needed for the task, and
- the change would make it wrong, misleading, incomplete, or stale.

Common triggers: architecture, behavior, usage, evaluation semantics, external contracts,
reproducibility, maintainability.

## 2. Update rules by tier

- **Tier A** — usually required when active specs, design docs, eval docs, or matrices
  exist for the changed area.
- **Tier B** — update when interfaces change, new config keys/flags appear, behavior
  becomes user-visible, a non-obvious constraint is added, or architecture/eval semantics
  change.
- **Tier C** — usually unnecessary unless a behavior/architecture/contract boundary is
  crossed.

## 3. Repository layout assumption

When formal spec evolution is required, use a flat fixed-anchor topology:

- `docs/specs/00_*.md` — overview and top-level decomposition
- `docs/specs/algo_*.md` — one per major algorithm / research module
- `docs/specs/dev_*.md` — one per integration / system component
- `docs/specs/integration_*.md` — end-to-end assembly and validation checklist
- `docs/specs/status_*.md` — handoff snapshots (only when the user requests handoff)
- `docs/specs/legacy/` — superseded specifications
- `docs/design/` — global architecture / system framework / overall structure
- `docs/matrix_*.md` — spec-to-implementation matrices
- `docs/tradeoffs.md` — approved/unavoidable project-level deviations

Move a superseded pre-implementation spec to `docs/specs/legacy/` once formalized active
docs replace it.

## 4. Required anchor documents

**`00_*.md`** — purpose; scope and explicit non-goals; primary success criteria;
top-level decomposition; links.

**`algo_*.md`** (model blocks, losses, data semantics, eval protocols, research modules):
1. Goals & Boundaries 2. Math/Logic/Interfaces 3. Code Mapping 4. Tradeoffs 5. Verification

**`dev_*.md`** (service components, integration boundaries, state ownership, subsystems):
1. Goals & Boundaries 2. Interfaces/Responsibilities 3. Code Mapping 4. Tradeoffs 5. Verification

**`integration_*.md`** — end-to-end assembly view; dependencies; validation checklist;
benchmark/regression/harness entry points; known hard boundaries; final acceptance status.

**`status_*.md`** — see `status_template.md`; only when handoff is requested; a
current-state snapshot, never an append-only diary.

### Tradeoff layering

Two layers, no duplication:
- **Leaf-doc tradeoffs** (`algo_*` / `dev_*`): local, module-level choices, limitations,
  implementation-level alternatives.
- **Global tradeoffs** (`docs/tradeoffs.md`): project-level deviations — spec vs actual,
  approved compromises, unavoidable deviations, major rejected alternatives.

If a topic appears in both, keep the leaf version short and reference the global entry by
stable ID (e.g. `TRD-001`). See `tradeoff_template.md`.

### Spec-to-implementation matrix

`docs/matrix_*.md` is **mandatory for Tier A**, recommended for substantial Tier B. It
maps original intent → current status → implementation pointer → verification pointer, and
is the requirement-level coverage source of truth. References deviations by tradeoff ID
rather than duplicating them. See `matrix_template.md`.

## 5. Omission rule

If a module is omitted, state exactly: **Not implemented in the current version.**

## 6. What earns a place in the always-loaded file

Most repos have one file the agent reads on every session (`CLAUDE.md`, `AGENTS.md`, a
project README). Its budget is the scarcest in the repo: everything in it is paid for on
every task, whether or not it is relevant.

The test is not "is this important?" — it is **"would not knowing this make me do the wrong
thing right now?"**

| Belongs in the always-loaded file | Belongs in `docs/` |
|---|---|
| **Negative knowledge** — what has been tried and falsified, so it is not retried. One line + a pointer: `approach X: no gain, see docs/experiments.md §24` | The experiment, its numbers, and its conditions |
| **Judgment guardrails** — the noise floor, hard limits (latency budget, memory ceiling), the invariant that looks optional but is not | Per-case tables answering "how much exactly" |
| **Definition-change dates** — and the warning that figures across them are not comparable (§7) | The definitions themselves |
| Environment, paths, commands, traps specific to this repo | Detailed procedures executed by following them step by step |

Negative knowledge is the most valuable and the most often dropped: it is the only class
whose absence makes someone redo work that has already been paid for.

Do not migrate content for its own sake — move it the next time you are editing that file
anyway. The one case that justifies a dedicated pass is a long list re-read on every
session; compressing that buys the most context back.

## 7. Definition changes must be dated in place

When an evaluation set, scoring rule, label definition, filtering step, or data contract
changes, every figure recorded before it stops being comparable with every figure after —
silently, and in a way that looks exactly like a result.

Two records are required, and neither substitutes for the other:

1. In the affected doc, at the point of change:
   `⚠ Definition changed <date>: <what changed>. Figures spanning this date are not comparable.`
2. In the always-loaded file (§6), one line with the date, so the next session cannot
   compare across it by accident.

The same discipline applies to figures themselves: **record the command/script, the date,
and the sample size with every number.** A number with no provenance cannot be re-checked
or compared, and later readers have less context than you, not more. See
`empirical_claims.md` §9–10.

Stale beats missing is false here: a wrong-but-confident number outlives the person who
knew its caveat.

## 8. Moving content changes its reader

Relocating a document is not copying it. A note written by one person for themselves and
the same text inside a shared source-of-truth doc are **different artifacts**, because the
reader changed:

| In a personal note | In a shared doc read by teammates and agents |
|---|---|
| A privileged command is a reminder to the one person who knows when it applies | An instruction that will be executed, by someone who does not |
| A credential or host inline is that person's own | A secret published to everyone with repo access |
| An omitted precondition is obvious to the author | A missing precondition — the step fails or does damage |
| "I'll clean this up later" | A contract others build on |

So when promoting content into `docs/`, a spec, a README, or the always-loaded file,
re-judge **each paragraph** against the new reader:

- Does it still apply, or was it true only in the author's local situation?
- Does it need a boundary it did not need before ("only on the staging host", "never with
  `--force`", "requires approval first")?
- Does it contain anything that should not be published at this level?
- Was a precondition carried in the author's head rather than the text?

Content that cannot be made safe for the new reader stays where it is, and gets referenced
rather than inlined.

## 9. One document, one lifetime

Two rules decide what belongs in the same file:

- **Things that change together live together.** A test-set definition, its evaluation
  protocol, and its acceptance thresholds drift apart the moment they are split across
  files, and nothing detects the drift.
- **Things with different lifetimes live apart.** A results report expires; the protocol it
  was measured under must stay valid. Putting the protocol inside the report rots the
  protocol on the report's schedule.

## 10. Alignment check

When implementation changes materially: update affected leaf docs; update `docs/design/`
if structure changed; update the matrix if coverage/status changed; update integration
docs if validation/assembly changed; update handoff docs only when requested. Remove stale
docs, dead references, and deprecated harnesses in the touched path.
