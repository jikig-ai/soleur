export const meta = {
  name: 'plan-review-workflow',
  description:
    'Workflow-backed soleur:plan-review — read the plan, fan a FIXED eng panel (DHH + Kieran + code-simplicity, +architecture-strategist +spec-flow-analyzer at the single-user-incident threshold) plus a relevance-gated NAMED CEO/design/devex panel (cpo/cmo/ux-design-lead/cto) in parallel, then consolidate via the delete-over-fix rule and tag each decision with a decisionClass (mechanical|taste|user-challenge) per decision-principles.md so taste findings are surfaced, never silently auto-applied.',
  // Phase titles mirror the phase() calls below so progress groups line up.
  phases: [
    { title: 'Load', detail: 'read the plan file + detect the brand-survival threshold + independent relevance signals for the named panel' },
    { title: 'Review', detail: 'eng panel (3 baseline, +2 at threshold) + relevance-gated named panel (0–4), in parallel' },
    { title: 'Consolidate', detail: 'orthogonal-axis merge with delete-over-fix on co-fired scopes + decisionClass tagging' },
  ],
}

// ---------------------------------------------------------------------------
// API-budget disclosure (per hr-autonomous-loop-skill-api-budget-disclosure).
// This workflow fans out ONE agent per reviewer in the panel. The ENG panel is
// 3 (baseline) or 5 (single-user-incident threshold). The relevance-gated NAMED
// panel adds 0–4 agents (cpo/cmo/ux-design-lead/cto), spawned ONLY when the
// plan is relevant to the lens (independent content scan — never always-on, so
// a pure-infra plan pays for at most the devex lens). Plus 1 consolidation
// agent — i.e. between 4 (baseline, no named) and 10 (threshold + full named)
// agents total per run. Named reviewers are C-suite / never-downgrade
// (ADR-053 tier 3) → they stay `inherit`; no new model pin. Each agent is a real
// Anthropic API session billed against the session key; BSL-1.1 disclaims
// runtime/API cost. Both panel sizes are computed and reported in the Load phase
// log before fan-out, so the count is confirmable before any agent spawns.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Input. args may be a bare string (the plan file path) or an object:
//   { plan }  — path to the plan markdown to review
// ---------------------------------------------------------------------------
const planPath = (typeof args === 'string' ? args : args?.plan) || ''
if (!planPath) {
  throw new Error('plan-review-workflow requires a plan file path (args = "path/to/plan.md" or { plan }).')
}

// The literal sentinel the plan must declare in its `## User-Brand Impact`
// section to escalate the baseline 3-agent panel to the 5-agent panel.
// SKILL.md §"Brand-survival threshold: single-user incident".
const THRESHOLD_SENTINEL = 'Brand-survival threshold: single-user incident'

// ---------------------------------------------------------------------------
// Reviewer registry. Each lens reuses the REAL Soleur agent via agentType, so
// the workflow inherits that agent's system prompt and only appends the
// StructuredOutput instruction. `panel` tags which orthogonal axis the
// reviewer belongs to (SKILL.md consolidation rule): the simplification panel
// (DHH + code-simplicity) and the correctness panel (Kieran +
// architecture-strategist + spec-flow) are treated as orthogonal axes.
// ---------------------------------------------------------------------------
const REVIEWERS = {
  'dhh-rails': {
    agentType: 'soleur:engineering:review:dhh-rails-reviewer',
    panel: 'simplification',
    lens: 'Rails philosophy — JS-framework contamination, unnecessary abstraction, overengineering in the plan',
  },
  'kieran-rails': {
    agentType: 'soleur:engineering:review:kieran-rails-reviewer',
    panel: 'correctness',
    lens: 'strict Rails conventions and convention drift — naming, controller complexity, Turbo patterns',
  },
  'code-simplicity': {
    agentType: 'soleur:engineering:review:code-simplicity-reviewer',
    panel: 'simplification',
    lens: 'code-simplicity — the smallest design that works; flag scope that should be cut rather than built',
  },
  // --- threshold-gated additions (single-user-incident brand-survival) ---
  architecture: {
    agentType: 'soleur:engineering:review:architecture-strategist',
    panel: 'correctness',
    lens: 'blast radius and system-design fit — how a single-user incident propagates across the architecture',
  },
  'spec-flow': {
    agentType: 'soleur:product:spec-flow-analyzer',
    panel: 'correctness',
    lens: 'spec/flow gaps — FRs added without implementation, missing states, broken user flows',
  },
  // --- named CEO/design/devex panel (relevance-gated; ADR-084 / #5985) ---
  // These reviewers critique the FINISHED plan through business/design/devex
  // lenses. Their findings are frequently TASTE, so consolidation routes them
  // through decisionClass and never auto-applies. They are C-suite /
  // never-downgrade (ADR-053 tier 3) → no model pin; they stay `inherit`.
  cpo: {
    agentType: 'soleur:product:cpo',
    panel: 'named',
    lens: 'product strategy, positioning, scope-vs-roadmap fit — is this the right thing to build for the operator and the roadmap?',
  },
  cmo: {
    agentType: 'soleur:marketing:cmo',
    panel: 'named',
    lens: 'market/GTM implications, brand-voice, messaging risk in any user-facing copy the plan introduces',
  },
  'ux-design-lead': {
    agentType: 'soleur:product:design:ux-design-lead',
    panel: 'named',
    lens: 'user-flow completeness, UX decay, design-taste risk in user-facing surfaces',
  },
  // cto's DEVEX lens is deliberately DISTINCT from architecture-strategist's
  // structural/blast-radius lens so the two do not produce duplicate findings.
  cto: {
    agentType: 'soleur:engineering:cto',
    panel: 'named',
    lens: 'developer/operator experience, maintenance/DX cost, build-vs-buy, ongoing engineering strategy — NOT blast-radius/structural (that is architecture-strategist)',
  },
}

