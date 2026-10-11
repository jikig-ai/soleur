# Tasks — fix: Realign dormant env-gated integration tests to migration 133's 240 s liveness contract

Plan: `knowledge-base/project/plans/2026-10-11-fix-mig133-integration-test-threshold-drift-plan.md`
Issue: #9993 (link only — do NOT `Closes`; sibling legs #9994/#9995 keep the tracker open)

Constraint: edit ONLY the two named test files. Do not touch the deleteUser-500
(#9994) or MU1-JWT-401 (#9995) defect surfaces. Synthetic `*@soleur.test` users
on dev only.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm no drift since plan-write: `git log --oneline origin/main -3 -- apps/web-platform/test/worktree-write-lease.integration.test.ts apps/web-platform/test/conversation-archive-release-slot.integration.test.ts apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql` — re-read the two files if a sibling landed.
- [ ] 0.2 Re-grep the stale literals as anchors: `grep -n "ageHeartbeat(121)\|backdateSlotHeartbeat(stuckConv, 200)\|120" apps/web-platform/test/worktree-write-lease.integration.test.ts apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` — the edit table in the plan keys on these; if lines moved, match on content.

## Phase 1 — `apps/web-platform/test/worktree-write-lease.integration.test.ts`

- [ ] 1.1 Add module constant `const STALE_LEASE_AGE_S = 300;` beside `SYNTHETIC_EMAIL_PATTERN` (~:38) with comment: `// 300 s = 240 s mig-133 lease expiry + 60 s DB-vs-runner clock-skew margin`.
- [ ] 1.2 Replace `await ageHeartbeat(121);` at the three stale-arm sites (AC2(c) :222, AC2(e) :251, AC2(f) :260) with `await ageHeartbeat(STALE_LEASE_AGE_S);`.
- [ ] 1.3 Update the three `120s` comments — :9 (`240s heartbeat expiry (mig 133)`), :18 (`sleeping 240s`), :236 (`no 240s wait — tombstone`).

## Phase 2 — `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`

- [ ] 2.1 Update the boundary-comment block :301-308 to 240 s semantics (`now() - 240s`; cite mig 133 as the live threshold writer; `just past 240s is reaped`; `under 240s is preserved`).
- [ ] 2.2 Retitle :327 to `stale-heartbeat slot (300 s old) is reaped by lazy sweep on next acquire — dead-end window now past the 240 s threshold` and update comments :330 (`past 240 s (mig 133)`) and :342 (`past the 240 s threshold (mig 133)`).
- [ ] 2.3 `await backdateSlotHeartbeat(stuckConv, 200);` → `await backdateSlotHeartbeat(stuckConv, 300);` (or a `STALE_SLOT_AGE_S = 300` constant mirroring Phase 1).
- [ ] 2.4 Negative-gate comments ONLY: :365 `under the 240 s threshold`, :378 `well within the 240 s threshold` — keep `backdateSlotHeartbeat(liveConv, 60)` literal UNCHANGED.

## Phase 3 — Sweep + live verification

- [ ] 3.1 Census re-run (AC6): `grep -rn "ageHeartbeat\|backdate" apps/web-platform/test/ | grep -v "worktree-write-lease\|conversation-archive-release-slot"` — expect zero heartbeat-aging carriers elsewhere.
- [ ] 3.2 Residual `120` audit (AC4): `grep -n "120" <both files>` — every surviving token must sit inside an explicit historical citation (`raised 120→240`, `was 120 s, mig 133`), never as the live contract.
- [ ] 3.3 Live green — worktree-lease leg (AC5):
  `cd apps/web-platform && doppler run -p soleur -c dev_scheduled -- env WORKTREE_LEASE_INTEGRATION_TEST=1 npm run test:ci -- test/worktree-write-lease.integration.test.ts --project unit` → 8/8 pass.
- [ ] 3.4 Live green — slot-trigger leg (AC5):
  `cd apps/web-platform && doppler run -p soleur -c dev_scheduled -- env SLOT_TRIGGER_INTEGRATION_TEST=1 npm run test:ci -- test/conversation-archive-release-slot.integration.test.ts --project unit` → 6/6 pass.
  Non-blocking noise: an `afterAll` deleteUser 500 hook error (#9994) — per-test results are the verdict.

## Phase 4 — Ship prep

- [ ] 4.1 AC sweep against the plan's `## Acceptance Criteria` (AC1–AC7).
- [ ] 4.2 PR body: reference `issue #9993` — never `Closes #9993` (tracker stays open until #9994/#9995 land) + `## Changelog` section.
- [ ] 4.3 Post-merge note for operator digest: next nightly run should show `worktree-lease` + `slot-trigger` legs green.
