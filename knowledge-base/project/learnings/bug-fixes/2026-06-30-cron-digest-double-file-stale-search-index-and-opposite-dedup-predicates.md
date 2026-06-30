# Learning: a cron's in-prompt dedup read the STALE GitHub *search* index, not the fresh *LIST* index — and producer-vs-audit dedup need OPPOSITE predicates over a byte-identical title

category: bug-fixes
module: inngest-cron-substrate / cron-community-monitor
date: 2026-06-30
refs: #5751, #5732, #5728; runbook cloud-scheduled-tasks.md H11

## Problem

`cron-community-monitor` filed **two** `[Scheduled] Community Monitor - <date>` digest
issues per day (`#5737`+`#5740`, `#5596`+`#5597`, `#5592`+`#5593`), ~1.5–3.5 min apart,
same title + `scheduled-community-monitor` label, but slightly different content.

The issue body (and the orchestrator's first hypothesis) blamed the handler's
`ensureScheduledAuditIssue` audit fallback firing despite `heartbeatOk`. **Phase 0
falsified that**: pulling `#5737`/`#5740` directly showed BOTH are full eval-generated
**digests** (live `## Platform Status`/metrics), not the hardcoded `Automated FAILED
self-report` audit body. And the audit fallback has a same-title dedup, so it never
double-files anyway. The real defect: the **eval digest producer ran twice** (H-A:
multiple serialized invocations — on 06-30 both 07:04/07:08 issues predate the 08:00
cron, i.e. two operator manual-triggers), and the only guard — the in-prompt `DEDUP
RULE` — was unreliable (H-C).

## Solution / Key Insight

**The in-prompt dedup read the wrong GitHub index.** The prompt's `DEDUP RULE` used
`gh issue list --search 'Community Monitor in:title'` — GitHub's **search index** lags
the primary store by minutes to tens of minutes. So a second invocation 1–4 min after
the first did not see the first's just-created issue and filed a duplicate. The fix:
switch the dedup to the **LIST endpoint** (`GET /issues?labels=…&sort=created&desc`),
which hits the **fresh primary index**, and move the load-bearing guard out of the
non-deterministic LLM prompt into a **handler-side `step.run` dedup** keyed on
`runStartedAt.slice(0,10)` — reliable because `concurrency:{scope:"fn",limit:1}`
serializes the invocations, so invocation #2's LIST read runs after #1's create.

**Three reusable rules:**

1. **For "did a recent sibling write land yet?" dedup, never read the search index —
   read the LIST/primary endpoint.** A `--search`/`in:title` query is eventual-consistent
   and silently stale within the few-minutes window that duplicate-detection cares about.
   This is the same family as the #5732 lesson "verify cron recovery by the digest issue,
   not the routine_runs row" — trust the fresh primary source, not a lagging derived index.

2. **A producer dedup and an audit-fallback dedup over a BYTE-IDENTICAL title need
   OPPOSITE predicates — keep them separate.** Both file `[Scheduled] Community Monitor -
   <date>`. The audit dedup must **count** a FAILED stub (avoid double-auditing); the
   producer dedup must **exclude** it (a stub must not suppress a same-day real digest →
   zero-digest). Collapsing them into "one shared read" (the plan's tempting suggestion)
   would break one caller. The only discriminator is the **body** (`Automated FAILED
   self-report`) — so single-source that literal as a shared constant, or a reword silently
   breaks stub-exclusion → zero digests (caught at review, 2 agents converged).

3. **Match a real digest with a POSITIVE full-title anchor, not `endsWith(date)`.** A loose
   `title.endsWith(date)` matches any coincidental issue ending in today's date
   (`Investigate community drop 2026-06-30`) → suppresses the genuine digest. An exact
   `title === \`${PREFIX} ${date}\`` is **fail-open on title drift** (worst case a duplicate
   paper-cut, never zero-digest) — the correct direction for the dangerous axis.

## Why it matters

The dangerous failure mode of a dedup guard is OVER-suppression → ZERO digests (the only
community-health signal goes dark). Every design choice here is biased to fail-open:
LIST-read (fresh), fail-OPEN on a GitHub error, positive title anchor, body-based stub
exclusion. The regression test asserts the observable invariant (2 invocations → exactly
1 issue, through a fake octokit store), not a "dedup mock called once" proxy.

## Session Errors

1. **A full `vitest run test/server/inngest/` surfaced `cron-claude-eval-mcp-flags.test.ts`
   #5691 (`resolveClaudeBin` drift-guard) as failing** — Recovery: ran it in isolation
   (8/8 green), confirmed byte-identical to main + main CI green → pre-existing
   parallel-execution flake (the test's `git grep`/`execFileSync` from a `__dirname`-relative
   REPO_ROOT is sensitive to concurrent vitest workers in a worktree), NOT a #5751
   regression. Proceeded; CI is the authoritative gate. **Prevention:** when a full-directory
   run fails a test the diff doesn't touch, re-run it in isolation before treating it as a
   regression — same discriminator as the existing `nav-states`/`hook-test-on-worktree`
   flake learnings (isolation-green + main-CI-green + untouched-by-diff = pre-existing flake).

2. **An implementation subagent first read the main checkout** (absolute `apps/web-platform/`
   paths resolve to the bare/main tree, not the worktree) — Recovery: it self-caught and
   re-targeted the `.worktrees/` path before any edits; no wrong-tree writes. **Prevention:**
   already covered by the worktree-CWD class — subagents must `cd <worktree-abs-path>` and
   verify `pwd` before file ops (the one-shot planning-subagent template already mandates
   this CWD-verification first tool call).