// FIXED eng panels. The SCRIPT (not a model) owns who reviews: the 3-agent
// baseline catches overengineering and convention drift; the 5-agent panel
// adds blast-radius (architecture-strategist) and flow gaps (spec-flow-analyzer)
// when the single-user-incident threshold fires.
const BASELINE_PANEL = ['dhh-rails', 'kieran-rails', 'code-simplicity']
const THRESHOLD_PANEL = ['architecture', 'spec-flow']

// ---------------------------------------------------------------------------
// Named-panel composition (ADR-084 / #5985). DUPLICATE of
// `../lib/named-panel.mjs` — the Workflow runtime has no import/filesystem
// access, so the pure decision function is inlined here (self-contained
// convention, like safeTitle/safeId). Keep this copy BYTE-IDENTICAL to the lib
// module; the drift guard in test/plan-review-named-panel.test.ts checks the
// wiring stays present. CPO Condition 1: activation is driven by an INDEPENDENT
// content scan (the detect step's signals), never by trusting the plan's own
// `## Domain Review` verdict.
// ---------------------------------------------------------------------------
const NAMED_LENSES = ['cpo', 'cmo', 'cto', 'ux-design-lead']
function computeNamedPanel(signals) {
  const s = signals || {}
  const active = new Set()
  // Step 1 — mechanical UI-surface scan (independent): a UI-surface hit forces
  // ux-design-lead + cpo regardless of the Domain Review verdict.
  if (s.uiSurfaceHit) {
    active.add('ux-design-lead')
    active.add('cpo')
  }
  // Step 2 — fresh independent relevance read (NOT the verdict line).
  if (s.productSignal) active.add('cpo')
  if (s.marketingSignal) active.add('cmo')
  if (s.uxSignal) active.add('ux-design-lead')
  if (s.devexSignal) active.add('cto')
  // Step 4 — if none activate, the named panel is empty (eng panel still runs).
  return NAMED_LENSES.filter((k) => active.has(k))
}

// ---------------------------------------------------------------------------
// Schemas — validated at the tool-call layer, so agents retry on mismatch.
// ---------------------------------------------------------------------------
const REVIEW_SCHEMA = {
  type: 'object',
  required: ['findings', 'verdict'],
  additionalProperties: false,
  properties: {
    verdict: { type: 'string', enum: ['approve', 'approve-with-changes', 'request-changes'], description: "this reviewer's overall stance on the plan" },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'title', 'severity', 'scope', 'kind', 'description'],
        additionalProperties: false,
        properties: {
          id: { type: 'string', description: 'short stable slug, unique within this reviewer' },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'P3'] },
          scope: { type: 'string', description: 'the plan section / feature / capability the finding targets (used to detect cross-panel co-fire)' },
          kind: { type: 'string', enum: ['simplify-cut', 'correctness-bug', 'convention-drift', 'flow-gap', 'blast-radius', 'product-strategy', 'market-gtm', 'ux-design', 'devex', 'other'], description: 'classifies the finding so the consolidator can apply delete-over-fix (eng) and decisionClass (named)' },
          description: { type: 'string' },
          suggestedChange: { type: 'string' },
          decisionClass: { type: 'string', enum: ['mechanical', 'taste', 'user-challenge'], description: 'this reviewer\'s suggested class per decision-principles.md (the consolidator adjudicates the final class). Named-panel findings touching user-visible/money/scope default to taste; a finding arguing the operator\'s stated scope should change is user-challenge.' },
        },
      },
    },
  },
}

