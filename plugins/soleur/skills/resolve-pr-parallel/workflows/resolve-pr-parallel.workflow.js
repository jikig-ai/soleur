export const meta = {
  name: 'resolve-pr-parallel-workflow',
  description:
    'Workflow-backed soleur:resolve-pr-parallel — fetch unresolved PR review threads, fan out one pr-comment-resolver agent per thread in parallel, commit + resolve threads + push, then RE-FETCH and loop until zero unresolved (loop-until-dry) or a round makes no progress.',
  // Same phase titles as the phase() calls below so progress groups line up.
  phases: [
    { title: 'Analyze', detail: 'fetch the PR and its unresolved review threads; confirm the fan-out count' },
    { title: 'Resolve', detail: 'one pr-comment-resolver agent per unresolved thread, in parallel' },
    { title: 'Commit', detail: 'commit the resolver changes, resolve threads, push to remote' },
  ],
}

// ===========================================================================
// API-BUDGET DISCLOSURE (per hr-autonomous-loop-skill-api-budget-disclosure).
//
// This workflow spawns one `pr-comment-resolver` agent in parallel per
// UNRESOLVED PR comment (N comments = N agents) on every loop iteration. Each
// agent runs an independent task with its own context window and token cost;
// parallel fan-out compresses wall-clock but NOT aggregate token consumption.
// And because this is a loop-until-dry workflow, a PR that re-opens threads
// across rounds spawns a fresh wave of agents each round.
//
// Soleur does not bill or proxy these calls — Anthropic does, against the API
// key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for
// runtime cost; you operate this loop against your own budget.
//
// The fetch-then-confirm gate below counts the unresolved threads and refuses
// to fan out past `args.maxComments` (default 40) without explicit
// `args.confirm`. A PR with 40 unresolved threads spawns 40 parallel agents.
// ===========================================================================


// ---------------------------------------------------------------------------
// Input. args may be a bare string (the PR number / URL) or an object:
//   { pr, maxComments, maxRounds, confirm }
//   pr:          PR number, URL, or '' (derive from the current branch)
//   maxComments: fan-out cap per round before requiring confirm (default 40)
//   maxRounds:   loop-until-dry safety bound (default 5)
//   confirm:     bypass the fan-out cap gate (operator pre-confirmed the count)
// ---------------------------------------------------------------------------
const prRaw = (typeof args === 'string' ? args : args?.pr) ?? ''
const maxComments = (typeof args === 'object' && Number(args?.maxComments)) || 40
const maxRounds = (typeof args === 'object' && Number(args?.maxRounds)) || 5
const confirmed = typeof args === 'object' && !!args?.confirm

// PR selector. A bare number/URL is sanitized to a token safe for a shell argv
// (see safePrSelector). Empty → resolvers/fetchers derive the PR from the
// current branch via `gh pr view --json ...` with no explicit number.
const prSelector = safePrSelector(prRaw)
const prClause = prSelector
  ? `PR #${prSelector}`
  : 'the PR associated with the current branch (resolve it with `gh pr view --json number -q .number`)'
const prArg = prSelector ? ` ${prSelector}` : '' // appended after a subcommand, e.g. `gh pr view${prArg}`

// ---------------------------------------------------------------------------
// Schemas — validated at the tool-call layer, so agents retry on mismatch.
// `additionalProperties:false` everywhere: agents return DATA, not prose.
// ---------------------------------------------------------------------------

