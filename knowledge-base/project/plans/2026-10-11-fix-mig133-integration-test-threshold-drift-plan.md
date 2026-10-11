---
title: "fix: Realign dormant env-gated integration tests to migration 133's 240 s liveness contract"
type: fix
date: 2026-10-11
slug: fix-mig133-integration-test-threshold-drift
branch: feat-one-shot-mig133-lease-slot-240s-drift
issue: 9993
lane: cross-domain
brand_survival_threshold: none
---

# fix: Realign dormant env-gated integration tests to migration 133's 240 s liveness contract

## Overview

Migration 133 (`apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql`)
raised every concurrency-slot / worktree-lease liveness threshold 120 s → 240 s in
lockstep with the paired TS constants (`SLOT_STALENESS_THRESHOLD_SECONDS = 240`,
`LEASE_LIVENESS_WINDOW_MS = 240_000`). Two env-gated integration test files were
never updated and still assert the pre-133 120 s contract, so the
`worktree-lease` and `slot-trigger` legs of
`.github/workflows/scheduled-integration-suites.yml` (wired by #9855 PR 2,
plan `2026-10-10-feat-dormant-integration-ci-plan.md`) fail deterministically on
every nightly run and keep re-commenting on tracker #9993.

*Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).*

## Problem Statement / Motivation

The suites are the alarm the dormant-CI work exists to keep live; right now they
are red for a reason that is NOT a product defect — the substrate correctly runs
240 s and the tests are stale. Verified live against dev on 2026-10-11 with the
exact CI commands:

- `worktree-write-lease.integration.test.ts`: **3 failed / 5 passed** —
  AC2(c), AC2(e), AC2(f) all fail at `ageHeartbeat(121)` call sites
  (`expected undefined to be 'host-b-…'`, `expected undefined to be 2`): a
  121 s-aged heartbeat is still fresh under the 240 s expiry, so cross-host
  `acquire_worktree_lease` correctly returns zero rows.
- `conversation-archive-release-slot.integration.test.ts`: **1 failed / 5
  passed** — `stale-heartbeat slot (200 s old) …` fails with
  `expected 'cap_hit' to be 'ok'`: a 200 s-old slot heartbeat is inside the
  240 s lazy-sweep window, so `acquire_conversation_slot` correctly does NOT
  reap and the cap-hit branch fires. The 60 s fresh-heartbeat negative gate
  PASSED (60 < 240 remains fresh) — it stays valid unchanged.

A red leg that isn't a defect trains operators to ignore the leg — the precise
rot #3373 / #3221 warned about. The fix restores the legs to asserting the live
contract.

## Proposed Solution

Update the stale-arm literals in both files to a value comfortably past the
240 s threshold — **300 s** (240 + 60 s clock-skew margin; the DB compares
`heartbeat_at`/`last_heartbeat_at` written from the runner's `Date.now()`
against the DB's `now()`, and the brief explicitly rules out a minimal
241-style bump) — and update every comment/title that presents 120 s as the
live contract. Introduce one named constant per file at the helper so the
margin rationale lives in exactly one place (three identical literals invite
the same partial-update drift this PR removes).

### Exact edits — `apps/web-platform/test/worktree-write-lease.integration.test.ts`

| Site | Before | After |
|---|---|---|
| Header comment ~:9 | `AC2(c) cross-host re-acquire after the 120s heartbeat expiry → gen+1.` | `AC2(c) cross-host re-acquire after the 240s heartbeat expiry (mig 133) → gen+1.` |
| Header comment ~:18 | `bypasses RLS) rather than sleeping 120s.` | `bypasses RLS) rather than sleeping 240s.` |
| Helper `ageHeartbeat` ~:191 | (no contract note) | Add comment: `// Aged past the 240 s mig-133 lease expiry; 300 s = 240 + 60 s DB-vs-runner clock-skew margin.` and constant `const STALE_LEASE_AGE_S = 300;` (module scope, beside `SYNTHETIC_EMAIL_PATTERN`) |
| AC2(c) :222 | `await ageHeartbeat(121);` | `await ageHeartbeat(STALE_LEASE_AGE_S);` |
| AC2(d) comment :236 | `(no 120s wait — tombstone)` | `(no 240s wait — tombstone)` |
| AC2(e) :251 | `await ageHeartbeat(121);` | `await ageHeartbeat(STALE_LEASE_AGE_S);` |
| AC2(f) :260 | `await ageHeartbeat(121);` | `await ageHeartbeat(STALE_LEASE_AGE_S);` |

