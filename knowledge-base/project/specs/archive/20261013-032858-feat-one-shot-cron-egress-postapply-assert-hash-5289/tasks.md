---
feature: fix-cron-egress-postapply-assert-triggers-replace
issue: 5289
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-14-fix-cron-egress-postapply-assert-triggers-replace-plan.md
---

# Tasks — fold cron_egress_firewall post-apply assertion block into triggers_replace (#5289)

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Phase 1 — Read & RED (tests first)

- [x] 1.1 Read `server.tf:719-886`, `cron-egress-firewall.test.sh:379-468` (Phase 2.1), `server-tf-set-e.test.sh`, `cloud-init.yml` cron-egress section.
- [x] 1.2 In `cron-egress-firewall.test.sh`, retarget Phase 2.1 extraction from `$SERVER_TF` to `cron-egress-postapply-assert.sh` (AC6).
- [x] 1.3 Add delivery + trigger-fold asserts for `cron-egress-postapply-assert.sh` in the "-- server.tf delivery --" section (AC7).
- [x] 1.4 Add the cloud-init mirror assert in "-- cloud-init fresh-host mirror --" (AC8).
- [x] 1.5 Run `bash apps/web-platform/infra/cron-egress-firewall.test.sh` → confirm it FAILS (script/delivery/trigger-fold absent). RED established.

## Phase 2 — Extract & wire

- [x] 2.1 Create `apps/web-platform/infra/cron-egress-postapply-assert.sh`: shebang, `set -e` first, verbatim assertion sequence from `server.tf:824-883` (sentinels, journalctl tails, container probes, fresh-host WARN-skip) (AC1).
- [x] 2.2 Add `file("${path.module}/cron-egress-postapply-assert.sh")` to the `config_hash = sha256(join(",", [ … ]))` list (AC2).
- [x] 2.3 Add `provisioner "file"` for the script after the 9 artifact deliveries, before the run remote-exec (AC3).
- [x] 2.4 Collapse the 2nd `remote-exec` to `["set -e", "chmod +x /usr/local/bin/cron-egress-postapply-assert.sh", "bash /usr/local/bin/cron-egress-postapply-assert.sh"]` (AC4).
- [x] 2.5 `terraform fmt server.tf` + `terraform validate` (AC10).

## Phase 3 — Retarget drift-guards & GREEN

- [x] 3.1 Confirm Phase 2.1 extraction now reads the script (block = whole script body); keep ≥15 sentinel floor, 5 protected sentinels, unguarded-command check, journalctl-tail, runbook-name parity, non-vacuity probe (AC6).
- [x] 3.2 Re-run `server-tf-set-e.test.sh`; if block count < floor, bump `>= 13` + comment with evidence (AC5).
- [x] 3.3 Run all three suites → GREEN (AC9).

## Phase 4 — Cloud-init mirror & docs

- [x] 4.1 Add the script to `cloud-init.yml write_files` (mode 0755, `/usr/local/bin/cron-egress-postapply-assert.sh`); artifact-parity only, NO runcmd execution (AC8).
- [x] 4.2 Confirm `cron-egress-blocked.md` sentinel-name parity still holds (verify; edit only if parity test newly fails).

## Phase 5 — Ship

- [x] 5.1 `terraform fmt -check`, full infra suite green (AC9, AC10).
- [ ] 5.2 Push; open PR with `Ref #5289` (NOT `Closes`) (AC11); split AC into Pre-merge / Post-merge.

## Phase 6 — Post-merge (operator / automated)

- [ ] 6.1 After merge, read `apply-web-platform-infra.yml` apply run: `gh run list --workflow apply-web-platform-infra.yml --limit 1 --json conclusion,databaseId` + `gh run view <id> --log | grep -E 'Apply complete|ASSERT-FAILED:'` → expect `1 changed`, no `ASSERT-FAILED:` (AC12).
- [ ] 6.2 `gh issue close 5289 --comment "<apply-run-url> re-provisioned; post-apply block green on live host"` (AC13).