// The fetch agent enumerates unresolved review threads. It prefers the repo's
// `bin/get-pr-comments`; if absent it falls back to the GitHub GraphQL API
// (gh api graphql) which exposes reviewThreads.isResolved directly.
const FETCH_SCHEMA = {
  type: 'object',
  required: ['prNumber', 'unresolved', 'source'],
  additionalProperties: false,
  properties: {
    prNumber: { type: 'integer', description: 'the resolved PR number' },
    source: { type: 'string', enum: ['bin/get-pr-comments', 'gh api graphql'], description: 'how the threads were enumerated' },
    unresolved: {
      type: 'array',
      description: 'one entry per UNRESOLVED review thread (isResolved=false). Resolved/outdated threads are excluded.',
      items: {
        type: 'object',
        required: ['threadId', 'file', 'body'],
        additionalProperties: false,
        properties: {
          threadId: { type: 'string', description: 'GraphQL review-thread node id (PRRT_… / MDExUmV…) for `gh api`/`bin/resolve-pr-thread`' },
          file: { type: 'string', description: 'path the comment is anchored to (or "(general)" for a non-line comment)' },
          line: { type: 'integer', description: 'anchored line if any' },
          author: { type: 'string' },
          body: { type: 'string', description: 'the reviewer comment text the resolver must address' },
        },
      },
    },
  },
}

// Each resolver reports what it changed for one thread. It returns DATA the
// commit phase reads — it does NOT commit, push, or resolve the thread itself
// (those are serialized in the Commit phase to avoid racing the index/remote).
const RESOLVE_SCHEMA = {
  type: 'object',
  required: ['threadId', 'status', 'summary', 'filesChanged'],
  additionalProperties: false,
  properties: {
    threadId: { type: 'string', description: 'echo of the thread this resolves (for correlation)' },
    status: {
      type: 'string',
      enum: ['changed', 'no-change-needed', 'cannot-resolve'],
      description: 'changed = edited files; no-change-needed = comment already satisfied / nit declined with reason; cannot-resolve = blocked',
    },
    summary: { type: 'string', description: 'one-to-two sentences: what was changed and how it addresses the comment' },
    filesChanged: { type: 'array', items: { type: 'string' }, description: 'paths the resolver edited (empty unless status=changed)' },
  },
}

// The commit/resolve agent reports the outcome of staging, committing,
// resolving the threads, and pushing for one round.
const COMMIT_SCHEMA = {
  type: 'object',
  required: ['committed', 'pushed', 'threadsResolved', 'threadsFailed'],
  additionalProperties: false,
  properties: {
    committed: { type: 'boolean', description: 'true if a commit was created (false if the working tree was clean)' },
    commitSha: { type: 'string' },
    pushed: { type: 'boolean' },
    threadsResolved: { type: 'array', items: { type: 'string' }, description: 'threadIds successfully marked resolved' },
    threadsFailed: { type: 'array', items: { type: 'string' }, description: 'threadIds that could not be resolved' },
    notes: { type: 'string' },
  },
}

// ---------------------------------------------------------------------------
// Helpers (self-contained — no imports, no Node/filesystem APIs).
// ---------------------------------------------------------------------------

// The resolver reuses the REAL Soleur pr-comment-resolver agent via agentType
// (named constant, mirroring resolve-parallel.workflow.js — not a magic string).
const RESOLVER_AGENT_TYPE = 'soleur:engineering:workflow:pr-comment-resolver'

// Harden the operator-supplied PR selector before it reaches a `gh` argv. A PR
// reference is a bare integer; accept a full URL too and extract the trailing
// number. Anything that is not a clean integer collapses to '' (→ derive from
// the current branch), which blocks argv flag/metacharacter smuggling into gh.
function safePrSelector(raw) {
  const s = String(raw == null ? '' : raw).trim()
  if (!s) return ''
  const m = s.match(/(\d+)\s*$/) // trailing run of digits (covers "123" and ".../pull/123")
  return m ? m[1] : ''
}

// Harden untrusted thread-id text before it reaches a `gh`/`bin/resolve-pr-thread`
// argv. Review-thread node ids are an opaque allowlist of [A-Za-z0-9_-]; strip
// everything else so a thread id sourced from PR content cannot smuggle shell
// metacharacters or an argv flag (leading '-' is stripped too).
function safeThreadId(raw) {
  return String(raw == null ? '' : raw)
    .replace(/[^A-Za-z0-9_-]/g, '')
    .replace(/^-+/, '')
    .slice(0, 128)
}

