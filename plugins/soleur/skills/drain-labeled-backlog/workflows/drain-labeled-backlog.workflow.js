export const meta = {
  name: 'drain-labeled-backlog-workflow',
  description:
    'Workflow-backed soleur:drain-labeled-backlog — query open issues for a label/milestone, cluster by code area (qualified-over-bare, deepest-first, frequency tie-break), then pipeline() each picked cluster: stage 1 builds a scoped one-shot brief from issue bodies, stage 2 delegates the cluster to /soleur:one-shot. Respects --top-n and --dry-run.',
  // Same phase titles as the phase() calls below so progress groups line up.
  phases: [
    { title: 'Cluster', detail: 'one agent validates label/milestone and groups open issues by code area' },
    { title: 'Confirm', detail: 'apply --top-n / --min-cluster-size floor; dry-run stops here' },
    { title: 'Drain', detail: 'pipeline: build a scoped brief per cluster, then delegate each to /soleur:one-shot' },
    { title: 'Report', detail: 're-query the milestone for the backlog delta (before/after/closed)' },
  ],
}

// ===========================================================================
// API-BUDGET DISCLOSURE (mirrors SKILL.md §decision_gate, per
// hr-autonomous-loop-skill-api-budget-disclosure).
//
// This workflow delegates EACH picked cluster to `/soleur:one-shot`, which runs
// a full plan → deepen → work → review → QA → compound → ship pipeline
// (30–90 min wall-clock per cluster; non-trivial Anthropic credit per run,
// scaling with plan complexity and review-cycle count). With --top-n N the cost
// multiplies by N: ONE full one-shot fans out PER PICKED CLUSTER, so N clusters
// = N one-shots = N×(the agents one-shot itself spawns). Anthropic bills every
// one of those agents against the key in your session — Soleur neither bills nor
// proxies them. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime
// cost; you operate this loop against your own budget.
//
// The --dry-run flag previews the picked clusters and the one-shot scope
// argument that WOULD be built, delegating nothing. CONFIRM cluster scope
// (size, --top-n, milestone) before allowing the workflow to fan out.
// ===========================================================================

// ---------------------------------------------------------------------------
// Input. args may be a bare string (the label) or an object:
//   { label, milestone, topN, minClusterSize, dryRun }
//   label:          GitHub label driving the backlog query (default below)
//   milestone:      milestone TITLE to drain (never a numeric id — gh rejects it)
//   topN:           how many clusters to consider / delegate (default 1)
//   minClusterSize: minimum issues in a cluster before it is picked (default 3)
//   dryRun:         preview picked clusters + scope; delegate nothing
// A bare string is treated as the label.
// ---------------------------------------------------------------------------
const DEFAULT_LABEL = 'deferred-scope-out'
const DEFAULT_MILESTONE = 'Post-MVP / Later' // 15+ of 22 open scope-outs live here at plan time; the current-phase milestone would return an empty cluster set on first run.
const DEFAULT_TOP_N = 1
const DEFAULT_MIN_CLUSTER = 3

const label = (typeof args === 'string' ? args : args?.label) || DEFAULT_LABEL
const milestone = (typeof args === 'object' && args?.milestone) || DEFAULT_MILESTONE
const topN = Math.max(1, Number((typeof args === 'object' && args?.topN) || DEFAULT_TOP_N) | 0)
const minClusterSize = Math.max(1, Number((typeof args === 'object' && args?.minClusterSize) || DEFAULT_MIN_CLUSTER) | 0)
const dryRun = typeof args === 'object' && !!args?.dryRun

