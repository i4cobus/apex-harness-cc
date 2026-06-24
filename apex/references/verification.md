# Verification (incl. Adversarial)

Kernel §2 says close the loop with evidence. This file adds the piece the original APEX
skill lacked: **adversarial verification** — defending against the model's confirmation
bias by having independent perspectives try to *refute* a claim rather than confirm it.

## Why self-review is not enough

An agent reviewing its own work tends to confirm it. "I checked it and it looks right" is
the weakest form of evidence precisely when the blast radius is highest. The fix is
independence: a verifier that did not produce the artifact, prompted to break it.

## Verification ladder (cheapest credible first)

1. **Existing tests** that exercise the changed claim.
2. **Observability** — actually run it and look at the output (`verify` skill drives the
   real app/behavior).
3. **Diff critique** — `code-review` on the change for correctness and regressions.
4. **Targeted harness** — only when 1–3 can't isolate the claim (see workflow.md §5).
5. **Adversarial verification** — for high-blast Tier A claims, the steps below.

Stop climbing once you have credible evidence for the *specific* claim. Don't run the
whole ladder as ritual.

## When to verify adversarially

Reach for adversarial verification when a wrong-but-plausible result would be expensive:
- correctness-critical algorithm / math / loss / evaluation logic
- a security-relevant change
- a contract or schema other code depends on
- a research claim that downstream interpretation rests on
- any finding you are about to report as "confirmed" with real consequences

For routine Tier B/C work, single-pass verification (ladder 1–3) is enough.

## Patterns

### Independent skeptics (majority refute → kill)
Spawn N independent verifiers, each prompted to **refute** the claim and to default to
"refuted" under uncertainty. Keep the claim only if a majority fail to refute it.

```
Agent ×3, each: "Try to refute this claim: <claim>. Inspect <evidence/paths>.
Default to refuted=true if you cannot positively confirm it. Return {refuted, why}."
→ survives only if ≥2 of 3 do NOT refute.
```

### Perspective-diverse panel
When a claim can fail in more than one way, give each verifier a distinct lens instead of
N identical skeptics — diversity catches failure modes redundancy can't:
- **correctness** — is the logic/math right?
- **security** — what's the abuse case?
- **does-it-reproduce** — run it cold from the stated inputs.
- **contract** — do callers/dependents still hold?

### Completeness critic
A final pass that asks "what's missing — an unrun check, an unverified claim, an unread
source?" Whatever it finds becomes the next round of work. Prevents silent truncation.

## Running it in Claude Code

**Light (1–3 checks):** use the Agent tool directly, e.g. spawn 3 skeptics in one message
so they run concurrently, then judge.

**Structured (Tier A, fan-out + synthesis):** run the shipped workflow — `Workflow` tool
with the `apex-verify` script (see `../../workflows/apex-verify.js`). It takes a claim +
evidence pointers, fans out a refuter panel and a perspective-diverse panel, and returns a
verdict with the dissents. Invoke it explicitly; it is opt-in (it can spawn several
agents), so only use it for claims that warrant the spend.

> Workflows require explicit opt-in. Either the user asked for multi-agent verification,
> or you are running the `apex-verify` workflow they installed for exactly this purpose —
> state that you're spending agents on it before you do.

## Recording the result

- Report the verdict honestly, including dissents — "2/3 skeptics cleared it; one flagged
  X, mitigated by Y."
- If verification could not cover part of the claim, **narrow the claim** (kernel §2) and
  say what remains unverified (kernel §3).
- For Tier A, the verification pointer goes in the coverage matrix
  (`matrix_template.md`).
