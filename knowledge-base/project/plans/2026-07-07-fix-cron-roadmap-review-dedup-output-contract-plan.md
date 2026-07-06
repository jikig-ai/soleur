---
title: "fix: cron-roadmap-review output-contract — remove prompt-level 6-day DEDUP RULE"
date: 2026-07-07
type: fix
branch: feat-one-shot-roadmap-review-dedup-output-contract
lane: single-domain
brand_survival_threshold: none
status: draft
---

# 🐛 fix: cron-roadmap-review output-contract — remove the prompt-level 6-day DEDUP RULE

## Enhancement Summary

**Deepened on:** 2026-07-07 · **Plan-review panel:** Kieran, DHH, code-simplicity (eng tier — `none` threshold).

### Key improvements applied
1. **Kieran F1 (blocking mechanical):** AC "surviving-anchors" check rewritten from a summed
   `grep -c` (which reads `6`, not `4`, because the header comment echoes three anchor literals)
   to per-anchor presence assertions.
2. **DHH #2 → deepen-plan Precedent-Diff reversal:** DHH proposed pinning the digest title date to
   `runStartedAt`; the Phase 4.4 precedent-diff gate showed all 7 cohort crons use a static prompt
   + agent-derived date (5 run with no backstop — the canonical pattern), so pinning roadmap alone
   would be a snowflake. **Reverted the pin; deferred cohort-wide.** Added a Precedent-Diff table.
3. **Files-to-Edit #3/#4 (code-simplicity confirmed):** the `_cron-shared.ts` citation re-point +
   `cron-shared.test.ts` fixture-label flip are kept inline — comment-accuracy fixes *forced* by
   the primary change, not scope creep.

### New considerations discovered
- The comment-and-exit path is **fragile, not deterministically RED** — `verifyScheduledIssueCreated`
  credits a dedup-comment via `updated_at` (Research Reconciliation row 1). The fix removes that
  fragility regardless.
- The cross-midnight-UTC skew is a **cohort-wide** property (deferral), not a roadmap-only bug.
- `cron-community-monitor` carries the identical DEDUP-RULE bug (sibling deferral).

### Deepen-plan gate status
4.6 User-Brand Impact ✅ · 4.7 Observability ✅ · 4.8 PAT-shaped ✅ · 4.9 UI-wireframe ✅ (no UI
surface — Files-to-Edit are `.ts` only) · 4.4 Precedent-Diff ✅ (drove the date-pin reversal).

## Overview

The `scheduled-roadmap-review` Better Stack / Sentry cron monitor goes RED (or produces no
weekly digest artifact) on manual / duplicate runs. The root cause is **two overlapping dedup
mechanisms** inside `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` that
fight the output-aware heartbeat contract:

1. **Code-level, correct (`dedup-digest-check`, lines 220–248):** calls
   `digestIssueExistsForDate({ date: runStartedAt.slice(0,10), titlePrefix: "[Scheduled] Weekly Roadmap Review -" })`
   — a **same-date** check. When a *real* digest already exists for TODAY it posts a green
   heartbeat and returns *before* spawning the eval. It excludes FAILED-fallback self-report
   stubs (via `isRealScheduledDigest`). This correctly handles "manual trigger fires the same
   day as the 09:00 Monday cron."

2. **Prompt-level, buggy (`ROADMAP_REVIEW_PROMPT` DEDUP RULE, lines 165–167 + the `## Output`
   wording at 169):** instructs the eval — *"If any `scheduled-roadmap-review` results from
   within the last 6 days exist, do NOT create a new issue. Instead, post your findings as a
   comment on the most recent existing issue and exit."*

The prompt's 6-day rule is the defect. When the eval takes the **comment-and-exit** path it
produces **no new dated `[Scheduled] Weekly Roadmap Review - <date>` digest** in the run window.
Two further defects compound it:
- **(a) prior-run-day match:** the 6-day window matches a *legitimate prior run's* digest (on
  2026-07-06 it matched the real 2026-06-30 digest, exactly 6 days prior), suppressing a
  genuinely-new run-day's digest.
