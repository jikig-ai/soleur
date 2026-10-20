export const meta = {
  name: 'agent-native-audit-workflow',
  description:
    'Workflow-backed soleur:agent-native-audit — deterministic parallel fan-out of 8 agent-native principle auditors (Explore sub-agents), each returning a 0-100 sub-score + structured findings, synthesized into one scored report with a weighted overall score and impact-ranked recommendations. Supports a single-principle run via args.',
  // Same phase titles as the phase() calls below so progress groups line up.
  phases: [
    { title: 'Scope', detail: 'load agent-native principles + resolve which principle audits to run' },
    { title: 'Audit', detail: '8 principle auditors (Explore), in parallel — each returns a 0-100 sub-score + findings' },
    { title: 'Synthesize', detail: 'weighted overall score, status tiers, impact-ranked Top-10 recommendations' },
  ],
}

// ---------------------------------------------------------------------------
// API-BUDGET DISCLOSURE (hr-autonomous-loop-skill-api-budget-disclosure)
//
// This workflow fans out ONE Explore sub-agent per principle audit. A full run
// is 8 principle auditors in parallel + 1 synthesis agent = up to 9 agents
// (a single-principle run is 1 auditor + 1 synthesis = 2). Each agent is a live
// model call billed against the Anthropic session key. Under BSL-1.1 the
// software is provided WITHOUT WARRANTY and Soleur disclaims liability for any
// runtime/API cost incurred by these calls — the operator owns that spend.
// CONFIRM the auditor count (printed in the Audit phase log) before the fan-out
// proceeds; abort the session if the count is unexpected.
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Input. args may be a bare string (a single principle selector) or an object:
//   { principle, target }
//   principle: optional single-principle selector ('action parity', '5', 'crud', …);
//              when set, only that one auditor runs (SKILL.md §"Single Principle Audit").
//   target:    optional human label for the project under review (report header only).
// ---------------------------------------------------------------------------
const principleArg = (typeof args === 'string' ? args : args?.principle) || ''
const projectLabel = (typeof args === 'object' && args?.target) || ''

