---
title: "Tasks — fix(infra): infra-config-apply.sh mktemp EACCES"
issue: 4827
branch: feat-one-shot-4827-infra-config-mktemp
lane: single-domain
plan: knowledge-base/project/plans/2026-06-02-fix-infra-config-apply-mktemp-eacces-plan.md
---

# Tasks: infra-config-apply.sh mktemp EACCES fix

Derived from `knowledge-base/project/plans/2026-06-02-fix-infra-config-apply-mktemp-eacces-plan.md`.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm a deploy-writable staging dir in `webhook.service:ReadWritePaths` (e.g. `/var/lock` or `/var/lib/inngest`). **Prefer the simpler design:** root helper does mktemp-in-dest, so staging need only hold the deploy-user-decoded payload temporarily.
- [ ] 0.2 Read `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` to learn the sudoers/handler parity-assertion shape the new entry must satisfy.
- [ ] 0.3 Re-read the precedent `ci-deploy.sh:683-788` (fixed-path extract + TOCTOU guards + `sudo /usr/bin/bash <fixed>`) and `deploy-inngest-bootstrap.sudoers:5-8` (sudo-rs no-wildcards).

## Phase 1 — RED (cq-write-failing-tests-before)

- [ ] 1.1 Add `test_prod_mode_escalated_move` to `infra-config-apply.test.sh`: with `TEST_DESTDIR` unset (prod mode) + mocked `sudo`/helper on PATH, assert the handler does NOT mktemp in a root-owned dest dir and DOES invoke the pinned escalation helper with `(payload/temp, dest, mode, owner)`. Must FAIL against current `mktemp "${dest_dir}/..."`.
- [ ] 1.2 (if helper form) Add `infra-config-install.test.sh` RED: helper rejects a dest NOT in its hardcoded allowlist (`install_rejected`); rejects symlinked/wrong-owner staging input (TOCTOU).

## Phase 2 — GREEN

- [ ] 2.1 In `infra-config-apply.sh`, branch the write mechanism on `[[ -z "$DESTDIR" ]]` (same predicate as the existing `chown` skip at `:124`). Test mode unchanged (`mktemp` in dest + `mv`). Prod mode delegates the privileged write to the root helper.
- [ ] 2.2 Create `apps/web-platform/infra/infra-config-install.sh` (root helper): hardcoded dest allowlist (the 8 FILE_MAP dests), TOCTOU guards (symlink/owner refuse), `mktemp` in dest dir, `base64 -d` payload, `chmod`/`chown`/atomic `mv`. Mirror `ci-deploy.sh:693-702` guard shape.
- [ ] 2.3 Preserve the visudo arm for `/etc/sudoers.d/*` (validate temp before escalation) and the per-file failure accounting + state JSON. Add `install_failed`/`install_rejected` reasons.
- [ ] 2.4 Decide helper delivery: **keep helper OUT of webhook FILE_MAP** (cloud-init + SSH-bootstrap delivery only) to avoid `files_total` count churn and the helper-can't-deliver-itself paradox.

## Phase 3 — Delivery surfaces (IaC, no operator SSH)

- [ ] 3.1 Add `Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install` + `deploy ALL=(root) NOPASSWD: INFRA_CONFIG_INSTALL` (wildcard-free) to `deploy-inngest-bootstrap.sudoers`.
- [ ] 3.2 Mirror the new sudoers alias into `cloud-init.yml`'s `deploy-inngest-bootstrap` write_files block (`:54-69`).
- [ ] 3.3 Add the `infra-config-install.sh` helper to `cloud-init.yml` write_files + deliver via the SSH handler-bootstrap bridge (`server.tf:284`, mirror the `cat-infra-config-state.sh` `provisioner "file"` at `:362`). The bridge's `triggers_replace` already hashes `infra-config-apply.sh`, so a handler edit re-fires delivery.
- [ ] 3.4 Extend `infra-config-handler-bootstrap.test.sh` parity assertions if the sudoers/helper parity shape changed.

## Phase 4 — Verify

- [ ] 4.1 `bash apps/web-platform/infra/infra-config-apply.test.sh` exits 0 (all existing tests + new prod-mode test).
- [ ] 4.2 `bash -n` on `infra-config-apply.sh` + `infra-config-install.sh`; assert sudoers wildcard-free (`! grep -E 'Cmnd_Alias.*\*' deploy-inngest-bootstrap.sudoers`).
- [ ] 4.3 `terraform fmt -check` / `validate` on `server.tf` / `cloud-init.yml` edits.
- [ ] 4.4 Tri-surface sudoers parity: `deploy-inngest-bootstrap.sudoers` ≡ `cloud-init.yml` mirror ≡ bootstrap-bridge body.

## Post-merge (operator — automatable verification, no SSH)

- [ ] PM.1 After admin `terraform apply` (egress IP ∈ `var.admin_ips` — `/soleur:admin-ip-refresh` if handshake reset): `curl -s .../hooks/infra-config-status | jq` → `{exit_code:0, files_written:8, files_total:8}`.
- [ ] PM.2 `curl -s .../hooks/deploy-status | jq '.journald_storage.persistent'` → `true` (stale `cat-deploy-state.sh` self-healed).
- [ ] PM.3 `gh issue close 4827` (use `Ref #4804` in PR body, NOT `Closes` — #4804 is the umbrella drift issue).