### Exact edits — `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`

| Site | Before | After |
|---|---|---|
| Boundary-comment block :301-308 | `last_heartbeat_at < now() - 120s` / `migration 029 line ~131` / `just past 120s is reaped` / `under 120s is preserved` | `now() - 240s` / cite mig 133 as the live threshold writer (was 029/093) / `just past 240s is reaped` / `under 240s is preserved` |
| Test title :327 | `stale-heartbeat slot (200 s old) is reaped by lazy sweep on next acquire — closes 120-180 s dead-end window` | `stale-heartbeat slot (300 s old) is reaped by lazy sweep on next acquire — dead-end window now past the 240 s threshold` |
| Comment :329-334 | `heartbeat lapsed past 120 s` | `heartbeat lapsed past 240 s (mig 133)` |
| Comment :342-344 | `past the 120 s threshold` | `past the 240 s threshold (mig 133)` |
| Call :345 | `await backdateSlotHeartbeat(stuckConv, 200);` | `await backdateSlotHeartbeat(stuckConv, 300);` (or `STALE_SLOT_AGE_S = 300` mirroring the lease file) |
| Negative-gate comment :365 | `fresh (under the 120 s threshold)` | `fresh (under the 240 s threshold)` — **60 s literal UNCHANGED** |
| Negative-gate comment :378 | `Backdate to 60 s — well within the 120 s threshold.` | `Backdate to 60 s — well within the 240 s threshold.` — literal stays `60` |

Comments may retain the token `120` only inside an explicit historical citation
(e.g. "raised 120→240 in mig 133") — never as the live contract.

## Technical Considerations

- **Why 300 and not 241/250:** `ageHeartbeat`/`backdateSlotHeartbeat` write a
  timestamp computed from the runner's `Date.now()`; the SQL predicates compare
  against the DB's `now()`. The dangerous skew direction is runner-ahead-of-DB
  (effective age shrinks). 300 s tolerates up to ~60 s of runner-ahead skew —
  far beyond anything an NTP-synced GH runner + Supabase dev will produce.
- **Over-aging cannot false-pass:** both stale-arm assertions require the row
  to be *past* expiry; a larger margin only moves it further past. The boundary
  sensitivity is pinned by the unchanged 60 s negative gate.
- **No other stale-threshold carriers:** census of `apps/web-platform/test/`
  (see Research Insights) found heartbeat-aging logic in exactly these two
  files. `agent-runner-stuck-active-reaper.test.ts` already mocks
  `SLOT_STALENESS_THRESHOLD_SECONDS: 240`; the `120_000` hits in
  `dsar-author-redaction.integration.test.ts`/`api-checkout-idempotency.test.ts`
  are vitest/marker timeouts, not liveness thresholds; migration-shape tests
  pin historical migration bodies by design.
