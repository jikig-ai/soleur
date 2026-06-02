---
feature: Provision persistent + bounded journald storage on prod inngest host
issue: 4792
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-feat-persistent-bounded-journald-prod-inngest-host-plan.md
---

# Tasks — feat: persistent + bounded journald storage (#4792)

## Phase 0 — Host-state verification (read-only, before sizing)
- [ ] 0.1 Extend `cat-deploy-state.sh` with a `journald_storage` field (no-SSH preferred): `/var/log/journal` present/absent, `journalctl --header` persistence marker, root-disk `df` headroom, inngest-store size.
- [ ] 0.2 Read host state via `/hooks/cat-deploy-state` webhook (or one-time read-only fallback). Record: dir present? current `Storage=`? `/` headroom? inngest store size?
- [ ] 0.3 Verify L3 firewall allowlist (`firewall.tf` + `admin_ips`) vs operator/CI egress IP before any apply (SSH gate, `hr-ssh-diagnosis-verify-firewall`).
- [ ] 0.4 Confirm/adjust sizing caps (`SystemMaxUse=1G`, `SystemKeepFree=2G`) against the live `df /` numbers.

## Phase 1 — Source-of-truth drop-in + tests (RED first)
- [ ] 1.1 Write failing `journald-config.test.sh`: byte-parity, required-keys, YAML round-trip, `terraform_data` shape assertions (mirror `cloud-init-inngest-bootstrap.test.sh`).
- [ ] 1.2 Create `apps/web-platform/infra/journald-soleur.conf` (`[Journal]`: `Storage=persistent`, `SystemMaxUse=1G`, `SystemKeepFree=2G`, `RuntimeMaxUse=200M`).

## Phase 2 — Fresh-host (cloud-init) parity
- [ ] 2.1 Add `write_files` entry for `/etc/systemd/journald.conf.d/00-soleur.conf` (byte-identical to the standalone file, literal heredoc, perms 0644).
- [ ] 2.2 Add `runcmd` step (create `/var/log/journal` + `systemd-tmpfiles --create` + journald restart + journal flush), placed before the container-start step.
- [ ] 2.3 Confirm `python3 yaml.safe_load(cloud-init.yml)` round-trips.

## Phase 3 — Live-host apply path (terraform_data, SSH precedent)
- [ ] 3.1 Add `resource "terraform_data" "journald_persistent"` in `server.tf` modeled on `disk_monitor_install` (SSH `connection { agent=true }`, `triggers_replace = sha256(file(...))`, `file` provisioner, `remote-exec` create-dir->restart->flush->positive-assertions). Header comment matching siblings.
- [ ] 3.2 `terraform fmt -check` + `terraform validate` for `apps/web-platform/infra/`.
- [ ] 3.3 Run `journald-config.test.sh` to GREEN.

## Phase 4 — Ship
- [ ] 4.1 PR body: Phase 0 host-state answers + L3 verification + sizing rationale + `Ref #4792` (NOT `Closes`).
- [ ] 4.2 Post-merge: terraform apply (CI terraform path or `-target=terraform_data.journald_persistent` via canonical triplet); positive post-assertions pass.
- [ ] 4.3 Post-apply no-SSH verification via `cat-deploy-state` webhook (`journald_storage = persistent`).
- [ ] 4.4 `gh issue close 4792`.
