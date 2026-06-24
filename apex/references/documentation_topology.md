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

## 6. Alignment check

When implementation changes materially: update affected leaf docs; update `docs/design/`
if structure changed; update the matrix if coverage/status changed; update integration
docs if validation/assembly changed; update handoff docs only when requested. Remove stale
docs, dead references, and deprecated harnesses in the touched path.
