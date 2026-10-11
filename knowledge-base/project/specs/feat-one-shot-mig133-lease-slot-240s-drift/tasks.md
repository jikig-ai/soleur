# Tasks — fix: Realign dormant env-gated integration tests to migration 133's 240 s liveness contract

Plan: `knowledge-base/project/plans/2026-10-11-fix-mig133-integration-test-threshold-drift-plan.md`
Issue: #9993 (link only — do NOT `Closes`; sibling legs #9994/#9995 keep the tracker open)

Constraint: edit ONLY the two named test files. Do not touch the deleteUser-500
(#9994) or MU1-JWT-401 (#9995) defect surfaces. Synthetic `*@soleur.test` users
on dev only.

## Phase 0 — Preconditions

- [x] 0.1 Confirm no drift since plan-write: `git log --oneline origin/main -3 -- apps/web-platform/test/worktree-write-lease.integration.test.ts apps/web-platform/test/conversation-archive-release-slot.integration.test.ts apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql` — re-read the two files if a sibling landed.
- [x] 0.2 Re-grep the stale literals as anchors: `grep -n "ageHeartbeat(121)\|backdateSlotHeartbeat(stuckConv, 200)\|120" apps/web-platform/test/worktree-write-lease.integration.test.ts apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` — the edit table in the plan keys on these; if lines moved, match on content.

## Phase 1 — `apps/web-platform/test/worktree-write-lease.integration.test.ts`

- [x] 1.1 Add module constant `const STALE_LEASE_AGE_S = 300;` beside `SYNTHETIC_EMAIL_PATTERN` (~:38) with comment: `// 300 s = 240 s mig-133 lease expiry + 60 s DB-vs-runner clock-skew margin`.
- [x] 1.2 Replace `await ageHeartbeat(121);` at the three stale-arm sites (AC2(c) :222, AC2(e) :251, AC2(f) :260) with `await ageHeartbeat(STALE_LEASE_AGE_S);`.
- [x] 1.3 Update the three `120s` comments — :9 (`240s heartbeat expiry (mig 133)`), :18 (`sleeping 240s`), :236 (`no 240s wait — tombstone`).

## Phase 2 — `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`

- [x] 2.1 Update the boundary-comment block :301-308 to 240 s semantics (`now() - 240s`; cite mig 133 as the live threshold writer; `just past 240s is reaped`; `under 240s is preserved`).
- [x] 2.2 Retitle :327 to `stale-heartbeat slot (300 s old) is reaped by lazy sweep on next acquire — dead-end window now past the 240 s threshold` and update comments :330 (`past 240 s (mig 133)`) and :342 (`past the 240 s threshold (mig 133)`).
- [x] 2.3 `await backdateSlotHeartbeat(stuckConv, 200);` → `await backdateSlotHeartbeat(stuckConv, 300);` (or a `STALE_SLOT_AGE_S = 300` constant mirroring Phase 1).
- [x] 2.4 Negative-gate comments ONLY: :365 `under the 240 s threshold`, :378 `well within the 240 s threshold` — keep `backdateSlotHeartbeat(liveConv, 60)` literal UNCHANGED.

## Phase 2.5 — Folded-in same-class carriers (discovered by the deepen sweep)

- [x] 2.5.1 `apps/web-platform/lib/ws-client.ts`: comment :204 `(60 s reaper tick + 120 s threshold ≈ 3 min)` → `(240 s staleness + up to one 300 s reaper poll ≈ ~9 min passive; a retry reaps immediately via the lazy sweep)`; `CONCURRENCY_CAP` reason :210 `~3 minutes` → `~10 minutes`. *(targets corrected post-review — the reaper tick was widened 60→300 s by #4801; see plan §Key Improvements #2)*
- [x] 2.5.2 `apps/web-platform/test/ws-protocol.test.ts`: comment :486 `~3 min = 60 s tick + 120 s threshold` → `~10 min ≈ 240 s staleness + up to one 300 s reaper poll`; assertion :492 `toContain("3 minutes")` → `toContain("10 minutes")`. *(same post-review correction)*
- [x] 2.5.3 `apps/web-platform/server/host-identity.ts`: comments :5/:26 `120s lockout` / `up to 120s` → `240s`; thrown error string :38 `up to 120s.` → `up to 240s.`
- [x] 2.5.4 `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts`: comment :373 `stale (>120s)` → `stale (>240s)`; plus same-file residual carriers `120`/`120_000` → `240`/`240_000`, retired symbol names → `SLOT_STALENESS_THRESHOLD_SECONDS`, `0-180s` window → `~9 min` derivation (review-round folds).
- [x] 2.5.5 Unit-verify the coupled assertion (AC8): `cd apps/web-platform && npm run test:ci -- test/ws-protocol.test.ts --project unit` → 52/52 green.
- [x] 2.5.6 Review-round folds (same defect class): `server/ws-handler.ts` `≤60 s` → `≤300 s` ×2; `server/conversations-tools.ts` `~3 min` agent-facing description → `~4 min` wedge / `~9 min` reap; `agent-runner-stuck-active-reaper.test.ts` header `60 s` → `300 s`; slot-test title → `${STALE_SLOT_AGE_S}` template literal; mig-029→093 provenance.

## Phase 3 — Sweep + live verification

- [x] 3.1 Census re-run (AC6): `grep -rn "ageHeartbeat\|backdate" apps/web-platform/test/ | grep -v "worktree-write-lease\|conversation-archive-release-slot"` — expect zero heartbeat-aging carriers elsewhere.
- [x] 3.2 Residual `120` audit (AC4): `grep -n "120" <both files>` — every surviving token must sit inside an explicit historical citation (`raised 120→240`, `was 120 s, mig 133`), never as the live contract.
- [x] 3.3 Live green — worktree-lease leg (AC5):
  `cd apps/web-platform && doppler run -p soleur -c dev_scheduled -- env WORKTREE_LEASE_INTEGRATION_TEST=1 npm run test:ci -- test/worktree-write-lease.integration.test.ts --project unit` → 8/8 pass.
- [x] 3.4 Live green — slot-trigger leg (AC5):
  `cd apps/web-platform && doppler run -p soleur -c dev_scheduled -- env SLOT_TRIGGER_INTEGRATION_TEST=1 npm run test:ci -- test/conversation-archive-release-slot.integration.test.ts --project unit` → 6/6 pass.
  Non-blocking noise: an `afterAll` deleteUser 500 hook error (#9994) — per-test results are the verdict.

## Phase 4 — Ship prep

- [x] 4.1 AC sweep against the plan's `## Acceptance Criteria` (AC1–AC7).
- [x] 4.2 PR body: reference `issue #9993` — never `Closes #9993` (tracker stays open until #9994/#9995 land) + `## Changelog` section.
- [x] 4.3 Post-merge note for operator digest: next nightly run should show `worktree-lease` + `slot-trigger` legs green.
