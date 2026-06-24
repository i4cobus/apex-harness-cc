export const meta = {
  name: 'apex-verify',
  description: 'Adversarially verify a high-blast claim: a refuter panel + a perspective-diverse panel, then a synthesized verdict with dissents.',
  whenToUse: 'Tier A / correctness-critical claims where a plausible-but-wrong result would be expensive. Opt-in: spawns several agents.',
  phases: [
    { title: 'Refute' },
    { title: 'Perspectives' },
    { title: 'Synthesize' },
  ],
}

// args: { claim: string, evidence?: string[], refuters?: number, repoHint?: string }
const claim = (args && args.claim) || 'No claim provided — fail closed.'
const evidence = (args && args.evidence) || []
const refuterCount = (args && args.refuters) || 3
const repoHint = (args && args.repoHint) || ''

const evidenceBlock = evidence.length
  ? `Evidence pointers to inspect:\n${evidence.map((e, i) => `  ${i + 1}. ${e}`).join('\n')}`
  : 'No evidence pointers were supplied; locate the relevant code/tests yourself before judging.'

const context = `${repoHint ? `Repo context: ${repoHint}\n` : ''}Claim under test:\n"${claim}"\n\n${evidenceBlock}`

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['refuted', 'confidence', 'why'],
  properties: {
    refuted: { type: 'boolean', description: 'true if the claim is wrong, unsupported, or you could not positively confirm it' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    why: { type: 'string', description: 'concrete reasoning, citing what you inspected (path:line, command output)' },
  },
}

const LENS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['lens', 'holds', 'finding'],
  properties: {
    lens: { type: 'string' },
    holds: { type: 'boolean', description: 'true if the claim survives this lens' },
    finding: { type: 'string' },
  },
}

phase('Refute')
log(`Refuter panel: ${refuterCount} independent skeptics`)
const refuters = await parallel(
  Array.from({ length: refuterCount }, (_, i) => () =>
    agent(
      `You are an independent skeptic (#${i + 1}). Try to REFUTE the following claim by ` +
        `inspecting the actual code/tests/output. Do not take prior reasoning on trust. ` +
        `Default to refuted=true if you cannot positively confirm the claim.\n\n${context}`,
      { label: `refute#${i + 1}`, phase: 'Refute', schema: VERDICT_SCHEMA },
    ),
  ),
)

phase('Perspectives')
const LENSES = [
  { key: 'correctness', q: 'Is the core logic/math correct? Walk it, do not eyeball it.' },
  { key: 'security', q: 'What is the abuse/edge case that breaks it? Untrusted input, boundaries, races.' },
  { key: 'reproduce', q: 'Reproduce it cold from the stated inputs. Does the observed output match the claim?' },
  { key: 'contract', q: 'Do callers/dependents/schemas still hold after this? Find a consumer that would break.' },
]
const lenses = await parallel(
  LENSES.map((l) => () =>
    agent(
      `Verify the claim strictly through the "${l.key}" lens. ${l.q}\n\n${context}`,
      { label: `lens:${l.key}`, phase: 'Perspectives', schema: LENS_SCHEMA },
    ),
  ),
)

phase('Synthesize')
const refuterResults = refuters.filter(Boolean)
const lensResults = lenses.filter(Boolean)
const notRefuted = refuterResults.filter((r) => !r.refuted).length
const survivesPanel = refuterResults.length > 0 && notRefuted * 2 > refuterResults.length // strict majority
const lensFails = lensResults.filter((l) => !l.holds)

const verdict = {
  claim,
  survives: survivesPanel && lensFails.length === 0,
  refuterPanel: { total: refuterResults.length, notRefuted, refuted: refuterResults.length - notRefuted },
  refuterDissents: refuterResults.filter((r) => r.refuted).map((r) => ({ confidence: r.confidence, why: r.why })),
  lensFailures: lensFails.map((l) => ({ lens: l.lens, finding: l.finding })),
  note:
    refuterResults.length === 0
      ? 'No refuter returned — treat as UNVERIFIED, not confirmed.'
      : survivesPanel && lensFails.length === 0
        ? 'Claim survived the refuter majority and all lenses.'
        : 'Claim did NOT clear verification — see dissents/lensFailures before reporting it as confirmed.',
}

log(verdict.note)
return verdict
