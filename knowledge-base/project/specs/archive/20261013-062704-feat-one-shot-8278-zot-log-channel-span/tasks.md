# Tasks — feat-one-shot-8278-zot-log-channel-span (#8278)

Derived from `knowledge-base/project/plans/2026-10-06-fix-zot-log-channel-span-grading-plan.md`.
Failing fixtures first (cq-write-failing-tests-before): Phase 2 cases are written
against the CURRENT probe and must redden before the rewrite lands.

## 1. Fixture suite — RED phase (tests/scripts/test-zot-log-channel-probe.sh)

- [ ] 1.1 `row()` gains a `dt` parameter; add `boot_marker_row()`, `dropped_row()`, two-boot control helpers.
- [ ] 1.2 New RED cases: straddle pre-boundary leak → no exit 1; post-boundary leak → exit 1 with `boot=`; post_fail only on old boot → `not_delivered`; forged `zot_last_err=` tail carrying ` boot_id=`/`log_shipper_post_fail=` → verdict unaffected; no usable `boot_id` → exit 3; non-integer pass summary → exit 3; `unknown` boot sentinel never scopes; in-window BOOT marker tightens boundary; DROPPED row with foreign newer boot_id does not select the boot; unscopeable leak row → exit 3 naming ungraded count.
- [ ] 1.3 Update stale pins: `boot_marker(n)`/`reporter_carries_shipper_fields` evidence strings, `since=72h` stub assertion, single-dt fixtures that need a span; raise the assertion floor in the same diff.
- [ ] 1.4 Run the suite against the CURRENT probe — the new straddle/scope cases MUST be red.

## 2. Probe rewrite (scripts/followthroughs/zot-log-channel-7440.sh)

- [ ] 2.1 Carry `dt` + channel tag through both decoders (`jq … @tsv | sort`); delete the `--since 72h` BOOT-marker query and the `n_boot`/`BOOT_MARKER` delivery arm.
- [ ] 2.2 Host-scope control rows on the trusted head (` zot_last_err=` cut); derive `NEWEST_BOOT` + boundary `B0` from host-scoped stamped rows ONLY (ctl rows, BOOT markers; DROPPED rows never select).
- [ ] 2.3 ONE awk pass emits the summary line (all counts + delivery fields); integer guard → exit 3.
- [ ] 2.4 Rewrite the verdict chain on the summary fields; preserve every existing reason token, `control_missing` ahead of boot derivation, counts-only FAIL arm, first-tick `-1` softening; add `boot=` to verdict messages.
- [ ] 2.5 `FLOOR_ROWS` over the bounded span (`min(WINDOW_MIN, bounded-span-minutes)` base).
- [ ] 2.6 New header: one-pass/trusted-region Guard Contract, exit table incl. exit 3, why 72h is gone, `dt` as boundary key, ±5-min residual.

## 3. Verify + record

- [ ] 3.1 `bash tests/scripts/test-zot-log-channel-probe.sh` all green incl. new cases.
- [ ] 3.2 `bash apps/web-platform/infra/zot-log-shipper.test.sh` green unchanged; `bash -n` + shellcheck clean on the probe.
- [ ] 3.3 `git diff origin/main --name-only` shows NO change to `apps/web-platform/infra/cloud-init-registry.yml`, `zot-upload-ceiling-7556.sh`, `zot-fill-rate-7341.sh`, or the sweeper workflow.
- [ ] 3.4 ADR-184 addendum: record the one-pass newest-boot shape, exit 3, and the retired `boot_marker(1)`/72h arm.
- [ ] 3.5 PR body: `Closes #8278`; no `soleur:followthrough` directive added anywhere.