- **(b) FAILED-fallback self-perpetuation:** the prompt's `gh issue list --label
  scheduled-roadmap-review --state all` does **not** distinguish a real digest from a
  FAILED-fallback self-report issue filed by `ensureScheduledAuditIssue` (which also carries the
  `scheduled-roadmap-review` label). A prior RED run's fallback issue therefore makes the next
  re-fire within 6 days comment-and-exit onto the fallback — self-perpetuating the missing-digest
  / RED state.

**The fix:** remove the prompt-level 6-day DEDUP RULE and the `## Output` "If no recent duplicate
exists…" preamble that depends on it; rely on the code-level **same-date** dedup which already
short-circuits genuine same-day duplicates with a green heartbeat before the eval spawns. This
brings roadmap-review into line with the 5 other always-create cohort crons (content-generator,
growth-audit, growth-execution, competitive-analysis, seo-aeo-audit) which carry **no**
comment-and-exit DEDUP RULE and rely purely on the code-level same-date dedup (see Precedent-Diff
below).

Net contract: **every distinct run-day that reaches the eval MUST create its dated digest**
(the monitor's check-in artifact); same-day manual+cron duplicates are handled code-side before
the eval spawns.

> **Deepen-plan precedent-diff reversal (DHH plan-review #2 vs. cohort precedent).** DHH proposed
> also *pinning* the digest title date to `runStartedAt` (injecting it into the prompt) to close a
> cross-midnight-UTC skew between the dedup key (`runStartedAt.slice(0,10)`, host UTC) and the
> agent-derived title date. The deepen-plan precedent-diff gate (Phase 4.4) then showed all **7
> cohort crons use a static prompt const + agent-derived title date** and **none** inject
> `runStartedAt`; the 5 always-create siblings run this way with no comment-and-exit backstop and
> that is the canonical, accepted pattern (#5786: "a duplicate paper-cut beats a missed digest").
> The cross-midnight skew is therefore a **cohort-wide pre-existing property**, not roadmap-
> specific, and pinning roadmap alone would make it a snowflake diverging from 7 siblings.
> **Decision: keep the narrow fix; defer the date-pin as a cohort-wide follow-up** (see Non-Goals).

**Scope:** ONLY the roadmap-review dedup/output-contract bug. Do NOT touch
`cron-content-generator` (verified: it carries zero DEDUP RULE). The June credit-exhaustion cause
of the monitor failures is separately tracked and resolved — out of scope here. The identical
prompt-DEDUP-RULE pattern in `cron-community-monitor` is a **sibling deferral** (see Non-Goals).

## Research Reconciliation — Spec vs. Codebase

The feature brief's stated failure mechanism needed one correction against the live code. It does
not change the fix, but it sharpens the "why" and adds one in-scope comment/test-accuracy edit.

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| Comment-and-exit path → `verify-output`/`resolveOutputAwareOk` returns `heartbeatOk=false` → terminal heartbeat `ok:false` (deterministic RED). | `verifyScheduledIssueCreated` (`_cron-shared.ts:699`) filters on **`updated_at >= runStartedAt`** (`since` param), and the comment at `:680–688` **explicitly credits a dedup-comment as valid output** — a comment bumps the existing issue's `updated_at` into the run window → green. So comment-and-exit is **fragile, not deterministically RED**: it stays green *iff* the LLM's comment actually lands on a `scheduled-roadmap-review`-labeled issue; it goes RED only when the comment fails/mis-places. **Either way it produces no dated digest artifact.** | Fix is unchanged and still correct — the real defect is "monitor color + digest presence made to depend on LLM comment-placement behavior instead of a deterministic dated artifact," plus defects (a)/(b) which are independent of verify-output. Reconciliation folded into Root Cause. |
| (implicit) `verifyScheduledIssueCreated`'s `updated_at` crediting exists *for* roadmap-review. | The `updated_at` crediting is shared and **still load-bearing for `cron-community-monitor`** (which retains its 24h DEDUP RULE). Only the *citation* ("roadmap-review's DEDUP RULE") in `_cron-shared.ts:680–688` and the rationale-comment + fixture label in `cron-shared.test.ts:230–245` become stale once roadmap loses its rule. | Do **not** remove the `updated_at` filter (community-monitor needs it). Re-point the stale citation/comment to `cron-community-monitor` and flip the `cron-shared.test.ts` fixture label to `scheduled-community-monitor` so the test rationale stays truthful. Behavior-preserving. |
| The requested new test ("a run reaching the eval always yields a dated digest (green); a same-date pre-existing digest short-circuits to a green heartbeat without spawning"). | This behavior is **already proven for roadmap-review** by `cron-cohort-dedup.test.ts` — AC1 (two serialized same-date invocations file exactly ONE digest, spawn called once), AC1b (skip path posts a GREEN heartbeat, does NOT execute `claude-eval` or `verify-output`), AC3 (a FAILED audit stub does not suppress the real digest). | Do NOT duplicate the behavioral cohort test. Instead add **regression-guard anchors** in `cron-roadmap-review.test.ts`: assert the removed DEDUP-RULE / comment-and-exit strings are **absent**, and assert the new unconditional `## Output` wording is **present**. The cohort suite remains the behavioral gate. |
| (implicit) The code-level same-date dedup fully guarantees "same-day handled code-side." | **Cross-midnight-UTC skew (DHH plan-review #2):** the dedup KEY is `runStartedAt.slice(0,10)` (host UTC date captured in Node at handler start, `cron-roadmap-review.ts:215–234`), but the digest TITLE date is **agent-derived** — `ROADMAP_REVIEW_PROMPT` is a static const (line 117) whose `## Output` "Title format: … YYYY-MM-DD" (line 170) injects nothing; the spawned claude computes "today" from its own container clock. When a run crosses UTC midnight the title date can differ from the key, so the same-date dedup can MISS (duplicate) or over-suppress. **However** the deepen-plan precedent-diff gate (Phase 4.4) showed this is a **cohort-wide property**: all 7 always-create cohort crons use a static prompt const + agent-derived title date + `digestIssueExistsForDate({date: runStartedAt.slice(0,10)})`, and the 5 without a DEDUP RULE run this way with no backstop (the accepted #5786 "paper-cut beats missed digest" baseline). | **Do NOT fold in (precedent-diff reversal).** Pinning roadmap alone makes it a snowflake diverging from 7 siblings; the skew is not created by this PR (removing the DEDUP RULE only aligns roadmap with the 5 backstop-free siblings). Defer as a **cohort-wide** follow-up (Non-Goals) alongside the community-monitor tracking issue. |

## Root Cause (verified 2026-07-06 / re-verified 2026-07-07)

- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts:165–167` — the DEDUP RULE.
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts:169–172` — the `## Output`
  "If no recent duplicate exists, create a new issue…" preamble that assumes the removed rule.
- Interacts with `_cron-shared.ts` `verifyScheduledIssueCreated` (`updated_at` crediting) and
  `digestIssueExistsForDate` / `isRealScheduledDigest` (same-date, FAILED-stub-excluding).
- **Unpinned title date (cohort-wide, out of scope here):** `ROADMAP_REVIEW_PROMPT` (static const)
  never injects `runStartedAt`; the eval self-computes the title `YYYY-MM-DD` from its own clock —
  a property shared by all 7 cohort crons, deferred cohort-wide (see Precedent-Diff + Non-Goals).

## Files to Edit

1. **`apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`** — remove the DEDUP RULE
   block (165–167) from `ROADMAP_REVIEW_PROMPT`; rewrite the `## Output` section so the eval
   **unconditionally creates** the dated digest after analysis (drop the "If no recent duplicate
   exists" conditional). Keep the exact surviving substring `create a new issue with:` (do NOT
   paraphrase — the AC4 presence test pins it verbatim). Preserve the verbatim-extraction anchors
   (Part 1 / Part 2 / MILESTONE RULE / BIDIRECTIONAL RULE) and the other safety guards (ISSUE
   CLOSURE SAFETY, ROADMAP.MD CONFLICT GUARD, CLONE DEPTH RULE, STAGING RULE). Leave the header
   verbatim-extraction comment (113–116) intact (all four anchors survive; the AC uses per-anchor
   presence checks so the comment's echoes do not skew a count). `ROADMAP_REVIEW_PROMPT` stays a
   static const (no date-pin — see Precedent-Diff); the sole edit is deleting the DEDUP RULE +
   rewriting `## Output`.

2. **`apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts`** — remove the two
   assertions referencing the removed rule: the `["DEDUP RULE", …]` row (line 103) and the
   `["post your findings as a comment on the most recent existing issue", …]` row (the `it.each`
   row spanning lines 108–116). Update the file header comment (lines 10–14) that lists DEDUP RULE
   as a safety-guard anchor. **Add** a new `describe` block asserting: (i) the removed strings
   `DEDUP RULE`, `within the last 6 days`, `post your findings as a comment on the most recent
   existing issue`, `If no recent duplicate exists` are **absent** from `SUT_SOURCE`; (ii) the new
   unconditional output wording — the verbatim substring `create a new issue with:` — is
   **present**.

3. **`apps/web-platform/server/inngest/functions/_cron-shared.ts`** (comment-only, 680–688) —
   re-point the `verifyScheduledIssueCreated` rationale from "roadmap-review's DEDUP RULE" to
   "`cron-community-monitor`'s DEDUP RULE" (the cron that still uses comment-and-exit). No
   behavior change; the `updated_at` filter stays.

4. **`apps/web-platform/test/server/inngest/cron-shared.test.ts`** (230–245) — update the
   "credits a dedup-comment" test's rationale comment and flip its fixture `label` from
   `scheduled-roadmap-review` to `scheduled-community-monitor` so the test documents a cron that
   still owns the DEDUP RULE. Assertion outcome unchanged (`true`).

## Files to Create

None.

## Implementation Phases

**Phase 1 — Prompt fix (contract change first).**
- Delete the DEDUP RULE block (`cron-roadmap-review.ts:165–167`).
- Rewrite `## Output` (169–172): after "create a GitHub issue summarizing your findings",
  proceed directly to "create a new issue with: …" — no 6-day conditional, no comment-and-exit
  fallback. Keep the exact substring `create a new issue with:`.
- `ROADMAP_REVIEW_PROMPT` stays a static const (no date-pin — Precedent-Diff).
- Leave the header verbatim-extraction anchor comment (113–116) intact (all four anchors survive).

**Phase 2 — Test updates (consumer of the contract).**
- Remove the two stale anchor rows in `cron-roadmap-review.test.ts`; update the header comment.
- Add the regression-guard `describe` (absence of removed strings + presence of new
  unconditional wording).
- Re-point the `_cron-shared.ts` comment and update `cron-shared.test.ts`'s dedup-comment
  fixture label + rationale.

**Phase 3 — Verify.**
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-roadmap-review.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-shared.test.ts`
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`

## User-Brand Impact

**If this lands broken, the user experiences:** the founder's weekly roadmap-review digest issue
stops being filed on manual/duplicate runs, and the `scheduled-roadmap-review` Sentry/Better
Stack monitor either false-pages RED or goes dark — eroding trust in the cron observability
signal (a false alarm the operator learns to ignore, or a missed real failure).

**If this leaks, the user's data / workflow / money is exposed via:** N/A — the change edits an
internal cron prompt + tests only; it moves no user data, touches no auth/schema/API surface, and
the spawned eval already runs under the operator installation token with an env allowlist.

**Brand-survival threshold:** none.
- `threshold: none, reason: internal operator-only cron observability contract; no customer data, no auth/schema/migration/API-route surface, single-operator blast radius.`

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in "scheduled-roadmap-review" (postSentryHeartbeat) — green on
        every run-day that produces its dated digest; the code-level dedup-skip path also posts
        green (ok:true) without spawning.
  cadence: weekly (cron "0 9 * * 1" UTC) + on-demand operator "cron/roadmap-review.manual-trigger".
  alert_target: Sentry cron-monitor "scheduled-roadmap-review" (Terraform
                sentry_cron_monitor.scheduled_roadmap_review) + Better Stack heartbeat.
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (existing; unchanged).
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (op tags:
               scheduled-output-missing, verify-output-failed, digest-dedup-read-failed,
               handler-body-threw, ensure-audit-issue-failed).
  fail_loud: true — a run that reaches the eval and creates no dated digest emits
             scheduled-output-missing and posts ok:false; ensureScheduledAuditIssue files a
             FAILED-fallback audit issue before the terminal heartbeat.
failure_modes:
  - mode: eval reaches the code but produces no dated digest (post-fix regression, e.g. prompt drift)
    detection: resolveOutputAwareOk finds no scheduled-roadmap-review issue in the run window
    alert_route: Sentry op:scheduled-output-missing + monitor RED + FAILED audit issue
  - mode: same-date duplicate (manual + cron same day)
    detection: dedup-digest-check → digestIssueExistsForDate true (excludes FAILED stubs)
    alert_route: green heartbeat, no spawn (healthy; no alert)
  - mode: GitHub LIST read error during dedup check
    detection: digestIssueExistsForDate catch → fail-OPEN (spawns)
    alert_route: Sentry op:digest-dedup-read-failed (non-paging), then normal eval path
logs:
  where: Sentry events (durable); pino app logs on the Hetzner host (not shipped to warehouse —
         which is why stderr/stdout tails are folded into the Sentry extras via formatTailForSentry).
  retention: Sentry default project retention.
discoverability_test:
  command: >-
    curl -s "https://sentry.io/api/0/organizations/<org>/monitors/scheduled-roadmap-review/checkins/?per_page=1"
    -H "Authorization: Bearer $SENTRY_API_TOKEN" | jq '.[0].status'
  expected_output: "ok" on the run-day following a successful digest creation (no ssh required).
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `cron-roadmap-review.ts` `ROADMAP_REVIEW_PROMPT` contains **none** of:
      `DEDUP RULE`, `within the last 6 days`, `post your findings as a comment on the most recent
      existing issue`, `If no recent duplicate exists`.
      Verify: `grep -c -E 'DEDUP RULE|within the last 6 days|post your findings as a comment on the most recent existing issue|If no recent duplicate exists' apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` → `0`.
- [ ] AC2 — the four verbatim-extraction anchors survive. Use **per-anchor presence** assertions
      (NOT a summed `grep -c` — the header verbatim-extraction comment at lines 114–115 echoes
      three of the anchor literals, so a count would read `6`, not `4`; Kieran plan-review F1). The
      new `cron-roadmap-review.test.ts` `it.each` block asserts each of `Part 1: Issue-to-Milestone
      Alignment`, `Part 2: Bidirectional Integrity Gate`, `MILESTONE RULE:`, `BIDIRECTIONAL RULE:`
      is present in `SUT_SOURCE`.
- [ ] AC3 — the surviving safety-guard anchors are intact, asserted per-anchor (the existing
      `it.each` rows for `ISSUE CLOSURE SAFETY:`, `ROADMAP.MD CONFLICT GUARD:`, `CLONE DEPTH RULE:`,
      `STAGING RULE (#5091):` remain green).
- [ ] AC4 — the `## Output` section unconditionally creates the dated digest: the verbatim
      substring `create a new issue with:` is present and the removed 6-day conditional strings are
      absent (new `cron-roadmap-review.test.ts` presence + absence assertions pass).
- [ ] AC5 — `cron-roadmap-review.test.ts` no longer asserts the removed rule and DOES assert
      absence of the removed strings + presence of the new wording.
- [ ] AC6 — behavioral invariant unchanged: the cohort suite still proves exactly-one-digest +
      green-skip-no-spawn for roadmap-review (the mock ignores the prompt, so removing the DEDUP
      RULE cannot regress it).
      Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cohort-dedup.test.ts` → roadmap-review rows green.
- [ ] AC7 — `cron-shared.test.ts` "credits a dedup-comment" test still returns `true` with the
      re-pointed `scheduled-community-monitor` fixture label + updated rationale.
- [ ] AC8 — `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-roadmap-review.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-shared.test.ts` all green.
- [ ] AC9 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] AC10 — `cron-content-generator.ts` untouched (scope guard).
      Verify: `git diff --name-only` does not list `cron-content-generator.ts`.

## Open Code-Review Overlap

None. (Checked: the plan's Files-to-Edit are `cron-roadmap-review.ts`, its test, `_cron-shared.ts`
comment, and `cron-shared.test.ts`; no open `code-review`-labeled issue was found touching these
paths during planning. Re-run `gh issue list --label code-review --state open` at /work if in doubt.)

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change — an internal cron prompt + test-accuracy edit on an already-provisioned
observability surface. No user-facing UI surface (no `components/**`, no `app/**/page.tsx`), no
business-domain implications. Product/UX Gate: NONE (mechanical UI-surface override did not fire).

## Architecture Decision (ADR/C4)

**No architectural decision.** This removes a redundant/conflicting prompt-level mechanism and
aligns behavior with the already-shipped #5786 code-level same-date dedup contract. It reverses no
ADR (there is no ADR for the cron dedup/output-aware-heartbeat contract; it lives in code comments
+ #5751/#5786 + learnings) and introduces no new substrate, ownership boundary, or trust boundary.

**No C4 impact.** Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): C4 models the
`inngest` container and the BetterStack monitoring system, but does **not** model individual cron
handlers, the per-cron Sentry monitor, or the dedup/output contract as elements. No external human
actor, external system/vendor, container/data-store, or actor↔surface access relationship changes.
No `.c4` edit required.

## Non-Goals / Deferrals

- **`cron-community-monitor` sibling bug (DEFERRAL — tracking issue required).** It carries the
  identical prompt DEDUP RULE (24h window, comment-and-exit; `cron-community-monitor.ts:229–234`)
  and the same defect (b) FAILED-fallback self-perpetuation. It is DAILY, so the 24h window ≈
  same-date, making defect (a) milder, but the "comment-and-exit produces no dated digest" and
  self-perpetuation defects still apply. **Out of scope per the explicit "ONLY roadmap-review"
  scope.** Re-evaluation criterion: apply the same "remove prompt DEDUP RULE, rely on code-level
  same-date dedup" fix once this PR validates the pattern. **When that fix lands, the shared
  `verifyScheduledIssueCreated` `updated_at` filter AND the re-pointed `_cron-shared.ts:680–688`
  citation come out together** — after community-monitor loses its rule, no cron relies on the
  `updated_at`-crediting-of-a-comment path, so the citation would again go stale (DHH plan-review
  F4). File a `gh issue create` tracking issue (milestone from `knowledge-base/product/roadmap.md`)
  at ship time and record this coupling in it.
- **Cohort-wide title-date pinning (DEFERRAL — cohort-wide, tracking issue).** The digest title
  date is agent-derived across all 7 always-create cohort crons, so the code-level same-date dedup
  can skew across a UTC-midnight boundary (DHH plan-review #2). This is a **pre-existing cohort
  property**, not created by this PR, and #5786 accepts the resulting rare duplicate as a paper-cut.
  Pinning only roadmap-review would make it a snowflake diverging from 6 siblings (Precedent-Diff).
  Defer as a single cohort-wide change (inject `runStartedAt.slice(0,10)` into all 7 prompts, or a
  shared prompt-builder) if determinism is later judged worth the divergence. File a tracking issue.
- **`cron-content-generator`** — verified to carry no DEDUP RULE (0 matches); nothing to fix.
- **June credit-exhaustion cause** — separately tracked and resolved; not addressed here.

## Test Strategy

- Runner is **vitest** (`apps/web-platform/node_modules/.bin/vitest`); include globs
  `test/**/*.test.ts` (node project) — the target files under `test/server/inngest/` match.
- Source-anchor discipline (`cq-test-fixtures-synthesized-only`): `cron-roadmap-review.test.ts`
  reads the real SUT via `readFileSync` and asserts on `SUT_SOURCE` — keep that pattern for both
  the absence-anchors (removed strings) and the presence-anchor (new unconditional wording).
- The **behavioral gate is the existing `cron-cohort-dedup.test.ts`** (roadmap-review row): do not
  add a redundant behavioral handler test; extend only the source-anchor guards.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it (threshold: none +
  scope-out reason bullet).
- The new `cron-roadmap-review.test.ts` **presence** anchor for the unconditional `## Output`
  wording must span **no punctuation boundary** that `.includes()` / `toContain` would break on
  (e.g. avoid a phrase crossing `(` `)` `:` `—`). Pick a clean substring from the final prompt
  text (e.g. `create a new issue with:`) after Phase 1 is written, and confirm it is unique to
  the post-fix wording (not present in a surviving safety guard).
- Do **not** remove `verifyScheduledIssueCreated`'s `updated_at`/`since` filter — it is still
  load-bearing for `cron-community-monitor`'s retained DEDUP RULE. Only re-point the stale
  citation.
- Keep the removed-string grep (AC1) scoped to `cron-roadmap-review.ts` only — `_cron-shared.ts`
  and `cron-community-monitor.ts` legitimately still contain `DEDUP RULE` and comment-and-exit
  language.
- Do NOT assert surviving anchors with a summed `grep -c` — the header verbatim-extraction comment
  (lines 114–115) echoes three of the four Part-1/Part-2/MILESTONE/BIDIRECTIONAL literals, so a
  count reads `6` not `4` (Kieran F1). Use per-anchor presence assertions (the test file already
  uses `it.each` for exactly this).
- With comment-and-exit gone, the fail-OPEN-on-read-error path (`digest-dedup-read-failed` →
  spawn) now reliably files a duplicate digest on a GitHub LIST blip where the old rolling window
  might have absorbed it (DHH F5). This is the intended priority and matches the 5 always-create
  cohort siblings ("a duplicate paper-cut beats a missed digest", #5786). Acceptable — no
  additional guard.

## Precedent-Diff — Cohort Consistency (deepen-plan Phase 4.4)

Grepped the sibling always-create cohort crons (`git grep -n "runStartedAt.slice(0, 10)"
apps/web-platform/server/inngest/functions/cron-*.ts` + prompt-const inventory):

| Cron | Prompt shape | Title date source | Code-level same-date dedup | Comment-and-exit DEDUP RULE |
|---|---|---|---|---|
| cron-roadmap-review (this PR) | static const → static const | agent-derived | `digestIssueExistsForDate` | **removing it** |
| cron-content-generator | static const | agent-derived | `digestIssueExistsForDate` | none |
| cron-growth-audit | static const | agent-derived | `digestIssueExistsForDate` | none |
| cron-growth-execution | static const | agent-derived | `digestIssueExistsForDate` | none |
| cron-competitive-analysis | static const | agent-derived | `digestIssueExistsForDate` | none |
| cron-seo-aeo-audit | static const | agent-derived | `digestIssueExistsForDate` | none |
| cron-campaign-calendar | static const | agent-derived | `digestIssueExistsForDate` (` (heartbeat)` suffix) | none |
| cron-community-monitor | static const | agent-derived | `digestIssueExistsForDate` | 24h (deferral) |

**Conclusion:** the fix keeps roadmap-review's prompt a static const — identical in shape to the 5
backstop-free always-create siblings, which are the canonical accepted pattern. No divergence. The
alternative DHH #2 (a `runStartedAt`-injecting prompt-builder) would have made roadmap the only
cron of 7 with a builder — a novel pattern; deferred cohort-wide instead (Non-Goals). No other
precedent (SECURITY DEFINER, atomic-write, lock, RPC-permission) is touched by this change.
