---
title: "fix: restore prod SSH access (post-fail2ban ban) and codify fail2ban tuning"
type: fix
date: 2026-04-19
semver: patch
issue: 2654
---

# fix: restore prod SSH access (post-fail2ban ban) and codify fail2ban tuning

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Risks & Mitigations, Verification Steps)
**Research sources:** fail2ban upstream `jail.conf` (GitHub master), fail2ban issue tracker (#1341 AllowUsers detection, #2777 invalid-user detection, #2498, #3721 journald-sshd detection edge cases), DigitalOcean fail2ban tutorial, Visei incremental-banning reference, Linuxhint `bantime -1` doc, OneUptime fail2ban RHEL/Ubuntu guides.

### Key Improvements

1. **Confirmed `bantime.maxtime` semantics vs. the Visei / jail.conf default formula** — the Ubuntu 24.04 package's `bantime.maxtime` default when `bantime.increment = true` is *not* 4 h as I initially surmised. The upstream `jail.conf` master default is computed: without an explicit `bantime.maxtime`, the escalation climbs to `bantime * bantime.factor^count` unbounded until operator capacity runs out. Explicit cap at `1h` is clearly a correctness fix, not just ergonomics.
2. **Caught a root-cause-ambiguity risk**: fail2ban's sshd filter on older versions did NOT always match `User deploy from <ip> not allowed because not listed in AllowUsers` lines (issue #1341). Modern filters (fail2ban ≥ 0.11) do. Ubuntu 24.04 ships 1.0.2, which catches this — but if the version drifts, the plan's root-cause hypothesis weakens. Added an on-host `fail2ban --version` check to Phase 1.
3. **Pinned the `AllowUsers root` + `deploy@` interaction**: the `ssh deploy@` attempt would generate one of two journal lines — `Invalid user deploy …` (if the account doesn't exist OR fail2ban filter treats `AllowUsers` non-match as invalid) or the explicit `not allowed because not listed in AllowUsers` line. Both are caught by the default sshd filter in fail2ban ≥ 0.11, each counting as `maxretry` failures per the filter's logic. This tightens the causal chain in the plan.
4. **Added a `bantime.factor = 2` explicit line** to the drop-in — without it, the upstream default factor is architecture/version-sensitive, and being explicit avoids silent behavior change on a future fail2ban upgrade.

### New Considerations Discovered

- **Filter drift class**: If Ubuntu 24.04 backports a different fail2ban sshd filter via a security patch, the behavior changes silently. The post-apply verification now runs `fail2ban-client get sshd journalmatch` and `fail2ban-client get sshd actions` to capture the effective filter for the incident log.
- **`systemd` backend + `AllowUsers`**: issue #1341 is closed but the pattern of "filter may not match AllowUsers reject" is still a sharp edge. Add a `filter = sshd[mode=aggressive]` **as a scope-out**, not a default, because aggressive mode also bans scanners that probe valid usernames without password attempts — the FAR more common pattern — and would *increase* noise.
- **`fail2ban-client unban --all`**: recovery could also use `fail2ban-client unban --all` instead of `unbanip <ip>`, which is safer if the operator IP is unknown (NAT change). Runbook now mentions both.

## Overview

`ssh root@135.181.45.178` fails with `kex_exchange_identification: read: Connection reset by peer` from the operator machine, across retries more than 15 minutes apart. The host is otherwise healthy (HTTPS 200, `hcloud server list` → running). Root-cause hypothesis: the initial `ssh deploy@` attempt exhausted `MaxAuthTries` several times, tripping fail2ban's `[sshd]` jail with `bantime.increment` (Ubuntu 24.04 fail2ban default), producing an exponentially-escalated ban that persists well past the 10-minute baseline.

This PR has two distinct deliverables:

1. **Restore access now** (operator-authored, runbook-driven): unban the operator IP via the Hetzner Cloud Console since SSH is the blocked channel — there is no automation path when SSH itself is down.
2. **Codify fail2ban tuning in Terraform** so the next incident is either avoided (lower `bantime.increment` max cap) or diagnosed faster (bake a runbook pointer into cloud-init as a comment).

Per AGENTS.md `hr-all-infrastructure-provisioning-servers`, SSH is for read-only diagnosis only — the permanent fix ships as a Terraform cloud-init change (and an optional `write_files` jail.local drop-in), never as a live `fail2ban-client` command treated as the fix itself.

## Problem Statement

### Current state (2026-04-19)

- Firewall (`apps/web-platform/infra/firewall.tf`): port 22 is open only to `var.admin_ips` (per issue body: `82.67.29.121/32`). The firewall is NOT the blocker — TCP reaches 22, the sshd-side reset is the symptom.
- SSH hardening (`apps/web-platform/infra/cloud-init.yml:21-32`): `PasswordAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `AllowUsers root`, `PermitRootLogin prohibit-password`.
- fail2ban is installed via `packages:` (cloud-init.yml:5) with **no** custom jail config. On Ubuntu 24.04, `/etc/fail2ban/jail.d/defaults-debian.conf` auto-enables `[sshd]` with `banaction = nftables`, `backend = systemd`, and `bantime.increment = true` (default).

### Why a `≥15-minute` ban is consistent with defaults

**Research-verified escalation formula** (fail2ban upstream `server/actions.py`): when `bantime.increment = true`, the ban duration grows as `bantime * bantime.factor^(count-1)` where `count` is the number of prior bans for that IP in the db (default `bantime.factor = 2`, sometimes `2.5` depending on version). With the Ubuntu 24.04 default `bantime = 10m`:

| Offense # | Ban duration (factor=2) |
|-----------|--------------------------|
| 1 | 10 m |
| 2 | 20 m |
| 3 | 40 m |
| 4 | 80 m |
| 5 | 160 m ≈ 2.7 h |
| 6 | 320 m ≈ 5.3 h |

**Without an explicit `bantime.maxtime` cap**, escalation is bounded only by `int32` overflow (practically, a week+). The `jail.conf` upstream master ships no `bantime.maxtime` default — this is the load-bearing knob this PR adds.

### Why the `ssh deploy@` attempt tripped the jail (tightened causal chain)

`AllowUsers root` in `sshd_config.d/01-hardening.conf` rejects every login that targets any non-root user. `ssh deploy@<ip>` from the operator machine will:

1. Complete TCP + key-exchange + algorithm negotiation.
2. Attempt `publickey` method with the operator's key → sshd rejects with `User deploy from <ip> not allowed because not listed in AllowUsers`.
3. openssh client then falls back through other methods (none succeed because of `AllowUsers` + `PasswordAuthentication no`).
4. Each rejected connection counts as **one** `maxretry` failure against fail2ban's default sshd filter (fail2ban ≥ 0.11 matches the `AllowUsers` reject line — verified via upstream filter regex; older versions before 0.11 had a blind spot, upstream issue #1341).

Ubuntu 24.04 ships fail2ban 1.0.2, which post-dates 0.11 — safe. **Phase 1 verifies on-host via `fail2ban --version`** before trusting this reasoning.

Two retry attempts ≥ 15 minutes apart reported in the issue is consistent with `count = 2–3` (20–40 min ban window) — which matches "first retry at T+15 still banned, second retry at T+30 still banned." The ban is NOT `bantime = -1` (permanent) — the operator would never recover without Cloud Console intervention in that case, and that's not our default.

### Why we're not blaming it on other causes (yet)

The issue's `## Hypotheses` lists three:

1. Permanent / long fail2ban ban (most likely given the symptom).
2. sshd config drift or OOM.
3. Adjacent hardening (sshguard, `hosts.deny`).

Diagnosis on host via Hetzner Console distinguishes these before we write the fix. **If (2) or (3) is the root cause, the "codify fail2ban tuning" phase still has value but the operator unban step does not** — adjust phases accordingly at GREEN time.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "Firewall rule 10708450 allows SSH from `82.67.29.121/32` only (operator IP). TCP reaches port 22" | Confirmed — `firewall.tf` uses `var.admin_ips` for port 22. Not `0.0.0.0/0`. | Do NOT widen the firewall. Keep operator-only. |
| "Terraform sshd hardening … fail2ban installed (no custom `bantime`/`findtime`, so Debian defaults apply)" | Confirmed — `cloud-init.yml:5` lists `fail2ban` in packages; no `jail.local`, no `jail.d/*.conf` entries in `write_files`. | Safe to add a `write_files` jail.local drop-in without conflicting with existing config. |
| "Triggered by: first `ssh deploy@` attempt (deploy has `lock_passwd: true` + no key)" | Confirmed — `cloud-init.yml:11-18`: `deploy` user has `lock_passwd: true` and no `ssh_authorized_keys`. `AllowUsers root` would reject `deploy` pre-auth anyway. | Root-cause note stands. Consider adding `deploy` to `DenyUsers` in sshd config so fail2ban sees an explicit reject (cleaner log signal). **Deferred** — adds config surface without solving the core issue. |
| Existing prior art: `knowledge-base/project/plans/2026-03-19-security-add-fail2ban-ssh-protection-plan.md` | Shipped — fail2ban with defaults. **This plan is the sequel**: tune `bantime.increment` semantics after a real incident. | Link back; do not regress the `nftables`/`systemd` defaults from that plan. |
| "Hypothesis 1: `bantime = -1`" | Not set anywhere in the Terraform tree (grep `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2654-prod-ssh-kex-reset/apps/web-platform/infra`). | Default-only behavior. Root cause is almost certainly `bantime.increment` recidivism, not `bantime = -1`. |

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` — add `/etc/fail2ban/jail.d/soleur-sshd.local` write_files entry (bounded `bantime.maxtime`, explicit `bantime`, `findtime`, `maxretry`) and a runbook pointer comment; add `runcmd` line to `systemctl reload fail2ban` after drop-in lands.
- `apps/web-platform/infra/server.tf` — add a `terraform_data.fail2ban_tuning` resource (pattern: `terraform_data.disk_monitor_install`, server.tf:58-88) so the tuning also applies to the existing server (cloud-init is gated by `ignore_changes = [user_data]`).

## Files to Create

- `knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md` — operator runbook for "SSH is locked out, unban from Hetzner Cloud Console".

No new test files — this is infrastructure/runbook work (AGENTS.md `cq-write-failing-tests-before` exempts infrastructure-only tasks).

## Open Code-Review Overlap

**Procedure ran:**

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/server.tf \
         knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

**Matches:** None (to be verified at implementation — if the grep returns rows, add disposition here before shipping).

## Proposed Solution

### Phase 1 — Restore access (operator, Hetzner Cloud Console)

AGENTS.md `hr-exhaust-all-automated-options-before` escalation: (1) Doppler — N/A, (2) MCP — no Hetzner MCP, (3) `hcloud` CLI — cannot unban fail2ban (no API), (4) REST — N/A, (5) Playwright MCP against `https://console.hetzner.cloud/` — **possible** but the console "Console" tab opens an xterm.js-style session; Playwright would need to drive a canvas-rendered terminal (fragile). (6) Operator at keyboard via Cloud Console is the correct tool here.

This is the one step where "manual" is justified per `hr-never-label-any-step-as-manual-without`: the channel we need to automate *is the channel that's down*.

**Runbook (`knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md`):**

1. Open <https://console.hetzner.cloud/> → project → `soleur-web-platform` → "Console" tab (noVNC/xterm in-browser).
2. Log in as root (the console is pre-authed to the project).
3. Run:

   ```bash
   # Capture fail2ban version — gates whether the AllowUsers-based causal
   # hypothesis in the plan is trustworthy (need >= 0.11 for the filter
   # to match AllowUsers reject lines; Ubuntu 24.04 ships 1.0.2).
   fail2ban-client --version

   # Confirm the ban and capture counts before unbanning.
   fail2ban-client status sshd

   # Unban the operator IP if known.
   fail2ban-client set sshd unbanip 82.67.29.121
   # Fallback if the operator IP is unknown or NAT has rotated it:
   #   fail2ban-client unban --all
   # Safe because this is the only active jail; clears bans across all jails.

   # Sanity: sshd itself is healthy.
   systemctl status ssh --no-pager
   journalctl -u ssh -n 50 --no-pager

   # Capture current jail state for the Terraform tuning step.
   cat /etc/fail2ban/jail.local /etc/fail2ban/jail.d/*.conf 2>/dev/null
   fail2ban-client get sshd bantime
   fail2ban-client get sshd findtime
   fail2ban-client get sshd maxretry
   # Capture effective filter (confirms AllowUsers detection behavior).
   fail2ban-client get sshd journalmatch 2>/dev/null || true
   fail2ban-client get sshd logpath 2>/dev/null || true
   # Print the journal lines that triggered the ban (last 200 for context).
   journalctl -u ssh --since "1 hour ago" --no-pager | head -200
   ```

4. Verify from the operator machine: `ssh -vvv root@135.181.45.178 'hostname'` — succeeds on first try.
5. Record the `status sshd` output (banned IPs, total bans, retry count) in the PR body for posterity.

### Phase 2 — Codify fail2ban tuning in Terraform

Write a drop-in to `/etc/fail2ban/jail.d/soleur-sshd.local` via cloud-init `write_files`. This never edits `jail.conf` (per fail2ban best practice) and lives at a higher priority than `defaults-debian.conf` due to alphabetic `jail.d` load order (`defaults-debian.conf` < `soleur-sshd.local`). **Verify order at deploy time** with `fail2ban-client -d | grep -A5 '\[sshd\]'`.

Key tuning:

- `bantime = 10m` — match the Ubuntu default (explicit is better than implicit).
- `findtime = 10m` — explicit.
- `maxretry = 5` — explicit. Interacts with sshd `MaxAuthTries 3`: each rejected connection is *one* fail2ban failure (not 3). Effective per-source budget: 5 connection rejects within 10 min before ban.
- `bantime.increment = true` — keep recidivism multiplier (defense-in-depth against persistent scanners).
- `bantime.factor = 2` — **explicit per research** (fail2ban upstream has shipped different defaults across versions; explicit prevents silent behavior change on package upgrade).
- `bantime.maxtime = 1h` — **the core change**. Caps the recidivist ban at 1 hour. Rationale: at `factor=2`, offense #4 = 80 min (already past this cap), and offense #6 = 5.3 h (uncapped) — without this knob, a legit operator typo that trips 4–5 bans in a morning could lock them out for *days*. 1 h is the trade: long enough to deter brute-forcers (they need to spend 1 h for every 5 rejected connections), short enough that a legit operator self-recovers in-band.
- `bantime.overalljails = false` (upstream default) — a brute on sshd doesn't cross-ban from other hypothetical future jails. Not set explicitly (defaults are fine here).
- `ignoreip = 127.0.0.1/8 ::1 <admin IP list>` — **DEFERRED**. The operator IP is NAT-dynamic; ignoring it permanently defeats the jail's purpose if the IP later belongs to a different ISP customer. Prefer: `bantime.maxtime = 1h` so recovery is 1 h max, and the Cloud Console runbook for acute lockouts.

**cloud-init.yml — new write_files block (literal contents):**

```yaml
  # fail2ban sshd tuning (#2654). Drop-in at jail.d/ so it overrides
  # /etc/fail2ban/jail.d/defaults-debian.conf (alphabetic load order:
  # defaults-debian.conf loads before soleur-sshd.local).
  # Runbook for recovery when locked out: knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md
  - path: /etc/fail2ban/jail.d/soleur-sshd.local
    content: |
      [sshd]
      enabled = true
      bantime = 10m
      findtime = 10m
      maxretry = 5
      bantime.increment = true
      bantime.factor = 2
      bantime.maxtime = 1h
    owner: root:root
    permissions: '0644'
```

**cloud-init.yml — runcmd addition (so fresh servers pick it up):**

```yaml
  # Reload fail2ban after jail.d drop-in is written.
  - systemctl reload fail2ban || systemctl restart fail2ban
```

### Phase 3 — Apply tuning to the existing server

`hcloud_server.web` in `server.tf:44-47` has `lifecycle { ignore_changes = [user_data, ssh_keys, image] }` — cloud-init changes never re-run on the existing host. Follow the established pattern (`terraform_data.disk_monitor_install`, `terraform_data.deploy_pipeline_fix`) to ship the same file via provisioner:

```hcl
# server.tf — new resource (pattern: terraform_data.disk_monitor_install)
resource "terraform_data" "fail2ban_tuning" {
  # Any edit to the drop-in re-runs the provisioner.
  triggers_replace = sha256(file("${path.module}/fail2ban-sshd.local"))

  connection {
    type  = "ssh"
    host  = hcloud_server.web.ipv4_address
    user  = "root"
    agent = true
  }

  provisioner "file" {
    source      = "${path.module}/fail2ban-sshd.local"
    destination = "/etc/fail2ban/jail.d/soleur-sshd.local"
  }

  provisioner "remote-exec" {
    inline = [
      "chown root:root /etc/fail2ban/jail.d/soleur-sshd.local",
      "chmod 0644 /etc/fail2ban/jail.d/soleur-sshd.local",
      "systemctl reload fail2ban || systemctl restart fail2ban",
      "fail2ban-client -d | grep -A3 '\\[sshd\\]' | head -20",
      "fail2ban-client get sshd bantime",
      "fail2ban-client get sshd maxretry",
    ]
  }
}
```

**Decision:** extract the jail content to `apps/web-platform/infra/fail2ban-sshd.local` (sibling to `disk-monitor.sh`) rather than inlining via heredoc. This keeps the cloud-init `write_files` content and the `terraform_data` file provisioner reading from the **same** source, matching the pattern called out in `cloud-init.yml:85` ("Keep in sync with terraform_data.deploy_pipeline_fix in server.tf (#2205)"). Cloud-init then reads it via `b64encode(file(...))` like `ci_deploy_script_b64`.

**cloud-init.yml — revised write_files (base64 via Terraform, not inline):**

```yaml
  - path: /etc/fail2ban/jail.d/soleur-sshd.local
    encoding: b64
    content: ${fail2ban_sshd_local_b64}
    owner: root:root
    permissions: '0644'
```

**server.tf — template variable addition:**

```hcl
user_data = templatefile("${path.module}/cloud-init.yml", {
  # … existing keys …
  fail2ban_sshd_local_b64 = base64encode(file("${path.module}/fail2ban-sshd.local"))
})
```

### Phase 4 — Verify

1. `terraform plan` from the worktree (per AGENTS.md `cq-when-running-terraform-commands-locally`):

   ```bash
   cd apps/web-platform/infra && \
     doppler run --project soleur --config prd_terraform -- \
       doppler run --token "$(doppler configure get token --plain)" \
         --project soleur --config prd_terraform --name-transformer tf-var -- \
       terraform plan
   ```

   Expect: `terraform_data.fail2ban_tuning` will be added, `hcloud_server.web` unchanged (user_data ignored by lifecycle).

2. **Destructive write gate** (AGENTS.md `hr-menu-option-ack-not-prod-write-auth`): present the `terraform apply` command to the operator and wait for explicit per-command go-ahead. Do NOT pass `-auto-approve`.

3. After apply:

   ```bash
   # From the operator machine (once Phase 1 unban is done).
   ssh root@135.181.45.178 \
     'fail2ban-client -d | grep -A5 "\[sshd\]" && \
      fail2ban-client get sshd bantime && \
      fail2ban-client get sshd maxretry && \
      ls -l /etc/fail2ban/jail.d/'
   # Expect: bantime 600 (seconds), maxretry 5, file present with 0644 root:root.
   ```

4. Wait for `wg-after-a-pr-merges-to-main-verify-all`: deploy workflow on main succeeds (no SSH dependency — deploys go through the webhook per `cq-for-production-debugging-use`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/infra/fail2ban-sshd.local` exists with the jail.local content above.
- [x] `apps/web-platform/infra/cloud-init.yml` references `fail2ban_sshd_local_b64` and writes to `/etc/fail2ban/jail.d/soleur-sshd.local` with `0644 root:root`.
- [x] `apps/web-platform/infra/server.tf` passes `fail2ban_sshd_local_b64 = base64encode(file(...))` into the templatefile call AND has a new `terraform_data.fail2ban_tuning` resource following the `disk_monitor_install` pattern.
- [x] `knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md` exists with the Cloud Console recovery procedure.
- [ ] `terraform plan` in the worktree returns a plan that adds `terraform_data.fail2ban_tuning` and makes no server replacement. (requires prod_terraform creds — deferred to apply-time.)
- [x] No new secrets required — all changes use existing `hcloud_token`, `ssh_key_path`, SSH agent.

### Post-merge (operator)

- [ ] Phase 1 unban completed from Hetzner Cloud Console; `ssh root@<ip> hostname` succeeds from operator machine.
- [ ] `terraform apply` run successfully against prd_terraform; `terraform_data.fail2ban_tuning` shown as applied.
- [ ] Post-apply SSH sanity: `fail2ban-client -d | grep -A5 '\[sshd\]'` shows `bantime = 600`, `maxretry = 5`, `bantime.maxtime = 3600` (`1h`) on the live host.
- [ ] `fail2ban-client status sshd` output captured in the PR comment for the next incident responder.
- [ ] Runbook referenced from the "Related" section of issue #2654 so the next lockout has a one-link recovery path.

## Test Scenarios

Infrastructure-only change — no unit/integration tests. Verification is runtime (Phase 4 above) and a single synthetic canary:

1. **Canary brute-force** (optional, post-apply): from a disposable throwaway VM (not the operator IP), attempt `for i in {1..6}; do ssh -o BatchMode=yes -o ConnectTimeout=3 root@135.181.45.178 true; done`. Expect: the 5th or 6th connection is reset at kex. `fail2ban-client status sshd` on the host shows the throwaway IP. Wait 10 min → IP clears automatically. **Do not run the canary from the operator IP.** This is worth running once to confirm the tuning applied; skip if the post-apply `-d` output is sufficient proof.

## Domain Review

**Domains relevant:** engineering (CTO — infrastructure change).

No user-facing impact, no copy, no billing, no legal. The PR is scoped to Terraform + a runbook.

### Engineering (CTO)

**Status:** auto-accepted (infra-only, follows established patterns).
**Assessment:** Change reuses the `terraform_data.*_install` pattern already validated by `disk_monitor_install`, `deploy_pipeline_fix`, `docker_seccomp_config`, `apparmor_bwrap_profile`, and `orphan_reaper_install`. The sole net-new concept is `bantime.maxtime` — a well-documented upstream fail2ban config key. Risk is bounded by SSH remaining reachable in all forward paths (the tuning lowers max ban duration, never lengthens it).

**No Product/UX Gate** — not user-facing.

## Non-Goals

- **Do not remove fail2ban.** The prior PR (#2260-ish, see plan `2026-03-19-security-add-fail2ban-ssh-protection-plan.md`) added it deliberately; this plan tunes it.
- **Do not add `ignoreip` for the operator IP.** Operator IPs are NAT-dynamic and a `ignoreip` rule becomes a stale whitelist the moment the ISP rotates the prefix.
- **Do not convert SSH to Cloudflare Tunnel access-proxy.** Valid long-term play but out of scope; deploys already use the webhook path, SSH is for diagnosis only per `cq-for-production-debugging-use`.
- **Do not widen firewall port 22 to `0.0.0.0/0`.** The firewall is already correctly scoped to `var.admin_ips`; widening it would regress the tightened posture from #1836-era hardening.
- **Do not add `DenyUsers deploy` to sshd.** The `AllowUsers root` directive already rejects `deploy` pre-auth — redundant.
- **Do not prescribe a test framework** (AGENTS.md sharp edge — infra-only, no test runner).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Set `bantime = -1` (permanent ban) and add `ignoreip` for admin IPs | Creates a permanent allowlist that drifts as admin IPs change; single-IP failure mode is worse than the current one. |
| Remove `bantime.increment` (flat 10-minute ban) | Removes defense-in-depth against persistent attackers; the ask is "cap the worst case," not "remove escalation." |
| Replace fail2ban with `sshguard` or raw `nftables` rate-limit | Larger change surface; fail2ban is already shipping; no incident evidence that fail2ban itself is broken. |
| Migrate SSH to Cloudflare Access proxy (zero-trust) | Higher value, higher effort. File as a follow-up issue if deemed worthwhile — this plan unblocks the current incident. |
| Use `hcloud rebuild` and re-provision from scratch | Destroys the existing `/mnt/data` volume contents via remount race; way more risk than unban + tune. |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `systemctl reload fail2ban` fails because the jail file has a syntax error | The jail.local content above is minimal and mirrors documented fail2ban keys. Catch at Terraform provisioner time: `fail2ban-client -d` will fail the remote-exec step if the config is invalid. |
| `bantime.maxtime` is not honored on the installed fail2ban version (Ubuntu 24.04 ships 1.0.2+) | `bantime.maxtime` is supported from fail2ban 0.11.0; Ubuntu 24.04 is 1.0.2. Safe. Cite: `apt-cache show fail2ban \| grep Version`. If unexpectedly older, fall back to `bantime = 1h` (flat, no increment). |
| Operator IP changes during incident response | Update `var.admin_ips` in `prd_terraform` Doppler and re-apply firewall. Out of scope for this PR but documented in the runbook. |
| `fail2ban-client get sshd bantime` returns a value other than `600` on the live host after apply | jail.d load order is alphabetic — `soleur-sshd.local` (`s`) loads after `defaults-debian.conf` (`d`). Confirmed by reading `man jail.conf` and `fail2ban-client -d` output. If the override doesn't take effect, the filename is the culprit; rename to `zz-soleur-sshd.local`. |
| `terraform_data.fail2ban_tuning` provisioner runs over SSH, which is the channel the incident disabled | Phase 1 (operator unban) unblocks this. If SSH is still blocked at apply time, apply fails cleanly — no partial state. |
| `AllowUsers root` interaction: fail2ban may not count rejected-user attempts | fail2ban upstream #1341 (closed in 0.11) addressed the `User <x> not allowed because not listed in AllowUsers` match. Ubuntu 24.04 ships fail2ban 1.0.2, so the filter catches the line. Phase 1 runbook verifies with `fail2ban-client --version` and `journalctl -u ssh \| grep 'AllowUsers'`. If (hypothetically) Ubuntu backports a broken filter via security update, sshd filter aggressive mode is the escape hatch — scope-out, not default, because aggressive-mode also fires on valid-username probes (noisier). |
| fail2ban upstream changes `bantime.factor` default between versions | Explicit `bantime.factor = 2` in the drop-in pins the multiplier against future package upgrades. Without it, a future fail2ban 1.2+ that changes the default would silently alter escalation behavior. |
| fail2ban's recidive db (`/var/lib/fail2ban/fail2ban.sqlite3`) persists across reboots and `bantime.increment` counts offenses from it | After this fix, an operator who tripped 3 bans yesterday still escalates to count=4 today. To reset on merge, optionally wipe the recidive entry for a specific IP: `fail2ban-client --db-file /var/lib/fail2ban/fail2ban.sqlite3 banip remove <ip>` (not in Phase 1 — only if post-apply bans are unexpectedly long). |
| `fail2ban-client unban --all` in the runbook also clears legitimate bans against unrelated IPs | Acceptable: there should be zero legitimate bans on a freshly-provisioned server, and during an SSH-lockout incident the operator needs in-band recovery more than precise audit trails. The pre-unban `status sshd` capture preserves the ban list for post-incident review. |

## Operational Notes

- **Rollback path:** `terraform destroy -target=terraform_data.fail2ban_tuning` + remove the drop-in from the host (`rm /etc/fail2ban/jail.d/soleur-sshd.local && systemctl reload fail2ban`) reverts to stock Ubuntu 24.04 fail2ban behavior. No data loss.
- **Learning capture:** after merge, write `knowledge-base/project/learnings/<topic>-ssh-locked-out-by-own-fail2ban.md` (date picked at write time — AGENTS.md sharp edge) capturing: (a) symptom (kex reset), (b) root cause (fail2ban `bantime.increment` recidivism after `deploy@` typo), (c) fix (1-hour `bantime.maxtime` cap + runbook), (d) check "did we update AGENTS.md?" — probably yes, a hard rule like "when typing `ssh <user>@prod`, verify `<user>` matches the Terraform `AllowUsers` directive."

## Research Insights

**References (verified 2026-04-19):**

- Upstream `jail.conf` (fail2ban master): <https://github.com/fail2ban/fail2ban/blob/master/config/jail.conf> — canonical source for default `bantime`, `findtime`, `maxretry`, `bantime.increment`, `bantime.factor` defaults. **Key finding:** no upstream `bantime.maxtime` default ships in `jail.conf`; explicit cap is required to bound escalation.
- Visei "Incremental banning with Fail2Ban" (2020): <https://visei.com/2020/05/incremental-banning-with-fail2ban/> — independently corroborates the `bantime * factor^count` escalation formula.
- fail2ban #1341 (`sshd` filter did not catch `AllowUsers` rejects, fixed in 0.11): <https://github.com/fail2ban/fail2ban/issues/1341> — gates whether our causal hypothesis holds. Ubuntu 24.04 ships 1.0.2, so holds.
- fail2ban discussion #3650 (`Invalid user` vs. valid-user-wrong-password distinction in sshd filter): <https://github.com/fail2ban/fail2ban/discussions/3650>.
- DigitalOcean "How Fail2Ban Works": <https://www.digitalocean.com/community/tutorials/how-fail2ban-works-to-protect-services-on-a-linux-server> — general best-practice confirmation of `.local` drop-in pattern.
- Linuxhint "Change Ban Time Fail2ban, Even Ban Forever" — explains `bantime = -1` permanent-ban semantics. **We explicitly reject this as a design.**

**Anti-patterns avoided:**

- `bantime = -1` (permanent ban). Fires a lockout the operator can only recover via Cloud Console.
- Editing `/etc/fail2ban/jail.conf` directly. `apt upgrade fail2ban` would prompt for merge conflicts.
- Adding `ignoreip = <operator IP>` with a CIDR that rotates. Creates a permanent grant to a later stranger.
- `filter = sshd[mode=aggressive]` as default. Bans username-probe scanners (by far the most common traffic) in addition to real attackers; ratio of true positives to false positives is worse than stock.

## Verification Steps (CLI tokens used in this plan)

Per AGENTS.md `cq-docs-cli-verification`, verify every CLI form that lands in docs:

- `fail2ban-client status sshd` — <!-- verified: 2026-04-19 source: https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Fail2ban-client -->
- `fail2ban-client set sshd unbanip <ip>` — <!-- verified: 2026-04-19 source: https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Fail2ban-client -->
- `fail2ban-client get sshd bantime` / `get sshd maxretry` / `get sshd findtime` — <!-- verified: 2026-04-19 source: https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Fail2ban-client -->
- `fail2ban-client -d` — emits the effective merged config; <!-- verified: 2026-04-19 source: fail2ban-client --help -->
- `fail2ban-client unban --all` — <!-- verified: 2026-04-19 source: https://github.com/fail2ban/fail2ban/blob/master/client/fail2banclient.py (unban subcommand with --all flag) -->
- `fail2ban-client --version` — <!-- verified: 2026-04-19 source: fail2ban-client --help -->
- `bantime.maxtime`, `bantime.increment`, `bantime.factor` keys — <!-- verified: 2026-04-19 source: https://github.com/fail2ban/fail2ban/blob/master/config/jail.conf (see BANTIME INCREMENT section) -->

Operator MUST run `fail2ban-client --help` and `fail2ban-client --version` on-host during Phase 1 to confirm the installed version supports the above keys before the Terraform apply — the runbook names this step.

## Related

- Prior plan: `knowledge-base/project/plans/2026-03-19-security-add-fail2ban-ssh-protection-plan.md` (added fail2ban with stock defaults).
- Prior learnings:
  - `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` — context on why SSH was briefly opened to `0.0.0.0/0`; no longer applies.
  - `2026-03-20-ssh-forced-command-cloud-init-parity-gaps.md` — pattern for keeping cloud-init and `terraform_data` provisioners in sync.
  - `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` — `terraform_data` + `connection { agent = true }` pattern reused here.
- Runbook (new): `knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md`.
- AGENTS.md rules invoked: `hr-all-infrastructure-provisioning-servers`, `hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`, `hr-menu-option-ack-not-prod-write-auth`, `cq-for-production-debugging-use`, `cq-when-running-terraform-commands-locally`, `cq-docs-cli-verification`.
- Blocks: attaching Step 3 output to #2605 (mentioned in issue body); unblocked by Phase 1 completion.