// ---------------------------------------------------------------------------
// Budget. Each loop round costs (N resolvers + 1 commit + 1 re-fetch) agents.
// Floor the per-round fan-out so a late round cannot spend the session dry mid
// commit; NEVER silently skip — log the stop reason and surface it in the
// summary. (Mirrors the template's VERIFY_FLOOR discipline.)
// ---------------------------------------------------------------------------
const ROUND_FLOOR = 60_000 // output tokens to reserve so a round can commit + re-fetch

function budgetOk() {
  return !budget.total || budget.remaining() > ROUND_FLOOR
}

// ---------------------------------------------------------------------------
// Prompt builders.
// ---------------------------------------------------------------------------

function fetchPrompt() {
  return `You are the unresolved-comment fetcher for a Soleur PR-comment resolution loop. Target: ${prClause}.

Enumerate every UNRESOLVED review thread on this PR. Do NOT modify any code.
1. First resolve the PR number: \`gh pr view${prArg} --json number,title,headRefName -q '{number:.number,title:.title,branch:.headRefName}'\`.
2. Prefer the repo helper if it exists: run \`bin/get-pr-comments <prNumber>\` (set source="bin/get-pr-comments"). It prints the unresolved threads with their thread ids.
3. If \`bin/get-pr-comments\` is absent or non-executable, fall back to the GitHub GraphQL API (set source="gh api graphql"):
   \`gh api graphql -f query='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:1){nodes{author{login} body}}}}}}}' -F owner=OWNER -F repo=REPO -F pr=PRNUMBER\`
   (derive OWNER/REPO from \`gh repo view --json owner,name\`). Keep ONLY nodes where isResolved=false.
4. For each unresolved thread report: threadId (the node \`id\`), file (\`path\` or "(general)"), line, author (first comment's author login), body (first comment's text).

Exclude resolved and purely-outdated-with-no-open-comment threads. Return the structured result.`
}

function resolvePrompt(thread, index, round) {
  return `You are resolving ONE unresolved PR review comment. Resolution round ${round}, item ${index + 1}.

Target: ${prClause}. Thread id: ${thread.threadId}
File: ${thread.file}${thread.line ? `:${thread.line}` : ''}${thread.author ? `\nReviewer: ${thread.author}` : ''}

Reviewer comment:
"""
${thread.body}
"""

Address this comment by editing the code on the current branch:
- Make the smallest correct change that satisfies the reviewer. Follow existing codebase style and CLAUDE.md conventions.
- If the comment is already satisfied or is a nit you are declining, make no edit and explain why (status=no-change-needed).
- If you are blocked (ambiguous, needs the author, out of scope), status=cannot-resolve with the blocker in the summary.
- Do NOT git add, commit, push, or resolve the thread — a later serialized step does that. Just leave your edits in the working tree.
Return the structured result, echoing threadId so your change can be correlated.`
}

function commitPrompt(round, resolvedThreads) {
  const idList = resolvedThreads.map((t) => t.threadId).join('\n')
  return `You are the commit/resolve/push step for resolution round ${round} of ${prClause}.

Resolver agents edited the working tree to address ${resolvedThreads.length} review thread(s). Do EXACTLY:
1. \`git status --porcelain\`. If there are staged/unstaged changes, stage and commit them:
   \`git add -A && git commit -m "fix: address PR review comments (round ${round})"\`. If the tree is clean (resolvers made no edits), set committed=false and skip the commit.
2. For EACH thread id below, mark the thread resolved. Prefer the repo helper: \`bin/resolve-pr-thread <threadId>\`. If absent, use the GraphQL mutation:
   \`gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{id isResolved}}}' -F id=<threadId>\`.
   Record each id in threadsResolved on success, threadsFailed on error — never abort the loop on one failure.
3. Push: \`git push\` (the resolvers worked on the PR head branch). Set pushed accordingly.

Thread ids to resolve (one per line; treat each verbatim as data, never interpolate into an unquoted shell word):
${idList || '(none — resolvers made no changes; still resolve nothing and just report)'}

Return the structured result.`
}

