---
title: "fix: follow-through monitor closes timed-out issues as not-planned, not completed"
issue: 6132
branch: feat-one-shot-6132-followthrough-notplanned-close
type: bug
lane: single-domain
brand_survival_threshold: aggregate pattern
created: 2026-07-07
---

# 🐛 fix: follow-through monitor closes timed-out issues as not-planned (#6132)

## Enhancement Summary

**Deepened on:** 2026-07-07

**Key improvements from the deepen pass:**
1. **AC determinism fix.** The verify-negative pass found that AC1/AC3 originally
   counted the literal `not planned`, which the planned Sharp-Edges clarifier line
   (added inside the prompt) would also contain — making the count
   non-deterministic. AC1 now counts the exact `<number>`-command form; AC3 is
   asserted by the region-scoped T9 test (Guard A slice), not a raw grep. Phase 1
   now forbids the Guard A comment / Sharp Edges clarifier from reproducing the
   exact command string.
2. **CLI form verified live** (Verify-the-command gate): `gh issue close --help`
   → `-r, --reason string   Reason for closing: {completed|not planned|duplicate}`
   with example `gh issue close 123 --reason "not planned"` (verified 2026-07-07).
   The prompt embeds this agent-facing CLI form, so the token is pinned.
3. **Precedent-diff (Phase 4.4).** Sibling give-up cron
   `cron-stale-deferred-scope-outs.ts:299` already records give-up closes as
   `state_reason: "not_planned"` (via octokit). This plan uses the CLI equivalent
   `--reason "not planned"` because the follow-through monitor closes through the
   agent's `gh` verbs, not octokit — same semantic, different (already-allowlisted)
   mechanism. No novel pattern.
4. **allowlist no-op confirmed.** `git grep` confirms `--add-label` appears
   exactly once (old Guard C step 1, being removed); `Bash(gh issue close:*)` +
   `Bash(gh issue edit:*)` already cover the new verbs — no `--allowedTools` change.

**Halt gates:** 4.6 User-Brand Impact (present, threshold `aggregate pattern`),
4.7 Observability (present, 5 fields, no-SSH discoverability test), 4.8 PAT-shaped
var (none), 4.9 UI wireframe (no UI surface) — all pass.

## Overview

The follow-through monitor's Guard C ("MAX POLLING EXCEEDED") closes a timed-out
(never-verified) follow-through issue with a **bare `gh issue close`**, which the
GitHub CLI records as `state_reason: COMPLETED`. So an issue the automation is
*giving up on* is recorded as **done** — while still carrying the
`needs-attention` label Guard C just applied. A 2026-07-07 audit found **73
issues** in this contradictory state (closed COMPLETED + `needs-attention`
present + a "Maximum polling period reached" give-up comment posted 2–4s
before the close).

**This is a recurrence-prevention change only.** The 73 pre-existing issues were
already drained in the 2026-07-07 audit (22 reopened, 35 reclassified
COMPLETED→NOT_PLANNED, 16 left legitimately-closed, `needs-attention` stripped
from all 51 that stayed closed). This plan changes only the monitor prompt so
the bug cannot recur.

**The fix is a single-file prompt edit** to the `FOLLOW_THROUGH_PROMPT` string
in `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`,
plus test assertions. No TS control-flow, no infra, no schema, no allowlist
changes.

## Research Reconciliation — Issue Body vs. Codebase

The issue body contains a **factually wrong** premise that was verified false
during routing. The PR description MUST correct it.

| Issue-body claim | Reality (verified) | Plan response |
|---|---|---|
| "The monitor is **not in this repo** … runs in the external `soleur-ai` GitHub App / bot backend. This issue tracks the fix there." | The monitor IS an in-repo Inngest cron function. `git grep "Maximum polling period reached"` → `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts:166`. The strings "business days" and "manual intervention required" also live in that file's `FOLLOW_THROUGH_PROMPT`. `soleur-ai[bot]` is the GitHub App identity the in-repo cron authenticates as (mints an installation token, `buildSpawnEnv` injects it as `GH_TOKEN`). | Fix in-repo. Correct the "not in this repo / fix in the bot service" framing in the PR body. |
| "Proposed fix (in the bot service)" | No bot service; the close is emitted by the agent driven by the in-repo prompt (Guard C step 3: `gh issue close <number>`). | Change Guard C's close in the prompt. |
| Bug at "the bot backend" | Bug at `cron-follow-through-monitor.ts` lines 161–170 (Guard C ordering: add-label → comment → **bare close**). | Rewrite Guard C. |