- **afterAll asymmetry:** the lease file's cleanup `console.warn`s on
  `deleteUser` failure; the slot file *throws*. If the intermittent dev
  `deleteUser` 500s recur during verification (#9994, out of scope), the slot
  file's hook failure must be read as non-blocking per the brief — per-test
  results are the verdict. Do NOT soften the throw in this PR.

## Files to Edit

- `apps/web-platform/test/worktree-write-lease.integration.test.ts` — 3 call sites + 3 comment sites + named constant (table above)
- `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` — 1 call site + test title + comment block/sites (table above)

## Files to Create

- None.

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user-facing artifact — the change edits env-gated test files only. The *indirect* surface is operator trust in the `worktree-lease`/`slot-trigger` legs: a mis-set constant leaves a leg red (noise, noticed nightly) or falsely green (only if a literal were *under* the threshold while asserting staleness — AC4's live green run and the unchanged 60 s negative gate rule that out).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — synthetic `*@soleur.test` users on dev only (`hr-destructive-prod-tests-allowlist`).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is two test files with no production-path changes; the suites exist to protect the user-facing slot/lease contract, but this diff does not alter what users experience — it restores the test's fidelity to the contract already live on dev.

*Scope-out override:* `threshold: none, reason: env-gated integration-test constants and comments only — no production, schema, auth-flow, or migration code changes.`

## Observability

```yaml
liveness_signal:
  what: scheduled-integration-suites worktree-lease + slot-trigger legs green
  cadence: nightly 04:30 UTC (workflow_dispatch-able)
  alert_target: ci/integration-suites tracker #9993; Sentry cron monitor on missed run
  configured_in: .github/workflows/scheduled-integration-suites.yml:217 (worktree-lease), :262 (slot-trigger)
error_reporting:
  destination: GitHub issue tracker, label ci/integration-suites (#9993)
  fail_loud: vitest assertion output in the leg step log (e.g. "expected 'cap_hit' to be 'ok'")
failure_modes:
  - mode: threshold drifts again on a future migration (e.g. mig >133 changes the contract)
    detection: the same legs go red on the nightly run and comment on #9993
    alert_route: ci/integration-suites issue tracker
  - mode: dev deleteUser 500s recur (tracked #9994)
    detection: slot file afterAll throws; lease file warns
    alert_route: #9994 tracker (out of scope here)
logs:
  where: GitHub Actions run logs for scheduled-integration-suites.yml
  retention: GitHub default (~90 days)
discoverability_test:
  command: grep -c "interval '240 seconds'" apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql
  expected_output: "3"
```

## Open Code-Review Overlap

2 open scope-outs touch these files; neither names a new concern for this diff:

- **#3373** `review: SLOT_TRIGGER_INTEGRATION_TEST not wired into nightly CI — boundary tests will silently rot` — **acknowledge**: this exact failure (the boundary test rotting under mig 133) is what the issue predicted; the nightly wiring it asked for shipped in #9855 PR 2, and this PR is the remediation of the drift it caught. `do-not-autoclose` label; closure belongs to that scope-out's own lifecycle.
- **#3221** `ci: nightly cron for env-gated integration tests — review #3217` — **acknowledge**: same disposition; superseded by `scheduled-integration-suites.yml`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "`ageHeartbeat(121)` → a value >240 with clock-skew margin (suggest 250 or 300 — DB now() vs runner Date.now() can skew; do NOT use 241). Update comments citing the 120s expiry (~lines 9, 18, 236) to the 240s contract from migration 133." | Files-to-Edit lease file (edit table) | mapped |
| 2 | "`backdateSlotHeartbeat(stuckConv, 200)` → >240 with margin; update the test title ('200 s old', '120-180 s dead-end window') and comments describing the 120s threshold to 240s semantics. Keep the 60s negative test as-is." | Files-to-Edit slot file (edit table) | mapped |
| 3 | "Sweep both files for any other 120s-derived constants; re-verify no other integration test file carries the same stale-threshold assumption." | AC5 + Research Insights census | mapped |
| 4 | "Verification: these legs are env-gated integration tests runnable against dev with the same command CI uses" | AC4 + Test Scenarios verification commands | mapped |
| 5 | "Out of scope: the other failing legs (supabase-dev/byok deleteUser 500s; mu1 JWT 401) have their own open trackers — do not touch." | — | descoped — justification: tracked by #9994 (deleteUser 500s) and #9995 (MU1 401); touching them would collide with their own fixes |

### Plan-Item Provenance

| Plan item | User words cited (verbatim) | Verdict |
|---|---|---|
| lease-file edits | ask 1 (quoted above) | asked |
| slot-file edits | ask 2 (quoted above) | asked |
| sweep census + AC5 | ask 3 (quoted above) | asked |
| live-dev verification AC4 | ask 4 (quoted above) | asked |
| named constant `STALE_*_AGE_S = 300` | — | inferred — justification: three identical `ageHeartbeat(121)` literals were the partial-update-drift vector; a single named constant concentrates the margin rationale in one comment and one edit site |

### Split Assessment

- Subsystems touched: 1 — apps/web-platform
- Planned files: 2 | Estimated changed lines: ~25
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `apps/web-platform/test/worktree-write-lease.integration.test.ts` contains zero remaining `ageHeartbeat(121)` call sites; all three stale-arm calls (AC2 c/e/f) use `STALE_LEASE_AGE_S = 300` (or a literal ≥ 250 with equivalent margin comment)
- [ ] AC2: `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` backdates the stale slot ≥ 250 s (300); the test title no longer reads "200 s old" / "120-180 s dead-end window"
- [ ] AC3: the fresh-heartbeat negative gates remain `60` and remain passing — `backdateSlotHeartbeat(liveConv, 60)` and `ageHeartbeat` are untouched below the threshold
- [ ] AC4: no comment or title in either file presents 120 s as the live contract; any surviving `120` token appears only inside an explicit historical citation (e.g. "raised 120→240 in mig 133")
- [ ] AC5: both legs pass green against dev with the exact CI commands —
  `doppler run -p soleur -c dev_scheduled -- env WORKTREE_LEASE_INTEGRATION_TEST=1 npm run test:ci -- test/worktree-write-lease.integration.test.ts --project unit` → 8/8 pass, and
  `doppler run -p soleur -c dev_scheduled -- env SLOT_TRIGGER_INTEGRATION_TEST=1 npm run test:ci -- test/conversation-archive-release-slot.integration.test.ts --project unit` → 6/6 pass
  (afterAll `deleteUser` 500 noise is non-blocking per brief; per-test results are the verdict)
- [ ] AC6: grep census confirms no other `*.test.ts` carries a heartbeat-aging literal or a 120 s-derived staleness assumption (evidence recorded in Research Insights)
- [ ] AC7: PR body does NOT use `Closes #9993` — sibling legs (#9994, #9995) keep the tracker open; reference `issue #9993` only

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-machinery change only. Mechanical
UI-surface scan: `## Files to Edit` contains no path matching the
`ui-surface-terms.md` glob superset → Product/UX gate NONE. Engineering
assessment question ("significant architectural decisions / beyond normal
implementation") not met — literal constant updates against an already-applied
migration.

## Test Scenarios

- **AC2(c/e/f) re-acquire boundary (integration):** Given a held lease whose heartbeat is aged 300 s (past the 240 s mig-133 expiry), when a different host calls `acquire_worktree_lease`, then it takes over with gen+1.
- **Stale-slot lazy sweep (integration):** Given a slot heartbeat backdated 300 s under cap=1, when a new conversation acquires, then the lazy sweep reaps the stale row and status is `ok`.
- **Fresh-slot negative gate (integration):** Given a slot heartbeat backdated 60 s (inside 240 s), when a new conversation acquires under cap=1, then `cap_hit` fires — the boundary's lower bound.
- **Verification commands (deterministic):** the two `doppler run -p soleur -c dev_scheduled` invocations quoted in AC5.

## Success Metrics

- `worktree-lease` and `slot-trigger` leg outcomes go green on the next
  scheduled/dispatch run of `scheduled-integration-suites.yml`.
- #9993 receives no further comments naming these two legs (other legs'
  comments continue until #9994/#9995 land).

## Dependencies & Risks

- **DB-vs-runner clock skew** → mitigated by 300 s (60 s margin); the aging write and the RPC read are separate round trips, so more margin is strictly safer for the stale arm.
- **Intermittent dev `deleteUser` 500s (#9994)** → may throw in the slot file's `afterAll` and fail the file despite green tests; read per-test results as the verdict (brief's known-noise clause). Not softened — out of scope.
- **Hourly `user_concurrency_slots_sweep` pg_cron** could theoretically reap the 300 s-aged slot between backdate and acquire (~1 s window, once an hour); outcome is identical either way (slot gone → `ok`) — non-issue.
- **Verification requires Doppler `dev_scheduled` access** — verified working from this worktree on 2026-10-11 (both baseline runs executed).

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Derive the aged value from the live constants (`LEASE_LIVENESS_WINDOW_MS`/`SLOT_STALENESS_THRESHOLD_SECONDS` + margin) | The literal IS the independent contract pin: a future mig-134 bump would silently flow through a derived value, while a literal turns the next drift red — the alarm working as designed. Also avoids pulling the server module graph into env-gated files that today import only `@supabase/supabase-js` + `crypto`. |
| Extend `concurrency-heartbeat-backoff.test.ts`'s drift-guard to grep these two files | The guard greps the `120_000` / `interval '120 seconds'` literal families; `121`/`200`-style aged-heartbeat args are a different shape and a bespoke regex overfits. Only the scheduled dev run can validate a literal against the LIVE DB contract anyway. |
| Minimal bump (241) | Brief explicitly rules out — DB `now()` vs runner `Date.now()` skew can exceed 1 s. |
| Sleeping real elapsed time | Already rejected by the suite's design — `ageHeartbeat`/`backdateSlotHeartbeat` exist precisely to avoid multi-minute sleeps. |
| Soften the slot file's `afterAll` throw → `console.warn` (match lease file) | Touches the #9994 defect surface — out of scope per brief; the throw is that file's deliberate strictness. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6 — filled above (`none` + scope-out reason).
- `afterAll` in the slot file THROWS on `deleteUser` error (unlike the lease file's warn): a green test list + red hook = leg still red. Read per-test results for the verdict; do not "fix" the hook in this PR.
- Do not `git add` the `plans/` directory — only this file + `tasks.md`.
- Line numbers above are anchors, not contracts — match on the quoted content (`ageHeartbeat(121)`, `backdateSlotHeartbeat(stuckConv, 200)`, the `120 s` comment phrases) if lines have drifted.

## Research Insights

### Premise Validation (Phase 0.6)

All cited artifacts verified against the worktree AND live against dev:

- `apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql` —
  `interval '240 seconds'` at `acquire_conversation_slot` lazy sweep (:83),
  `user_concurrency_slots_sweep` pg_cron body (:138), `acquire_worktree_lease`
  takeover (:217); `find_stuck_active_conversations` default 240 (:150).
- Lease test: `ageHeartbeat(121)` at :222/:251/:260; `120s` comments at :9/:18/:236 — matches the brief's citations.
- Slot test: `backdateSlotHeartbeat(stuckConv, 200)` at :345; `120 s` semantics in comments :303-308/:330/:342/:365/:378 and title :327.
- Workflow legs at `.github/workflows/scheduled-integration-suites.yml:217-230`
  and `:262-275` — commands identical to the brief's verification commands
  (CI appends `--reporter=verbose`).
- TS substrate already at 240: `server/concurrency.ts:31`
  (`SLOT_STALENESS_THRESHOLD_SECONDS = 240`), `server/worktree-write-lease.ts:83`
  (`LEASE_LIVENESS_WINDOW_MS = 240_000`); mig-133 drift-guard
  `test/concurrency-heartbeat-backoff.test.ts` pins both + the 3 SQL literals.
- **Live red baseline (2026-10-11):** lease suite 3 failed/5 passed (AC2 c/e/f);
  slot suite 1 failed/5 passed (`expected 'cap_hit' to be 'ok'`); 60 s negative
  gate passed.
- Tracker: #9993 OPEN (`[ci/integration-suites] Nightly integration suites failed`);
  sibling leg trackers #9994 (deleteUser 500s), #9995 (MU1 401) — both OPEN, out of scope.
- Issue cited: none in the brief; #9993 selected as `issue:` (NOT `closes:` —
  other legs keep it open).

### Property List / Cut List (Phase 0.6b)

- **P1** stale-arm literals exceed the 240 s contract with clock-skew margin.
- **P2** comments/titles describe the live 240 s mig-133 contract, not 120 s.
- **P3** the 60 s negative gates remain untouched and still valid.
- **P4** no other integration file carries the stale-threshold assumption.

**Cuts:** derived-constant imports (P1 already bought by literals — see
Alternatives); drift-guard regex extension (no stable literal family to grep —
see Alternatives); #9994/#9995 fixes (explicitly descoped by the brief).

### Census — no other stale-threshold carriers

`grep` over `apps/web-platform/test/**` for `ageHeartbeat`, `backdate`,
`heartbeat_at` writes, `interval '1..`, `12x`/`200` staleness literals: only the
two target files. `agent-runner-stuck-active-reaper.test.ts:131` already mocks
`SLOT_STALENESS_THRESHOLD_SECONDS: 240`. `120_000` hits elsewhere are vitest
timeouts/marker ages, not liveness thresholds. `test/supabase-migrations/*`
sentinels pin historical migration bodies — correct to leave.

### Applicable learnings

- `knowledge-base/project/learnings/bug-fixes/2026-05-05-cc-stuck-active-conversation-leaks-slot.md` — divergent thresholds silently false-reap; cited by mig 133's own header. This fix is the test-side mirror of the same coupling.
- `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — two-stage `--json` + standalone `jq --arg` used for the overlap query.
- Sibling plan `knowledge-base/project/plans/2026-10-10-feat-dormant-integration-ci-plan.md` — wired these legs; its deepen-plan ran inline (no Task tool in pipeline context), precedent for this plan's review handling.

### Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| `acquire_worktree_lease` expires at `240 seconds` on dev | mig 133 :217 + live red run confirms 121 s is fresh | literals → 300 |
| `ageHeartbeat(121)` at 3 sites | :222/:251/:260 confirmed | all three → `STALE_LEASE_AGE_S` |
| `backdateSlotHeartbeat(stuckConv, 200)` under-reaps under 240 s | :345 confirmed; live run `cap_hit` | → 300 |
| 60 s negative gate stays valid | passed live under 240 s | unchanged |
| cleanup deleteUser 500s are noise | lease file warns; slot file throws — read per-test results | documented in Risks; not softened |

### Gate dispositions

- **Phase 1.4 network-outage:** no trigger pattern in the brief (the "500s" cited is HTTP 500 plural on a descoped leg, not a connectivity symptom). Skipped.
- **Phase 1.5/1.5b community/functional overlap:** test-constant fix; no community artifact class applies; no uncovered stack. Skipped.
- **Phase 1.6 external research:** strong local context + verified live diagnosis → skipped.
- **Phase 2.7 GDPR:** Files-to-Edit are `test/*.ts` — outside the regulated-surface path set; synthetic users only; triggers (a)-(d) none. Skipped.
- **Phase 2.8 IaC:** no new infrastructure. Skipped.
- **Phase 2.9 Observability:** `test/` is outside the detection path set; section included anyway because restoring the legs IS the liveness signal.
- **Phase 2.10 ADR/C4:** no architectural decision — test alignment to an already-recorded contract (mig 133's own header + `concurrency-heartbeat-backoff.test.ts` are the record). Skipped.
- **Phase 2.11 Encryption Posture:** no persistent store, no new connection. Skipped.
- **Phase 2.12 Guard Contract:** deliverable contains no guard/gate/lint. Skipped.
- **Phase 4.5 advisor consult:** trivially mechanical (two files, constant updates, no architecture choice) — skipped per the carve-out.
- **Plan review:** the multi-agent panel (`plan-review` skill) cannot be spawned in this pipeline context (no Task tool). Standing checks run inline instead: every edit-table anchor verified against the live files at write time; every AC is deterministic over file state or the two pinned live test runs; nothing is taste-class pending operator decision.

## References & Research

- Migration: `apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql` (+ `.down.sql`)
- Contract pins: `apps/web-platform/server/concurrency.ts:31`, `apps/web-platform/server/worktree-write-lease.ts:83`, `apps/web-platform/test/concurrency-heartbeat-backoff.test.ts`
- Workflow: `.github/workflows/scheduled-integration-suites.yml:217-230`, `:262-275`
- Trackers: #9993 (red legs), #9994 (deleteUser 500s — out of scope), #9995 (MU1 401 — out of scope), #3373 / #3221 (rot warnings — acknowledged)
- Parent: `knowledge-base/project/plans/2026-10-10-feat-dormant-integration-ci-plan.md` (#9855 PR 2)
- Plan: `2026-07-18-perf-supabase-disk-io-write-reduction-plan.md` (mig 133's origin)
