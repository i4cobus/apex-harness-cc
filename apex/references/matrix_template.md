# Spec-to-Implementation Matrix Template

Use for `docs/matrix_<topic>.md`. This is the requirement-level coverage source of truth.

| Requirement ID | Original Intent | Current Status | Implementation Pointer | Verification Pointer | Notes |
|---|---|---|---|---|---|
| R1 |  | Implemented / Partially Implemented / Deferred / Not Implemented |  |  |  |
| R2 |  | Implemented / Partially Implemented / Deferred / Not Implemented |  |  |  |

## Guidance

- **Requirement ID** — short stable id (`R1`, `Ablation-1`, `API-3`).
- **Original Intent** — what the original spec actually asked for.
- **Current Status** — `Implemented` / `Partially Implemented` / `Deferred` / `Not Implemented`.
- **Implementation Pointer** — file, module, API, config key, or doc reference (use
  `path:line` so it is clickable).
- **Verification Pointer** — test, harness, benchmark, command, `verify`/`code-review`
  run, or manual validation path.
- **Notes** — constraints, partial-scope clarification, or a short pointer to a relevant
  project-level tradeoff id (e.g. `TRD-001`).

## Rules

- This is a coverage document, not a tradeoff log.
- It is the requirement-level status source of truth — handoff docs link here instead of
  duplicating rows.
- If status differs from the spec because of a project-level deviation, reference the
  `docs/tradeoffs.md` entry by id in **Notes**. Do not duplicate full tradeoff narratives.