**Premise validation (Phase 0.6):** Cited `#6132` is OPEN (`gh issue view 6132`
→ `state: OPEN`, `type/bug`, `priority/p2-medium`, milestone `Post-MVP / Later`).
Cited file/symbol paths all confirmed on the worktree. Sibling precedent
`cron-stale-deferred-scope-outs.ts:299` already closes give-up issues with
`state_reason: "not_planned"` (via octokit) — confirms `not_planned` is the
established codebase semantic for "automation is giving up." CLI form verified:
`gh issue close --help` → `-r, --reason string   Reason for closing:
{completed|not planned|duplicate}` and example `gh issue close 123 --reason
"not planned"` (verified 2026-07-07).

## User-Brand Impact

**If this lands broken, the user experiences:** every timed-out follow-through
issue continues to be recorded as `state_reason: COMPLETED` — a false "done"
signal on post-deploy verifications, prod spot-checks, secret rotations, and
GDPR/compliance follow-throughs that never actually ran. Any metric or audit
that trusts `state_reason` silently overcounts completed work, and
`needs-attention` keeps appearing on closed issues (making the label meaningless).

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this
change corrects an issue's `state_reason` bookkeeping and a label; it touches no
data-processing path, no secret, and no external data-movement surface. There is
no data-exposure vector.

- **Brand-survival threshold:** aggregate pattern — the harm is corpus-wide
audit/metric integrity that accumulates across every timed-out follow-through,
not a single-user data-exposure incident. (The underlying "was the secret
rotated / was erasure verified" facts are unaffected by the label; the bug
degrades the bookkeeping signal, and the human audit/triage remains the control
for any specific un-done item.)

## Design Decision — one coherent close semantic

The task offered two options (close-as-not-planned + strip label, OR leave open
for triage). **Chosen: close as `not planned` AND strip `needs-attention` before
the close.** Rationale:

- It matches the issue author's own primary proposed fix ("Close with
  `state_reason: not_planned` … Remove the `needs-attention` label on close").
- It matches the sibling give-up cron (`cron-stale-deferred-scope-outs.ts`)
  which closes as `not_planned`.
- "Leave open" would leave every timed-out issue accumulating in the open
  `follow-through` corpus forever (re-listed each run), and would not produce a
  close-reason to assert on (the task's step 5 requires asserting the
  close-reason on the timeout path).
- Guard A (predicate PASSES → auto-close) **stays a plain COMPLETED close** —
  a bare `gh issue close` defaults to COMPLETED, which is correct there.

**Invariant established:** `needs-attention` only ever lives on OPEN issues.
Guard B adds it (issue stays open). Guard C strips it **before** closing.

**Label-strip is ordered BEFORE the close** (not after) so a mid-transition
crash can only ever leave the issue OPEN-with-`needs-attention` (a valid state
for the invariant), never CLOSED-with-`needs-attention` (the exact bug shape).

## Implementation Phases

### Phase 1 — Rewrite Guard C in `FOLLOW_THROUGH_PROMPT`

File: `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`
(the `MAX POLLING EXCEEDED (30 business days) — Guard C` block, currently
lines ~161–170).

Replace the current ordering:

```
(1) gh issue edit <number> --add-label "needs-attention"
(2) gh issue comment <number> --body "Maximum polling period reached ..."
(3) gh issue close <number>                         ← BARE close = COMPLETED (bug)
```

with:

