# Tasks: web-1 retirement step 2a — dedicated bastion host and birth route (Ref #12866, epic #9421)

Plan: knowledge-base/project/plans/2026-11-17-feat-dedicated-bastion-host-gated-routes-plan.md

Lane: cross-domain (no spec.md on this branch; fail-closed default).

## Phase 1 - Tests first
- 1.1 Reader characterization commit: pin the web callers' current `fresh-host-boot-trail.sh` output byte for byte.
- 1.2 Write `tests/scripts/test-bastion-host-birth-gate.sh` (Guard 1 rows 1-9, 5a-5c, harness rows) over synthesized `tfplan.json` fixtures; see it RED.
- 1.3 Write `apps/web-platform/infra/bastion.test.sh` (EGRESS rows 1-13, SETTLE, HOSTKEY, BUDGET, SHAPE); render through Terraform; SKIP-PARTIAL locally without terraform, FAIL under CI.
- 1.4 Add the bastion create fixture row to `tests/scripts/test-destroy-guard-counter-web-platform.sh`.
- 1.5 Write `tests/scripts/test-bastion-boot-verify.sh`; add the reader strict-mode mutation rows (untagged event, other-host tag, missing anchor, unbound token).

## Phase 2 - Terraform
- 2.1 `bastion.tf`: key, server (cx23 literal, `ipv6_enabled = false`, x86 and DSN preconditions), `local.bastion_private_ip`, network attachment, firewall (zero rules) with a separate attachment, outputs, EXPOSURE note. Run `terraform validate`.
- 2.2 `tests/scripts/lib/bastion-resources.txt`; parity test: exclusions, `stripDispatchJobs`, and the job's `-target` lines equal to the list.

## Phase 3 - Cloud-init
- 3.1 `bastion-cloud-init.yml`: baseline nftables (inet, input/output drop) before `network-pre.target`; ssh masked; Terraform host key via `ssh_keys`.
- 3.2 ADR-326 blocks byte-identical to `cloud-init.yml` (anchor lines; same helper names through `templatefile`).
- 3.3 `bastion-egress.sh` plus its service and timer (atomic swap, never empties the set; apt mirror and Sentry allowlist, each cited).
- 3.4 Readiness emit (first boot only, exact `QUERY` literals, `var.sentry_dsn`).

## Phase 4 - Birth route
- 4.1 Reader strict mode (`BOOT_TRAIL_STRICT`, `BOOT_TRAIL_HOST_NAME`, `verdict=` line).
- 4.2 `scripts/lib/bastion-boot-verify.sh` (ready only on `verdict=ready`; else poweroff, recovery text, comment on #12879).
- 4.3 `tests/scripts/lib/bastion-host-birth-gate.sh`.
- 4.4 `bastion_host_create` job (inherits the workflow concurrency group; DSN and token asserts; ephemeral SSH key step; birth gate, then stock gate; SHA and addresses in the summary; `plan_only` stop; apply the gated plan; boot-verify after green or failed apply).
- 4.5 HALT bastion arm and the widened break-glass abort clause.
- 4.6 `soleur-host-bootstrap-observability.test.sh` AC8d loop and AC8 emitter pin; `scripts/test-all.sh` registrations.

## Phase 5 - Records
- 5.1 ADR-327 amendment via soleur:architecture.
- 5.2 C4: bastion container, `github -> bastion`, `bastion -> sentry`, views include; run c4-code-syntax, c4-render, c4-count-parity.
- 5.3 `expenses.md` rows (USD with EUR and FX in Notes, `approved-not-billing`, `verify_by`).
- 5.4 `encryption-posture-ledger.json` rows; `python3 scripts/lint-encryption-posture.py` PASS.
- 5.5 `knowledge-base/engineering/operations/runbooks/bastion-host.md`.

## Phase 6 - Post-merge (Operator Holds)
- 6.1 With the owner's typed go: `plan_only` rehearsal, arm a watch, show the SHA and resource list.
- 6.2 With the second go (quoting the rehearsal run ID, accepting EUR 5.99/month): check that no bastion path changed since the rehearsal SHA, dispatch the real birth, watch it, read the trail.
- 6.3 Flip the ledger rows to `active`; #12866 closes when the birth reads ready and #12879 has merged.
