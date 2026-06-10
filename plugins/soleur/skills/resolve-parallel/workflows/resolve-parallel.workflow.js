export const meta = {
  name: 'resolve-parallel-workflow',
  description:
    'Workflow-backed soleur:resolve-parallel — deterministic TODO-comment sweep: grep the codebase for TODO/FIXME/HACK/XXX markers, build dependency tiers (blockers first), resolve each tier with parallel() pr-comment-resolver agents (one agent per item), then commit and push.',
  // Same phase titles as the phase() calls below so progress groups line up.
  phases: [
    { title: 'Analyze', detail: 'one agent greps the codebase for TODO comments and structures them' },
    { title: 'Plan', detail: 'order items into dependency tiers (blockers resolve before dependents)' },
    { title: 'Implement', detail: 'tier-by-tier: one pr-comment-resolver agent per item, in parallel within each tier' },
    { title: 'Commit', detail: 'stage resolved files, commit, and push to remote' },
  ],
}

// ---------------------------------------------------------------------------
// API-budget disclosure (per hr-autonomous-loop-skill-api-budget-disclosure).
// This workflow fans out ONE resolver agent PER unresolved TODO item: N TODOs
// => N agents (plus 1 analyze + 1 plan + 1 commit). Every agent is a real
// Anthropic API call billed against THIS session's key. The BSL-1.1 license
// disclaims runtime/API cost — Soleur does not reimburse it. The discovered
// item count is logged BEFORE the Implement fan-out so the count is visible
// before any resolver spawns; a hard cap (MAX_ITEMS) bounds an accidental
// blast radius from a runaway grep.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Input. args may be a bare string (a path/glob scope) or an object:
//   { scope, markers, push, maxItems }
//   scope:    pathspec to restrict the grep (default: whole repo)
//   markers:  override the TODO-marker set (default: TODO|FIXME|HACK|XXX)
//   push:     push to remote after commit (default: true)
//   maxItems: hard cap on the number of resolver agents (default: MAX_ITEMS)
// ---------------------------------------------------------------------------
const scope = (typeof args === 'string' ? args : args?.scope) || '.'
const markers =
  (typeof args === 'object' && typeof args?.markers === 'string' && args.markers.trim()) ||
  'TODO|FIXME|HACK|XXX'
const doPush = typeof args === 'object' && args?.push === false ? false : true
const MAX_ITEMS = 60
const maxItems =
  typeof args === 'object' && Number.isInteger(args?.maxItems) && args.maxItems > 0
    ? Math.min(args.maxItems, MAX_ITEMS)
    : MAX_ITEMS

// Harden the marker set before it reaches a grep argv: the analyze agent runs
// `git grep -nE` with this alternation, so keep it to word-chars and the pipe
// alternator only. Anything else is dropped — never let untrusted args smuggle
// shell metacharacters into the resolver's grep.
const safeMarkers = String(markers)
  .replace(/[^A-Za-z0-9_|]/g, '')
  .replace(/\|+/g, '|')
  .replace(/^\||\|$/g, '')
  || 'TODO|FIXME|HACK|XXX'