const CONSOLIDATION_SCHEMA = {
  type: 'object',
  required: ['decisions', 'summary'],
  additionalProperties: false,
  properties: {
    summary: { type: 'string', description: 'overall recommendation for the plan author' },
    deleteOverFixApplied: { type: 'boolean', description: 'true if any co-fired scope was resolved by cutting it rather than fixing each finding' },
    decisions: {
      type: 'array',
      items: {
        type: 'object',
        required: ['scope', 'resolution', 'rationale', 'sourceFindingIds', 'decisionClass'],
        additionalProperties: false,
        properties: {
          scope: { type: 'string' },
          resolution: { type: 'string', enum: ['delete', 'fix', 'keep'], description: "delete = cut the scope (dissolves its findings); fix = address findings inline; keep = no change" },
          rationale: { type: 'string' },
          sourceFindingIds: { type: 'array', items: { type: 'string' }, description: 'ids of the reviewer findings this decision consolidates' },
          coFired: { type: 'boolean', description: 'true when BOTH the simplification and correctness panels fired on this scope' },
          decisionClass: { type: 'string', enum: ['mechanical', 'taste', 'user-challenge'], description: 'per decision-principles.md (ADR-084): mechanical = one right answer, auto-appliable by the consumer; taste = user-visible/money/scope call, surfaced never auto-applied; user-challenge = argues the operator\'s stated direction should change, never auto-decided. Named-panel findings default to taste; on ambiguity bias to the more-surfaced class (unsure taste-vs-user-challenge → user-challenge).' },
        },
      },
    },
  },
}

// ---------------------------------------------------------------------------
// Prompt builders.
// ---------------------------------------------------------------------------
function reviewPrompt(key) {
  const r = REVIEWERS[key]
  const isNamed = r.panel === 'named'
  const namedGuidance = isNamed
    ? `

You are a NAMED CEO/design/devex reviewer. TWO hard rules:
1. **Structured advisory only — do NOT use AskUserQuestion.** Return your findings as structured output; never ask the operator a question. (This runs in a headless Task subagent that cannot answer — an AskUserQuestion would hang the pipeline.)
2. **Set "decisionClass" on each finding.** Your findings touch user-visible / money / scope, so they DEFAULT to "taste" (surfaced to the operator, never silently auto-applied). Use "user-challenge" for any finding arguing the operator's STATED scope/direction should change (drop/merge/split/add). Reserve "mechanical" only for a clearly factual/typo/broken-link fix. On ambiguity, bias to the more-surfaced class.`
    : `

Set "decisionClass": eng correctness/simplification findings are "mechanical" (auto-appliable) — EXCEPT a simplify-cut of operator-requested scope, which is "user-challenge".`
  return `You are reviewing an IMPLEMENTATION PLAN (not code) through ONE lens: ${r.lens}.

Read the plan at \`${planPath}\` in full (use your Read tool). Review the PLAN's design, scope, and approach — there is no diff and no code to run.

Report ONLY findings within your lens. For each finding:
- Assign severity P0 (plan-blocking) / P1 (must address) / P2 (should address) / P3 (nice-to-have).
- Set "scope" to the specific plan section / feature / capability the finding targets. Be consistent and concrete: a downstream consolidator detects when panels BOTH fire on the same scope, so name the scope the same way another reviewer naturally would.
- Set "kind" to classify the finding (simplify-cut, correctness-bug, convention-drift, flow-gap, blast-radius, product-strategy, market-gtm, ux-design, devex, other).
- In "suggestedChange", state the smallest correct change to the PLAN.${namedGuidance}
Be precise and conservative. Return an empty findings array if the plan is clean for your lens, and set your overall verdict.`
}

