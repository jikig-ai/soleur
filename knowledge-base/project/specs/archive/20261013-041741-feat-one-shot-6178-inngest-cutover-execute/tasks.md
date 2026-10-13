# Tasks — Author Phase-2 `op=execute` Inngest cutover workflow (#6178)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All host-state / systemctl prose below is behaviour authored INSIDE OCI-baked scripts +
     systemd units (delivered via cloud-init + inngest-bootstrap.sh) or out-of-band Doppler
     writes on soleur-inngest/prd (ignore_changes[value]) — NOT manual provisioning. See the
     plan's §Infrastructure (IaC) and §Flow-Review Reconciliation. -->

Derived from `knowledge-base/project/plans/2026-07-08-feat-inngest-cutover-execute-workflow-plan.md`
(post flow-review reconciliation). Build order top-to-bottom; each task names its target
file(s). `Ref #6178` (NOT `Closes` — #6178 stays open until Phase-4 soak). Authoring only:
workflow + host scripts + hooks.json.tmpl + tests + runbook. No cutover execution.

Flow-review IDs (P0-1…P2-17) trace each task back to a folded defect; see the plan's
`## Flow-Review Reconciliation`.

---

## Phase A — Ledger follow-up (do FIRST)

- [x] **A.1** Flip expense rows 21/22/23 `approved-not-billing` → `active` (past-tense
  clause; keep due date + DPA note).
  `knowledge-base/operations/expenses.md`

## Phase B — 2.0 empty-registry probe (web-host, webhook-delivered)

- [x] **B.1** Create the registry probe: POST `{ functions { id } }` to
  `10.0.1.40:8288/v0/gql`, emit pure JSON `{registry_empty,function_count,function_ids}`,
  `curl --max-time`, fail-LOUD on non-array `.data.functions`.
  `apps/web-platform/infra/inngest-registry-probe.sh`
- [x] **B.2** Register the registry probe on all six webhook-delivery surfaces:
  - `apps/web-platform/infra/server.tf` (triggers_replace join)
  - `apps/web-platform/infra/push-infra-config.sh` (b64 entry; fix prior trailing comma)
  - `apps/web-platform/infra/hooks.json.tmpl` (pass-environment + new GET hook block `inngest-registry-probe`, HMAC/403)
  - `apps/web-platform/infra/infra-config-apply.sh` (FILE_MAP)
  - `apps/web-platform/infra/infra-config-install.sh` (DEST_SPEC + local mirror list)
  - `.github/workflows/apply-deploy-pipeline-fix.yml` (on.push.paths)
  - `plugins/soleur/skills/ship/SKILL.md` (DPF doc list + array + regex alternation)
- [x] **B.4** Create the double-fire verify probe (P1-12): POST `runs(first, filter:
  RunsFilterV2!, orderBy)` `{ timeField: STARTED_AT, functionIDs, from, until }` to
  `10.0.1.40:8288/v0/gql`, paginate `pageInfo.hasNextPage`, emit pure JSON `{runs:[…]}`,
  `curl --max-time`, fail-LOUD on non-array `.data.runs`. Register on the **same six
  surfaces** as B.2 (new GET hook block `inngest-doublefire-probe`).
  `apps/web-platform/infra/inngest-doublefire-probe.sh` + the seven surface files above
- [x] **B.3** Update registration parity tests for **both** web-host scripts:
  - `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` (TRIGGER_FILES: probe + doublefire)
  - `apps/web-platform/infra/infra-config-install.test.sh` (managed-dest count `13 → 15` + mirror)
  - `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (both hook ids in existence loop)
  - `apps/web-platform/infra/infra-config-apply.test.sh` (`test_b64_delivery_parity` — run it)

## Phase C — 2.2b+2.3 cutover-flip oneshot + FSM + guard (OCI-baked, Doppler-armed)

- [x] **C.1** Create the flip oneshot implementing the FSM (P0-1/P0-3/P1-4/P1-5/#5450):
  forward path **stop → FLUSHALL → assert DBSIZE==0 → start**; transitions
  `armed`→`flipping`→`done`; `armed`+DBSIZE≠0 → terminal `aborted` (no start); `rollback` →
  stop + `rolled-back`; `flipping` reboot → no re-FLUSHALL; `done`/`rolled-back`/`aborted`/unset
  → no-op. Every branch emits `logger -t inngest-cutover-flip` JSON (P0-2) + writes host-path
  state slot. Fixture seams `CUTOVER_FLIP_FLAG`/`CUTOVER_REDIS_DBSIZE`/`CUTOVER_FLAG_SET_CMD`/`CUTOVER_SYSTEMCTL_CMD`.
  `apps/web-platform/infra/inngest-cutover-flip.sh`
- [x] **C.1b** Create the on-host state reader (debug aid only — NOT the operator gate).
  `apps/web-platform/infra/cat-inngest-cutover-state.sh`
- [x] **C.2** Create the oneshot service + poll timer; **timer ships ENABLED and is never
  disabled** (P0-1), `OnUnitActiveSec=30s`/`OnBootSec=30s`.
  `apps/web-platform/infra/inngest-cutover-flip.service`,
  `apps/web-platform/infra/inngest-cutover-flip.timer`
- [x] **C.3a** Create the ExecStartPre arm-atomicity guard (P1-5): block start when URI is
  prod and flag not in `{armed, flipping, done}`. Fixture seams `GUARD_POSTGRES_URI`/`GUARD_FLIP_FLAG`.
  `apps/web-platform/infra/inngest-server-flip-guard.sh`
- [x] **C.3b** Bake the flip trio + flip-guard into the OCI image (cp -> COPY -> ENTRYPOINT /tmp stage).
  `.github/workflows/build-inngest-bootstrap-image.yml`
- [x] **C.3c** Install the flip trio + flip-guard on the dedicated host; enable the poll
  timer at install; wire `inngest-server-flip-guard.sh` as `ExecStartPre=` on
  `inngest-server.service`.
  `apps/web-platform/infra/inngest-bootstrap.sh`
- [x] **C.3d** Bump the OCI image tag so the dark host pulls the new image (v1.1.18 ->
  v1.1.19). NOTE: the dedicated host's image tag pin lives in the `IREF=` line of
  `cloud-init-inngest.yml` (templatefile'd by inngest-host.tf), NOT in `inngest.tf`
  locals — `inngest.tf` has no image-tag local. Bumped there.
  `apps/web-platform/infra/cloud-init-inngest.yml`
- [x] **C.4** (Doc — folds into F.1) Operator arm sequence is pure Doppler writes
  (`INNGEST_POSTGRES_URI`, `INNGEST_HEARTBEAT_URL`, `INNGEST_CUTOVER_FLIP=armed`); no host
  control-plane step; confirm `exit_code:0` via Better Stack.

## Phase D — `op=execute` / `op=verify` / `op=rollback` workflow arms

- [x] **D.1** Add `execute` + `verify` + `rollback` to the `op` choice list + `case "$OP"`;
  `$OP` env-only; `concurrency.group: deploy-inngest-restart`; every new `curl --max-time`;
  `timeout-minutes` >= poll budget.
  `.github/workflows/cutover-inngest.yml`
- [x] **D.2** `op=execute` spine: 2.0 registry-probe (ABORT on non-empty + remediation text,
  P1-6); 2.1 capture across computed-once `$CUTOVER_HOSTS` (record `Σcaptured`); 2.2 quiesce
  the same host-set (P1-8); **QUIESCE HARD GATE** — assert zero inngest running before the
  SEAM, else exit non-zero (P1-7); SEAM prints arm + 2.4 instructions (Better Stack confirm,
  not host read; P0-2). No CI prod-write.
  `.github/workflows/cutover-inngest.yml`
- [x] **D.3** `op=verify`: precondition registry-non-empty (2.4 happened, P1-9/P2-17); 2.6
  double-fire check via `/hooks/inngest-doublefire-probe` (P1-12), bucket
  `floor(startedAt/cron_period)`, no `scheduled_tick`; auto-emit missed-tick `trigger-cron`
  list (P2-16).
  `.github/workflows/cutover-inngest.yml`
- [x] **D.4** `op=rearm` gating + reconciliation: precondition 2.4 happened; partial-rearm
  branch surfaces `Σcaptured != rearmed` delta loudly + offers re-arm retry (P1-11).
  `.github/workflows/cutover-inngest.yml`
- [x] **D.5** Document rollback sequence in the SEAM (stop dedicated via Doppler `rollback` ->
  app repoint loopback -> `op=rollback`); same path is the `aborted` recovery (P0-1/P0-3/P1-13).
  `.github/workflows/cutover-inngest.yml`
- [x] **D.6** Add `op=rollback` arm: re-enable + restart inngest on every `$CUTOVER_HOSTS`
  host (reverse of 2.2) + inventory confirm; `$OP` env-only, `--max-time`, same concurrency
  group (P1-13).
  `.github/workflows/cutover-inngest.yml`

## Phase E — Tests

- [x] **E.1** Extend workflow test: `execute`+`verify`+`rollback` choices; execute quiesce
  hard-gate assertion (P1-7); verify calls doublefire hook + no `scheduled_tick`; rollback
  assertion; both hook ids in existence loop; `--max-time` count-parity; `$OP` env-only.
  `apps/web-platform/infra/cutover-inngest-workflow.test.sh`
- [x] **E.2** Registry-probe fixture test (empty/non-empty/malformed fail-LOUD).
  `apps/web-platform/infra/inngest-registry-probe.test.sh`
- [x] **E.3** Flip FSM test: order stop->FLUSHALL->assert->start; `armed`->`flipping`->`done`;
  timer never disabled; DBSIZE!=0 -> `aborted`/exit1; `rollback` -> `rolled-back`; `flipping`
  reboot no re-FLUSHALL; no-op states; `logger` line on every branch.
  `apps/web-platform/infra/inngest-cutover-flip.test.sh`
- [x] **E.4** Flip-guard test (P1-5): prod URI + unset flag -> block; prod URI + armed/flipping/done
  -> allow; dark URI -> allow.
  `apps/web-platform/infra/inngest-server-flip-guard.test.sh`
- [x] **E.5** Double-fire probe fixture test (valid runs / malformed fail-LOUD / `--max-time`).
  `apps/web-platform/infra/inngest-doublefire-probe.test.sh`
- [x] **E.6** Run parity guards green (count now `15`): `infra-config-apply.test.sh`,
  `infra-config-install.test.sh`, `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`.

## Phase F — Runbook + drift-guard

- [x] **F.1** Extend cutover procedure: gated op sequence; exact Doppler arm commands;
  Better Stack flip-state read (no host read, P0-2); 2.0 non-empty remediation (P1-6);
  rollback sequence (P1-13); `aborted` recovery (P0-3); heartbeat suppression window (P2-14);
  bounded-outage note. `Ref #6178`.
  `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- [x] **F.2** Register flip trio + flip-guard on cloud-init/OCI surfaces only; confirm they
  are **absent** from the webhook surfaces and that the two web-host probes stay disjoint;
  confirm `cat-inngest-cutover-state.sh` is debug-aid-only.
  (verification across `server.tf` / `push-infra-config.sh` / `infra-config-*.sh`)

## Cross-cutting checks (before PR-ready)

- [x] Amend **ADR-100** Decision 6a + Alternatives (flip mechanism); no C4 changes.
- [x] Acceptance criteria AC-EXEC1/EXEC2/QUIESCE-GATE/VERIFY/ROLLBACK/PROBE/FLIP/GUARD/
  REGISTER/LEDGER/NOSSH/NOBODY all satisfied.
- [x] No `ssh` in any new runbook/discoverability command (AC-NOSSH).
- [x] No reminder bodies/actors/connection strings echoed (AC-NOBODY).
- [x] Every new `curl` carries `--max-time`; `$OP` env-only (no `${{ inputs.op }}`);
  every new hook id exists in `hooks.json.tmpl`; concurrency group `deploy-inngest-restart`.