// Sanitize the scope pathspec the same way before it reaches a shell argv.
// Allow path-ish characters only; reject shell metacharacters outright.
function safePath(raw) {
  return (
    String(raw)
      .replace(/[\x00-\x1f\x7f]/g, ' ') // control chars
      .replace(/[`$"'\\;|&<>(){}[\]!*?~#]/g, ' ') // shell metacharacters
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 200) || '.'
  )
}
const safeScope = safePath(scope)

const grepCmd = `git grep -nE '${safeMarkers}' -- ${safeScope}`

// ---------------------------------------------------------------------------
// Schemas — validated at the tool-call layer, so agents retry on mismatch.
// additionalProperties:false everywhere; agents return DATA, not prose.
// ---------------------------------------------------------------------------
const ANALYZE_SCHEMA = {
  type: 'object',
  required: ['items', 'scanned'],
  additionalProperties: false,
  properties: {
    scanned: { type: 'integer', description: 'count of TODO-marker hits the grep returned' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'file', 'line', 'marker', 'text'],
        additionalProperties: false,
        properties: {
          id: { type: 'string', description: 'short stable slug, unique within this run (e.g. "auth-rename-1")' },
          file: { type: 'string', description: 'repo-relative path of the file holding the TODO' },
          line: { type: 'integer', description: 'line number of the TODO comment' },
          marker: { type: 'string', enum: ['TODO', 'FIXME', 'HACK', 'XXX'] },
          text: { type: 'string', description: 'the TODO comment text (the work to do)' },
          symbol: { type: 'string', description: 'enclosing function/class/symbol name if discernible, else ""' },
        },
      },
    },
  },
}

const PLAN_SCHEMA = {
  type: 'object',
  required: ['tiers', 'rationale'],
  additionalProperties: false,
  properties: {
    rationale: { type: 'string', description: 'one paragraph: why this tiering (which items block which)' },
    mermaid: { type: 'string', description: 'mermaid flowchart showing the resolution order (tiers as ranks)' },
    tiers: {
      type: 'array',
      description: 'ordered list of tiers; tier[0] resolves fully before tier[1] starts. Items WITHIN a tier are independent and run in parallel.',
      items: {
        type: 'object',
        required: ['ids'],
        additionalProperties: false,
        properties: {
          ids: { type: 'array', items: { type: 'string' }, description: 'item ids in this tier' },
          why: { type: 'string', description: 'one sentence: what makes this tier a unit / why it precedes the next' },
        },
      },
    },
  },
}

const RESOLVE_SCHEMA = {
  type: 'object',
  required: ['id', 'status', 'summary', 'filesTouched'],
  additionalProperties: false,
  properties: {
    id: { type: 'string', description: 'the item id this resolution belongs to' },
    status: { type: 'string', enum: ['resolved', 'partial', 'skipped'], description: 'resolved = TODO removed + change made; skipped = could not safely act' },
    summary: { type: 'string', description: 'what was changed and why the TODO is now satisfied' },
    todoRemoved: { type: 'boolean', description: 'true if the literal TODO/FIXME/HACK/XXX comment line was deleted' },
    filesTouched: { type: 'array', items: { type: 'string' }, description: 'repo-relative paths modified' },
  },
}

const COMMIT_SCHEMA = {
  type: 'object',
  required: ['committed', 'pushed'],
  additionalProperties: false,
  properties: {
    committed: { type: 'boolean', description: 'true if a commit was created (false if the tree was clean)' },
    pushed: { type: 'boolean', description: 'true if the commit was pushed to remote' },
    branch: { type: 'string', description: 'branch the commit landed on' },
    sha: { type: 'string', description: 'short SHA of the new commit, or "" if none' },
    note: { type: 'string', description: 'one line if committed=false or push was skipped' },
  },
}

// The resolver reuses the REAL Soleur pr-comment-resolver agent via agentType,
// so the workflow inherits that agent's resolution system prompt and only
// appends the StructuredOutput instruction. One source of resolution expertise.
const RESOLVER_AGENT_TYPE = 'soleur:engineering:workflow:pr-comment-resolver'

// ---------------------------------------------------------------------------
// Prompt builders.
// ---------------------------------------------------------------------------
const analyzePrompt = `You are the TODO-discovery gate for a parallel resolution sweep.

Gather every outstanding TODO-style comment in the codebase (scope: ${safeScope}).
Source of truth — run exactly:
  ${grepCmd}

For EACH hit, emit one item:
- id: a short stable slug unique within this run (derive it from the file basename + a counter, e.g. "auth-rename-1"). IDs must be deterministic given the grep order — do NOT use timestamps or random values.
- file, line: from the grep output.
- marker: which of TODO / FIXME / HACK / XXX it is.
- text: the TODO comment text — the actual work the comment asks for. Read enough surrounding code to capture intent.
- symbol: the enclosing function/class/symbol name if you can read it, else "".

Do NOT resolve anything yet — only inventory. If grep returns nothing, return items: [] and scanned: 0.
Set scanned to the total number of grep hits you saw.`

function planPrompt(items) {
  return `You are sequencing TODO resolutions into dependency tiers for a parallel sweep.

Here are ${items.length} TODO items (JSON):
${JSON.stringify(items, null, 2)}

Group the items into ORDERED tiers. A later tier may depend on an earlier tier; items WITHIN a tier must be independent so they can run in parallel.

Tiering rules (deterministic — apply in order):
1. A "blocker" is any item that, once resolved, changes the meaning of other items: a rename/move, an API/signature change, a shared-type or interface change, a config/constant rename. Blockers go in EARLIER tiers than the items they affect.
2. Two items touching the SAME file generally must NOT share a tier (parallel edits to one file race). Put them in successive tiers.
3. Items that are fully independent (different files, no shared symbol) belong in the SAME tier so they parallelize.
4. If no dependencies exist at all, emit a single tier containing every id — maximum parallelism.

Output:
- tiers: ordered array; tier[0] resolves before tier[1] starts.
- rationale: one paragraph explaining the ordering.
- mermaid: a flowchart (\`flowchart TD\`) showing the tiers as ranks and the blocking edges between them.

Every input id must appear in EXACTLY one tier. Do not invent ids.`
}

function resolvePrompt(item, tierIndex, tierTotal) {
  return `You are resolving ONE TODO comment from a parallel sweep (tier ${tierIndex + 1} of ${tierTotal}).
Other resolvers in this SAME tier are editing DIFFERENT files concurrently — stay strictly within the file(s) this TODO requires. Do not touch unrelated files, do not run \`git commit\` or \`git push\` (the workflow commits the whole tier afterward), and do not \`git stash\`.

The TODO to resolve:
- id: ${item.id}
- file: ${item.file}:${item.line}
- marker: ${item.marker}
- enclosing symbol: ${item.symbol || '(unknown)'}
- comment text: ${item.text}

Steps:
1. Read ${item.file} around line ${item.line} for full context. Confirm the ${item.marker} is still present and still applies.
2. Implement the change the comment asks for — the smallest correct fix. Follow the surrounding code's conventions.
3. DELETE the now-satisfied ${item.marker} comment line (set todoRemoved=true). If the work is genuinely larger than a focused fix or cannot be done safely, set status="partial" or "skipped" and leave the comment in place (todoRemoved=false) with a summary of why.
4. Do NOT commit, push, or stage — just leave the edits in the working tree.

Report the resolution object: id, status, summary, todoRemoved, filesTouched.`
}

function commitPrompt(resolved, tierCount) {
  const fileList = [...new Set(resolved.flatMap((r) => r.filesTouched || []))].slice(0, 200)
  return `You are finalizing a parallel TODO-resolution sweep. ${resolved.length} TODO item(s) across ${tierCount} tier(s) were resolved by sibling agents; their edits are already in the working tree.

Steps (do them exactly; do NOT \`git stash\`, do NOT amend existing history):
1. Run \`git status --short\` and \`git diff --stat\` to confirm there are staged-or-unstaged changes. If the tree is clean, return committed=false, pushed=false with a note — nothing to do.
2. Stage the resolved files. Prefer staging the specific paths that changed (the resolvers reported these files): ${fileList.length ? fileList.join(', ') : '(none reported — fall back to `git add -u` for tracked modifications only)'}. Do NOT \`git add -A\` blindly.
3. If the current branch is the default branch (main/master), create a working branch first: \`git switch -c chore/resolve-todos\`. Otherwise commit on the current branch.
4. Commit with a message summarizing the swept TODOs, e.g. "chore: resolve ${resolved.length} TODO comment(s) via parallel sweep". End the commit message body with the trailer:
   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
5. ${doPush ? 'Push to remote: `git push -u origin HEAD`.' : 'Do NOT push (push disabled for this run); set pushed=false.'}
6. Report: committed, pushed, branch, sha (short), note.`
}

// ---------------------------------------------------------------------------
// Budget. The resolver fan-out is the expensive part; floor it so the commit
// step always has headroom. NEVER silently skip — log dropped coverage.
// ---------------------------------------------------------------------------
const COMMIT_FLOOR = 40_000 // output tokens to reserve for the commit step
const droppedResolution = []

function budgetOk() {
  return !budget.total || budget.remaining() > COMMIT_FLOOR
}

// ---------------------------------------------------------------------------
// Run.
// ---------------------------------------------------------------------------
phase('Analyze')
log('tier pins: analyze→sonnet, commit→sonnet (mechanical steps per ADR-053; plan + resolvers inherit the session model)')
// Pinned 'sonnet': TODO inventory extraction is mechanical (ADR-053).
const analysis = await agent(analyzePrompt, { label: 'analyze', phase: 'Analyze', schema: ANALYZE_SCHEMA, model: 'sonnet' })
let items = (analysis?.items || []).filter((i) => i && i.id && i.file)

if (!items.length) {
  log('No TODO comments found in scope — nothing to resolve.')
  return {
    scope: safeScope,
    markers: safeMarkers,
    scanned: analysis?.scanned ?? 0,
    items: 0,
    tiers: 0,
    resolved: 0,
    committed: false,
    pushed: false,
    note: 'no TODO comments discovered',
  }
}

// API-budget disclosure: surface the resolver count BEFORE any fan-out, and
// enforce the hard cap so a runaway grep cannot spawn an unbounded swarm.
let capped = false
if (items.length > maxItems) {
  capped = true
  log(`⚠ ${items.length} TODO items discovered — capping resolver fan-out at ${maxItems} (MAX_ITEMS=${MAX_ITEMS}). Re-run with a narrower scope to address the rest.`)
  items = items.slice(0, maxItems)
}
log(`Discovered ${items.length} TODO item(s) — this Implement phase will spawn ${items.length} pr-comment-resolver agent(s), one per item (billed against this session key).`)

phase('Plan')
const plan = await agent(planPrompt(items), { label: 'plan', phase: 'Plan', schema: PLAN_SCHEMA })

// The SCRIPT (not the model) owns tier execution: map planned id-tiers back to
// real item objects, drop unknown ids, and append any item the planner forgot
// as a trailing tier so nothing is silently lost.
const byId = new Map(items.map((i) => [i.id, i]))
const placed = new Set()
const tiers = []
for (const t of plan?.tiers || []) {
  const tierItems = (t.ids || []).map((id) => byId.get(id)).filter((i) => i && !placed.has(i.id))
  for (const i of tierItems) placed.add(i.id)
  if (tierItems.length) tiers.push(tierItems)
}
const orphans = items.filter((i) => !placed.has(i.id))
if (orphans.length) {
  log(`⚠ planner omitted ${orphans.length} item(s); appending them as a final tier.`)
  tiers.push(orphans)
}
log(`Plan: ${tiers.length} tier(s) — ${tiers.map((t) => t.length).join(' → ')} item(s) per tier. ${plan?.rationale || ''}`)
if (plan?.mermaid) log(plan.mermaid)

// -------------------------------------------------------------------------
// Implement. Tiers are a BARRIER chain: tier N fully resolves before tier N+1
// starts (blockers land before dependents). Items WITHIN a tier run via
// parallel() — independent files, no race. A dead resolver becomes null
// (filter(Boolean)); a budget-floor hit surfaces the item as "skipped" rather
// than dropping it silently.
// -------------------------------------------------------------------------
phase('Implement')
const resolutions = []
for (let ti = 0; ti < tiers.length; ti++) {
  const tier = tiers[ti]
  const tierResults = (
    await parallel(
      tier.map((item) => () => {
        if (!budgetOk()) {
          droppedResolution.push(item.id)
          return Promise.resolve({
            id: item.id,
            status: 'skipped',
            summary: `UNRESOLVED — token budget floor (${COMMIT_FLOOR}) reached before this item; left in place so the commit step has headroom.`,
            todoRemoved: false,
            filesTouched: [],
          })
        }
        return agent(resolvePrompt(item, ti, tiers.length), {
          label: `resolve:t${ti + 1}:${item.id}`,
          phase: 'Implement',
          schema: RESOLVE_SCHEMA,
          agentType: RESOLVER_AGENT_TYPE,
        })
      }),
    )
  ).filter(Boolean)
  resolutions.push(...tierResults)
  log(`Tier ${ti + 1}/${tiers.length} done: ${tierResults.filter((r) => r.status === 'resolved').length}/${tier.length} resolved.`)
}

const resolved = resolutions.filter((r) => r.status === 'resolved')
const partial = resolutions.filter((r) => r.status === 'partial')
const skipped = resolutions.filter((r) => r.status === 'skipped')

// -------------------------------------------------------------------------
// Commit & push. Only if at least one item actually changed the tree.
// -------------------------------------------------------------------------
phase('Commit')
let commit = { committed: false, pushed: false, branch: '', sha: '', note: '' }
const touched = resolutions.filter((r) => (r.filesTouched || []).length && r.status !== 'skipped')
if (touched.length) {
  commit =
    // Pinned 'sonnet': commit-message generation over a known diff is mechanical (ADR-053).
    (await agent(commitPrompt(touched, tiers.length), { label: 'commit', phase: 'Commit', schema: COMMIT_SCHEMA, model: 'sonnet' })) || commit
} else {
  commit.note = 'no files were modified by any resolver — skipped commit'
  log(commit.note)
}

if (droppedResolution.length) {
  log(`⚠ budget floor hit — ${droppedResolution.length} item(s) left UNRESOLVED: ${droppedResolution.join(', ')}`)
}
log(
  `Done: ${resolved.length} resolved, ${partial.length} partial, ${skipped.length} skipped across ${tiers.length} tier(s). ` +
    `Commit: ${commit.committed ? `${commit.sha || 'created'}${commit.pushed ? ' (pushed)' : ''}` : 'none'}.`,
)

return {
  scope: safeScope,
  markers: safeMarkers,
  scanned: analysis?.scanned ?? items.length,
  capped,
  maxItems,
  items: items.length,
  tiers: tiers.length,
  tierSizes: tiers.map((t) => t.length),
  totals: {
    resolved: resolved.length,
    partial: partial.length,
    skipped: skipped.length,
    droppedForBudget: droppedResolution.length,
  },
  budget: { total: budget.total, spent: budget.spent(), droppedResolution },
  commit: {
    committed: !!commit.committed,
    pushed: !!commit.pushed,
    branch: commit.branch || '',
    sha: commit.sha || '',
    note: commit.note || '',
  },
  resolutions: resolutions.map((r) => ({ id: r.id, status: r.status, todoRemoved: !!r.todoRemoved, files: r.filesTouched || [], summary: r.summary })),
}
