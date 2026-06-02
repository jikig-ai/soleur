---
title: "Tasks — fix(infra): infra-config-apply.sh mktemp EACCES"
issue: 4827
branch: feat-one-shot-4827-infra-config-mktemp
lane: single-domain
plan: knowledge-base/project/plans/2026-06-02-fix-infra-config-apply-mktemp-eacces-plan.md
---

# Tasks: infra-config-apply.sh mktemp EACCES fix

Derived from `knowledge-base/project/plans/2026-06-02-fix-infra-config-apply-mktemp-eacces-plan.md`.

## Security-review course-correction (#4827 commit review, CRITICAL)

The automated commit security review flagged that the escalation helper trusted
caller-supplied `mode`/`owner` (setuid via `4755`) and allowed writing
`/etc/sudoers.d/*` with caller-controlled content (an unbounded escalation: a
deploy user invoking the helper directly could install `NOPASSWD: ALL`). Fixed:
- mode/owner now come from an authoritative per-dest table in the helper; a
  caller whose values disagree is rejected (rc=3).
- the sudoers grant was REMOVED from the webhook FILE_MAP + helper allowlist
  (8→7 files). It is delivered root-only (SSH bridge + cloud-init), never via the
  deploy-user webhook path. `visudo` validates syntax, not policy, so it cannot
  make sudoers content-write safe — removal is the only robust fix.

## Phase 0 — Preconditions

- [x] 0.1 Staging dir: `/var/lock` (deploy-writable, in `webhook.service:ReadWritePaths`, already holds the state file). Root helper re-stages into the dest dir, so staging-fs is irrelevant to atomicity.
- [x] 0.2 Read `infra-config-handler-bootstrap.test.sh` (block-extraction + provisioner-pair assertion shape).
- [x] 0.3 Re-read precedent `ci-deploy.sh:683-788` + `deploy-inngest-bootstrap.sudoers`.

## Phase 1 — RED (cq-write-failing-tests-before)

- [x] 1.1 Added `test_prod_mode_escalated_move` to `infra-config-apply.test.sh` (RED-confirmed against the old `mktemp "${dest_dir}/..."`).
- [x] 1.2 Created `infra-config-install.test.sh` RED (allowlist reject, symlink/owner TOCTOU, + setuid/owner-seize/sudoers-dest rejection).

## Phase 2 — GREEN

- [x] 2.1 Branched the write mechanism on `[[ -z "$DESTDIR" ]]`. Test mode unchanged; prod mode escalates via the root helper.
- [x] 2.2 Created `infra-config-install.sh` (root helper): authoritative dest→mode/owner table (7 dests), TOCTOU guards (symlink/owner/dest-symlink), mktemp-in-dest, atomic mv.
- [x] 2.3 Per-file accounting + `install_failed`/`install_rejected` reasons. (Sudoers visudo arm removed — sudoers no longer webhook-managed.)
- [x] 2.4 Helper kept OUT of webhook FILE_MAP (cloud-init + SSH-bootstrap delivery).

## Phase 3 — Delivery surfaces (IaC, no operator SSH)

- [x] 3.1 Added wildcard-free `Cmnd_Alias INFRA_CONFIG_INSTALL` grant to `deploy-inngest-bootstrap.sudoers`.
- [x] 3.2 Mirrored the alias into `cloud-init.yml`'s sudoers write_files block.
- [x] 3.3 Added the helper to `cloud-init.yml` write_files + `infra_config_install_script_b64` template var + bridge `provisioner "file"`. Bridge ALSO delivers the updated sudoers root-only (visudo + atomic install) and `deploy_pipeline_fix depends_on` it (breaks the chicken-and-egg).
- [x] 3.4 Extended `infra-config-handler-bootstrap.test.sh` (AC7: helper + sudoers delivery). Wired `infra-config-install.test.sh` into `infra-validation.yml`.

## Phase 4 — Verify

- [x] 4.1 `infra-config-apply.test.sh` exits 0 (57). `infra-config-install.test.sh` (14). All 18 infra suites green.
- [x] 4.2 `bash -n` clean; sudoers wildcard-free (alias has no `*`).
- [x] 4.3 `terraform fmt -check` + `validate` pass.
- [x] 4.4 Sudoers parity (source ≡ cloud-init inline) green via `cloud-init-inngest-bootstrap.test.sh` AC5.

## Post-merge (operator — automatable verification, no SSH)

- [ ] PM.1 After admin `terraform apply` (egress IP ∈ `var.admin_ips` — `/soleur:admin-ip-refresh` if handshake reset): `curl -s .../hooks/infra-config-status | jq` → `{exit_code:0, files_written:7, files_total:7}` (8→7: sudoers is now root-managed, not webhook-pushed).
- [ ] PM.2 `curl -s .../hooks/deploy-status | jq '.journald_storage.persistent'` → `true` (stale `cat-deploy-state.sh` self-healed).
- [ ] PM.3 `gh issue close 4827` (use `Ref #4804` in PR body, NOT `Closes` — #4804 is the umbrella drift issue).