// ---------------------------------------------------------------------------
// Principle registry. The 8 core agent-native principles audited by SKILL.md,
// each mapped to: a stable key, the canonical headline, the auditor's task
// brief (faithful to the source sub-agent prompt), the scoring DENOMINATOR
// MEANING (so the auditor knows what "X out of Y" counts), and an impact WEIGHT
// used to compute the weighted overall score. Parity is the foundational
// principle (agent-native-architecture SKILL.md: "Without it, nothing else
// matters") so it carries the heaviest weight.
//
// Auditors all run as Explore sub-agents (read-only enumeration of the codebase)
// per SKILL.md Step 2 (`subagent_type: Explore`).
// ---------------------------------------------------------------------------
const PRINCIPLES = {
  'action-parity': {
    title: 'Action Parity',
    tenet: 'Whatever the user can do, the agent can do.',
    weight: 3,
    denom: 'count of user actions; numerator = those with a corresponding agent tool',
    task: `Enumerate ALL user actions in the frontend (API calls, button clicks, form submissions): search API service files, fetch calls, form handlers, routes, and components for user interactions. Then find every agent tool definition and map user actions to agent capabilities. A user action is covered if a tool (or composition of primitives) lets the agent achieve the SAME outcome — not a 1:1 button-to-tool mapping. The anti-pattern is an "orphan UI action": something a user can do that the agent cannot achieve.`,
  },
  'tools-as-primitives': {
    title: 'Tools as Primitives',
    tenet: 'Tools provide capability, not behavior.',
    weight: 2,
    denom: 'count of agent tools; numerator = those that are proper primitives (not workflow-shaped)',
    task: `Find and read ALL agent tool files. Classify each tool as PRIMITIVE (good — read/write/store/list/bash: enables capability without business logic) or WORKFLOW (bad — encodes business logic, makes decisions, orchestrates a choreographed sequence). The cardinal sin is a tool like process_feedback that categorizes/prioritizes/notifies internally: that is the agent executing your code instead of figuring things out. Flag every workflow-shaped tool that should be decomposed into primitives.`,
  },
  'context-injection': {
    title: 'Context Injection',
    tenet: 'System prompt includes dynamic context about app state.',
    weight: 2,
    denom: 'count of expected runtime context types; numerator = those actually injected',
    task: `Find context-injection code (search for "context", "system prompt", "inject"). Read agent prompts and system messages. Enumerate what IS injected versus what SHOULD be: available resources (files, drafts, documents, data types), user preferences/settings, recent activity, the available-capabilities list (tools documented in user vocabulary), session history, and workspace state. The anti-pattern is "context starvation" — the agent does not know what resources exist in the app, so it asks "what feed?" instead of acting.`,
  },
  'shared-workspace': {
    title: 'Shared Workspace',
    tenet: 'Agent and user work in the same data space.',
    weight: 2,
    denom: 'count of data stores/tables/models; numerator = those the agent shares with the user (not isolated)',
    task: `Identify all data stores / tables / models. For each, check whether the agent reads/writes the SAME store the user does, or a separate one. The anti-pattern is "sandbox isolation": the agent has its own data space (e.g. agent_output/ alongside user_files/) so its work never lands where the user sees it. Score how many stores are genuinely shared.`,
  },
  'crud-completeness': {
    title: 'CRUD Completeness',
    tenet: 'Every entity has full CRUD (Create, Read, Update, Delete).',
    weight: 2,
    denom: 'count of entities/models; numerator = those with all four agent CRUD operations',
    task: `Identify all entities/models in the codebase. For EACH entity, check whether agent tools exist for Create, Read, Update, AND Delete. The anti-pattern is incomplete CRUD — the agent can create a journal entry but has no tool to update or delete it ("I don't have a tool for that"). Score per entity (full CRUD or not) and overall; list every entity's missing operations.`,
  },
  'ui-integration': {
    title: 'UI Integration',
    tenet: 'Agent actions are immediately reflected in the UI.',
    weight: 2,
    denom: 'count of agent write/mutation paths; numerator = those that propagate to the UI immediately',
    task: `Check how agent writes/changes propagate to the frontend. Look for streaming updates (SSE, WebSocket), polling, shared state/services with reactive binding, event buses, or file watching. The anti-pattern is "silent actions": the agent changes state but the UI does not update, so the user never sees the result. Score how many agent mutation paths surface immediately in the UI.`,
  },
  'capability-discovery': {
    title: 'Capability Discovery',
    tenet: 'Users can discover what the agent can do.',
    weight: 1,
    denom: '7 discovery mechanisms (FIXED denominator)',
    task: `Check for these SEVEN discovery mechanisms and score against all 7: (1) onboarding flow showing agent capabilities, (2) help documentation, (3) capability hints in the UI, (4) the agent self-describing in its responses, (5) suggested prompts/actions, (6) empty-state guidance, (7) slash commands such as /help or /tools. The denominator is always 7. Rate the quality of each that exists.`,
  },
  'prompt-native': {
    title: 'Prompt-Native Features',
    tenet: 'Features are prompts defining outcomes, not code.',
    weight: 1,
    denom: 'count of features/behaviors; numerator = those defined in prompts (not hardcoded)',
    task: `Read all agent prompts. Classify each feature/behavior as defined in a PROMPT (good — outcomes described in natural language, behavior changes via prompt edit) or in CODE (bad — business logic hardcoded, behavior changes require a refactor). The test: to change how a feature behaves, do you edit prose or refactor code? Flag every code-defined feature that should be prompt-native.`,
  },
}

// Selector → principle key. Faithful to SKILL.md §"Valid arguments". A bare or
// unrecognized selector means "run all 8".
const SELECTOR_TO_KEY = {
  '1': 'action-parity', 'action parity': 'action-parity', 'parity': 'action-parity', 'action-parity': 'action-parity',
  '2': 'tools-as-primitives', 'tools': 'tools-as-primitives', 'primitives': 'tools-as-primitives', 'tools-as-primitives': 'tools-as-primitives',
  '3': 'context-injection', 'context': 'context-injection', 'injection': 'context-injection', 'context-injection': 'context-injection',
  '4': 'shared-workspace', 'shared': 'shared-workspace', 'workspace': 'shared-workspace', 'shared-workspace': 'shared-workspace',
  '5': 'crud-completeness', 'crud': 'crud-completeness', 'crud-completeness': 'crud-completeness',
  '6': 'ui-integration', 'ui': 'ui-integration', 'integration': 'ui-integration', 'ui-integration': 'ui-integration',
  '7': 'capability-discovery', 'discovery': 'capability-discovery', 'capability-discovery': 'capability-discovery',
  '8': 'prompt-native', 'prompt': 'prompt-native', 'features': 'prompt-native', 'prompt-native': 'prompt-native',
}

