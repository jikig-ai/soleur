export const meta = {
  name: 'review-workflow',
  description:
    'Workflow-backed soleur:review — deterministic change-class fan-out, per-finding adversarial verification (no-barrier pipeline), provenance-driven disposition, structured findings report.',
  // Same phase titles as the phase() calls below so progress groups line up.
  phases: [
    { title: 'Classify', detail: 'one agent computes the change class + diff stats' },
    { title: 'Review', detail: 'one dimension agent per lens, in parallel' },
    { title: 'Verify', detail: 'adversarial skeptics refute each finding as soon as its dimension lands' },
    { title: 'Synthesize', detail: 'dedup, provenance disposition, structured report' },
  ],
}

// ---------------------------------------------------------------------------
// Input. args may be a bare string (the review target) or { target, deepReview }.
//   target: PR number, branch name, or '' (current branch vs origin/main)
//   deepReview: force the full 8-dimension pass regardless of class
// ---------------------------------------------------------------------------
const target = (typeof args === 'string' ? args : args?.target) || ''
const deepReview =
  (typeof args === 'object' && !!args?.deepReview) ||
  (typeof target === 'string' && /deep review|full review/i.test(target))
const range = 'origin/main...HEAD'

// ---------------------------------------------------------------------------
// Dimension registry — each lens reuses the REAL Soleur reviewer agent via
// agentType, so the workflow inherits that agent's system prompt and only
// appends the StructuredOutput instruction. One source of review expertise.
// ---------------------------------------------------------------------------
const DIMENSIONS = {
  'git-history':    { agentType: 'soleur:engineering:research:git-history-analyzer',        lens: 'commit-history archaeology; verify deletion/bump/refactor rationale against cited PRs and issues' },
  pattern:          { agentType: 'soleur:engineering:review:pattern-recognition-specialist', lens: 'design patterns, anti-patterns, code duplication, naming conventions' },
  architecture:     { agentType: 'soleur:engineering:review:architecture-strategist',        lens: 'architectural compliance and system-design fit of the change' },
  security:         { agentType: 'soleur:engineering:review:security-sentinel',              lens: 'OWASP/CWE flaws, hardcoded secrets, authz, multi-org/workspace boundary integrity (R1–R6)' },
  performance:      { agentType: 'soleur:engineering:review:performance-oracle',             lens: 'algorithmic complexity, DB queries, caching, memory, scalability' },
  'data-integrity': { agentType: 'soleur:engineering:review:data-integrity-guardian',        lens: 'migrations, data models, persistence safety, PII handling' },
  'agent-native':   { agentType: 'soleur:engineering:review:agent-native-reviewer',          lens: 'agent-user parity — any action/context a user has, an agent has too' },
  'code-quality':   { agentType: 'soleur:engineering:review:code-quality-analyst',           lens: 'code smells, severity-scored quality, refactoring roadmap' },
}

// Deterministic class → dimension mapping. This is the part that moves out of
// the SKILL.md prose decision tree and into auditable code: the classify agent
// reports a class, the SCRIPT owns which dimensions that class fans out to.
const CLASS_DIMENSIONS = {
  code: ['git-history', 'pattern', 'architecture', 'security', 'performance', 'data-integrity', 'agent-native', 'code-quality'],
  'non-code': ['git-history', 'pattern', 'security', 'code-quality'],
  'lockfile-only': ['git-history', 'security'],
  'deletion-dominated': ['git-history', 'security'],
}

