# Tradeoff Log Template

Use this exact structure for each material deviation in `docs/tradeoffs.md`.

## Entry

### [TRD-001] Short Title
- **Original Spec/Idea:** ...
- **Actual Implementation:** ...
- **Reasoning:** ...

## ID rules

- Short stable id per entry (`TRD-001`, `TRD-002`, …); keep it stable once assigned so
  leaf docs and matrices can reference it.
- The short title summarizes the deviation in one line.

## Rules

- Record only approved deviations, unavoidable deviations, or major rejected alternatives.
- No FAQ-style prose.
- Not a substitute for architecture docs, leaf docs, or the matrix.
- A tradeoff log records deviations; it does **not** authorize silent simplification.
- Project-level only. Keep ordinary module-level design tradeoffs in the relevant leaf
  doc unless they also represent a material project-level deviation.
- When a leaf doc or matrix needs to mention a deviation, reference it by id instead of
  repeating the explanation.
