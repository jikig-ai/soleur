---
title: Provision persistent + bounded journald storage on prod inngest host
type: feat
issue: 4792
parent_issue: 4773
ref_pr: 4786
branch: feat-one-shot-journald-persistent-storage-4792
date: 2026-06-02
classification: ops-only-prod-write
lane: cross-domain
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 reviewed: the APPLY path is fully Terraform-routed via
`terraform_data.journald_persistent` (an SSH-connection provisioner identical to
the 6 existing `server.tf` host-config provisioners) + cloud-init for fresh
hosts. The only non-IaC reference is a ONE-TIME, READ-ONLY host-state probe in
Phase 0 (does /var/log/journal exist? current Storage=?), which the issue
explicitly requires before sizing. The preferred probe is the existing no-SSH
/hooks/cat-deploy-state webhook (extended with a journald_storage field); the
raw remote-read form is a fallback one-time read, never a provisioning write.
The systemd-journald restart / journal-flush verbs appear only inside the .tf
provisioner remote-exec (the Terraform-routed mechanism) and in cloud-init
runcmd — never as a manual operator step.
-->

# feat: Provision persistent + bounded journald storage on prod inngest host (#4792)

> Spec lacks valid `lane:` (no spec.md for this branch — one-shot path skipped brainstorm) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Hypotheses (Network-Outage Deep-Dive), Research Reconciliation (precedent-diff), Sizing, Files to Edit (provisioner shape).
**Gates run:** 4.4 precedent-diff (SSH `terraform_data` shape) · 4.5 Network-Outage Deep-Dive (FIRED — SSH provisioner) · 4.6 User-Brand Impact (PASS) · 4.7 Observability (PASS, all 5 fields) · 4.8 PAT-shaped variable (PASS, none).

### Key Improvements
1. **L3 firewall fact pinned (Network-Outage Deep-Dive):** `firewall.tf` gates SSH port 22 ingress to `var.admin_ips` ONLY — the CI-deploy SSH rule was removed in #749 (deploys use the CF-Tunnel webhook). So the journald `terraform_data` SSH provisioner reaches the host iff the operator/CI egress IP is in `admin_ips`. Verified, not assumed.
2. **Precedent-diff (Phase 4.4):** the SSH `terraform_data` provisioner shape is NOT novel — 6 sibling provisioners in `server.tf` use the exact `connection { type="ssh"; host=hcloud_server.web.ipv4_address; user="root"; agent=true }` + `triggers_replace = sha256(file(...))` + `file` + `remote-exec` + positive-assertion shape (`disk_monitor_install:68`, `fail2ban_tuning:146`). The journald provisioner is a 1:1 clone of `disk_monitor_install` with a different payload.
3. **cx33 disk fact made authoritative-by-probe:** the plan no longer hard-asserts "80 GB" as a sizing input — Phase 0's live `df /` is the authoritative number; the `SystemKeepFree=2G` hard floor makes the journal safe regardless of the exact root size.
4. **Provider pin verified:** `hetznercloud/hcloud` is pinned at `1.63.0` (`~> 1.49`); `hcloud_server.web.ipv4_address` is a stable attribute across this range (used by all 6 sibling provisioners).

### New Considerations Discovered
- The journald drop-in dir `/etc/systemd/journald.conf.d/` is the standard systemd override path; no repo precedent for a journald drop-in specifically, but cloud-init already writes other `/etc/systemd/system/*` units via `write_files` literal heredocs — match that style (NOT base64).
- `ci-deploy.sh` runs BOTH the app container (`:450`) and the canary (`:616`) with `--log-driver journald`. The on-disk journal therefore absorbs canary log volume too (transient, during deploys) — folded into the `SystemMaxUse=1G` headroom reasoning (Risk R3).

## Overview

The prod host `hcloud_server.web` (`soleur-web-platform`, tagged `host_name = "soleur-inngest-prd"` in `vector.toml:265`) runs systemd-journald with **no persistent-storage or sizing configuration**. There is no `Storage=persistent`, no `SystemMaxUse`, no `SystemKeepFree`, and no `mkdir -p /var/log/journal` anywhere under `apps/web-platform/infra/` (verified by grep: the only `/var/log/journal` references are reader-side `journal_directory` lines in `vector.toml`, all 3 journald sources).

