# Tasks — inngest LUKS first-boot EnvironmentFile ordering (#9939)

Plan: `knowledge-base/project/plans/2026-10-10-chore-inngest-luks-first-boot-envfile-ordering-plan.md`

## Phase 1 — Unit conditions

- [x] Add `ConditionPathExists=/etc/default/inngest-doppler` + `ConditionPathExists=/etc/default/inngest-luks` to the `inngest-luks-open.service` `[Unit]` block in `apps/web-platform/infra/cloud-init-inngest.yml` (after `Before=`), with a why-comment (skip-vs-fail; env files can be absent on stage abort / pre-write pull-in).
- [x] Add `ConditionPathExists=/etc/default/inngest-server` + `ConditionPathExists=/etc/default/inngest-luks-volumes` to `[Unit]` in `apps/web-platform/infra/inngest-luks-cutover.service` (comment: the timer is not the only trigger — `[Install] WantedBy=multi-user.target`).
- [x] Add the same two lines to `[Unit]` in `apps/web-platform/infra/inngest-luks-cutover.timer` (comment: evaluated at activation, not per-elapse; file set mirrors the service's `EnvironmentFile=` set).
- [x] Keep every `EnvironmentFile=` line unprefixed — no `-` tolerance.

## Phase 2 — Evidence-channel guard

- [x] `scripts/followthroughs/inngest-provision-rehearsal-capture.sh`: forbidden-row check counting `Failed to start inngest-luks` in the mode's row set (`HOST_ROWS` for phase-a/phase-b, `POST_ROWS` for post-reboot) → `viol` on `> 0`.

## Phase 3 — Suite pins

- [x] `apps/web-platform/infra/inngest-redis-luks.test.sh`: T1.x asserts for both condition lines + unprefixed `EnvironmentFile=` retained; mutation row dropping a condition → RED; floor bump.
- [x] `apps/web-platform/infra/inngest.test.sh`: arm asserting both committed trio files carry both conditions + unprefixed `EnvironmentFile=`.
- [x] `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh`: fixture arm injecting a `Failed to start inngest-luks-cutover.service` row → expects `viol`/FAIL; clean fixture still passes.

## Phase 4 — Ratchet + PR disposition

- [x] `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 53 → 54 with the PLACEMENT/TRUTH/NO SUBSTITUTE comment.
- [ ] PR body references `Ref #9939` (NOT `Closes` — issue stays open until post-merge evidence lands).

## Phase 5 — Post-merge verification (evidence for issue close)

- [ ] Confirm mint → build → `bump-cloud-init-pin` delivered a `vinngest-v*` tag whose carriers are byte-identical to the merged files (advisory GuardA green on main).
- [ ] Dispatch `inngest-provision-rehearsal.yml` (`dry_run=false`); evidence artifact carries `REHEARSAL_PHASE_B_RECOVERY=PASS` + `REHEARSAL_POST_REBOOT_LATCH=PASS` with zero `Failed to start inngest-luks*` rows.
- [ ] `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-assert-absence.sh --host soleur-inngest-prd --absence 'Failed to start inngest-luks' --control SOLEUR_INNGEST_LUKS_CUTOVER --since 6h` → `SOLEUR_ABSENCE_ASSERT outcome=clean`.
- [ ] Attach evidence to #9939 and close.