// ---------------------------------------------------------------------------
// Schemas — validated at the tool-call layer, so agents retry on mismatch.
// ---------------------------------------------------------------------------
const CLASSIFY_SCHEMA = {
  type: 'object',
  required: ['class', 'changedFiles', 'totalFiles', 'totalLines', 'hasSource', 'rationale'],
  additionalProperties: false,
  properties: {
    class: { type: 'string', enum: ['code', 'non-code', 'lockfile-only', 'deletion-dominated'] },
    changedFiles: { type: 'array', items: { type: 'string' } },
    totalFiles: { type: 'integer' },
    totalLines: { type: 'integer' },
    deletedFilesPct: { type: 'number' },
    deletedLinesPct: { type: 'number' },
    hasSource: { type: 'boolean' },
    anyLockfile: { type: 'boolean' },
    rationale: { type: 'string' },
  },
}

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  additionalProperties: false,
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'title', 'severity', 'file', 'description', 'provenance', 'fixSizeLines'],
        additionalProperties: false,
        properties: {
          id: { type: 'string', description: 'short stable slug, unique within this dimension' },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['P1', 'P2', 'P3'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          description: { type: 'string' },
          // pr-introduced findings can never be scoped out (mirrors SKILL.md §Step 1).
          provenance: { type: 'string', enum: ['pr-introduced', 'pre-existing'] },
          fixSizeLines: { type: 'integer', description: 'estimated LOC to fix' },
          filesTouched: { type: 'integer', description: 'estimated files the fix touches' },
          suggestedFix: { type: 'string' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['isReal', 'confidence', 'reason'],
  additionalProperties: false,
  properties: {
    isReal: { type: 'boolean', description: 'true only if the finding survives refutation' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    reason: { type: 'string' },
  },
}

// ---------------------------------------------------------------------------
// Prompt builders.
// ---------------------------------------------------------------------------
// Parallel-safe diff access: for a PR number, every agent reads the diff
// read-only via `gh pr diff <N>` (no checkout — concurrent checkouts would
// race on a shared working tree). For a branch/empty target, use the local
// `origin/main...HEAD` range.
const isPR = /^\d+$/.test(String(target).trim())
const prNum = isPR ? String(target).trim() : null
const diffCmd = isPR ? `gh pr diff ${prNum}` : `git diff ${range}`
const fileDiffCmd = isPR
  ? `gh pr diff ${prNum} (locate the section for the file; gh pr diff has no pathspec filter)`
  : `git diff ${range} -- <file>`
const targetClause = isPR
  ? `Review target: PR #${prNum}. Read the change READ-ONLY via \`${diffCmd}\` (do NOT \`gh pr checkout\` — other agents share this working tree). For file context beyond the diff, read the file on the current branch or \`gh api\` the PR head.`
  : target
    ? `Review target: branch "${target}". Diff range: ${range} (\`${diffCmd}\`).`
    : `Review target: the current branch. Diff range: ${range} (\`${diffCmd}\`).`

const classifyPrompt = `You are the change-classification gate for a Soleur code review.
${targetClause}

Compute, over the change, exactly as the review SKILL does (source of truth: \`${diffCmd}\`${isPR ? `; file list via \`gh pr view ${prNum} --json files\`` : ''}):
- changedFiles = ${isPR ? `the paths in \`gh pr view ${prNum} --json files\`` : `\`git diff --name-only ${range}\``}
- totalFiles, deleted file/line counts, totalLines = added+deleted
- hasSource = any changed path matches \`\\.(ts|tsx|js|jsx|rb|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|mjs|cjs)$\`
- anyLockfile = any path matches package-lock.json|bun.lock|yarn.lock|Cargo.lock|go.sum|Gemfile.lock|poetry.lock|uv.lock

Apply this decision tree, FIRST MATCH WINS:
1. lockfile-only: every non-lockfile change is knowledge-base/** or *.md AND anyLockfile AND NOT hasSource.
2. deletion-dominated: totalFiles>0 AND totalLines>0 AND deletedFiles≥80% AND deletedLines≥80% AND NOT hasSource.
3. code: hasSource.
4. non-code: otherwise.

Return the classification object. Do not review the code — only classify.`

function reviewPrompt(dim) {
  const d = DIMENSIONS[dim]
  return `You are reviewing a code change through ONE lens: ${d.lens}.
${targetClause}

Read the diff (\`${diffCmd}\`) and any surrounding context you need. Report ONLY findings within your lens. For each finding:
- Assign severity P1 (critical) / P2 (important) / P3 (nice-to-have).
- Tag provenance: "pr-introduced" if this change added/modified the critiqued code (inspect ${fileDiffCmd}), else "pre-existing". When ambiguous, default to pr-introduced.
- Estimate fixSizeLines and filesTouched for the smallest correct fix.
Be precise and conservative — a finding you cannot defend will be refuted in the next stage. Return an empty findings array if the diff is clean for your lens.`
}

function verifyPrompt(f) {
  return `Adversarially verify this code-review finding. Your DEFAULT is that it is NOT real — set isReal=false unless the evidence is concrete and you can reproduce the reasoning against the actual diff.

Finding:
- title: ${f.title}
- severity: ${f.severity}
- file: ${f.file}${f.line ? `:${f.line}` : ''}
- provenance: ${f.provenance}
- description: ${f.description}
${f.suggestedFix ? `- proposed fix: ${f.suggestedFix}` : ''}

${targetClause}
Inspect the actual code at that location (read the change via \`${diffCmd}\`, locate ${f.file}, and read the file for context). Try to refute it: is it a false positive, already handled elsewhere, or out of scope for the change? Only return isReal=true if the finding genuinely holds against the real code.`
}

// Deterministic disposition — replaces the SKILL's prose cost-of-filing gate.
// pr-introduced ⇒ always fix inline; small pre-existing ⇒ fix inline; else
// it is a scope-out candidate that a human (or a CONCUR agent) signs off on.
function disposition(f) {
  if (f.provenance === 'pr-introduced') return 'fix-inline'
  const lines = f.fixSizeLines ?? 999
  const files = f.filesTouched ?? 9
  if (lines <= 30 && files <= 2) return 'fix-inline'
  return 'scope-out-candidate'
}

// ---------------------------------------------------------------------------
// Run.
// ---------------------------------------------------------------------------
phase('Classify')
const classification = await agent(classifyPrompt, {
  label: 'classify',
  phase: 'Classify',
  schema: CLASSIFY_SCHEMA,
})

const cls = deepReview ? 'code' : classification.class
const dims = CLASS_DIMENSIONS[cls] || CLASS_DIMENSIONS.code
log(
  `Class: ${cls}${deepReview ? ' (forced via deep review)' : ''} — ` +
    `${classification.totalFiles} files / ${classification.totalLines} lines → ` +
    `${dims.length} dimension agents: ${dims.join(', ')}`,
)

// Pipeline: NO barrier between Review and Verify. The moment the `security`
// dimension review lands, its findings start getting refuted while the
// `performance` dimension is still reading the diff. Wall-clock = slowest
// single (review → verify-its-findings) chain, not sum of stage maxima.
const perDimension = await pipeline(
  dims,
  // Stage 1 — review through one lens (reuses the real Soleur reviewer agent).
  (dim) =>
    agent(reviewPrompt(dim), {
      label: `review:${dim}`,
      phase: 'Review',
      schema: FINDINGS_SCHEMA,
      agentType: DIMENSIONS[dim].agentType,
    }),
  // Stage 2 — adversarially verify every finding from this dimension.
  (review, dim) =>
    parallel(
      (review?.findings || []).map((f) => () =>
        agent(verifyPrompt(f), {
          label: `verify:${dim}:${f.id}`,
          phase: 'Verify',
          schema: VERDICT_SCHEMA,
        }).then((verdict) => ({ ...f, dimension: dim, verdict })),
      ),
    ),
)

phase('Synthesize')
const all = perDimension.flat().filter(Boolean)
const confirmed = all.filter((f) => f.verdict?.isReal)
const refuted = all.filter((f) => !f.verdict?.isReal)

// Dedup confirmed findings by file + normalized title (cross-dimension overlap).
const seen = new Set()
const deduped = []
for (const f of confirmed) {
  const key = `${f.file}::${f.title.trim().toLowerCase().slice(0, 60)}`
  if (seen.has(key)) continue
  seen.add(key)
  deduped.push({ ...f, disposition: disposition(f) })
}

const order = { P1: 0, P2: 1, P3: 2 }
deduped.sort((a, b) => (order[a.severity] - order[b.severity]) || a.file.localeCompare(b.file))

const report = {
  target: target || '(current branch)',
  class: cls,
  dimensionsRun: dims,
  totals: {
    raised: all.length,
    confirmed: deduped.length,
    refuted: refuted.length,
    fixInline: deduped.filter((f) => f.disposition === 'fix-inline').length,
    scopeOutCandidates: deduped.filter((f) => f.disposition === 'scope-out-candidate').length,
  },
  bySeverity: {
    P1: deduped.filter((f) => f.severity === 'P1'),
    P2: deduped.filter((f) => f.severity === 'P2'),
    P3: deduped.filter((f) => f.severity === 'P3'),
  },
  findings: deduped,
  refuted: refuted.map((f) => ({ title: f.title, file: f.file, reason: f.verdict?.reason })),
}

log(
  `Done: ${deduped.length} confirmed (${report.totals.fixInline} fix-inline, ` +
    `${report.totals.scopeOutCandidates} scope-out), ${refuted.length} refuted.`,
)

return report
