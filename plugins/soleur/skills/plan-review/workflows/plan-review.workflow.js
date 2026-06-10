export const meta = {
  name: 'plan-review-workflow',
  description:
    'Workflow-backed soleur:plan-review — read the plan, fan a FIXED specialist panel (DHH + Kieran + code-simplicity) in parallel, escalate to a 5-agent panel (+architecture-strategist +spec-flow-analyzer) when the plan declares the single-user-incident brand-survival threshold, then consolidate via the delete-over-fix rule when the simplification and correctness panels both fire on the same scope.',
  // Phase titles mirror the phase() calls below so progress groups line up.
  phases: [
    { title: 'Load', detail: 'read the plan file + detect the brand-survival threshold' },
    { title: 'Review', detail: 'fixed reviewer panel (3 baseline, +2 when the threshold fires), in parallel' },
    { title: 'Consolidate', detail: 'orthogonal-axis merge with delete-over-fix on co-fired scopes' },
  ],
}

// ---------------------------------------------------------------------------
// API-budget disclosure (per hr-autonomous-loop-skill-api-budget-disclosure).
// This workflow fans out ONE agent per reviewer in the panel: 3 in the
// baseline case, 5 when the plan declares the single-user-incident
// brand-survival threshold, plus 1 consolidation agent — i.e. 4 or 6 agents
// total per run. Each agent is a real Anthropic API session billed against the
// session key; BSL-1.1 disclaims runtime/API cost. The panel size is FIXED and
// reported in the Load phase log before fan-out, so the count is confirmable
// before any agent spawns. There is no per-item array here — the panel is a
// small, bounded constant, not an unbounded N.
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
}

// FIXED panels. The SCRIPT (not a model) owns who reviews: the 3-agent
// baseline catches overengineering and convention drift; the 5-agent panel
// adds blast-radius (architecture-strategist) and flow gaps (spec-flow-analyzer)
// when the single-user-incident threshold fires.
const BASELINE_PANEL = ['dhh-rails', 'kieran-rails', 'code-simplicity']
const THRESHOLD_PANEL = ['architecture', 'spec-flow']

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
          kind: { type: 'string', enum: ['simplify-cut', 'correctness-bug', 'convention-drift', 'flow-gap', 'blast-radius', 'other'], description: 'classifies the finding so the consolidator can apply delete-over-fix' },
          description: { type: 'string' },
          suggestedChange: { type: 'string' },
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
        required: ['scope', 'resolution', 'rationale', 'sourceFindingIds'],
        additionalProperties: false,
        properties: {
          scope: { type: 'string' },
          resolution: { type: 'string', enum: ['delete', 'fix', 'keep'], description: "delete = cut the scope (dissolves its findings); fix = address findings inline; keep = no change" },
          rationale: { type: 'string' },
          sourceFindingIds: { type: 'array', items: { type: 'string' }, description: 'ids of the reviewer findings this decision consolidates' },
          coFired: { type: 'boolean', description: 'true when BOTH the simplification and correctness panels fired on this scope' },
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
  return `You are reviewing an IMPLEMENTATION PLAN (not code) through ONE lens: ${r.lens}.

Read the plan at \`${planPath}\` in full (use your Read tool). Review the PLAN's design, scope, and approach — there is no diff and no code to run.

Report ONLY findings within your lens. For each finding:
- Assign severity P0 (plan-blocking) / P1 (must address) / P2 (should address) / P3 (nice-to-have).
- Set "scope" to the specific plan section / feature / capability the finding targets. Be consistent and concrete: a downstream consolidator detects when the simplification panel and the correctness panel BOTH fire on the same scope, so name the scope the same way another reviewer naturally would.
- Set "kind" to classify the finding (simplify-cut, correctness-bug, convention-drift, flow-gap, blast-radius, other).
- In "suggestedChange", state the smallest correct change to the PLAN.
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

  return `You are consolidating a ${reviews.length}-agent plan-review panel into ONE actionable set of decisions for the plan author.

Treat the two panels as ORTHOGONAL AXES:
- SIMPLIFICATION panel (DHH + code-simplicity): "is this over-architected? what should be cut?"
- CORRECTNESS panel (Kieran${thresholdFired ? ' + architecture-strategist + spec-flow' : ''}): "is this right? what are the bugs / convention drift / flow gaps / blast-radius?"

THE DELETE-OVER-FIX RULE (apply it explicitly):
When BOTH panels fire on the SAME scope — i.e. the simplification panel says "too complex, remove" AND the correctness panel raises specific bugs/gaps on that same scope — PREFER DELETE OVER FIX. A feature that simultaneously triggers "remove it" and "it has N specific bugs" is over-architected; cutting it DISSOLVES the bugs. Many correctness findings (e.g. FRs added without implementation) vanish when the cut lands. Precedent: 2026-05-11 #2720 plan v1→v2, 953→829 lines, 4 P0 issues dissolved when the matrix-split cut landed.

For each distinct scope:
- Decide resolution = delete | fix | keep. Set coFired=true when both panels fired on it; for a co-fired scope, default to "delete" and only choose "fix" if cutting the scope is clearly infeasible (state why in rationale).
- List the sourceFindingIds you are consolidating so dissolved findings are traceable.
Set deleteOverFixApplied=true if you cut at least one co-fired scope, and write a short author-facing summary.

=== SIMPLIFICATION PANEL ===
${block(byPanel('simplification'))}

=== CORRECTNESS PANEL ===
${block(byPanel('correctness'))}`
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
const THRESHOLD_SCHEMA = {
  type: 'object',
  required: ['thresholdDeclared'],
  additionalProperties: false,
  properties: {
    thresholdDeclared: { type: 'boolean', description: `true iff the plan literally declares "${THRESHOLD_SENTINEL}" (in its ## User-Brand Impact section)` },
    evidence: { type: 'string', description: 'the matching line, or empty if absent' },
  },
}
const detect = await agent(
  `Read the implementation plan at \`${safePlan}\` (use your Read tool). Determine ONLY whether it literally declares the brand-survival threshold sentinel:
"${THRESHOLD_SENTINEL}"
(it would appear in a "## User-Brand Impact" section). Return thresholdDeclared=true only on a literal match; do not infer it from tone. Do not review the plan.`,
  // Pinned 'sonnet': schema-constrained sentinel detection is mechanical (ADR-051).
  { label: 'detect-threshold', phase: 'Load', schema: THRESHOLD_SCHEMA, model: 'sonnet' },
)
log('tier pins: detect-threshold→sonnet (mechanical step per ADR-051; reviewers + consolidate inherit the session model)')