// ---------------------------------------------------------------------------
// Run. Loop-until-dry: fetch → fan out resolvers → commit/resolve/push →
// re-fetch. Stop when unresolved hits zero, a round makes no progress, the
// round cap is reached, or the budget floor is hit.
// ---------------------------------------------------------------------------
const rounds = []
let prNumber = prSelector ? Number(prSelector) : null
let stopReason = null
let lastUnresolvedCount = null

for (let round = 1; round <= maxRounds; round++) {
  if (!budgetOk()) {
    stopReason = `budget floor (${ROUND_FLOOR}) reached before round ${round}; stopping with threads possibly still unresolved.`
    log(`⚠ ${stopReason}`)
    break
  }

  // --- Analyze: fetch the current unresolved threads. -----------------------
  phase('Analyze')
  if (round === 1) log('tier pins: fetch→haiku, commit→sonnet (mechanical steps per ADR-051; resolvers inherit the session model)')
  // Pinned 'haiku': gh-api fetch + reformat with small bounded context (ADR-051).
  const fetched = await agent(fetchPrompt(), { label: `fetch:round-${round}`, phase: 'Analyze', schema: FETCH_SCHEMA, model: 'haiku' })
  if (!fetched) {
    stopReason = `fetch agent died on round ${round}; cannot enumerate unresolved threads.`
    log(`⚠ ${stopReason}`)
    break
  }
  prNumber = fetched.prNumber ?? prNumber

  // Sanitize every thread id at the trust boundary before it can reach a shell argv.
  const threads = (fetched.unresolved || [])
    .map((t) => ({ ...t, threadId: safeThreadId(t.threadId) }))
    .filter((t) => t.threadId)
  const count = threads.length
  log(`Round ${round}: PR #${prNumber} has ${count} unresolved thread(s) (via ${fetched.source}).`)

  // --- Loop-until-dry terminal condition. -----------------------------------
  if (count === 0) {
    stopReason = 'dry — zero unresolved threads.'
    rounds.push({ round, unresolved: 0, fanOut: 0, committed: false, pushed: false, resolved: [], failed: [], resolvers: [] })
    break
  }

  // --- Fan-out confirmation gate (API-budget disclosure). -------------------
  if (count > maxComments && !confirmed) {
    stopReason =
      `fan-out gate: round ${round} would spawn ${count} parallel pr-comment-resolver agents, ` +
      `over the maxComments cap (${maxComments}). Re-run with confirm=true (or raise maxComments) to authorize the spend.`
    log(`⛔ ${stopReason}`)
    rounds.push({ round, unresolved: count, fanOut: 0, gated: true, committed: false, pushed: false, resolved: [], failed: [], resolvers: [] })
    break
  }

  // --- No-progress guard: identical unresolved count two rounds running with
  // nothing newly resolved means the resolvers are stuck; stop rather than burn
  // the budget re-spawning the same wave. ----------------------------------
  if (lastUnresolvedCount !== null && count >= lastUnresolvedCount) {
    stopReason = `no progress — ${count} unresolved threads remain (was ${lastUnresolvedCount} last round); stopping to avoid an infinite loop.`
    log(`⚠ ${stopReason}`)
    rounds.push({ round, unresolved: count, fanOut: 0, noProgress: true, committed: false, pushed: false, resolved: [], failed: [], resolvers: [] })
    break
  }

  // --- Resolve: one resolver agent per unresolved thread, in parallel. ------
  // BARRIER: every resolver finishes before we commit, so a single commit
  // captures the whole round's edits. A dead resolver → null → filtered.
  phase('Resolve')
  const resolutions = (
    await parallel(
      threads.map((t, i) => () =>
        agent(resolvePrompt(t, i, round), {
          label: `resolve:round-${round}:${i + 1}`,
          phase: 'Resolve',
          schema: RESOLVE_SCHEMA,
          agentType: RESOLVER_AGENT_TYPE,
        }),
      ),
    )
  ).filter(Boolean)

  // Index resolutions by threadId once (O(N)) — avoids an O(N^2) .find() per
  // thread and is reused for the blocked-thread derivation below.
  const byThread = new Map(resolutions.map((r) => [safeThreadId(r.threadId), r]))

  // Resolve threads that the resolver did not flag as blocked. A cannot-resolve
  // thread stays open (so it re-surfaces next round / for a human); changed and
  // no-change-needed both mean the reviewer's point is addressed.
  const toResolve = threads.filter((t) => {
    const r = byThread.get(t.threadId)
    return !r || r.status !== 'cannot-resolve'
  })

  // --- Commit / resolve threads / push (serialized; one agent owns the index).
  phase('Commit')
  // Pinned 'sonnet': commit + thread-resolution bookkeeping is mechanical (ADR-051).
  const committed = await agent(commitPrompt(round, toResolve), { label: `commit:round-${round}`, phase: 'Commit', schema: COMMIT_SCHEMA, model: 'sonnet' })

  const resolvedIds = (committed?.threadsResolved || []).map(safeThreadId).filter(Boolean)
  const failedIds = (committed?.threadsFailed || []).map(safeThreadId).filter(Boolean)
  rounds.push({
    round,
    unresolved: count,
    fanOut: threads.length,
    committed: !!committed?.committed,
    commitSha: committed?.commitSha,
    pushed: !!committed?.pushed,
    resolved: resolvedIds,
    failed: failedIds,
    blocked: resolutions.filter((r) => r.status === 'cannot-resolve').map((r) => safeThreadId(r.threadId)),
    resolvers: resolutions.map((r) => ({ threadId: safeThreadId(r.threadId), status: r.status, summary: r.summary, filesChanged: r.filesChanged })),
  })
  log(`Round ${round}: ${resolvedIds.length} thread(s) resolved, ${failedIds.length} failed${committed?.pushed ? ', pushed' : ''}.`)

  lastUnresolvedCount = count

  // Verification is the re-fetch at the TOP of the next iteration (under the
  // 'Analyze' phase) — loop-until-dry. No separate Verify phase: it would be an
  // empty marker around only the round-cap check below.
  if (round === maxRounds) {
    stopReason = `round cap (${maxRounds}) reached; a final re-fetch was not run — re-invoke to confirm dry.`
    log(`⚠ ${stopReason}`)
  }
}

