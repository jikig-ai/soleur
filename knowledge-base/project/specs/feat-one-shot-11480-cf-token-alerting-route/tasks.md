# Tasks: fix(cf-token-scope) retained Notifications probe route

Plan: `knowledge-base/project/plans/2026-10-29-fix-cf-token-scope-notification-route-plan.md`
Issue: #11480 | PR body: `Closes #11480`

## Phase 1 — Pre-flight

- [ ] 1.1 Duplicate gate: `git grep -n 'notification_policies' origin/main -- plugins/soleur` — if
  zero hits (sibling PR #11456 landed first), halt work and close #11480 as duplicate rather than
  shipping a no-op diff
- [ ] 1.2 Baseline: `bash plugins/soleur/test/cf-token-scope.test.sh` — confirm the suite is green
  before the change (148/148 at plan time) so post-change red is attributable

## Phase 2 — Core implementation

- [ ] 2.1 `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` — `DT_ROWS` retained row:
  label `accounts/<acct>/notification_policies` → `accounts/<acct>/alerting/v3/policies`; URL
  `accounts/\$ACCT/notification_policies?per_page=1` → `accounts/\$ACCT/alerting/v3/policies?per_page=1`
- [ ] 2.2 `plugins/soleur/skills/cf-token-scope/SKILL.md` — controls-table retained row →
  `accounts/<acct>/alerting/v3/policies` / `.../alerting/v3/policies?per_page=1` (keep the
  `Notifications` permission label — it names the scope, not the route)

## Phase 3 — URL-dispatch tests

- [ ] 3.1 `plugins/soleur/test/cf-token-scope.test.sh`: mock dispatch arm `*notification_policies*)`
  → `*alerting/v3/policies*)` — same position in the `case`, `MOCK_NOTIF` lever unchanged
- [ ] 3.2 D1 dry-run fragment loop: `notification_policies` → `alerting/v3/policies`
- [ ] 3.3 D7 post-widen assert: run under `MOCK_CURL_URLLOG` and assert the resolved
  `accounts/acct9876543210fedcba/alerting/v3/policies` URL appears in the log (corrected endpoint
  exercised on the `--expect-lb-scopes` path, per the issue)
- [ ] 3.4 Add `src_lacks 'notification_policies'` regression pin (near the D-doc/D12 block) and
  `d_has 'alerting/v3/policies' "$SKILLDOC"` doc pin

## Phase 4 — Verify acceptance criteria

- [ ] 4.1 `bash plugins/soleur/test/cf-token-scope.test.sh` — exit 0, all assertions green; record
  the pass count in the PR body
- [ ] 4.2 `git grep -n 'notification_policies' -- plugins/soleur/` → zero matches
- [ ] 4.3 `git grep -n 'alerting/v3/policies' -- plugins/soleur/skills/cf-token-scope/` → retained
  row, controls-table row, and dispatch arm all present
- [ ] 4.4 Confirm a mocked 404 on the corrected route still exits 3 with per-row
  `denied (404, unverified` attribution (fail-closed posture unchanged)