function consolidatePrompt(reviews, thresholdFired) {
  // reviews: [{ key, panel, agentType, verdict, findings }]
  const byPanel = (p) => reviews.filter((r) => r.panel === p)
  const block = (rs) =>
    rs
      .map(
        (r) =>
          `### ${r.key} (${r.agentType}) — verdict: ${r.verdict}\n` +
          (r.findings.length
            ? r.findings
                .map((f) => `- [${f.id}] (${f.severity}, ${f.kind}) scope="${f.scope}" :: ${f.title} — ${f.description}${f.suggestedChange ? ` | change: ${f.suggestedChange}` : ''}`)
                .join('\n')
            : '- (no findings)'),
      )
      .join('\n\n') || '(no reviewers in this panel)'

  const hasNamed = byPanel('named').length > 0
  return `You are consolidating a ${reviews.length}-agent plan-review panel into ONE actionable set of decisions for the plan author.

Treat the ENG panels as ORTHOGONAL AXES:
- SIMPLIFICATION panel (DHH + code-simplicity): "is this over-architected? what should be cut?"
- CORRECTNESS panel (Kieran${thresholdFired ? ' + architecture-strategist + spec-flow' : ''}): "is this right? what are the bugs / convention drift / flow gaps / blast-radius?"
${hasNamed ? '- NAMED CEO/design/devex panel (cpo/cmo/ux-design-lead/cto): "is this the right thing to build, positioned right, well-designed, and cheap to maintain?" These are business/design/devex critiques of the FINISHED plan.\n' : ''}
THE DELETE-OVER-FIX RULE (apply it explicitly, ENG panels):
When BOTH eng panels fire on the SAME scope — i.e. the simplification panel says "too complex, remove" AND the correctness panel raises specific bugs/gaps on that same scope — PREFER DELETE OVER FIX. A feature that simultaneously triggers "remove it" and "it has N specific bugs" is over-architected; cutting it DISSOLVES the bugs. Many correctness findings (e.g. FRs added without implementation) vanish when the cut lands. Precedent: 2026-05-11 #2720 plan v1→v2, 953→829 lines, 4 P0 issues dissolved when the matrix-split cut landed.

CLASSIFY EACH DECISION with a decisionClass per decision-principles.md (ADR-084) — this is the load-bearing safety rule:
- "mechanical" = one right answer / purely technical (bug, convention-drift, flow-gap, blast-radius). The consumer AUTO-APPLIES these. EXCEPTION: a simplify-cut of OPERATOR-REQUESTED scope is NOT mechanical → user-challenge.
- "taste" = a user-visible / money / scope call where reasonable operators could disagree. NAMED-PANEL findings (cpo/cmo/ux/cto) DEFAULT TO TASTE — product/market/design findings are almost never mechanical. The consumer SURFACES these to the operator; it NEVER silently auto-applies them.
- "user-challenge" = the finding argues the operator's STATED scope/direction should change (drop/merge/split/add). Never auto-decided.
- This is a SINGLE-SIGNAL classification (your judgment only) — plan-review is NOT one of ADR-084's two both-signals consult gates. On ambiguity, bias to the MORE-SURFACED class (unsure taste-vs-user-challenge → user-challenge). Do NOT invent a second consult.

For each distinct scope:
- Decide resolution = delete | fix | keep. Set coFired=true when both ENG panels fired on it; for a co-fired scope, default to "delete" and only choose "fix" if cutting the scope is clearly infeasible (state why in rationale).
- Set decisionClass (mechanical | taste | user-challenge) per the rules above. Never tag a named-panel product/market/design/scope finding "mechanical" on ambiguity.
- List the sourceFindingIds you are consolidating so dissolved findings are traceable.
Set deleteOverFixApplied=true if you cut at least one co-fired scope, and write a short author-facing summary.

=== SIMPLIFICATION PANEL ===
${block(byPanel('simplification'))}

=== CORRECTNESS PANEL ===
${block(byPanel('correctness'))}
${hasNamed ? `\n=== NAMED CEO/design/devex PANEL (findings default to taste — surface, do not auto-apply) ===\n${block(byPanel('named'))}` : ''}`
}

