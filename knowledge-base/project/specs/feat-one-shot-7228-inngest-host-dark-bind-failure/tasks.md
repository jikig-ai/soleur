# Tasks — inngest dedicated-host: detection, diagnosis, cutover safety

Plan: `knowledge-base/project/plans/2026-08-11-fix-inngest-dedicated-host-bind-failure-plan.md`
Review findings that shaped it: `plan-review-findings.md` (same directory) — read it before
starting; three phases of the first draft were net-negative and the corrections are recorded there.

RED before GREEN for every behavioral change (`cq-write-failing-tests-before`).

## Phase 0 — Preconditions

- [ ] 0.1 Re-verify the outage is still live: `ECONNREFUSED` count against 10.0.1.40 in the last
      hour, field-isolated on `host`. Self-pull via
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`.
      Never ask the operator to fetch (`hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] 0.2 Confirm brake run 31486949232's outcome. Predicted: `confirm_flip_state` times out
      because the host ships no rows, so the run exits 1 while the flag write lands. Record which
      value `INNGEST_CUTOVER_FLIP` actually rests at — `rollback` vs `rolled-back` — and do not
      assert the terminal state without a discriminator.
- [ ] 0.3 Confirm `run-registered-suites.sh` still derives its list from `infra-validation.yml`,
      so new suites must be registered there to run at all.

## Phase 1 — Detection independent of the broken host (ships on merge)

- [ ] 1.1 RED: `inngest-consumer-probe.test.sh` — pings on 200 + non-empty registry; suppresses on
      500, on connection-refused, and on 200-with-empty-registry.
- [ ] 1.2 GREEN: `inngest-consumer-probe.sh` cloned from `web-zot-consumer-probe.sh`, wrapping
      `inngest-registry-probe.sh`. Mirror its suppression classification exactly.
- [ ] 1.3 `inngest-consumer-probe.timer`; install from `server.tf` on the web host.
- [ ] 1.4 New `betteruptime_heartbeat` + new `doppler_secret` in `inngest.tf`. Named resource
      addresses. Never a value edit on `doppler_secret.inngest_heartbeat_url_prd`
      (`ignore_changes = [value]` would plan no change and apply nothing).
- [ ] 1.5 `paused = true` in source + the ADR-117 measured-beat PATCH arm gate, per
      `web-probe.tf:39-40`. No UI step anywhere.
- [ ] 1.6 Row + `feeder` in `plugins/soleur/lib/heartbeat-manifest.ts`; `evidence.pattern` must
      resolve against `server.tf`.
- [ ] 1.7 Add the `-target=` line for both new resources to `apply-web-platform-infra.yml`.
- [ ] 1.8 Register `inngest-consumer-probe.test.sh` in `infra-validation.yml`.

## Phase 2 — Make the host diagnosable and verifiable

- [ ] 2.1 RED: listener-gate test — dedicated pusher must not ping when local `/health` is non-200.
- [ ] 2.2 GREEN: ~5 lines in the `HEARTBEATSCRIPTEOF` heredoc in `inngest-bootstrap.sh`.
- [ ] 2.3 Diagnostic-boot path: non-prod `INNGEST_POSTGRES_URI` variable for the dedicated host so
      the flip guard's prod detection yields `is_prod=false` and its ALLOW arm is taken. This is
      the mechanism that makes `## Hypotheses` decidable — treat it as the plan's centerpiece.
- [ ] 2.4 Extend `inngest-server-probe.sh` with `instance_id`, `cli_version`, `cutover_flag`.
      Keep the hourly cadence; do not add a timer, a `SYSLOG_IDENTIFIER`, or a `vector.toml` entry.
      `journal_tail` stays on the boot marker only.
- [ ] 2.5 RED: emitter tests — missing token and failed POST each emit a loud `logger -t` line.
- [ ] 2.6 GREEN: fix the two silent exits in `cloud-init-inngest.yml`'s emitter.
- [ ] 2.7 Token re-stage systemd oneshot: re-fetch from Doppler each boot, never a baked re-stamp.
      Assert over the RENDERED userdata, not the source template.

## Phase 3 — Cutover safety (must land before any host replace)

- [ ] 3.1 RED: `inngest-cutover-latch.test.sh` — `rolled-back` no-op poll, then `armed`, must
      REFUSE the flush. This is the regression the first draft would have introduced.
- [ ] 3.2 GREEN: make the latch append-only ("has `done` EVER been recorded"), not last-write-wins.
- [ ] 3.3 `RequiresMountsFor=/mnt/data` on `inngest-cutover-flip.service`; make the latch write
      fatal instead of `2>/dev/null || true`.
- [ ] 3.4 Sweep `cat-inngest-cutover-state.sh` to the new path — it is the no-SSH operator read
      surface and would otherwise report a false "no state".
- [ ] 3.5 RED: `done` refused on non-200 `/health`; refused on empty registry; guard refuses a
      foreign instance stamp.
- [ ] 3.6 GREEN: probe-derived `done` in `inngest-cutover-flip.sh`. Instance stamp in a SEPARATE
      Doppler key — appending it to the flag value breaks `inngest-server-flip-guard.sh`'s exact
      `case` match and the `EXPECTED_START_SITES` derivation.
- [ ] 3.7 Make `inngest-server-flip-guard.sh` read both keys and refuse a foreign stamp.
- [ ] 3.8 Confirm `inngest-server-flip-guard.test.sh` passes its derivation unmodified.
- [ ] 3.9 Sweep `scripts/cutover-inngest.sh`: `op=arm` copies the shared monitor's URL to the
      dedicated host; `op=rollback` unconditionally deletes it. Both need the new heartbeat.
- [ ] 3.10 `outputs.tf` consumer of `betteruptime_heartbeat.inngest_prd.url`.
- [ ] 3.11 Register every new suite in `infra-validation.yml`.

## Phase 4 — Record

- [ ] 4.1 Amend ADR-100 in place: Decision 6a completion criteria; fold in the
      terminal-state-must-be-re-derived rule; addendum that the cutover did not hold and the soak
      never started. Keep `status: adopting`; rewrite the blockquote implying a running soak.
      Mint NO new ordinal.
- [ ] 4.2 One C4 model line: the web-platform container gains a monitoring probe edge to the
      dedicated host container. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 4.3 Correct the stale arm64/cax11 prose in `inngest-betterstack-token.tf` and the false
      `DBSIZE` durability claim at `inngest-host.tf:229`.

## Phase 5 — Deferrals (must exist before PR-ready)

- [ ] 5.1 File the host-replace issue; cite as `Ref`, not `Closes`.
- [ ] 5.2 File the cutover-window issue (quiesce-web → confirm → arm → verify).
- [ ] 5.3 File the v1.41.1 bump issue, carrying the goose-migration coupling, the dual-arch
      checksum requirement, `--postgres-max-open-conns` as a durable-detection sentinel, and the
      `signkey-prod-` strip.
- [ ] 5.4 Move #7308's pin-freshness monitor onto the bump issue.
- [ ] 5.5 File the entropy-bound port as its own issue (unrelated subsystem).

## Phase 6 — Exit

- [ ] 6.1 Full `test-all.sh`; name the commit it covered.
- [ ] 6.2 Verify every AC in the plan, including that the new suites actually ran.
