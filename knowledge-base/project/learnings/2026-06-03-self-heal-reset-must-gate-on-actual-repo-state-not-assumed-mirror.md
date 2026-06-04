# Learning: a destructive git self-heal must gate on ACTUAL repo state, not an assumed "mirror" invariant

## Problem

An Owner's platform Knowledge Base view was stale — a post-mortem merged to
`origin/main` (PR #4846) was absent from the platform server's workspace clone.
Two root causes: (1) PR #4810's nav refactor removed the only manual "Sync now"
affordance (it lived solely in `KbContentHeader`, mounted only on the file-open
route), and (2) `syncWorkspace`'s `git pull --ff-only` silently mislabels a
diverged (non-fast-forward) clone as `sync_failed` and never recovers — the
`ERROR_CLASS_NON_FAST_FORWARD` constant existed and was fixtured in tests but
had **no producer**.

The first-draft fix for (2) proposed a blind `git reset --hard origin/<default>`
self-heal, justified by the premise "the workspace clone is a READ-ONLY mirror,
so a reset only discards phantom drift."

## Solution

**The "read-only mirror" premise was FALSE** (caught by deepen-plan's
verify-the-negative pass). `server/session-sync.ts` (`syncPull`/`syncPush`, via
`agent-runner.ts`) auto-commits + pushes `knowledge-base/**` agent-session work
into the SAME clone — so it legitimately holds un-pushed local commits. A blind
`reset --hard` would destroy that work (a per-user trust-ending event).

The self-heal was gated on actual repo state, reusing the existing
`hasLocalCommits` probe shape (`session-sync.ts:200-208`):

```ts
const localCommits = parseInt(revListOut.toString().trim(), 10); // git rev-list --count @{u}..HEAD
if (Number.isNaN(localCommits) || localCommits > 0) {
  // real un-pushed work OR unparseable count → ABORT, never reset (fail-safe)
  return { ok: false, error, errorClass: "non_fast_forward" };
}
await git(["reset", "--hard", `origin/${defaultBranch}`]); // only when count === 0
return { ok: true, recovered: true };
```

Default branch is resolved (`git symbolic-ref --short refs/remotes/origin/HEAD`),
never assumed `main`. Both branches are observable (Sentry: `op:self-heal-reset`
warn on success, `op:self-heal-aborted-dirty`/`op:self-heal-failed` fail_loud on
abort/error), and payloads omit `workspacePath` (raw userId).

## Key Insight

When a fix's safety argument rests on an invariant about a shared resource ("X is
read-only", "Y is append-only", "Z is never concurrently written"), **grep for
the writers before trusting it** — a sibling subsystem often violates it. Then
make the destructive operation gate on the *runtime* state that proves the
invariant holds right now (a `rev-list` count), and **fail-safe on ambiguity**:
`NaN || > 0 → abort`, never `=== expected → proceed-by-default`. The guard must
compute one mechanical boolean, not rely on the prose claim.

Corollary: a constant that is defined + fixtured but has no producer (grep for
its assignment sites) is a latent bug — ship the producer regardless of whether
the current incident needs it.

## Session Errors

1. **Supabase MCP OAuth never surfaced query tools** — browser showed
   "successful" twice but `execute_sql`/`list_projects` never registered;
   `complete_authentication` reported "no flow in progress" (the loopback
   listener auto-consumed the code). **Recovery:** pivoted off the live trace
   per the plan's decision gate. **Prevention:** treat Supabase MCP tool
   registration as externally flaky; do not block a user on it — fall back to
   Doppler `DATABASE_URL_POOLER` (per /work) or scope the work to not require
   the live read, and say so.
2. **`security-sentinel` review agent stream-idle timeout** (0 tokens).
   **Recovery:** inline fallback review per the review skill's Rate-Limit
   Fallback gate. **Prevention:** already covered by that gate; batch-spawn
   review agents in one message to reduce per-agent stall exposure.
3. **deepen-plan parallel Task subagents unavailable** in the planning
   subagent's tool set → ran inline. **Recovery/Prevention:** no functional
   impact; a nested subagent cannot itself spawn subagents — expect inline
   execution of deepen's research/review passes when running under a Task agent.
4. **Runtime `session-sync` import dragged `createChildLogger` into
   `kb-route-helpers`' test-mock surface** → 4 route tests failed at collection.
   **Recovery:** switched to a `import type { KbSyncErrorClass }` type-only
   import + locally-declared literal members (commit `b8dda26b`).
   **Prevention:** when reusing a shared union/constant from a heavy server
   module into a deliberately test-decoupled module, import the TYPE only and
   re-declare the literal members typed by the union — a runtime import drags
   the source module's module-init into every consumer's mock surface.
5. **Pencil `batch_design` format errors** (forwarded from planning) — JSON
   instead of the `I()/U()/C()` DSL, and copied-node descendant ID mismatch.
   **Recovery:** read the schema + `snapshot_layout` for real generated IDs.

## Tags
category: bug-fixes
module: apps/web-platform/server/kb-route-helpers.ts
related_prs: 4810, 4846, 2244