```
- MAX POLLING EXCEEDED (30 business days) — Guard C (idempotent
  max-polling-close-as-not-planned):
  First run `gh issue view <number> --json comments,state,labels --jq
  '{comments: .comments, state: .state, labels: .labels}'` and skip this
  transition if any existing comment starts with "Maximum polling ".
  Otherwise: ORDERING IS LOAD-BEARING — perform in this exact order:
  (1) `gh issue comment <number> --body "Maximum polling period reached (30
      business days). Stopping automated monitoring. @[author login] — manual
      intervention required."` (durable audit record — post FIRST).
  (2) If the `needs-attention` label is present (from the labels fetched
      above), `gh issue edit <number> --remove-label "needs-attention"` — strip
      the now-misleading label BEFORE closing so `needs-attention` never
      persists on a closed issue.
  (3) `gh issue close <number> --reason "not planned"` — this is a timed-out,
      never-verified issue: record it as NOT completed. NEVER a bare `gh issue
      close` here (a bare close defaults to state_reason COMPLETED, the exact
      #6132 bug); NEVER `--reason "completed"` on this timeout path.
  If (1) fails, do NOT proceed to (2)/(3) — the issue stays open and a future
  run retries the full transition. Torn-write recovery: if state is "closed"
  but no "Maximum polling " comment exists, post the comment now (the close
  succeeded but the comment was lost); and if `needs-attention` is still
  present on that closed issue, remove it.
```

Key deltas:
- The old step (1) `--add-label "needs-attention"` is **removed** (adding then
  stripping the same label within one guard is contradictory; and Guard B
  already applied it in a prior run — by 30 business days SLA is always
  exceeded, so `needs-attention` is present when Guard C fires).
- New step: conditional `--remove-label "needs-attention"` **before** close.
- Close now carries `--reason "not planned"`.
- The guard's view `--jq` already fetches `labels` (unchanged — it was added
  earlier for the label check), so the agent can condition the remove on
  presence with no extra API call shape.
- Idempotency guard ("skip if a comment starts with 'Maximum polling '")
  **unchanged**. Torn-write recovery kept, minimally extended to also strip a
  residual `needs-attention` on the recovered closed issue.

**Do NOT touch Guard A or Guard B.** Guard A's `gh issue close <number>` (after
the "Verified: … Auto-closing." comment) stays a bare/COMPLETED close — that is
the predicate-PASSES path and COMPLETED is correct. Add a one-line inline
comment near Guard A clarifying the bare close is intentionally COMPLETED (to
prevent a future "consistency" edit from giving it the timeout reason). **The
Guard A comment MUST NOT reproduce the exact command string `gh issue close
<number> --reason "not planned"`** — phrase it as prose ("stays a bare close =
COMPLETED; the timeout give-up path is the only not-planned close") so AC1's
count of the exact command form stays deterministic (1).

Also update the prompt's `## Sharp Edges` "NEVER close issues unless a predicate
passes or 30 business day max is exceeded." bullet region with a one-line
clarifier: predicate-pass closes are COMPLETED (bare close); the max-polling
give-up close is not-planned. This clarifier is prose (it may say the words "not
planned") but MUST NOT reproduce the exact `gh issue close <number> --reason
"not planned"` command form — again to keep AC1 deterministic.

### Phase 2 — `--allowedTools` verification (no change expected)

Confirm the agent's `--allowedTools` (line ~252,
`CLAUDE_CODE_FLAGS`) already permits the new verbs:

- `gh issue close <n> --reason "not planned"` → covered by
  `Bash(gh issue close:*)`.
- `gh issue edit <n> --remove-label "needs-attention"` → covered by
  `Bash(gh issue edit:*)`.

Both `Bash(gh issue close:*)` and `Bash(gh issue edit:*)` are already in the
allowlist. **No `--allowedTools` change is needed.** The plan records this
as a verified no-op (not a silent omission). The prompt↔flags "single agent
contract" note in the file (lines 103–105) is satisfied because the prompt only
adds new *flags/arguments* to already-allowlisted verbs, not new verbs.

### Phase 3 — Tests (`cron-follow-through-monitor.test.ts`)

The existing suite is handler-level and reaches the prompt via the claude spawn
args (`claudeArgs[lastIdx]`, as T1 already does for "Pre-Validated Predicate
Results"). To assert Guard-scoped content cleanly, **export
`FOLLOW_THROUGH_PROMPT`** from the SUT (consistent with the file's existing
"export for test parity" convention — `CLAUDE_CODE_FLAGS`,
`MAX_TURN_DURATION_MS`, `KILL_ESCALATION_MS` are already exported for tests).

Add a describe block `T9 — Guard C not-planned close semantics (#6132)` that
imports `FOLLOW_THROUGH_PROMPT`, slices the Guard C region (from the
`MAX POLLING EXCEEDED` anchor to the `WITHIN SLA, NO STATE CHANGE` anchor) and
the Guard A region (from `PREDICATE PASSES` anchor to `SLA EXCEEDED` anchor),
and asserts:

- Guard C region **contains** `gh issue close <number> --reason "not planned"`.
- Guard C region **contains** `--remove-label "needs-attention"`.
- Guard C region **does NOT contain** `--add-label` (old contradictory step
  gone; `--add-label` appears nowhere else in the prompt — verified by
  `git grep -n "add-label"`).
- Guard A region **contains** `gh issue close <number>` and **does NOT contain**
  `not planned` (predicate-pass close stays COMPLETED).

Verify the runner + path: `apps/web-platform/test/server/inngest/` matches
`vitest.config.ts` `include: test/**/*.test.ts`. Run with
`cd apps/web-platform && ./node_modules/.bin/vitest run
test/server/inngest/cron-follow-through-monitor.test.ts` (NOT `npm run -w …`;
NOT `bun test`). Typecheck with `cd apps/web-platform && ./node_modules/.bin/tsc
--noEmit`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `FOLLOW_THROUGH_PROMPT` Guard C closes with `--reason "not planned"`:
  `git grep -c 'gh issue close <number> --reason "not planned"'
  apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`
  returns `1`. (The exact `<number>`-command form appears only at Guard C step 3;
  the Guard A inline comment and the Sharp Edges clarifier MUST NOT reproduce
  this exact command string — see AC3 note.)
- [x] AC2 — Guard C strips the label before close: the Guard C region contains
  `gh issue edit <number> --remove-label "needs-attention"` AND the region no
  longer contains `--add-label` (`git grep -c 'add-label' <file>` returns `0` —
  verified pre-fix count is `1`, at the old Guard C step 1).
- [x] AC3 — Guard A unchanged / stays COMPLETED: asserted by the T9 test's
  region slice — the Guard A region (anchors `PREDICATE PASSES` →
  `SLA EXCEEDED (first time`) contains `gh issue close <number>` with **no**
  `--reason` token, and the only `--reason "not planned"` occurrence in the
  prompt falls inside the Guard C region (anchors `MAX POLLING EXCEEDED` →
  `WITHIN SLA, NO STATE CHANGE`). Do NOT use a bare `git grep -c 'not planned'`
  count as the gate — the Sharp Edges clarifier line legitimately contains the
  words "not planned" in prose, so a raw count is non-deterministic; the
  region-scoped test is the canonical assertion.
- [x] AC4 — No `--allowedTools` change: the `CLAUDE_CODE_FLAGS` `--allowedTools`
  value still contains `Bash(gh issue close:*)` and `Bash(gh issue edit:*)` and
  is otherwise byte-identical to `main` (verify via `git diff main -- <file>`
  showing no change to the `--allowedTools` line).
- [x] AC5 — New `T9` test block asserts the not-planned reason, the label
  removal, the absence of `--add-label` in Guard C, and Guard A staying
  reason-less. `vitest run test/server/inngest/cron-follow-through-monitor.test.ts`
  is green (all pre-existing T1–T8 tests still pass).
- [x] AC6 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
  (the new `export const FOLLOW_THROUGH_PROMPT` is well-typed).
- [ ] AC7 — PR body corrects the issue's "not in this repo / fix in the bot
  service" framing (states the monitor is the in-repo Inngest cron and the fix
  lands there). Use `Closes #6132` in the PR body.

### Post-merge (operator)

- [ ] AC8 — After the next weekday 09:00 fire (or a manual
  `inngest send cron/follow-through-monitor.manual-trigger`), the discoverability
  query below returns zero rows (no follow-through issue closed COMPLETED while
  carrying `needs-attention`). Automatable via `gh` — see Observability.
  `Automation: inline gh query, no SSH.`

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in for monitor slug "scheduled-follow-through"
        (postSentryHeartbeat at end of handler — unchanged by this PR)
  cadence: weekdays 09:00 (cron "0 9 * * 1-5")
  alert_target: Sentry cron monitor (apps/web-platform/infra/sentry/cron-monitors.tf)
  configured_in: cron-follow-through-monitor.ts SENTRY_MONITOR_SLUG
error_reporting:
  destination: Sentry via reportSilentFallback (existing, unchanged — mint/
               ensure-labels/validate-predicates/claude-eval error paths)
  fail_loud: true
failure_modes:
  - mode: Guard C regresses to COMPLETED close (this bug recurs)
    detection: gh query — a follow-through issue closed with state_reason
               COMPLETED while carrying needs-attention
    alert_route: post-merge discoverability_test (AC8); no new runtime alert
                 needed (behavior lives in the agent prompt, not a TS branch)
  - mode: gh issue edit --remove-label fails (label absent / transient 5xx)
    detection: the agent Sharp Edge "if gh commands fail for an issue, skip it
               and continue" handles it; the close still records not-planned
    alert_route: none new — non-fatal, next run reconciles
logs:
  where: Inngest run logs + Sentry (existing)
  retention: Sentry default
discoverability_test:
  command: >
    gh issue list --repo jikig-ai/soleur --state closed --label follow-through
    --search "reason:completed label:needs-attention" --json number,stateReason
    --jq 'length'
  expected_output: "0  (no follow-through issue closed COMPLETED while carrying needs-attention)"
```

No new TS error path, log call, or failure mode is introduced (the change is
confined to the agent-instruction string). The behavioral change is verifiable
entirely via the GitHub API — no SSH.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling bug fix on an existing agent-prompt surface. No
user-facing UI surface (Files to Edit: one server `.ts` + one test `.ts`; no
path matches the UI-surface globs, so the mechanical Product override does not
fire → Product NONE). No cross-domain implication for recurrence-prevention.
(The compliance angle — 22 of 73 were real un-done work — was handled by the
already-completed 2026-07-07 audit, out of scope here.)

## Architecture Decision (ADR/C4)

None — this is a bug fix on an existing surface (an agent-prompt close verb).
ADR-033 invariants I1–I6 (cron substrate) are untouched; no ownership/tenancy,
substrate, or trust-boundary change. No engineer reading the existing ADR corpus
+ C4 would be misled about the system after this ships. No external actor,
external system, or data store changes. C4 gate skipped (no architectural
decision).

## Sharp Edges

- The fix is a **string edit to an LLM agent prompt**, not deterministic code.
  The tests assert the *instruction text* (via the exported prompt / spawn
  args), which is the strongest available guard — they cannot execute the agent.
  Runtime correctness is confirmed post-merge via the AC8 discoverability query.
- `gh issue edit --remove-label X` errors (HTTP 422/404) if `X` is not present.
  Guard C conditions the remove on the label being present (fetched in the
  guard's `--json ...,labels` view), and the prompt's existing "if gh commands
  fail for an issue, skip it and continue" Sharp Edge covers the residual case.
- Ordering is load-bearing: comment FIRST (durable audit), then remove-label,
  then close. Removing the label **before** close guarantees a crash can only
  leave the issue OPEN-with-`needs-attention` (valid), never
  CLOSED-with-`needs-attention` (the bug).
- Residual torn-write window: if the agent posts the "Maximum polling " comment
  then crashes before closing, the idempotency guard (skip-if-comment-exists)
  will skip on the next run, leaving the issue OPEN with the comment. This is a
  pre-existing property of the comment-first idempotency design (not introduced
  here) and is a *safe* residual — the issue is open, `needs-attention` may
  still be present (valid on OPEN), and a human sees "manual intervention
  required." Not expanding the idempotency semantics (task: keep intact).
- A `## User-Brand Impact` section that is empty or placeholder fails
  deepen-plan Phase 4.6 — this one is filled with a concrete artifact, a
  non-applicable exposure vector, and an `aggregate pattern` threshold.
- Do not "consistency"-edit Guard A to also use `--reason "not planned"` — its
  COMPLETED close is correct (predicate passed). The inline comment added near
  Guard A in Phase 1 documents this.

## Open Code-Review Overlap

None — no open `code-review`-labelled issue references
`cron-follow-through-monitor.ts` or its test (single-file bug fix).
