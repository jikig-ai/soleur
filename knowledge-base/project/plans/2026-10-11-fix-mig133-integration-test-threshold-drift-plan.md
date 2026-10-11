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

## Enhancement Summary

**Deepened on:** 2026-10-11
**Sections enhanced:** Overview (scope update), Proposed Solution (discovered-carrier edit table), Technical Considerations, Files to Edit, User-Brand Impact (scope-out), Scope Check (inferred rows), Acceptance Criteria (AC4/AC8/AC9), Domain Review, Test Scenarios, Alternative Approaches, Research Insights (census/reconciliation/gate dispositions)
**Research agents used:** none — subagent spawning unavailable in this pipeline context; all deepen-plan halt gates and quality checks were executed inline.

### Key Improvements (deepen-plan)

1. **Widened the sweep beyond the brief's population** — found the same mig-133
   120→240 drift in `lib/ws-client.ts` (user-facing `~3 minutes` → `~10
   minutes`), `server/host-identity.ts` (operator-facing `up to 120s` → 240 s),
   `test/ws-protocol.test.ts` (coupled assertion), and
   `test/ws-handler-cap-hit-self-heal.test.ts` (stale comment). Folded in.
2. **Copy math re-derived against ADR-124** — the cap-hit reap is
   threshold-independent, but the background reaper's worst case is the
   300 s poll (`STUCK_ACTIVE_CHECK_INTERVAL_MS`, widened 60→300 s on
   2026-06-02) + 240 s staleness ≈ ~9 min; `~10 minutes` is the
   conservative correct figure. *(Post-review correction: the pre-merge
   derivation cited a "60 s reaper tick" retired by #4801.)*
3. **Sensitive-path re-check post fold-in** — `server/host-identity.ts` puts the
   diff inside the sensitive-path regex; scope-out reason updated, GDPR gate
   fired and assessed inline.

### Gates Run (deepen-plan, inline)

- 4.4 precedent-diff: PASS (synthetic-user lifecycle + RPC helpers mirror
  `concurrency-acquire-slot-workspace-id.integration.test.ts`; no novel pattern)
- 4.45 round-1 realism: negative claims verified (census ran; SQL predicate is
  strict `<`; synthetic-only dev users); no dropped symbols to re-grep
- 4.5 network-outage: 0 trigger hits in Overview/Problem — skipped
- 4.55 downtime & cutover: no infra/DDL/deploy surface — skipped
- 4.6 User-Brand Impact: PASS (section present, `none`, scope-out line carried)
- 4.7 Observability: PASS (5 fields, `grep` verb allowlisted, `expected_output: "3"` literal, <15 s, no ssh)
- 4.8 PAT shapes: none
- 4.9 UI-wireframe: N/A (no UI-surface file)
- 4.10 Encryption Posture: skipped (no store-class file match or prose store/connection)
- 4.11 Guard Contract: deliverable is not a guard (prose mentions of "guard"/"drift-guard" are rejected-alternative and existing-mechanism references only) — skipped
- 4.12 Scope Check: PASS (1 unfenced section, 3 subsections, Recommendation: single PR; inferred rows carry justifications)

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

**Scope update (deepen-plan sweep, 2026-10-11):** the mandated "no other file
carries the same stale-threshold assumption" census found the same mig-133
120→240 drift in four files outside the brief's integration-test population —
two of them in user/operator-facing strings (`lib/ws-client.ts`'s
`CONCURRENCY_CAP` copy "~3 minutes" → ~10 min under 240 s threshold + 300 s poll;
`server/host-identity.ts`'s thrown error "up to 120s" → 240 s). They are folded
into this plan as `inferred` items: identical defect class, all comment/string
literals, and deferring ~15 one-token edits to a second PR is disproportionate.

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

### Exact edits — discovered same-class carriers (folded in by the sweep)

| File | Site | Before | After |
|---|---|---|---|
| `apps/web-platform/lib/ws-client.ts` | comment :204 | `(60 s reaper tick + 120 s threshold ≈ 3 min)` | `(240 s staleness + up to one 300 s reaper poll ≈ ~9 min)` |
| `apps/web-platform/lib/ws-client.ts` | `CONCURRENCY_CAP` reason :210 | `…reclaim it within ~3 minutes.` | `…reclaim it within ~10 minutes.` |
| `apps/web-platform/test/ws-protocol.test.ts` | comment :486 | `~3 min = 60 s tick + 120 s threshold` | `~10 min ≈ 240 s staleness + up to one 300 s reaper poll` |
| `apps/web-platform/test/ws-protocol.test.ts` | assertion :492 | `.toContain("3 minutes")` | `.toContain("10 minutes")` |
| `apps/web-platform/server/host-identity.ts` | comments :5, :26 | `120s lockout` / `for up to 120s` | `240s lockout` / `for up to 240s` |
| `apps/web-platform/server/host-identity.ts` | thrown error string :38 | `each recreate-deploy out of its own worktree for up to 120s.` | `each recreate-deploy out of its own worktree for up to 240s.` |
| `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts` | comment :373 | `stale (>120s)` | `stale (>240s)` |

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
- **`~10 minutes` is the correct figure, not a paraphrase:** ADR-124 added a
  threshold-INDEPENDENT immediate reap on `start_session` cap-hit, but the
  background `find_stuck_active_conversations` reaper (300 s poll over the
  240 s threshold — `STUCK_ACTIVE_CHECK_INTERVAL_MS`, widened 60→300 s by
  #4801 on 2026-06-02) remains the worst-case path for a genuinely-stuck
  row — 240 + 300 = 540 s ≈ 9 min, rounded to `~10 minutes` for the copy.
  The `ws-protocol.test.ts` assertion pins the
  string (`"10 minutes"`), so copy and assertion must move together in one diff.
- **`lib/ws-client.ts` stays a literal:** it is client-side (`react`,
  `@/lib/supabase/client`) — importing `server/concurrency.ts` would cross the
  client/server import boundary, so the threshold-derived copy cannot be
  derived; the literal + adjacent derivation comment is the available shape.
- **`host-identity.ts` is the same constant:** the "120s lockout" it names is
  `LEASE_LIVENESS_WINDOW_MS` (240_000 post-133) — the self-lockout window a
  per-container-id host would wait out. `host-identity.test.ts` asserts only
  `/SOLEUR_HOST_ID is unset in production/` — the `120s` in the thrown string
  is unpinned and safe to update.
- **Excluded lookalikes (verified NOT this threshold):**
  `git-data-replication.ts`'s `GIT_DATA_QUEUE_TIMEOUT_MS` default 120_000 (a
  queue-grant window), `c4-staleness.ts`'s 120 s render budget, the
  `cc-dispatcher`/`cc-reprovision` 120 s clone timeouts,
  `sandbox-credential-deny-argv.test.ts`'s 120 s module default,
  `dsar-author-redaction`/`api-checkout-idempotency`'s `120_000` vitest/marker
  ages, and `STUCK_TIMEOUT_MS = 45_000` in `lib/ws-constants.ts` — none derive
  from mig-133's liveness contract and all stay.

## Files to Edit

- `apps/web-platform/test/worktree-write-lease.integration.test.ts` — 3 call sites + 3 comment sites + named constant (table above)
- `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` — 1 call site + test title + comment block/sites (table above)
- `apps/web-platform/lib/ws-client.ts` — derivation comment + `CONCURRENCY_CAP` reason string (folded-in carrier)
- `apps/web-platform/test/ws-protocol.test.ts` — explanatory comment + `"3 minutes"` assertion (coupled to the ws-client copy)
- `apps/web-platform/server/host-identity.ts` — 2 comments + thrown error string (folded-in carrier)
- `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts` — 1 stale comment (folded-in carrier)

## Files to Create

- None.

## User-Brand Impact

- **If this lands broken, the user experiences:** the only user-visible artifact in the diff is the `CONCURRENCY_CAP` close-frame copy — a wrong number there would misstate the reclaim window but is pinned by `ws-protocol.test.ts`; the rest is env-gated test files and comments. The *indirect* surface is operator trust in the `worktree-lease`/`slot-trigger` legs: a mis-set constant leaves a leg red (noise, noticed nightly) or falsely green (only if a literal were *under* the threshold while asserting staleness — AC4's live green run and the unchanged 60 s negative gate rule that out).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — synthetic `*@soleur.test` users on dev only (`hr-destructive-prod-tests-allowlist`).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is literal constants, comments, and two stale-number strings — no production logic, schema, auth-flow, or migration changes; it restores test and copy fidelity to the contract already live on dev.

*Scope-out override:* `threshold: none, reason: literal/comment/string accuracy updates — host-identity.ts matches the apps/web-platform/server/ sensitive path but the edit is three stale numbers in comments and one thrown error string; no production logic changes.`

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
| 3 | "Sweep both files for any other 120s-derived constants; re-verify no other integration test file carries the same stale-threshold assumption." | AC6 + Research Insights census + discovered-carrier edit table (folded-in files) | mapped |
| 4 | "Verification: these legs are env-gated integration tests runnable against dev with the same command CI uses" | AC5 + Test Scenarios verification commands | mapped |
| 5 | "Out of scope: the other failing legs (supabase-dev/byok deleteUser 500s; mu1 JWT 401) have their own open trackers — do not touch." | — | descoped — justification: tracked by #9994 (deleteUser 500s) and #9995 (MU1 401); touching them would collide with their own fixes |

### Plan-Item Provenance

| Plan item | User words cited (verbatim) | Verdict |
|---|---|---|
| lease-file edits | ask 1 (quoted above) | asked |
| slot-file edits | ask 2 (quoted above) | asked |
| sweep census + AC6 | ask 3 (quoted above) | asked |
| live-dev verification AC5 | ask 4 (quoted above) | asked |
| named constant `STALE_*_AGE_S = 300` | — | inferred — justification: three identical `ageHeartbeat(121)` literals were the partial-update-drift vector; a single named constant concentrates the margin rationale in one comment and one edit site |
| `lib/ws-client.ts` comment + `~3 minutes` copy edits | — | inferred — justification: found by the ask-3 sweep outside the stated integration-test population; same mig-133 drift class reaching user-facing copy that under-bounds the reclaim window (~3 min vs ~9 min actual); a second PR for one word + one comment is disproportionate |
| `test/ws-protocol.test.ts` comment + assertion edits | — | inferred — justification: mechanically coupled to the ws-client copy change — the assertion pins `"3 minutes"` and must move in the same diff or CI reds |
| `server/host-identity.ts` comment + error-string edits | — | inferred — justification: same ask-3 sweep find; "up to 120s" names `LEASE_LIVENESS_WINDOW_MS` (now 240 s) in an operator-facing thrown error; identical defect class |
| `test/ws-handler-cap-hit-self-heal.test.ts` comment edit | — | inferred — justification: same ask-3 sweep find; `>120s` comment beside mocks already at 240 — one-token documentation fix |

### Split Assessment

- Subsystems touched: 1 — apps/web-platform
- Planned files: 6 | Estimated changed lines: ~40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `apps/web-platform/test/worktree-write-lease.integration.test.ts` contains zero remaining `ageHeartbeat(121)` call sites; all three stale-arm calls (AC2 c/e/f) use `STALE_LEASE_AGE_S = 300` (or a literal ≥ 250 with equivalent margin comment)
- [ ] AC2: `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` backdates the stale slot ≥ 250 s (300); the test title no longer reads "200 s old" / "120-180 s dead-end window"
- [ ] AC3: the fresh-heartbeat negative gates remain `60` and remain passing — `backdateSlotHeartbeat(liveConv, 60)` and `ageHeartbeat` are untouched below the threshold
- [ ] AC4: no comment, title, string, or assertion in any edited file presents 120 s as the live contract; any surviving `120` token appears only inside an explicit historical citation (e.g. "raised 120→240 in mig 133")
- [ ] AC5: both legs pass green against dev with the exact CI commands —
  `doppler run -p soleur -c dev_scheduled -- env WORKTREE_LEASE_INTEGRATION_TEST=1 npm run test:ci -- test/worktree-write-lease.integration.test.ts --project unit` → 8/8 pass, and
  `doppler run -p soleur -c dev_scheduled -- env SLOT_TRIGGER_INTEGRATION_TEST=1 npm run test:ci -- test/conversation-archive-release-slot.integration.test.ts --project unit` → 6/6 pass
  (the non-zero pass counts themselves prove the env gates fired — a skipped suite reports 0 tests; afterAll `deleteUser` 500 noise is non-blocking per brief; per-test results are the verdict)
- [ ] AC6: grep census confirms no other `*.test.ts` carries a heartbeat-aging literal or a 120 s-derived staleness assumption (evidence recorded in Research Insights)
- [ ] AC7: PR body does NOT use `Closes #9993` — sibling legs (#9994, #9995) keep the tracker open; reference `issue #9993` only
- [ ] AC8: `lib/ws-client.ts` `CONCURRENCY_CAP` reason reads `~10 minutes` and its derivation comment reads `240 s staleness + up to one 300 s reaper poll ≈ ~9 min`; `npm run test:ci -- test/ws-protocol.test.ts --project unit` passes (the pinned assertion moves to `"10 minutes"` in the same diff)
- [ ] AC9: `server/host-identity.ts` and `test/ws-handler-cap-hit-self-heal.test.ts` contain no `120` token presented as the live lockout/staleness figure (each → `240s`)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-machinery + comment/copy-accuracy
change only. Mechanical UI-surface scan: `## Files to Edit` contains no path
matching the `ui-surface-terms.md` glob superset → Product/UX gate NONE. The
`lib/ws-client.ts` reason-string edit is a one-word number correction inside an
existing close-frame string, not a new surface — no copy review lane fires.
Engineering assessment question ("significant architectural decisions / beyond
normal implementation") not met — literal updates against an already-applied
migration.

## Test Scenarios

- **AC2(c/e/f) re-acquire boundary (integration):** Given a held lease whose heartbeat is aged 300 s (past the 240 s mig-133 expiry), when a different host calls `acquire_worktree_lease`, then it takes over with gen+1.
- **Stale-slot lazy sweep (integration):** Given a slot heartbeat backdated 300 s under cap=1, when a new conversation acquires, then the lazy sweep reaps the stale row and status is `ok`.
- **Fresh-slot negative gate (integration):** Given a slot heartbeat backdated 60 s (inside 240 s), when a new conversation acquires under cap=1, then `cap_hit` fires — the boundary's lower bound.
- **Copy-assertion parity (unit):** Given `CONCURRENCY_CAP` copy updated to `~10 minutes`, when `ws-protocol.test.ts` runs, then the `toContain("10 minutes")` assertion passes — copy and pin move atomically.
- **Verification commands (deterministic):** the two `doppler run -p soleur -c dev_scheduled` invocations quoted in AC5, plus `npm run test:ci -- test/ws-protocol.test.ts --project unit` for AC8.

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
| Defer the four discovered carriers (`ws-client`, `host-identity`, `ws-protocol`, `cap-hit-self-heal`) to a follow-up issue | Rejected at deepen-plan: identical mig-133 drift class surfaced by the mandated sweep, ~15 literal edits total, and one of them is user-facing copy that over-promises the reclaim window — a separate PR+issue cycle costs more than the fix and would ship a plan documenting its own unfixed finding. |

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

### Census — stale-threshold carriers (deepen-plan widened sweep)

Sweep over `apps/web-platform/{test,lib,server}` for `ageHeartbeat`, `backdate`,
`heartbeat_at` writes, `120 s`/`120s`/`12x`/`200` staleness literals:

- **Carriers (folded in):** the two brief files plus `lib/ws-client.ts` (comment
  `120 s threshold ≈ 3 min` + `~3 minutes` copy), `test/ws-protocol.test.ts`
  (derivation comment + `"3 minutes"` assertion — coupled to the copy),
  `server/host-identity.ts` (`120s lockout` comments + thrown error string),
  `test/ws-handler-cap-hit-self-heal.test.ts` (`>120s` comment beside 240 mocks).
- **Already correct:** `agent-runner-stuck-active-reaper.test.ts:131` and
  `ws-handler-cap-hit-self-heal.test.ts:109` mock `…: 240`; all
  heartbeat-cadence comments in `concurrency.ts`/`worktree-write-lease.ts`
  already read `25s→50s` / `30 s→60 s` / `4.8 missed 50 s beats`.
  *(Post-review addendum: that file's `:11` header still claimed the 60 s
  cadence — folded into this PR along with the `ws-handler.ts` `≤60 s`
  reaper comments and the `conversations-tools.ts` `~3 min` agent-facing
  description the `~3 min`-shaped census missed.)*
- **Excluded lookalikes:** see Technical Considerations — queue/render/clone/
  retry/vitest 120 s constants unrelated to mig-133; `test/supabase-migrations/*`
  sentinels pin historical bodies by design.

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
| sweep scope = "no other integration test file" | same drift class found in 4 more files (app copy + error string + unit-test comment/assertion) — falsifiable-premise catch | folded in as inferred items with justification (Scope Check) |

### Gate dispositions

- **Phase 1.4 network-outage:** no trigger pattern in the brief (the "500s" cited is HTTP 500 plural on a descoped leg, not a connectivity symptom). Skipped.
- **Phase 1.5/1.5b community/functional overlap:** test-constant fix; no community artifact class applies; no uncovered stack. Skipped.
- **Phase 1.6 external research:** strong local context + verified live diagnosis → skipped.
- **Phase 2.7 GDPR:** `server/host-identity.ts` matches the regulated-surface path regex, so the gate fires — assessed inline (no `soleur:gdpr-gate` spawn available): the diff is three stale numbers in comments + one thrown error string; no schema, no processing activity, no PII/auth-flow/API change; synthetic users only on dev. Compliant; triggers (a)-(d) none.
- **Phase 2.8 IaC:** no new infrastructure. Skipped.
- **Phase 2.9 Observability:** required post-fold-in (`server/host-identity.ts` matches `apps/*/server/`); section present regardless since restoring the legs IS the liveness signal.
- **Phase 2.10 ADR/C4:** no architectural decision — test alignment to an already-recorded contract (mig 133's own header + `concurrency-heartbeat-backoff.test.ts` are the record). Skipped.
- **Phase 2.11 Encryption Posture:** no persistent store, no new connection. Skipped.
- **Phase 2.12 Guard Contract:** deliverable contains no guard/gate/lint. Skipped.
- **Plan Step 4.5 advisor consult:** trivially mechanical (literal updates, no architecture choice) — skipped per the carve-out.
- **Plan review:** the multi-agent panel (`plan-review` skill) cannot be spawned in this pipeline context (no Task tool). Standing checks run inline instead: every edit-table anchor verified against the live files at write time; every AC is deterministic over file state or the two pinned live test runs; nothing is taste-class pending operator decision.

## References & Research

- Migration: `apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql` (+ `.down.sql`)
- Contract pins: `apps/web-platform/server/concurrency.ts:31`, `apps/web-platform/server/worktree-write-lease.ts:83`, `apps/web-platform/test/concurrency-heartbeat-backoff.test.ts`
- Workflow: `.github/workflows/scheduled-integration-suites.yml:217-230`, `:262-275`
- Trackers: #9993 (red legs), #9994 (deleteUser 500s — out of scope), #9995 (MU1 401 — out of scope), #3373 / #3221 (rot warnings — acknowledged)
- Parent: `knowledge-base/project/plans/2026-10-10-feat-dormant-integration-ci-plan.md` (#9855 PR 2)
- Plan: `2026-07-18-perf-supabase-disk-io-write-reduction-plan.md` (mig 133's origin)