// ---------------------------------------------------------------------------
// Harden the plan path before it reaches a shell argv. The path arrives from
// args (operator/caller-supplied) and is interpolated into prompts that
// instruct agents to read it; agents that drop to a shell must not be able to
// smuggle metacharacters. Strip control chars + shell metacharacters, collapse
// whitespace, cap length. (Used for the logged/displayed form; agents read the
// file with their Read tool, not a raw shell command.)
function safePath(raw) {
  return String(raw)
    .replace(/[\x00-\x1f\x7f]/g, ' ') // control chars incl. newlines
    .replace(/[`$"'\\;|&<>(){}[\]!*?~#]/g, ' ') // shell metacharacters, backslash, brackets
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 240)
}
const safePlan = safePath(planPath)

// ---------------------------------------------------------------------------
// Budget floor. The consolidation agent is the load-bearing final step; reserve
// headroom so a long review fan-out never starves it. NEVER silently skip —
// log if the floor is hit. The panel is small and bounded, so this is a guard
// rather than a throttle.
// ---------------------------------------------------------------------------
const CONSOLIDATE_FLOOR = 40_000 // output tokens to reserve for consolidation
function budgetOk() {
  return !budget.total || budget.remaining() > CONSOLIDATE_FLOOR
}

// ---------------------------------------------------------------------------
// Run.
// ---------------------------------------------------------------------------
phase('Load')
// Read the plan ONCE via a lightweight agent so the threshold detection is a
// real read of the file's `## User-Brand Impact` section, not a guess. The
// agent returns only whether the literal sentinel is present.
const DETECT_SCHEMA = {
  type: 'object',
  required: ['thresholdDeclared', 'uiSurfaceHit', 'productSignal', 'marketingSignal', 'uxSignal', 'devexSignal'],
  additionalProperties: false,
  properties: {
    thresholdDeclared: { type: 'boolean', description: `true iff the plan literally declares "${THRESHOLD_SENTINEL}" (in its ## User-Brand Impact section)` },
    evidence: { type: 'string', description: 'the matching threshold line, or empty if absent' },
    // INDEPENDENT relevance signals for the named panel (CPO Condition 1 — do
    // NOT read the plan's `## Domain Review` verdict line; judge from the actual
    // content of the Files sections + the plan body).
    uiSurfaceHit: { type: 'boolean', description: 'true iff `## Files to Create` or `## Files to Edit` contains a UI-surface path (components/**/*.tsx, app/**/page.tsx, app/**/layout.tsx, or an .njk/.html/.vue/.svelte/.astro/email-template path). Judge from the FILE PATHS, not from any "Domains relevant" verdict line.' },
    productSignal: { type: 'boolean', description: 'true iff the plan BODY (Overview, Files, User-Brand Impact) shows product/scope/roadmap-fit language — a product-strategy call is at stake.' },
    marketingSignal: { type: 'boolean', description: 'true iff the plan introduces user-facing copy or has market/GTM/brand/messaging implications.' },
    uxSignal: { type: 'boolean', description: 'true iff the plan touches user-facing flows / visual surfaces / UX.' },
    devexSignal: { type: 'boolean', description: 'true iff the plan edits code/infra/tooling/build (developer or operator experience is affected).' },
  },
}
log('tier pins: detect-threshold→sonnet (mechanical step per ADR-053; reviewers + consolidate inherit the session model)')
const detect = await agent(
  `Read the implementation plan at \`${safePlan}\` (use your Read tool), then return TWO independent judgments. Do NOT review the plan.

1. thresholdDeclared: true ONLY on a LITERAL match of the sentinel
   "${THRESHOLD_SENTINEL}"
   (it would appear in a "## User-Brand Impact" section). Do not infer from tone.

2. Relevance signals for a named CEO/design/devex review panel. Judge each INDEPENDENTLY from the plan's actual content — DO NOT read or trust any "Domains relevant: ..." verdict line (that line is the very authoring step this panel exists to double-check):
   - uiSurfaceHit: does \`## Files to Create\`/\`## Files to Edit\` list a UI-surface path (components/**/*.tsx, app/**/page.tsx, app/**/layout.tsx, .njk/.html/.vue/.svelte/.astro/email template)? Judge from the file paths.
   - productSignal: product/scope/roadmap-fit call at stake?
   - marketingSignal: user-facing copy, or market/GTM/brand/messaging implications?
   - uxSignal: user-facing flows / visual surfaces / UX touched?
   - devexSignal: code/infra/tooling/build edited (developer/operator experience affected)?`,
  // Pinned 'sonnet': schema-constrained detection/scan is mechanical (ADR-053).
  { label: 'detect-threshold', phase: 'Load', schema: DETECT_SCHEMA, model: 'sonnet' },
)

const thresholdFired = !!detect?.thresholdDeclared
const engPanel = thresholdFired ? [...BASELINE_PANEL, ...THRESHOLD_PANEL] : [...BASELINE_PANEL]
// Named panel from the INDEPENDENT relevance signals (never the verdict line).
const namedPanel = computeNamedPanel(detect || {})
const panel = [...engPanel, ...namedPanel]
log(
  `Plan: ${safePlan}. Brand-survival threshold ${thresholdFired ? 'DECLARED' : 'absent'} → ` +
    `eng panel ${engPanel.length} (${engPanel.join(', ')}); named panel ${namedPanel.length}` +
    `${namedPanel.length ? ` (${namedPanel.join(', ')})` : ' (none — not relevant)'}` +
    ` + 1 consolidator = ${panel.length + 1} agents.`,
)

phase('Review')
// BARRIER: every reviewer reads the same plan independently; consolidation
// needs all of them. A dead reviewer becomes null → filter(Boolean).
const reviewResults = (
  await parallel(
    panel.map((key) => () =>
      agent(reviewPrompt(key), {
        label: `review:${key}`,
        phase: 'Review',
        schema: REVIEW_SCHEMA,
        agentType: REVIEWERS[key].agentType,
      }).then((res) => (res ? { key, panel: REVIEWERS[key].panel, agentType: REVIEWERS[key].agentType, verdict: res.verdict, findings: res.findings || [] } : null)),
    ),
  )
).filter(Boolean)

const totalFindings = reviewResults.reduce((n, r) => n + r.findings.length, 0)
log(`Reviews in: ${reviewResults.length}/${panel.length} reviewers, ${totalFindings} findings total.`)

phase('Consolidate')
let consolidation = null
if (!reviewResults.length) {
  log('No reviewer returned — nothing to consolidate.')
} else if (!budgetOk()) {
  // Conservative: surface the raw panel rather than spend below the floor.
  log(`⚠ budget floor (${CONSOLIDATE_FLOOR}) reached — skipping consolidation agent; returning raw panel findings.`)
} else {
  consolidation = await agent(consolidatePrompt(reviewResults, thresholdFired), {
    label: 'consolidate',
    phase: 'Consolidate',
    schema: CONSOLIDATION_SCHEMA,
  })
}

// ---------------------------------------------------------------------------
// Structured summary.
// ---------------------------------------------------------------------------
const decisions = consolidation?.decisions || []
const classCount = (c) => decisions.filter((d) => d.decisionClass === c).length
const report = {
  plan: safePlan,
  thresholdDeclared: thresholdFired,
  panel: {
    size: panel.length,
    reviewers: panel.map((k) => ({ key: k, agentType: REVIEWERS[k].agentType, panel: REVIEWERS[k].panel })),
    simplification: panel.filter((k) => REVIEWERS[k].panel === 'simplification'),
    correctness: panel.filter((k) => REVIEWERS[k].panel === 'correctness'),
    named: namedPanel,
  },
  relevanceSignals: {
    uiSurfaceHit: !!detect?.uiSurfaceHit,
    productSignal: !!detect?.productSignal,
    marketingSignal: !!detect?.marketingSignal,
    uxSignal: !!detect?.uxSignal,
    devexSignal: !!detect?.devexSignal,
  },
  budget: { total: budget.total, spent: budget.spent() },
  totals: {
    reviewersReturned: reviewResults.length,
    reviewersExpected: panel.length,
    findings: totalFindings,
    decisions: decisions.length,
    coFiredScopes: decisions.filter((d) => d.coFired).length,
    deleted: decisions.filter((d) => d.resolution === 'delete').length,
    fixed: decisions.filter((d) => d.resolution === 'fix').length,
    kept: decisions.filter((d) => d.resolution === 'keep').length,
    // Per-decisionClass counts — the surface the consumer routes on
    // (mechanical → auto-apply; taste/user-challenge → surface, never auto-apply).
    mechanical: classCount('mechanical'),
    taste: classCount('taste'),
    userChallenge: classCount('user-challenge'),
  },
  deleteOverFixApplied: !!consolidation?.deleteOverFixApplied,
  summary: consolidation?.summary || '(consolidation not run)',
  reviews: reviewResults.map((r) => ({ reviewer: r.key, panel: r.panel, verdict: r.verdict, findingCount: r.findings.length, findings: r.findings })),
  decisions,
}

log(
  `Done: ${reviewResults.length}/${panel.length} reviewers (eng ${engPanel.length}, named ${namedPanel.length}), ${totalFindings} findings → ` +
    `${decisions.length} decisions (${report.totals.deleted} delete, ${report.totals.fixed} fix, ${report.totals.kept} keep; ` +
    `${report.totals.coFiredScopes} co-fired). class: ${report.totals.mechanical} mechanical (auto-apply), ` +
    `${report.totals.taste} taste + ${report.totals.userChallenge} user-challenge (surface, never auto-apply). ` +
    `delete-over-fix ${report.deleteOverFixApplied ? 'applied' : 'not triggered'}.`,
)

return report