// ---------------------------------------------------------------------------
// Harden untrusted text before it reaches a shell argv. The label and milestone
// flow into `gh` invocations the cluster/report agents run; issue titles flow
// into the one-shot brief. Strip control chars + shell metacharacters, collapse
// whitespace, cap length. Leading "-" is stripped so a value can never smuggle a
// flag into gh. Mirrors the template's safeTitle().
// ---------------------------------------------------------------------------
function safeArg(raw) {
  return String(raw)
    .replace(/[\x00-\x1f\x7f]/g, ' ') // control chars incl. newlines
    .replace(/[`$"'\\;|&<>(){}[\]!*?~#]/g, ' ') // shell metacharacters, backslash, brackets
    .replace(/\s+/g, ' ')
    .replace(/^-+/, '') // no leading dash → cannot be read as a gh flag
    .trim()
    .slice(0, 200)
}

const safeLabel = safeArg(label)
const safeMilestone = safeArg(milestone)

// ---------------------------------------------------------------------------
// Budget. Each delegated cluster is a full one-shot — by far the expensive part.
// Floor the remaining budget before each fan-out so we never start a one-shot we
// cannot afford to let run, and NEVER silently skip — log dropped clusters.
// ---------------------------------------------------------------------------
const ONE_SHOT_FLOOR = 200_000 // output tokens to reserve for one full one-shot run
const droppedClusters = []

function budgetOk() {
  return !budget.total || budget.remaining() > ONE_SHOT_FLOOR
}

// ---------------------------------------------------------------------------
// Schemas — validated at the tool-call layer, so agents retry on mismatch.
// additionalProperties:false everywhere; agents return DATA, not prose.
// ---------------------------------------------------------------------------

// Stage 0: cluster the backlog. Faithful port of group-by-area.sh — the agent
// runs the same gh queries + jq grouping and returns the structured clusters.
const CLUSTERS_SCHEMA = {
  type: 'object',
  required: ['labelValid', 'milestoneValid', 'totalOpen', 'clusters'],
  additionalProperties: false,
  properties: {
    labelValid: { type: 'boolean', description: 'label exists per `gh label list` (first column exact match)' },
    milestoneValid: { type: 'boolean', description: 'milestone TITLE exists per `gh api .../milestones` (open milestones)' },
    totalOpen: { type: 'integer', description: 'count of open issues carrying the label in the milestone' },
    error: { type: 'string', description: 'set when labelValid or milestoneValid is false; a readable fail-fast message' },
    clusters: {
      type: 'array',
      description: 'ALL clusters sorted by count desc; NOT pre-filtered by min-cluster-size',
      items: {
        type: 'object',
        required: ['area', 'count', 'issues'],
        additionalProperties: false,
        properties: {
          area: { type: 'string', description: 'top two path segments of the issue cluster (e.g. apps/web-platform)' },
          count: { type: 'integer' },
          issues: {
            type: 'array',
            items: {
              type: 'object',
              required: ['number', 'title'],
              additionalProperties: false,
              properties: {
                number: { type: 'integer' },
                title: { type: 'string' },
                files: { type: 'array', items: { type: 'string' }, description: 'file paths parsed from the issue body' },
                problem: { type: 'string', description: 'the issue body ## Problem section (verbatim or trimmed)' },
                proposedFix: { type: 'string', description: 'the issue body ## Proposed Fix section (verbatim or trimmed)' },
              },
            },
          },
        },
      },
    },
  },
}

// Stage 1: assemble the one-shot scope string for a single picked cluster.
const BRIEF_SCHEMA = {
  type: 'object',
  required: ['area', 'issueNumbers', 'scope'],
  additionalProperties: false,
  properties: {
    area: { type: 'string' },
    issueNumbers: { type: 'array', items: { type: 'integer' } },
    scope: { type: 'string', description: 'the full scope argument to hand to /soleur:one-shot (includes Closes #N lines)' },
  },
}

// Stage 2: outcome of delegating a cluster to /soleur:one-shot.
const ONE_SHOT_RESULT_SCHEMA = {
  type: 'object',
  required: ['area', 'status'],
  additionalProperties: false,
  properties: {
    area: { type: 'string' },
    status: { type: 'string', enum: ['merged', 'pr-open', 'failed'], description: 'merged = PR landed and closed the issues; pr-open = PR raised but not merged; failed = one-shot aborted' },
    prUrl: { type: 'string' },
    prNumber: { type: 'integer' },
    closedIssues: { type: 'array', items: { type: 'integer' } },
    notes: { type: 'string' },
  },
}

// Stage 3 (report): the post-drain backlog delta for the milestone.
const DELTA_SCHEMA = {
  type: 'object',
  required: ['after'],
  additionalProperties: false,
  properties: {
    after: { type: 'integer', description: 'open issues carrying the label in the milestone, re-queried after the drain' },
  },
}

// ---------------------------------------------------------------------------
// Prompt builders. Each names the EXACT gh/jq mechanics from group-by-area.sh
// so the agent reproduces the helper's behavior deterministically.
// ---------------------------------------------------------------------------
const clusterPrompt = `You are the backlog-clustering gate for a labeled-issue drain. Reproduce the logic of plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh EXACTLY — prefer running that script if it is present.

Label:     "${safeLabel}"
Milestone: "${safeMilestone}"   (this is a TITLE, never a numeric id)

Steps (fail fast, fail readable):
1. Validate the milestone TITLE exists among OPEN milestones:
   gh api "repos/:owner/:repo/milestones?state=open&per_page=100" --jq '.[].title' | grep -Fxq "${safeMilestone}"
   If absent → milestoneValid=false, set error, return (do NOT query issues).
2. Validate the label exists (first column of \`gh label list\`):
   gh label list --limit 200 | awk -F'\\t' '{print $1}' | grep -Fxq "${safeLabel}"
   If absent → labelValid=false, set error, return.
3. Query open issues (two-stage piping — gh --json … | jq; never \`gh --jq\` with --arg):
   gh issue list --label "${safeLabel}" --state open --milestone "${safeMilestone}" --json number,title,body,labels --limit 200
4. For each issue body, scan file paths with the NON-CAPTURING extension regex
   [A-Za-z0-9_./\\-]+\\.(?:ts|tsx|js|jsx|py|rb|go|md|sh|yml|yaml|sql|tf|njk)\\b
   Skip issues whose body names ZERO paths (area grouping requires a path).
5. Pick each issue's TOP path: qualified paths (containing "/") outrank bare
   filenames; among qualified, DEEPEST (most path segments) wins; ties broken by
   frequency; fall back to bare filenames only if no qualified path exists.
6. area = top TWO path segments of the top path (e.g. apps/web-platform), or the
   single segment if only one.
7. Group issues by area; return ALL clusters sorted by count DESC. Do NOT
   pre-filter by min-cluster-size — the workflow applies that floor itself.
8. For each issue also extract its body "## Problem" and "## Proposed Fix"
   sections and its parsed file paths, so a downstream brief can cite them.

Set totalOpen to the count of open labeled issues in the milestone. Return the structured object only — do not delegate or open any PR.`

function briefPrompt(cluster) {
  const issuesBlock = cluster.issues
    .map(
      (i) =>
        `  - #${i.number}: ${i.title}\n    Files: ${(i.files || []).join(', ') || '(none parsed)'}\n    Problem: ${i.problem || '(see issue body)'}\n    Fix: ${i.proposedFix || '(see issue body)'}`,
    )
    .join('\n')
  const closes = cluster.issues.map((i) => `Closes #${i.number}`).join('\n')
  return `You are assembling the scope argument for /soleur:one-shot to drain a labeled backlog cluster in ONE focused refactor PR. Return DATA only — do NOT invoke one-shot or open a PR.

Cluster area: ${cluster.area}   (${cluster.count} issues)
Originating label: ${safeLabel}

Pull the freshest "## Problem", "## Proposed Fix", and Location:/file paths for each issue via \`gh issue view <N> --json body\` if you need more than what is given below.

Issues in this cluster:
${issuesBlock}

Build a scope string in EXACTLY this shape (frame the work by the originating label — "${safeLabel} backlog"):

  Drain the ${safeLabel} backlog for code area ${cluster.area} by closing
  ${cluster.issues.map((i) => `#${i.number}`).join(' + ')} in a single focused refactor PR. Each issue names
  specific files and proposed fixes; fold them all into one change.

  Issues:
${issuesBlock}

  PR body MUST include these literal lines so merging closes every issue:
${closes}
  Reference PR #2486 as the pattern — one PR, multiple closures.

Return: area, the issueNumbers array, and the assembled scope string.`
}

function oneShotPrompt(brief) {
  return `Delegate this cluster to the full autonomous engineering pipeline. Use the Skill tool to invoke \`soleur:one-shot\` with the scope argument below as its args.

/soleur:one-shot owns worktree creation, plan, deepen, work, review, QA, compound, and ship. This step runs NO lifecycle phases itself — it only hands off the scope and reports the outcome.

The PR body MUST carry the \`Closes #<n>\` lines already present in the scope so the merge closes every issue in the cluster (issues: ${brief.issueNumbers.map((n) => `#${n}`).join(', ')}).

Scope argument (pass verbatim as the skill's args):
---SCOPE START---
${brief.scope}
---SCOPE END---

After one-shot returns, report: status (merged / pr-open / failed), the PR url + number, and which issue numbers were closed.`
}

const reportPrompt = `Re-query the backlog AFTER the drain to compute the delta. Run EXACTLY (two-stage piping):

gh issue list --label "${safeLabel}" --state open --milestone "${safeMilestone}" --json number --jq 'length'

Return only \`after\` = that count. Do not modify any issue.`

// ---------------------------------------------------------------------------
// Run.
// ---------------------------------------------------------------------------
phase('Cluster')
const clustered = await agent(clusterPrompt, { label: 'cluster', phase: 'Cluster', schema: CLUSTERS_SCHEMA })

// Fail-fast on invalid label/milestone — mirror the helper's exit 2 paths.
if (!clustered || !clustered.labelValid || !clustered.milestoneValid) {
  const why = !clustered
    ? 'clustering agent failed to return'
    : clustered.error || (!clustered.labelValid ? `label "${safeLabel}" not found in repo` : `milestone title "${safeMilestone}" not found (open milestones only)`)
  log(`Abort: ${why}`)
  return {
    label: safeLabel,
    milestone: safeMilestone,
    dryRun,
    aborted: true,
    reason: why,
  }
}

// ---------------------------------------------------------------------------
// Confirm: apply --min-cluster-size floor, then take the top --top-n. The
// SCRIPT (not the model) owns selection — the agent reported ALL clusters.
// ---------------------------------------------------------------------------
phase('Confirm')
const meets = (clustered.clusters || []).filter((c) => c.count >= minClusterSize).sort((a, b) => b.count - a.count)
const picked = meets.slice(0, topN)
const other = meets.slice(topN)
const below = (clustered.clusters || []).filter((c) => c.count < minClusterSize)

log(
  `Label "${safeLabel}" / milestone "${safeMilestone}": ${clustered.totalOpen} open. ` +
    `${meets.length} cluster(s) ≥ ${minClusterSize}; picking top ${topN} → ${picked.length}. ` +
    `${other.length} other, ${below.length} below floor.`,
)

// No cluster clears the floor → clean stop. Do NOT open a low-value PR.
if (picked.length === 0) {
  log(`No cleanup cluster available; backlog is distributed across too many areas (min-cluster-size=${minClusterSize}).`)
  return {
    label: safeLabel,
    milestone: safeMilestone,
    minClusterSize,
    topN,
    totalOpen: clustered.totalOpen,
    picked: [],
    clusters: { meets: meets.length, other: other.length, below: below.length },
    delegated: 0,
    message: 'No cleanup cluster available.',
  }
}

// ---------------------------------------------------------------------------
// Drain: pipeline() each picked cluster — NO barrier between brief-build and
// delegation, so cluster k's one-shot can start the moment its brief lands while
// cluster k+1's brief is still being assembled. Stage 1 builds the scoped brief;
// stage 2 hands it to /soleur:one-shot (skipped under --dry-run or budget floor).
// ---------------------------------------------------------------------------
phase('Drain')
const drainResults = await pipeline(
  picked,
  // Stage 1: scoped brief from issue bodies.
  (cluster) => agent(briefPrompt(cluster), { label: `brief:${cluster.area}`, phase: 'Drain', schema: BRIEF_SCHEMA }),
  // Stage 2: delegate the cluster to a full one-shot (gated on dry-run + budget).
  (brief, cluster) => {
    if (!brief) return { area: cluster.area, status: 'failed', notes: 'brief assembly failed' }
    if (dryRun) {
      return {
        area: brief.area,
        status: 'dry-run',
        issueNumbers: brief.issueNumbers,
        wouldDelegateScope: brief.scope,
      }
    }
    if (!budgetOk()) {
      droppedClusters.push(brief.area)
      return {
        area: brief.area,
        status: 'skipped-budget',
        issueNumbers: brief.issueNumbers,
        notes: `SKIPPED — token budget floor (${ONE_SHOT_FLOOR}) reached; not enough headroom to run a full one-shot for this cluster.`,
      }
    }
    return agent(oneShotPrompt(brief), { label: `one-shot:${brief.area}`, phase: 'Drain', schema: ONE_SHOT_RESULT_SCHEMA })
  },
)

const results = drainResults.filter(Boolean)

// ---------------------------------------------------------------------------
// Report: re-query the milestone for the backlog delta. Skipped on dry-run
// (nothing was delegated, so the count is unchanged).
// ---------------------------------------------------------------------------
phase('Report')
let after = null
if (!dryRun && results.some((r) => r.status === 'merged')) {
  const delta = await agent(reportPrompt, { label: 'report', phase: 'Report', schema: DELTA_SCHEMA })
  after = delta?.after ?? null
}

const before = clustered.totalOpen
const merged = results.filter((r) => r.status === 'merged')
const closed = after != null ? Math.max(0, before - after) : merged.reduce((n, r) => n + (r.closedIssues?.length || 0), 0)

const summary = {
  label: safeLabel,
  milestone: safeMilestone,
  dryRun,
  topN,
  minClusterSize,
  selection: {
    totalOpen: before,
    clustersMeetingFloor: meets.length,
    pickedCount: picked.length,
    otherClusters: other.map((c) => ({ area: c.area, count: c.count })),
    belowFloor: below.map((c) => ({ area: c.area, count: c.count })),
  },
  picked: picked.map((c) => ({ area: c.area, count: c.count, issues: c.issues.map((i) => i.number) })),
  budget: { total: budget.total, spent: budget.spent(), oneShotFloor: ONE_SHOT_FLOOR, droppedClusters },
  delegated: dryRun ? 0 : results.filter((r) => r.status === 'merged' || r.status === 'pr-open' || r.status === 'failed').length,
  results,
  backlogDelta: { before, after, closed },
}

if (droppedClusters.length) {
  log(`⚠ budget floor hit — ${droppedClusters.length} cluster(s) NOT delegated: ${droppedClusters.join(', ')}`)
}
log(
  dryRun
    ? `Dry-run: ${picked.length} cluster(s) would delegate to /soleur:one-shot (no fan-out). Confirm scope, then re-run without --dry-run.`
    : `Done: ${merged.length}/${picked.length} cluster(s) merged. Backlog ${before} → ${after ?? '?'} (closed ${closed}).`,
)

return summary