Consequences:
- If `/var/log/journal` is absent, journald runs **volatile** (RAM under `/run`, default cap ~10% of `/run`, **lost on reboot**). Vector's 3 journald sources read `/var/log/journal` — a volatile journal means Vector silently ships a truncated/empty journal after any reboot.
- PR #4786 (#4773, merged) redirected the `soleur-web-platform` container's stdout from `json-file` (~30 MB capped) into journald (`--log-driver journald`, `ci-deploy.sh:450` + `:616` canary, `cloud-init.yml:507`). At journald's **default** `SystemMaxUse` (min(10% of /var, 4 GB)) this is likely fine, but the added write pressure can accelerate eviction of the supervisor/system journal lines the two pre-existing Vector sources (`inngest_journald`, `system_journald`) depend on, and an unbounded volatile journal interacts badly with the `/var` disk-pressure that `disk-monitor.sh` already alerts on.

This is a deferred-scope-out (`pre-existing-unrelated`, CONCUR co-signed) now picked up for implementation. The complete fix is **three coupled parts** — the issue is explicit that the cloud-init half MUST NOT ship alone:

1. A `journald.conf` drop-in (`Storage=persistent` + explicit `SystemMaxUse` + `SystemKeepFree`, sized for the cx33's 80 GB disk).
2. `mkdir -p /var/log/journal` in `cloud-init.yml` runcmd (fresh-host parity).
3. A `terraform_data` SSH remote-exec provisioner that applies the drop-in + creates `/var/log/journal` + flushes the journal on the **already-running** host. `server.tf:56` carries `lifecycle { ignore_changes = [user_data] }`, so a cloud-init-only edit **never** applies to live prod. Shipping (1)+(2) without (3) lands dead config and creates false confidence.

### Host topology (resolved at plan time — prevents the #4792 "two hosts" misread)

There is exactly **one** prod host. `inngest.tf` provisions only Inngest *secrets / heartbeat / Vector config* — it has **no** server resource. `inngest-server.service` runs ON `hcloud_server.web` via `inngest-bootstrap.sh`. The name `soleur-inngest-prd` is a Vector `host_name` tag (`vector.toml:265,279`), not a distinct machine. "The prod inngest host" in #4792 == `hcloud_server.web` == the `cx33`.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — this is an operator-observability surface. The concrete operator artifact: after a host reboot, Better Stack Logs shows a gap in `inngest_journald` / `system_journald` / `app_container` sources because journald lost the pre-reboot journal (volatile mode), so a cron-failure or OOM that happened just before a reboot is unrecoverable. Secondary: if `SystemMaxUse` is sized too large relative to the cx33 `/` budget, the journal competes with the inngest SQLite store + Docker images for root-disk space and trips `disk-monitor.sh` WARN/CRIT alerts (false-positive disk pressure).

**If this leaks, the user's data / workflow / money is exposed via:** N/A — journald content already traverses Vector's 3-stage PII redaction (`pii_scrub_*` in `vector.toml`) before any egress. Persisting the journal to `/var/log/journal` on the host does not add an egress surface; the journal is root-only (`0700 systemd-journald`) on a host whose SSH is firewall-allowlisted to `admin_ips`. No new regulated-data surface.

**Brand-survival threshold:** `aggregate pattern` — a single broken-journald incident is an operator-visible observability gap, not a user-facing or data-exposure incident. The risk is aggregate (degraded RCA capability over time / repeated post-reboot log gaps), matching the parent #4773 threshold. `threshold: aggregate pattern, reason: operator-observability surface; journald content is PII-redacted by Vector before egress and host-local journal is root-only behind the SSH allowlist.`

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "prod inngest host (`soleur-inngest-prd`)" | No server named `soleur-inngest-prd`; it is the `host_name` tag on `hcloud_server.web` (`soleur-web-platform`, cx33). One host only. | Plan targets `hcloud_server.web`. Documented in Host Topology above so /work does not chase a phantom second host. |
| "`server.tf:56` carries `ignore_changes = [user_data]`" | Confirmed — `server.tf:55-57`: `ignore_changes = [user_data, ssh_keys, image]`. | The `terraform_data` SSH provisioner (Part 3) is the sole apply path to the live host, exactly per the existing `disk_monitor_install` / `resource_monitor_install` / `fail2ban_tuning` precedents (all SSH `connection { agent = true }`). |
| "precedent: existing `terraform_data` provisioners in `server.tf`/`tunnel.tf`/`ci-ssh-key.tf`" | Confirmed. SSH-based provisioners: `disk_monitor_install` (`server.tf:68`), `resource_monitor_install` (`:106`), `fail2ban_tuning` (`:146`), `docker_seccomp_config` (`:271`), `apparmor_bwrap_profile` (`:307`), `orphan_reaper_install` (`:334`) — all `connection { type="ssh"; agent=true }`. NOTE: `deploy_pipeline_fix` (`:218`) is the **exception** — it uses an HTTPS `local-exec` (`push-infra-config.sh`) through the CF Tunnel (#3756), NOT SSH. | Use the **SSH `connection`** precedent (the `disk_monitor_install` shape), NOT the `deploy_pipeline_fix` HTTPS-webhook shape. The webhook path (`infra-config-apply.sh`) only writes file payloads atomically; it cannot run the journald-daemon restart + journal flush the drop-in requires. |
| "default `SystemMaxUse` (min(10% of /var, 4 GB))" | journald `man journald.conf`: default `SystemMaxUse` = 10% of the filesystem, capped at 4 GB; `SystemKeepFree` = 15% of filesystem. | Plan sets explicit caps (see Sizing) so the budget is auditable in IaC, not derived from a kernel default that changes silently with disk size. |
| `/var/log/journal` already exists? current `Storage=`? | **Cannot be statically verified from the repo** — requires reading live host state. | Phase 0 host-state verification step (read-only) resolves this before sizing/apply. See Phase 0. |

## Sizing decision (cx33, 80 GB disk)

The cx33 has 4 vCPU / 8 GB RAM and a local NVMe root `/` (Hetzner cx33 nominal disk is ~80 GB; **the authoritative number is Phase 0's live `df -h /`, not this recollection** — do not hard-code 80 in the drop-in). `/var/log/journal` lives on root `/` (the 20 GB `hcloud_volume.workspaces` is a separate mount at `/mnt/data`). Budget reasoning (to be confirmed against Phase 0's live `df /` + inngest-store size):

- `SystemMaxUse=1G` — hard cap on the persistent journal. Comfortably holds days of WARN+ supervisor journald + the new app-container pino volume (Vector filters to `level >= 40` before egress, but the journal on disk holds ALL levels — see Risk R3). 1 GB on an 80 GB root is ~1.25%, well under `disk-monitor.sh`'s 80% WARN threshold even alongside Docker images + the inngest SQLite store.
- `SystemKeepFree=2G` — journald stops writing if free space on `/` drops below 2 GB, so the journal can never be the cause of a full-disk outage. This is the load-bearing safety bound; it overrides `SystemMaxUse` when disk is tight.
- `RuntimeMaxUse=200M` — bounds the volatile `/run` journal during the boot window before `/var/log/journal` is flushed.
- `Storage=persistent` — journald writes to `/var/log/journal` (created by the drop-in apply + cloud-init) and survives reboot.

These are starting values; Phase 0 confirms current disk headroom and adjusts the two caps if the inngest SQLite store + Docker image footprint already consume a large fraction of `/`. The single `SystemMaxUse` cap (1G) is the only aggregate; no multi-component sum is claimed that could disagree with it.

## Files to Create

- `apps/web-platform/infra/journald-soleur.conf` — the drop-in (`[Journal]` section: `Storage=persistent`, `SystemMaxUse=1G`, `SystemKeepFree=2G`, `RuntimeMaxUse=200M`). Single source of truth, copied byte-identically into cloud-init write_files AND read via `file()` by the `terraform_data` provisioner's `triggers_replace` + `file` provisioner — mirrors the `fail2ban-sshd.local` two-path pattern (`server.tf:147` + `:178`).
- `apps/web-platform/infra/journald-config.test.sh` — structural + parity assertions (mirrors `cloud-init-inngest-bootstrap.test.sh` style: awk-extract the write_files block, assert the drop-in keys are present in both cloud-init and the standalone file, assert byte-parity between `journald-soleur.conf` and the cloud-init inline copy, assert `python3 yaml.safe_load(cloud-init.yml)` round-trips, assert the `terraform_data.journald_persistent` block exists with an SSH `connection` and the required remote-exec verbs).

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` — (a) add a `write_files` entry for `/etc/systemd/journald.conf.d/00-soleur.conf` (perms `0644`, owner root) with a literal `content:` heredoc byte-matching `journald-soleur.conf` (match the surrounding write_files style — most entries are literal heredocs); (b) add a `runcmd` step that creates `/var/log/journal`, runs `systemd-tmpfiles --create --prefix /var/log/journal`, restarts journald, and flushes the journal. Place the runcmd step EARLY (before the Docker-install / `--log-driver journald` container-start) so fresh hosts persist from first container start.
- `apps/web-platform/infra/server.tf` — add `resource "terraform_data" "journald_persistent"` modeled on `disk_monitor_install` (`:68`): `connection { type="ssh"; host=hcloud_server.web.ipv4_address; user="root"; agent=true }`; `triggers_replace = sha256(file("${path.module}/journald-soleur.conf"))`; a `file` provisioner pushing the drop-in to `/etc/systemd/journald.conf.d/00-soleur.conf`; a `remote-exec` that creates `/var/log/journal` (mkdir -p, chmod 0755, chown root:systemd-journal), restarts journald, flushes the journal, then runs **positive post-assertions** (mirror `fail2ban_tuning`'s assertion pattern, `server.tf:197-199`): `test -d /var/log/journal`, a `journalctl --header` grep proving persistence, and a journald-active check. Add a header comment matching the sibling provisioners (cloud-init handles fresh / this handles existing / shows as "will be created" in drift reports).
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — NO edit expected (separate test for the inngest runcmd block); the new `journald-config.test.sh` covers this feature. If a shared test runner enumerates `*.test.sh`, confirm the new file is picked up.

## Apply path & host-state verification

See `## Infrastructure (IaC)` for the full apply-path classification. Summary: cloud-init (fresh) + idempotent SSH `terraform_data` provisioner (existing host) — path (b), the default for existing infra.

## Phase 0 — Host-state verification (READ-ONLY, before sizing/apply)

The issue explicitly requires answering "does `/var/log/journal` already exist? current journald `Storage=`?" before sizing. Two automatable read paths (no prod-write):

1. **No-SSH path (PREFERRED — already wired):** `cat-deploy-state.sh:41` already runs `journalctl` on the host and round-trips output via the `/hooks/cat-deploy-state` CF-Tunnel webhook (HMAC + CF Access auth via Doppler `prd_terraform`). It does NOT currently emit journald storage state. **Extend `cat-deploy-state.sh`** with a `journald_storage` field reporting: `/var/log/journal` present/absent, `journalctl --header` persistence marker, and root-disk `df` headroom + inngest-store size. Read it via the existing webhook. This keeps host-state verification fully no-SSH and reusable (also powers the Observability `discoverability_test`).
2. **Fallback one-time read (read-only, only if the webhook extension is deferred):** with the operator SSH agent loaded (same `agent = true` the provisioners use) and the operator egress IP in `admin_ips`, a single read-only command can report dir-present / current Storage / `df -h /` / inngest-store size. This is a READ, never a write — provisioning still goes through Terraform.

Record the answers (dir present? current Storage? `/` headroom? inngest store size?) in the PR body. If `/var/log/journal` already exists with `Storage=auto` defaulting to persistent, the drop-in still adds the explicit `SystemMaxUse`/`SystemKeepFree` bounds (the load-bearing half) — the feature is not a no-op. Adjust the two caps if `/` headroom is tighter than the cx33's nominal 80 GB (e.g. large Docker image cache).

## Hypotheses (SSH / network-outage gate — L3→L7, fires before any service-layer hypothesis)

This plan's apply path (Part 3) is a `terraform_data` with `connection { type = "ssh" }` + `remote-exec` against the live host. Per `hr-ssh-diagnosis-verify-firewall` and the plan-network-outage-checklist, the firewall + routing layers MUST be verified before any sshd/journald-service hypothesis if the apply fails to connect:

- **L3 — Firewall allow-list (verify FIRST):** read `firewall.tf` + the `admin_ips` Doppler value (or `hcloud firewall describe`) and diff against the operator/CI egress IP (`curl -s https://ifconfig.me/ip`). The journald provisioner connects over SSH exactly like `disk_monitor_install`; if `admin_ips` has drifted out from under the operator egress IP, the apply hits `ssh: handshake failed: connection reset by peer` (precedent: #3061, #2681) — this is firewall drift, NOT sshd/journald config. Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`. Fix via `/soleur:admin-ip-refresh`, not an sshd edit.
- **L3 — DNS / routing:** `dig +short <host>` resolves to `hcloud_server.web.ipv4_address`; confirm the apply targets the same IP the firewall allowlists.
- **L7 — service layer (ONLY after L3 verified):** sshd up, journald restart succeeded, `/var/log/journal` writable. The positive post-assertions in the provisioner cover the journald-service layer.

If the apply succeeds on first connect, note "L3 verified implicitly (handshake succeeded); no outage" in the PR body.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5 — FIRED via SSH-provisioner resource-shape trigger)

The `terraform_data.journald_persistent` resource carries `connection { type = "ssh" }` + `file` + `remote-exec` provisioners — the implicit-SSH-dependency trigger. Layer-by-layer verification status against `firewall.tf` (read at deepen time):

| Layer | Verification artifact | Status |
|---|---|---|
| **L3 firewall allow-list** | `firewall.tf:4-13` — `hcloud_firewall.web` opens port 22 ingress via `dynamic "rule"` over `var.admin_ips` ONLY. The CI-deploy SSH rule was **removed in #749** ("deploys now use webhook via Cloudflare Tunnel"). So the apply's SSH handshake succeeds **iff** the operator/CI egress IP (`curl -s https://ifconfig.me/ip`) is a member of `admin_ips` (Doppler `prd_terraform`). **This is the single load-bearing connectivity precondition.** | Verified (mechanism). Operator must confirm egress IP ∈ `admin_ips` at apply time (Phase 0.3 AC). |
| **L3 DNS / routing** | `dig +short <host>` must equal `hcloud_server.web.ipv4_address`. The 6 sibling SSH provisioners use the same `host = hcloud_server.web.ipv4_address` interpolation — no DNS hostname involved (direct IPv4), so DNS is not on the path. | Verified (no DNS dependency — direct IP). |
| **L7 TLS / proxy** | N/A — the apply path is raw SSH (port 22), not HTTPS. The CF-Tunnel HTTPS path (`deploy_pipeline_fix`) is explicitly NOT used here. | N/A. |
| **L7 service layer** | sshd up; journald restart succeeds; `/var/log/journal` writable. Covered by the provisioner's positive post-assertions. | Verified at apply by assertions. |

**Gap that must close before apply:** the egress-IP ∈ `admin_ips` check (Phase 0.3). If the apply hits `ssh: handshake failed: connection reset by peer`, the cause is firewall drift (admin-IP rotation), NOT sshd/journald — fix via `/soleur:admin-ip-refresh`, per `hr-ssh-diagnosis-verify-firewall` + runbook `admin-ip-drift.md`. Do NOT propose an sshd or journald-service fix before re-verifying L3. Precedent for this exact inversion: #3061 (handshake reset on `deploy_pipeline_fix` with zero SSH keywords in plan) and #2681 (admin-IP drift mistaken for fail2ban).

## Infrastructure (IaC)

### Terraform changes
- Files: `apps/web-platform/infra/server.tf` (add `terraform_data.journald_persistent`), `apps/web-platform/infra/journald-soleur.conf` (new source-of-truth file), `apps/web-platform/infra/cloud-init.yml` (fresh-host write_files + runcmd).
- No new providers, no new variables, no new secrets. Uses the existing `hcloud` provider (`hcloud_server.web.ipv4_address`) and the operator SSH agent (`agent = true`) — same dependency surface as the 6 existing SSH provisioners.
- Sensitive variables: none added. The drop-in carries no secrets (pure sizing config).

### Apply path
- **(b) cloud-init + idempotent SSH provisioner** — the default for existing infra. Cloud-init covers fresh hosts (parity; never re-applies to live prod due to `ignore_changes=[user_data]`); the `terraform_data` SSH `remote-exec` is the sole live-prod apply path. Idempotent: `mkdir -p`, daemon restart, and journal flush are all safe to re-run; `triggers_replace = sha256(file(...))` re-runs only when the drop-in content changes.
- **Expected blast-radius / downtime:** restarting `systemd-journald` is a sub-second daemon restart; logs buffered in `/run` during the restart are flushed, not lost. No container restart, no app downtime, no Vector restart (Vector reads `/var/log/journal` and reconnects). The apply runs through the normal `web-platform-release.yml` terraform path OR an operator `terraform apply -target=terraform_data.journald_persistent`.
- **Canonical TF invocation (if applied out-of-band by operator):** per `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` — `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)` + same for `AWS_SECRET_ACCESS_KEY`; `terraform init -input=false`; `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.journald_persistent`. Re-run `terraform plan` against live state immediately before apply (drift snapshots go stale).

### Distinctness / drift safeguards
- `dev != prd`: this host is prod-only (`soleur-web-platform`); no dev host equivalent. No `dev`/`prd` collision risk.
- `lifecycle.ignore_changes`: the new `terraform_data` shows as "will be created" in CI drift reports every plan (same as the 6 sibling provisioners) — expected, documented in the header comment. It is NOT added to any `ignore_changes` list.
- State-storage: the drop-in carries no secrets, so `terraform.tfstate` (R2 backend) gains no sensitive value from this change.

### Vendor-tier reality check
- N/A — no vendor resource created (no Hetzner/Cloudflare/Better Stack API resource). Pure host-config provisioner.

## Observability

```yaml
liveness_signal:
  what: "Better Stack Logs shows continuous coverage from inngest_journald + system_journald + app_container sources across a host reboot (no gap)"
  cadence: "continuous (Vector ships in real time); reboot is the test event"
  alert_target: "existing betteruptime_heartbeat.inngest_prd (60s) covers inngest-server liveness; journald persistence verified by post-reboot log continuity, not a new alert"
  configured_in: "vector.toml (3 journald sources) + inngest.tf (heartbeat)"
error_reporting:
  destination: "terraform apply output — the provisioner positive post-assertions (test -d /var/log/journal; journalctl --header persistence grep; journald-active check) fail the apply loudly if journald did not become persistent"
  fail_loud: true
failure_modes:
  - mode: "drop-in applied but /var/log/journal not created (journald stays volatile)"
    detection: "provisioner remote-exec 'test -d /var/log/journal' assertion"
    alert_route: "terraform apply exits non-zero -> CI red / operator sees failure"
  - mode: "SystemMaxUse sized too large -> journal competes for / disk"
    detection: "disk-monitor.sh (existing, 5-min systemd timer, 80% WARN / 95% CRIT) + host_metrics filesystem series in Better Stack"
    alert_route: "Resend email to ops@jikigai.com (disk-monitor.sh) + Better Stack filesystem chart"
  - mode: "post-reboot journal gap (persistence silently lost)"
    detection: "Better Stack Logs query for a gap in source_kind=journald around the reboot timestamp"
    alert_route: "manual RCA query (no auto-alert); discoverability_test below makes it checkable without SSH"
logs:
  where: "host /var/log/journal (persistent journal); shipped WARN+/CRIT+ to Better Stack Logs via Vector"
  retention: "host: bounded by SystemMaxUse=1G (rolling); Better Stack: per source 2457081 retention"
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $WEBHOOK_SECRET\" https://<app-domain>/hooks/cat-deploy-state | jq '.vector_journal_tail, .journald_storage'   # after Phase 0 extends cat-deploy-state.sh with a journald_storage field"
  expected_output: "journald_storage reports 'persistent' / dir present; vector_journal_tail is non-empty (Vector reading the journal)"
```

## Acceptance Criteria

### Pre-merge (PR)
- [x] `journald-soleur.conf` exists with `Storage=persistent`, `SystemMaxUse=1G`, `SystemKeepFree=2G`, `RuntimeMaxUse=200M` under a `[Journal]` section. (The single `SystemMaxUse` cap is the only aggregate; self-consistent by construction.)
- [x] `cloud-init.yml` write_files contains a byte-identical copy of the drop-in at `/etc/systemd/journald.conf.d/00-soleur.conf`, AND a runcmd step creating `/var/log/journal` + restarting journald + flushing the journal, placed before the container-start step. (Byte-parity via `${journald_soleur_conf_b64}` = `base64encode(file(...))` — same file() the provisioner pushes raw; the `fail2ban-sshd.local` two-path precedent. Stronger than a hand-maintained literal heredoc; deviation from plan's "literal heredoc" suggestion noted in commit.)
- [x] `cloud-init.yml` still parses: `python3 -c "import yaml; yaml.safe_load(open('apps/web-platform/infra/cloud-init.yml'))"` returns 0.
- [x] `server.tf` contains `resource "terraform_data" "journald_persistent"` with an SSH `connection` block (`agent = true`), `triggers_replace = sha256(file(.../journald-soleur.conf))`, a `file` provisioner to `/etc/systemd/journald.conf.d/00-soleur.conf`, and a `remote-exec` with the create-dir -> restart -> flush -> positive-assertion sequence.
- [x] `terraform fmt -check` and `terraform validate` pass for `apps/web-platform/infra/`.
- [x] `journald-config.test.sh` passes (32/32): byte-parity wiring, required-keys present, YAML round-trip, `terraform_data` block shape, runcmd ordering. Added as an explicit step in `infra-validation.yml` (CI runs infra `*.test.sh` by name, not glob).
- [ ] PR body records Phase 0 host-state answers: `/var/log/journal` present? current `Storage=`? `/` headroom? inngest store size? — and the L3 firewall/egress-IP verification result. (No-SSH path wired: `cat-deploy-state.sh` now emits `journald_storage`; live values captured at apply time via the webhook.)
- [ ] PR body uses `Ref #4792` (NOT `Closes #4792`) — the actual remediation runs at apply time, post-merge (ops-only-prod-write class). Closure is a post-merge step.

### Post-merge (operator / CI)
- [ ] Terraform apply runs (`web-platform-release.yml` terraform path on merge, OR operator `-target=terraform_data.journald_persistent` via the canonical invocation triplet). The provisioner positive post-assertions pass: `/var/log/journal` exists, `journalctl --header` reports persistent, journald active.
  - Automation: feasible via the merge-triggered terraform-apply CI path; not punted to manual SSH. If applied out-of-band, use the drift-runbook triplet.
- [ ] Post-apply verification (no SSH): `cat-deploy-state` webhook (extended in Phase 0) reports `journald_storage = persistent` and non-empty `vector_journal_tail`.
- [ ] `gh issue close 4792` after the apply succeeds and verification passes.

## Test Scenarios

- Fresh-host (cloud-init) parity: the awk-extracted write_files block + runcmd step are present and `bash -n`/`dash -n` clean (mirror `cloud-init-inngest-bootstrap.test.sh` AC4).
- Byte-parity: `journald-soleur.conf` content == the cloud-init inline copy (mirror the `deploy-inngest-bootstrap.sudoers` AC5 parity test).
- `terraform_data` shape: the block declares SSH `connection`, the drop-in `file` provisioner, and the load-bearing remote-exec verbs (create-dir, restart, flush) + the post-assertions.
- Idempotence (reasoned, not host-executed in CI): `mkdir -p`, daemon restart, and journal flush are all safe to re-run; `triggers_replace` hash ensures re-run only on content change.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` for issue bodies referencing `apps/web-platform/infra/server.tf`, `cloud-init.yml`, or `vector.toml`. **None** matched the three files this plan edits (checked at plan time). If the work phase finds a stale open scope-out touching these files, fold-in or acknowledge per the overlap procedure. Recorded `None` so the next planner sees the check ran.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/observability change. No user-facing UI, no schema/auth/API surface, no regulated-data movement (journald content is PII-redacted by Vector before egress; the on-host journal is root-only behind the SSH allowlist). GDPR/compliance gate (Phase 2.7): no regulated-data surface touched — skipped.

## Risks & Mitigations

- **R1 — SSH apply path unreachable (firewall drift):** mitigated by the L3->L7 Hypotheses gate; verify `admin_ips` vs egress IP before apply. Fix via `/soleur:admin-ip-refresh`, never an sshd edit.
- **R2 — Sizing too large for actual `/` headroom:** Phase 0 reads live `df /` + inngest store size; `SystemKeepFree=2G` is the hard safety bound — journald stops writing before it can fill the disk regardless of `SystemMaxUse`. `disk-monitor.sh` is the existing backstop.
- **R3 — On-disk journal holds ALL pino levels (not just WARN+):** Vector filters `level >= 40` *before egress to Better Stack*, but the host journal under `/var/log/journal` retains every level from the `--log-driver journald` container. This is the volume `SystemMaxUse=1G` bounds. Confirm the 1G cap holds for the app-container INFO volume during Phase 0 (`journalctl --disk-usage` after a representative window); raise the cap or tighten only if it churns faster than ~1 day of retention. Precedent for sizing-against-actual-volume: the inngest SQLite ~60MB/month figure in `inngest-server.md:195`.
- **R4 — Drop-in path/precedence:** systemd reads `/etc/systemd/journald.conf.d/*.conf` drop-ins over `/etc/systemd/journald.conf`; the `00-` prefix orders it first. Optionally verify with a `systemd-analyze cat-config systemd/journald.conf` diagnostic in the provisioner post-assertions.

### Precedent-diff (deepen-plan Phase 4.4)

The SSH `terraform_data` provisioner shape is **established precedent, not novel** — verified by grepping `server.tf` at deepen time. The journald provisioner is a 1:1 structural clone of `disk_monitor_install` (`server.tf:68-98`); the only payload difference is what the `remote-exec` does. Element-by-element:

- `connection`: identical to the precedent — `{ type="ssh"; host=hcloud_server.web.ipv4_address; user="root"; agent=true }`.
- `triggers_replace`: precedent uses `sha256(join(",", [secret, file(script)]))`; this plan uses `sha256(file(".../journald-soleur.conf"))` (no secret, so no `join`).
- `provisioner "file"`: precedent pushes a script to `/usr/local/bin/`; this plan pushes the drop-in to `/etc/systemd/journald.conf.d/00-soleur.conf`.
- `provisioner "remote-exec"`: precedent does daemon-reload + enable-timer; this plan does create-`/var/log/journal` + chown + journal-daemon restart + journal flush + **positive post-assertions**.
- positive post-assertions: adopt the **`fail2ban_tuning` pattern** (`server.tf:197-199` uses `test "$(...)" = 'expected'`) over `disk_monitor_install`'s informational list-timers — journald persistence is a state we must *prove*, not just *observe*. Mirrors fail2ban's "if the override silently didn't take, fail the provisioner" rationale.
- drift display: "will be created" every plan; add a header comment matching the siblings.

No deviation from precedent is required. The single judgment call (assertion style) is resolved toward the stricter `fail2ban_tuning` shape.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled (threshold: aggregate pattern).
- Do NOT use the `deploy_pipeline_fix` HTTPS-webhook (`push-infra-config.sh`) apply path for this provisioner — the webhook handler (`infra-config-apply.sh`) only writes file payloads atomically; it cannot restart the journal daemon + flush. Use the SSH `connection` precedent (`disk_monitor_install` shape). This is the single most likely /work misstep given `deploy_pipeline_fix` is the most prominent provisioner in `server.tf`.
- `/var/log/journal` lives on root `/`, NOT the `/mnt/data` workspace volume. Sizing is against the cx33's 80 GB root, minus Docker images + `/var/lib/inngest` SQLite + system. Do not assume the 20 GB workspace volume.
- `Closes #4792` would auto-close at merge BEFORE the apply runs (ops-only-prod-write). Use `Ref #4792`; close via `gh issue close 4792` post-apply.
- The host is named `soleur-inngest-prd` only as a Vector tag — there is one host (`hcloud_server.web`). Do not provision a second server.

## PR-body reminder

`Ref #4792` (not `Closes`). Body must include: Phase 0 host-state answers, L3 firewall/egress verification, sizing rationale (live `df /` numbers), and the post-apply `cat-deploy-state` verification result.
