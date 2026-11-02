# Tasks — feat-one-shot-11068-inngest-alerts-push (#11068)

Plan: `knowledge-base/project/plans/2026-10-25-chore-inngest-alerts-push-channel-plan.md`

## Phase 1 — probe first (RED)

- [ ] 1.1 Create `plugins/soleur/scripts/inngest-alerts-push-probe.ts` — standalone `bun` probe (~50 lines), modeled on `plugins/soleur/scripts/inngest-luks-alert-armed-probe.ts`: extract the resource blocks for `logtail_exploration_alert.inngest_luks_wrong_volume` + `logtail_exploration_alert.inngest_step_524` (betterstack-logs-alerts.tf) and `betteruptime_heartbeat.inngest_server_probe` (uptime-alerts.tf); exit 0 + `PUSH_ARMED` when all declare `push = true`, else exit 1 + `PUSH_MISSING <resource>` (first missing). `argv[2]` test seam takes a synthesized infra root.
- [ ] 1.2 RED check: run `bun plugins/soleur/scripts/inngest-alerts-push-probe.ts` on the unmodified tree — expect exit 1 with `PUSH_MISSING inngest_luks_wrong_volume`.

## Phase 2 — the flips (GREEN)

- [ ] 2.1 `apps/web-platform/infra/betterstack-logs-alerts.tf` — `push = true` on `logtail_exploration_alert.inngest_luks_wrong_volume` (~L298) and `logtail_exploration_alert.inngest_step_524` (~L740). One comment line per resource: #11068 flip under the #9168 measured-flip convention (revert to `push = false` if the apply refuses it). `email`/`call`/`sms`/`critical_alert`/`paused`/`escalation_target` unchanged.
- [ ] 2.2 `apps/web-platform/infra/uptime-alerts.tf` — `push = true` on `betteruptime_heartbeat.inngest_server_probe` (L538); comment names inngest_prd/inngest_consumer sibling parity + #11068. `paused`/`lifecycle`/`policy_id`/`team_wait` unchanged.
- [ ] 2.3 `bun plugins/soleur/scripts/inngest-alerts-push-probe.ts` — expect exit 0 `PUSH_ARMED`.

## Phase 3 — test-pin update

- [ ] 3.1 `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — section (d): flip the third `has` from `push = false` to `push = true`; update the pass label ("call/sms false, push true — parity with inngest_prd/inngest_consumer") and the (d) comment (`ops@ email only, like DP-10` is no longer the invariant). `EXPECTED_PASSES` stays 21 — expectation flips, count unchanged.
- [ ] 3.2 `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — 21 passed / 0 failed.

## Phase 4 — census + verify

- [ ] 4.1 Census check: `rg -n 'push\s*=\s*true' apps/web-platform/infra/betterstack-logs-alerts.tf apps/web-platform/infra/uptime-alerts.tf apps/web-platform/infra/inngest.tf` — all five Inngest-serving alert resources (`inngest_luks_wrong_volume`, `inngest_step_524`, `inngest_server_probe`, `inngest_prd`, `inngest_consumer`) carry `push = true`.
- [ ] 4.2 Mutation spot-check: temporarily revert any one resource to `push = false`; probe must exit 1 naming it; restore.
- [ ] 4.3 `terraform fmt -check` on the two edited .tf files (or run `terraform fmt`).

## Phase 5 — ship semantics

- [ ] 5.1 PR body first line states: merging this PR alone mutates production (per-merge apply-web-platform-infra, all three addresses on the `-target` allow-list). PR body carries `Ref #11068`, NOT `Closes`.
- [ ] 5.2 Post-merge: observe the merge-triggered apply run. Green → the apply IS the vendor-acceptance measurement; close #11068 with the run link. Refusal (422/no-op) → revert refused `push` attribute(s) to `false` in a follow-up + record the measurement in the resource comment; issue stays open with the measurement.
