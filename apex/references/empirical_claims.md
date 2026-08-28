# Empirical Claims

Kernel §2 says close the loop with evidence. `verification.md` covers *who* checks a claim.
This file covers the other half: **how a measurement earns the right to be called a result.**

It applies whenever a decision rests on a number — an accuracy, a latency, a win rate, a
benchmark delta, an A/B outcome. Every failure below is one where the code was correct, the
run completed, the number was real, and the *conclusion drawn from it* was still wrong.

Route here before reporting a quantitative claim, choosing between configurations on
measured evidence, or writing "X improves Y" into a doc.

## 1. Write the prediction down before you run

Decide, in writing and before execution, what each outcome would mean:

> `variant_A` reaches ≈0.91 and `variant_B` ≈0.95 on the held-out set. If both land near
> 0.91, the proposed mechanism is wrong.

Without a pre-registered prediction, any result can be narrated into a success after the
fact — a run "confirms" whichever hypothesis is convenient once the numbers are visible.
Pre-registration is what makes a negative result *readable* instead of quietly reinterpreted.

State it as a falsifiable pair: **what I expect** and **what would prove me wrong**.

## 2. One factor at a time will mislead you

A comparison that varies one factor while holding another at an arbitrary value measures
that factor **at that value only**. If the two interact, the single-factor result is not a
main effect and does not generalize.

The failure is not rare. It has a stable shape: a change looks decisively effective under
one configuration and does nothing under another, and both experiments are individually
clean.

Fill the grid before generalizing:

| | factor B low | factor B high |
|---|---|---|
| **factor A off** | cell 1 | cell 2 |
| **factor A on** | cell 3 | cell 4 |

Then state the conclusion **with its conditions attached**: not "A is effective", but "A is
effective when B is low; under B high it is indistinguishable from noise."

Before writing any "X works / X does not work", ask: *under what conditions was this
measured, and does it survive changing them?*

## 3. A negative result under a confounded setup means "not measured", not "refuted"

If some other variable made the effect unobservable in principle, the experiment did not
test the hypothesis — it tested something else. Distinguish sharply:

- **Refuted** — measured under conditions where the effect *could* have appeared, and it
  did not.
- **Not measured** — a confound made the effect invisible regardless of whether it exists.

Filing "not measured" as "refuted" is expensive twice over: it closes a live direction, and
the retraction later costs more than the caution would have. When you catch this, correct
the record to the *narrow* claim — "not measured under these conditions" — and resist the
symmetric over-correction of declaring the effect real.

## 4. Once an aggregate metric saturates, it has no resolving power

A pooled metric near its ceiling cannot detect a change confined to a small, weak subgroup:
the subgroup is averaged away, and a paired test over the pooled set reports "no
difference" for a real one.

- Identify the weakest subgroup *before* choosing what to report.
- Compare on the subgroup where the change is supposed to act, paired, on identical inputs.
- If the pooled metric is saturated, say so — reporting it as "no significant difference"
  is a claim the data cannot support.

## 5. Establish the noise floor before calling anything an improvement

Re-run the same configuration and record the spread. A difference smaller than that spread
is not an improvement, however clean the pipeline. Write the noise floor into the docs as a
guardrail (kernel §7) so later work does not re-litigate it:

> Same-config reruns vary by ±N. Deltas below N are noise; do not report them as gains.

Corollary: when several candidates are within the noise floor of each other, none of them
"wins" on the metric — pick on cost, simplicity, or risk, and say that is what you did.

## 6. Check whether a control was abnormally low before crediting the treatment

If the baseline cell is the worst of the set, part of the reported gain is that cell
returning to normal, not the treatment adding value. Compare the treated result against the
*other* cells, not only its own control.

This rarely reverses a selection decision, but it changes the **explanation** — and the
explanation is what the next person builds on. Correct it explicitly: the measured numbers
stand, the mechanism story changes.

## 7. Estimate the ceiling before committing to a target

A quantitative target above the achievable ceiling — label noise, annotation agreement,
irreducible ambiguity, an upstream stage's error rate — guarantees failure that will be
read as a modelling failure. Estimate the ceiling first (re-annotation agreement, a clean
subset, an oracle upper bound) and set the target under it, or state plainly that the
target is above the measurable ceiling and needs to be renegotiated (kernel §6).

## 8. When a result is overturned, bound the old claim — do not delete it

A superseded conclusion still carries information: what was tried, what it cost, and why it
looked right. Deleting it invites a repeat.

Mark it in place instead:

```
### ~~Conclusion: approach X does not work~~ — RETRACTED <date>, see §N
> This test ran under <condition>, which made the effect unobservable (see §N).
> Its validity range is <condition> only. Original text kept below.
```

Then follow through: anything that *cited* the retracted claim needs re-reading too. A
retraction that does not propagate leaves the conclusion alive under a different name.

## 9. Every number carries its provenance

A number without a source cannot be checked, reproduced, or compared later — and it will be
compared later, by someone with less context than you. Record with each figure: **the
command or script, the date, and the sample size.** A number with no provenance is not
evidence; treat it as an anecdote.

## 10. Metric-definition changes break comparability

The moment an evaluation set, a scoring rule, a label definition, or a filtering step
changes, figures from before and after are not comparable — silently, and in a way that
looks exactly like a result. See `documentation_topology.md` §7 for how to record it.

## Checklist before reporting a quantitative claim

- [ ] The prediction was written before the run (§1).
- [ ] The conditions the claim depends on are stated, not assumed away (§2).
- [ ] "No effect" is distinguished from "could not have been observed" (§3).
- [ ] The metric can still resolve the change; the weak subgroup is reported (§4).
- [ ] The delta exceeds the measured noise floor (§5).
- [ ] The control cell is not anomalous (§6).
- [ ] The number carries command + date + n (§9).
- [ ] No metric-definition change straddles the compared figures (§10).

Anything unchecked goes into the claim as a stated limitation (kernel §3), not into a
footnote nobody reads.