const thresholdFired = !!detect?.thresholdDeclared
const panel = thresholdFired ? [...BASELINE_PANEL, ...THRESHOLD_PANEL] : [...BASELINE_PANEL]
log(
  `Plan: ${safePlan}. Brand-survival threshold ${thresholdFired ? 'DECLARED' : 'absent'} → ` +
    `${panel.length}-agent panel (${panel.join(', ')}) + 1 consolidator = ${panel.length + 1} agents.`,
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
const report = {
  plan: safePlan,
  thresholdDeclared: thresholdFired,
  panel: {
    size: panel.length,
    reviewers: panel.map((k) => ({ key: k, agentType: REVIEWERS[k].agentType, panel: REVIEWERS[k].panel })),
    simplification: panel.filter((k) => REVIEWERS[k].panel === 'simplification'),
    correctness: panel.filter((k) => REVIEWERS[k].panel === 'correctness'),
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
  },
  deleteOverFixApplied: !!consolidation?.deleteOverFixApplied,
  summary: consolidation?.summary || '(consolidation not run)',
  reviews: reviewResults.map((r) => ({ reviewer: r.key, panel: r.panel, verdict: r.verdict, findingCount: r.findings.length, findings: r.findings })),
  decisions,
}

log(
  `Done: ${reviewResults.length}/${panel.length} reviewers, ${totalFindings} findings → ` +
    `${decisions.length} decisions (${report.totals.deleted} delete, ${report.totals.fixed} fix, ${report.totals.kept} keep; ` +
    `${report.totals.coFiredScopes} co-fired). delete-over-fix ${report.deleteOverFixApplied ? 'applied' : 'not triggered'}.`,
)

return report
