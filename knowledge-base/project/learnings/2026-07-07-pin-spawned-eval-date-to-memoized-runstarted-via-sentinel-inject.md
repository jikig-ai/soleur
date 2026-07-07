---
title: "Pin a spawned-eval-derived date to the handler's memoized runStartedAt via a {{SENTINEL}} + inject helper, guarded by a discovery-based drift test"
date: 2026-07-07
category: integration-issues
module: apps/web-platform/server/inngest/functions
tags: [cron, inngest, dedup, determinism, drift-guard, prompt-injection-substitution]
issue: 6143
pr: 6149
---

# Learning: pin an eval-computed date to the handler clock so title-date == dedup-key byte-identically

## Problem

The "always-create digest" Inngest cron cohort (9 handlers calling `digestIssueExistsForDate`) each
files a GitHub issue titled `[Scheduled] <task> - <date>`. The code-level same-date dedup key was
`runStartedAt.slice(0,10)` (host UTC, captured in the handler via a memoized
`step.run("run-started-at")`), but the issue-TITLE date was computed by the **spawned Claude eval from
its own container clock**. Across a UTC-midnight boundary the two could diverge, so
`isRealScheduledDigest`'s exact-title match (`title === ${titlePrefix} ${date}${titleSuffix}`) could
MISS (→ duplicate digest) or OVER-suppress (→ missed digest). Separately, `cron-community-monitor`
carried a redundant prompt-level "DEDUP RULE" (24h `gh issue list` → comment-and-exit) that produced
NO dated digest on the comment path and could self-perpetuate a FAILED-fallback stub.

## Solution

**Two coupled fixes, one PR (they must ship atomically — Part 1's removal exposes the skew Part 2 closes):**

1. **Removed the redundant prompt DEDUP RULE** from `cron-community-monitor.ts` (3 literal locations:
   a SHAPE-DIFF header comment, the prompt block, and a `#5751` code comment reworded), relying purely
   on the code-level same-date dedup (`digestIssueExistsForDate`, runs before the eval spawns) +
   `{ scope: "fn", limit: 1 }` serialization. The stale `_cron-shared.ts` comment about the
   `verifyScheduledIssueCreated` `updated_at`/`since` filter was **re-pointed** (not the filter — the
   filter is KEPT) to `cron-campaign-calendar`'s comment-bump path, which is now the SOLE consumer that
   needs `updated_at` crediting. A `cron-shared.test.ts` coupling-invariant assertion (anchored on the
   behavior-bearing prompt directive `Do NOT create a new issue`, NOT a source comment) test-enforces
   this: if campaign-calendar's comment-bump path is ever removed, the test reddens and tells the next
   engineer the filter is now tightenable to `created_at`.

2. **Pinned the title date** across all 9 crons: a distinctive `{{RUN_DATE}}` sentinel at each prompt's
   issue-title date position + a thin shared `injectRunDate(prompt, runStartedAt)` helper (in
   `_cron-shared.ts`) applied at each `spawnClaudeEval` call site. Because the injected date and the
   dedup key **both read the same `step.run("run-started-at")`-memoized `runStartedAt`**, they are
   byte-identical by construction, replay/retry-stable. `injectRunDate` **throws** if the sentinel is
   absent so a forgotten wiring is loud.

## Key Insight

- **When a spawned agent/subprocess computes a value that a parent gate compares against, don't let the
  child self-derive it — inject the parent's already-decided value.** Here the parent (handler) owns the
  authoritative `runStartedAt`; the eval must not re-derive the date from its own clock. A `{{SENTINEL}}`
  in a static prompt const + a substitution helper at the spawn edge is the minimal mechanism (not a
  prompt-builder refactor). Pin ONLY the value the gate keys on (the issue TITLE date) — leave secondary
  agent-derived dates (digest FILE names, `publish_date` frontmatter, audit-report paths) alone; pinning
  them would perturb unrelated consumers for a cosmetic gain.
- **Guard a cohort-wide convention with a DISCOVERY-BASED drift test, never a hardcoded path array.**
  `readdirSync(FUNCTIONS_DIR).filter(f => f.startsWith("cron-") && …includes("digestIssueExistsForDate"))`
  then assert each discovered file contains both `{{RUN_DATE}}` and `injectRunDate(`. A future digest
  cron that lands without the pin fails immediately; a hardcoded 9-path array would let cron #10 escape
  silently. (Precedent: `sentry-monitor-iac-parity.test.ts`.)
- **Make the injector fail LOUD (throw on missing sentinel)** so the failure surfaces at the CI
  drift-guard first and the runtime handler's red heartbeat second — never a silent literal-`{{RUN_DATE}}`
  title that defeats both dedup and output-verification.
- **Anchor test coupling-invariants on behavior-bearing tokens (prompt directives, config values),
  never on explanatory source comments** — a comment reword should not false-red a coupling test.
- **A byte-identity claim between two derived values is only true if they read the SAME source.** Verify
  both consumers slice the same memoized variable in every handler (grep the capture-site line vs the
  consumer-site line per file); a second independent `new Date()` would re-introduce the drift.

## Session Errors

**1. Over-edit then self-correct of the prompt deletion** — Recovery: reverted an editorializing
replacement sentence back to a clean single-block deletion before any commit, to honor the plan's
"single-block deletion" intent. Prevention: when a plan prescribes a pure deletion, delete exactly that
block; do not backfill explanatory prose the plan didn't ask for (the code-level dedup already documents
itself). One-off, self-caught within the edit cycle.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest/functions