function selectPrinciples(raw) {
  const key = SELECTOR_TO_KEY[String(raw).trim().toLowerCase()]
  return key ? [key] : Object.keys(PRINCIPLES)
}

// ---------------------------------------------------------------------------
// Schemas — validated at the tool-call layer, so agents retry on mismatch.
// additionalProperties:false everywhere: agents return DATA, not prose.
// ---------------------------------------------------------------------------
const AUDIT_SCHEMA = {
  type: 'object',
  required: ['scorePct', 'numerator', 'denominator', 'denominatorMeaning', 'summary', 'instances', 'gaps', 'recommendations'],
  additionalProperties: false,
  properties: {
    scorePct: { type: 'integer', minimum: 0, maximum: 100, description: '0-100 compliance sub-score = round(100 * numerator / denominator)' },
    numerator: { type: 'integer', minimum: 0, description: 'count satisfying the principle (e.g. user actions with a matching agent tool)' },
    denominator: { type: 'integer', minimum: 0, description: 'total counted (e.g. user actions found); 0 only when the principle is not applicable to this codebase' },
    denominatorMeaning: { type: 'string', description: 'what the X/Y counts in this codebase' },
    summary: { type: 'string', description: 'one-paragraph verdict for this principle' },
    instances: {
      type: 'array',
      description: 'the enumerated rows (user actions, tools, entities, stores, mechanisms, …) the score is computed over',
      items: {
        type: 'object',
        required: ['name', 'location', 'compliant'],
        additionalProperties: false,
        properties: {
          name: { type: 'string', description: 'the action / tool / entity / store / mechanism' },
          location: { type: 'string', description: 'file path or area where it lives' },
          compliant: { type: 'boolean', description: 'does this instance satisfy the principle?' },
          note: { type: 'string', description: 'e.g. matched agent tool, missing CRUD op, isolated store, …' },
        },
      },
    },
    gaps: {
      type: 'array',
      description: 'specific anti-pattern instances (orphan UI action, workflow-shaped tool, silent action, missing CRUD op, isolated store, …)',
      items: {
        type: 'object',
        required: ['gap', 'severity'],
        additionalProperties: false,
        properties: {
          gap: { type: 'string' },
          location: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
    recommendations: {
      type: 'array',
      description: 'concrete fixes to raise this sub-score',
      items: {
        type: 'object',
        required: ['action', 'impact', 'effort'],
        additionalProperties: false,
        properties: {
          action: { type: 'string', description: 'imperative fix, e.g. "add delete_note tool"' },
          impact: { type: 'string', enum: ['high', 'medium', 'low'] },
          effort: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

const SYNTH_SCHEMA = {
  type: 'object',
  required: ['narrative', 'strengths', 'topRecommendations'],
  additionalProperties: false,
  properties: {
    narrative: { type: 'string', description: 'executive verdict on overall agent-native maturity' },
    strengths: {
      type: 'array',
      description: "what's working excellently (top strengths across all principles)",
      items: { type: 'string' },
    },
    topRecommendations: {
      type: 'array',
      description: 'Top-10 recommendations ranked by impact across all principles',
      items: {
        type: 'object',
        required: ['priority', 'action', 'principle', 'effort'],
        additionalProperties: false,
        properties: {
          priority: { type: 'integer', minimum: 1, description: '1 = highest impact' },
          action: { type: 'string' },
          principle: { type: 'string', description: 'which principle this raises' },
          effort: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

// ---------------------------------------------------------------------------
// Prompt builders.
// ---------------------------------------------------------------------------
const targetClause = projectLabel
  ? `Project under review: "${projectLabel}". Audit the codebase at the current working directory.`
  : `Audit the codebase at the current working directory.`

function auditPrompt(key) {
  const p = PRINCIPLES[key]
  return `You are a read-only agent-native architecture auditor for ONE principle: ${p.title} — "${p.tenet}"
${targetClause}

Your task:
${p.task}

Enumerate exhaustively (do NOT sample — read the actual source: API service files, route/component files, agent tool definitions, system prompts, data models/migrations, UI update plumbing — whichever this principle requires). Then produce a SPECIFIC numeric score.

Scoring contract:
- denominator = ${p.denom}.
- numerator = the subset that satisfies the principle.
- scorePct = round(100 * numerator / denominator). If denominator is 0 (principle genuinely not applicable to this codebase), set scorePct 0 and say so in summary.
- "instances" must contain the enumerated rows the score is computed over, each marked compliant true/false.
- "gaps" must call out the concrete anti-pattern instances by name and location.
- "recommendations" must be concrete, imperative fixes with impact + effort.

Be precise and conservative: every count must be defensible against the real code. Return the structured audit object.`
}

function synthPrompt(audits) {
  // Pass the auditors' DATA (scores, gaps, recs) to the synthesizer as the
  // material for the executive report. No untrusted shell argv here — this
  // agent only reasons and returns structured data.
  const lines = audits.map(
    (a) =>
      `- ${a.title}: ${a.scorePct}% (${a.numerator}/${a.denominator} — ${a.denominatorMeaning}). ` +
      `Gaps: ${a.gaps.length}. Top rec: ${a.recommendations[0]?.action || '(none)'}.`,
  )
  return `You are synthesizing an agent-native architecture review from completed per-principle audits.
${targetClause}

Per-principle results:
${lines.join('\n')}

Full per-principle detail (instances, gaps, recommendations) is in the audit data you have been given. Produce:
1. narrative — an executive verdict on overall agent-native maturity, grounded in the scores above (parity is foundational: "without it, nothing else matters").
2. strengths — the top things working excellently across principles.
3. topRecommendations — the Top-10 fixes ranked by impact (priority 1 = highest), each tagged with the principle it raises and an effort estimate. Front-load high-impact / low-effort wins.

Return the structured synthesis object. Do not restate every audit row — distill.`
}

// ---------------------------------------------------------------------------
// Helpers (self-contained; no imports).
// ---------------------------------------------------------------------------
// Status tier per SKILL.md §"Status Legend": ✅ ≥80, ⚠️ 50-79, ❌ <50.
function statusTier(pct) {
  if (pct >= 80) return 'excellent'
  if (pct >= 50) return 'partial'
  return 'needs-work'
}

// Budget floor: reserve headroom for the synthesis agent so a long audit
// fan-out never starves the report. NEVER silently skip — log if we degrade.
const SYNTH_FLOOR = 40_000 // output tokens to reserve past the audit fan-out
function synthBudgetOk() {
  return !budget.total || budget.remaining() > SYNTH_FLOOR
}

// Weighted overall score: each principle contributes scorePct * weight. Parity
// is weighted heaviest because the source skill makes it foundational. An audit
// with denominator 0 (not applicable) is excluded from the weighting so an
// inapplicable principle does not drag the score to zero.
function weightedOverall(audits) {
  let num = 0
  let den = 0
  for (const a of audits) {
    if (a.denominator === 0) continue
    const w = PRINCIPLES[a.key].weight
    num += a.scorePct * w
    den += w
  }
  return den ? Math.round(num / den) : 0
}

// ---------------------------------------------------------------------------
// Run.
// ---------------------------------------------------------------------------
phase('Scope')
const keys = selectPrinciples(principleArg)
const singlePrinciple = keys.length === 1
// Budget disclosure / count confirmation (hr-autonomous-loop-skill-api-budget-disclosure):
// the auditor fan-out count is fixed by the selector and surfaced before fan-out.
log(
  `Agent-native audit scope: ${keys.length} principle auditor(s)` +
    `${singlePrinciple ? ` (single: ${PRINCIPLES[keys[0]].title})` : ' (full 8-principle pass)'} ` +
    `→ ${keys.length} Explore agent(s) + 1 synthesis = ${keys.length + 1} agents billed to the session key. ` +
    `Principles: ${keys.map((k) => PRINCIPLES[k].title).join(', ')}.`,
)

// Audit: 8 (or 1) Explore auditors in parallel — BARRIER. Each returns its
// 0-100 sub-score + findings. A failed auditor becomes null → filter(Boolean).
phase('Audit')
const auditResults = (
  await parallel(
    keys.map((key) => () =>
      agent(auditPrompt(key), {
        label: `audit:${key}`,
        phase: 'Audit',
        schema: AUDIT_SCHEMA,
        agentType: 'Explore', // SKILL.md Step 2: subagent_type: Explore
      }).then((r) => (r ? { key, title: PRINCIPLES[key].title, tenet: PRINCIPLES[key].tenet, ...r } : null)),
    ),
  )
).filter(Boolean)

const failed = keys.filter((k) => !auditResults.some((a) => a.key === k))
if (failed.length) {
  log(`⚠ ${failed.length} auditor(s) did not return: ${failed.map((k) => PRINCIPLES[k].title).join(', ')} — excluded from the overall score.`)
}

// Per-principle scoreboard (deterministic; the SCRIPT owns the tiering + weighting).
const scoreboard = auditResults
  .map((a) => ({
    principle: a.title,
    tenet: a.tenet,
    scorePct: a.scorePct,
    score: `${a.numerator}/${a.denominator}`,
    status: statusTier(a.scorePct),
    gapCount: a.gaps.length,
  }))
  // Stable, deterministic order: worst score first (most actionable on top), then by title.
  .sort((x, y) => x.scorePct - y.scorePct || x.principle.localeCompare(y.principle))

const overallPct = weightedOverall(auditResults)
const overallStatus = statusTier(overallPct)

// Synthesize: one agent distills the executive report. Budget-floored so the
// fan-out never starves it; degrade to a deterministic summary if floored.
phase('Synthesize')
let synthesis = null
if (auditResults.length && synthBudgetOk()) {
  synthesis = await agent(synthPrompt(auditResults), { label: 'synthesize', phase: 'Synthesize', schema: SYNTH_SCHEMA })
}
if (!synthesis) {
  // Deterministic fallback so the report is always complete: rank every
  // recommendation across principles by impact (high>medium>low) and take 10.
  const impactRank = { high: 0, medium: 1, low: 2 }
  const flat = []
  for (const a of auditResults) {
    for (const r of a.recommendations) flat.push({ ...r, principle: a.title })
  }
  flat.sort((x, y) => impactRank[x.impact] - impactRank[y.impact] || impactRank[x.effort] - impactRank[y.effort])
  synthesis = {
    narrative: !auditResults.length
      ? 'No auditors returned results.'
      : `Deterministic synthesis (synthesis agent unavailable or budget-floored). Weighted overall agent-native score: ${overallPct}% (${overallStatus}).`,
    strengths: auditResults
      .filter((a) => a.scorePct >= 80)
      .map((a) => `${a.title}: ${a.scorePct}% — ${a.summary}`),
    topRecommendations: flat.slice(0, 10).map((r, i) => ({ priority: i + 1, action: r.action, principle: r.principle, effort: r.effort })),
  }
}

// ---------------------------------------------------------------------------
// Return a structured summary (counts + what was done/verified).
// ---------------------------------------------------------------------------
const report = {
  project: projectLabel || '(current working directory)',
  mode: singlePrinciple ? `single-principle: ${PRINCIPLES[keys[0]].title}` : 'full 8-principle audit',
  overall: { scorePct: overallPct, status: overallStatus },
  statusLegend: { excellent: '≥80%', partial: '50-79%', needsWork: '<50%' },
  scoreboard,
  counts: {
    principlesRequested: keys.length,
    auditorsReturned: auditResults.length,
    auditorsFailed: failed.length,
    totalInstancesEnumerated: auditResults.reduce((n, a) => n + a.instances.length, 0),
    totalGaps: auditResults.reduce((n, a) => n + a.gaps.length, 0),
    totalRecommendations: auditResults.reduce((n, a) => n + a.recommendations.length, 0),
    excellent: scoreboard.filter((s) => s.status === 'excellent').length,
    partial: scoreboard.filter((s) => s.status === 'partial').length,
    needsWork: scoreboard.filter((s) => s.status === 'needs-work').length,
  },
  narrative: synthesis.narrative,
  strengths: synthesis.strengths,
  topRecommendations: synthesis.topRecommendations,
  // Full per-principle detail for drill-down.
  audits: auditResults.map((a) => ({
    principle: a.title,
    tenet: a.tenet,
    scorePct: a.scorePct,
    score: `${a.numerator}/${a.denominator}`,
    denominatorMeaning: a.denominatorMeaning,
    status: statusTier(a.scorePct),
    summary: a.summary,
    instances: a.instances,
    gaps: a.gaps,
    recommendations: a.recommendations,
  })),
  budget: { total: budget.total, spent: budget.spent() },
}

log(
  `Done: ${auditResults.length}/${keys.length} principle audits → overall ${overallPct}% (${overallStatus}). ` +
    `${report.counts.excellent} excellent / ${report.counts.partial} partial / ${report.counts.needsWork} needs-work, ` +
    `${report.counts.totalGaps} gaps, ${report.counts.totalRecommendations} recommendations.`,
)

return report