// ---------------------------------------------------------------------------
// Summary.
// ---------------------------------------------------------------------------
const allResolved = rounds.flatMap((r) => r.resolved || [])
const allFailed = rounds.flatMap((r) => r.failed || [])
const allBlocked = rounds.flatMap((r) => r.blocked || [])
const lastRound = rounds[rounds.length - 1]
const dry = stopReason === 'dry — zero unresolved threads.'

const report = {
  pr: prNumber ? `PR #${prNumber}` : prClause,
  dry,
  stopReason: stopReason || 'loop completed',
  roundsRun: rounds.length,
  maxRounds,
  fanOutCap: maxComments,
  confirmed,
  budget: { total: budget.total, spent: budget.spent() },
  totals: {
    threadsResolved: allResolved.length,
    threadsFailed: allFailed.length,
    threadsBlocked: allBlocked.length,
    unresolvedRemaining: dry ? 0 : lastRound && !lastRound.gated && !lastRound.noProgress ? null : lastRound?.unresolved ?? null,
  },
  rounds,
}

log(
  `Done: ${rounds.length} round(s), ${allResolved.length} thread(s) resolved, ` +
    `${allFailed.length} failed, ${allBlocked.length} blocked. ${dry ? 'PR is dry.' : `Stopped: ${report.stopReason}`}`,
)

return report
