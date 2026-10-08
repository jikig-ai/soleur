# Tasks: Retire the plaintext Redis AOF backstop volume (#8285, also #6894)

Plan: `knowledge-base/project/plans/2026-10-08-chore-retire-inngest-plaintext-redis-backstop-plan.md`

PR bodies use `Ref #8285` / `Ref #6894` only (no closing keyword). PR A's body first line: "Merging this alone does not mutate production."

## Phase 0 - Evidence re-pull (read-only, at work start and before each production phase)

- 0.1 Re-read `data_mount_devid` on the newest `host_role=dedicated` probe row (expect `scsi-0HC_Volume_106903269`), Doppler `soleur-inngest/prd` `INNGEST_LUKS_ACTIVE_VOLUME_ID` / `INNGEST_LUKS_CUTOVER`, wrong-volume alert `paused=false`, incident list, `scripts/followthroughs/inngest-luks-property-8296.sh` verdict, Hetzner volumes/servers/snapshots/backups.
- 0.2 Record `redis_keys` / `redis_active` from the newest probe row for the destruction record (informational only).
- 0.2b Throwaway local-backend experiment: an orphaned state entry is destroyed by `terraform apply -target=<addr>` alone.
- 0.2c Read the on-host `rollback)` arm / `assert_ids` and its fixtures: confirm rollback refuses with the plaintext device absent (else retire the op in PR A).
- 0.3 Confirm `squash_merge_commit_message` setting; keep closing keywords out of commit and PR bodies.

## Phase 1 - PR A: decouple, apparatus, gates (no production effect on merge)

- 1.1 `inngest-host.tf`: add `local.inngest_retired_plaintext_volume_id = "106261946"` and pass it as `inngest_volume_id`; delete `hcloud_volume.inngest_redis` and `hcloud_volume_attachment.inngest_redis` blocks and dependent comments. Keep the template key (AC5 floor 17).
  - 1.1.1 Write the Guard 1 static scan and matrix rows in `inngest-host.test.sh` first (RED).
- 1.2 Create `inngest-backstop-wipe.tf`, `cloud-init-inngest-backstop-wipe.yml`, `inngest-backstop-wipe.test.sh` (D2). Variables with defaults in `variables.tf`; reuse `var.betterstack_logs_token`.
  - 1.2.1 Write the Guard 3 matrix rows (refusal fixtures, call-site census, read-back mutation) before the script.
  - 1.2.2 Script order: bounded wait, identity guards, capture non-payload identity, `blkdiscard -z`, flush, full O_DIRECT read-back via `cmp`, signature check, evidence POST (token on stdin).
- 1.3 `apply-web-platform-infra.yml`: convert `inngest_volume_recut` into `inngest_backstop_retire` with `phase` (detach, wipe, teardown, destroy), join the `terraform-apply-web-platform-host` concurrency group, idempotent per-phase convergence, #8285 progress comment step, stock preflight; drop retired addresses from `inngest_host` and `inngest_host_replace` targets and jq selects; new `tests/scripts/lib/inngest-backstop-retire-gate.sh` + `tests/scripts/test-inngest-backstop-retire-gate.sh` (Guard 2 rows first); delete the old recut gate lib and test; adjust the shape/replace gate allow-sets.
  - 1.3.1 Live-store gate (2.0) in front of EVERY phase: flag `done`, pointer 106903269, live volume attached, fresh probe on it, no in-flight merge apply, untargeted plan with the server as a present no-op.
  - 1.3.2 Destroy-phase precondition (Guard 4): evidence row bound to `wipe_run_id` nonce, timestamp after detach, id and size match; D4 alternative inputs `erasure=provider-only` + `clo_attestation_ref`.
- 1.4 Update `plugins/soleur/test/terraform-target-parity.test.ts`, `stock-preflight-coverage.test.ts`, `web-host-escrow-preflight-census.test.ts`, `inngest-host.test.sh`, `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`; read the pre-merge infra-validation plan JSON (server no-op, only the two orphan deletes); run `python3 scripts/lint-encryption-posture.py`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 scripts/lint-guard-contract.py`.
- 1.5 Records: destruction-record template (`PENDING-EVIDENCE` fields), ADR-142 addendum (adopting), runbook "Retiring the backstop" section + 5a banner, roadmap row.
- 1.6 Review, QA, ship PR A; verify merge applied nothing to the retired addresses.

## Phase 2 - Production phases (each: show exact command, wait for named go-ahead, run, self-pull evidence)

- 2.1 `phase=detach` dispatch; verify plan shape (server and LUKS pair no-op) and `server: null` on volume 106261946.
- 2.2 `phase=wipe` dispatch (step B teardown accepts any subset of the wipe addresses; `phase=teardown` for a leaked host); verify the nonce-bound evidence row `result=wiped readback=zero sig_after=none`, wipe host and attachment gone.
- 2.3 `phase=destroy` dispatch; verify preconditions in log, one delete, Hetzner 404.
- 2.4 Verification read-backs: volume 404, server volumes `[106903269]`, state clean, probe row still on LUKS, alert quiet, snapshots/backups 0.
- 2.5 Target dates: PR A merged 10-12; detach 10-13; wipe 10-15; PR B merged by 10-21. Decision point 2026-10-17: if the wipe phase has not succeeded, ask for the D4 fallback (delete without zeroing, CLO-attested downgrade).

## Phase 3 - PR B: convergence (after 2.4)

- 3.1 Delete wipe `.tf`, template, test, retire job, gate lib and test; update parity tests.
- 3.2 Retire `op=luks-rollback` (workflow and orchestrator, suites, guard-vacuity floor); rewrite runbook 5a.
- 3.3 Ledger: remove the `hcloud_volume.inngest_redis` row, correct the LUKS row text; run the lint.
- 3.4 Delete the probe script + test + `run_suite` line; fix stale comments (betterstack-logs-alerts.tf, uptime-alerts.tf, inngest-redis-luks.tf, variables.tf, followthroughs/inngest-luks-cutover-6894.sh).
- 3.5 Complete the destruction record (counts only), Article 30 PA-13/PA-21/PA-22 in-cell amendments, compliance-posture row, `model.c4` edits + regenerate, expenses ledger, ADR-142 landed, CLO attestation.
- 3.6 Ship PR B with `Ref #8285`; afterwards `gh issue close 8285` and `gh issue close 6894` with PR link, run URLs, 404 read-back.
