# Tasks — feat-one-shot-8516-dead-probe-heartbeat (#8516)

Plan: `knowledge-base/project/plans/2026-10-07-chore-inngest-probe-dead-probe-heartbeat-plan.md`

## Phase 1 — Tracking issue + TDD red

- [ ] 1.1 File the feeder/arming tracking issue (body per plan `## Deferred Capabilities` D-A:
  candidate feeder shapes — external warehouse-verifying pusher recommended; 5400 s beat budget;
  re-evaluation 2026-10-22; labels `domain/engineering`, `type/chore`; note it must NOT be a
  `follow-through` sweeper enrollment bound to a closing tracker). Capture the issue number.
- [ ] 1.2 Write `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` (Guard Contract
  Guard 1) covering: resource presence, `period = 3600`, `grace = 1800`, `paused = true`,
  `ignore_changes = [paused]`, `email = true`, paid-tier policy gate, the paired `doppler_secret`
  (`name`, `value` reference, `visibility`, `ignore_changes = [value]`), the `#8516` citation
  inside the `inngest_luks_wrong_volume` comment block, both `-target=` lines in
  apply-web-platform-infra.yml, and the MANIFEST row. Run it — confirm RED.
- [ ] 1.3 Commit the failing test (`test(8516): pin the dead-probe heartbeat shape` or similar).

## Phase 2 — Implementation

- [ ] 2.1 `apps/web-platform/infra/betterstack-logs-alerts.tf`: add the #8516 citation comment
  inside the `logtail_exploration_alert.inngest_luks_wrong_volume` block (names the
  `treat_as_zero` blind spot + the heartbeat sibling).
- [ ] 2.2 `apps/web-platform/infra/uptime-alerts.tf`: add
  `betteruptime_heartbeat.inngest_server_probe` + `doppler_secret.inngest_server_probe_heartbeat_url`
  per the plan's Files-to-Edit spec, beside the DP-10 pair.
- [ ] 2.3 `.github/workflows/apply-web-platform-infra.yml`: append both `-target=` lines to the
  bridge-less allow-list near the other inngest heartbeat/secret entries (~line 667-672). Bare
  lines only — no comments inside the backslash-continued list.
- [ ] 2.4 `plugins/soleur/lib/heartbeat-manifest.ts`: add the MANIFEST row
  (`external-probe`, `paused: true`, `feeder.kind = "none"` +
  `url_secret = "INNGEST_SERVER_PROBE_HEARTBEAT_URL"` + `tracking_issue = <1.1's number>`,
  `arming_pending` same issue, `exempt_reason`).
- [ ] 2.5 `model.c4`: freshen the `inngestRedis` #8516 clause (born-paused heartbeat, feeder
  tracked).
- [ ] 2.6 `terraform fmt -check -recursive` over apps/web-platform/infra (+ write `terraform fmt`
  if needed).

## Phase 3 — Verify

- [ ] 3.1 `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — green.
- [ ] 3.2 `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts` — green.
- [ ] 3.3 `bun test plugins/soleur/test/terraform-target-parity.test.ts` — green.
- [ ] 3.4 `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts` — green.
- [ ] 3.5 C4 suites (`apps/web-platform/test/c4-*.test.ts`) — green.
- [ ] 3.6 Mutation spot-check: flip `grace = 1800` → `180` and `paused` → `false`, confirm the
  suite reddens, revert.
- [ ] 3.7 PR body: `Closes #8516` on its own line; blast-radius note (whole-allowlist apply on
  merge); `## Changelog` (semver:patch).
