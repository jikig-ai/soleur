---
title: "feat: add disk space monitoring and alerting for deploy servers"
type: feat
date: 2026-04-05
issue: "#1409"
---

# feat: Add Disk Space Monitoring and Alerting for Deploy Servers

## Overview

Add proactive disk space monitoring to both Hetzner deploy servers (web-platform CX33 and telegram-bridge CX22) so the team is alerted before disk exhaustion causes silent deploy failures. The root disk on the web-platform server hit 100% from Docker image accumulation (#1405), and the failure was only discovered when the deploy health check failed in CI -- no proactive alert existed.

## Problem Statement

On 2026-04-02, the web-platform deploy webhook accepted requests (HTTP 202) but ci-deploy.sh failed silently because the root disk was 100% full. Production stayed on the old version while CI reported a deploy verification failure. The root cause (Docker image accumulation) was fixed in #1405 with aggressive per-deploy pruning and a disk pre-flight check. However, the monitoring gap remains: there is no proactive alert when disk usage crosses a warning threshold. Other disk consumers (logs, volumes, temp files, build artifacts) could cause the same failure.

**Current observability stack:**

| Tool | Scope | Gap |
|------|-------|-----|
| Sentry | Application exceptions | No host-level metrics |
| Better Stack | Uptime (HTTP health checks) | No disk/CPU/memory metrics |
| Docker log rotation | Log size caps | Does not cover host disk |
| Weekly cron prune | Docker images >72h | Reactive cleanup, no alerting |
| ci-deploy.sh pre-flight | 5GB minimum check | Fails the deploy, does not alert proactively |

## Proposed Solution

**Option B: Lightweight cron + Discord webhook alert** -- a shell script on each server that runs every 5 minutes via cron, checks disk usage with `df`, and posts to a Discord webhook when usage exceeds 80%. This is the right choice for a two-server setup.

### Why Option B Over A and C

| Option | Approach | Verdict |
|--------|----------|---------|
| A: Better Stack Collector | Docker-based agent with `COLLECTOR_SECRET`, eBPF auto-instrumentation, OpenTelemetry pipeline | Overkill -- adds a Docker container to monitor Docker containers. The Collector is designed for multi-server fleets with dashboarding needs. Free tier may not cover infrastructure metrics. Requires account-level setup (source tokens, dashboard creation). |
| **B: Cron + Discord webhook** | **Shell script, systemd timer or cron, `curl` to Discord webhook** | **Right-sized -- zero dependencies, no new services, matches existing alerting pattern (Discord webhooks used in 5+ CI workflows). Provisioned via Terraform cloud-init (existing pattern).** |
| C: Prometheus + node_exporter + Grafana | Full metrics stack with scraping, TSDB, dashboarding | Massive overkill for 2 servers. Requires 3 additional containers, port exposure, persistent storage, and ongoing maintenance. |

### Design

```text
[cron: every 5 min] --> [disk-monitor.sh] --> df / --> usage > 80%?
                                                          |
                                                    yes   |   no
                                                    v     v
                                              POST Discord  (silent)
                                              webhook
```

**Components:**

1. **`disk-monitor.sh`** -- Shell script placed at `/usr/local/bin/disk-monitor.sh`
   - Checks root filesystem (`/`) usage via `df --output=pcent /`
   - If usage >= 80%, posts a structured Discord embed with: server hostname, disk usage %, available space, timestamp
   - Cooldown mechanism: writes last alert timestamp to separate files per threshold (`/var/run/disk-monitor-alert-80` and `/var/run/disk-monitor-alert-95`) to avoid alert flooding (re-alert every 1 hour per threshold, not every 5 minutes). Separate files ensure a 95% critical alert is not suppressed by a prior 80% warning.
   - Discord `allowed_mentions`: 80% alert uses `{parse: []}` (no pings), 95% alert uses `{parse: ["everyone"]}` (enables `@here`)
   - Exit 0 always (cron jobs that exit non-zero generate mail noise)

2. **Systemd timer** (preferred over raw crontab for logging/management)
   - `disk-monitor.timer` -- runs every 5 minutes
   - `disk-monitor.service` -- executes disk-monitor.sh as root (needs `df` access)
   - Logs to journalctl for debugging

3. **Discord webhook URL** -- stored in Doppler `prd` config as `DISCORD_OPS_WEBHOOK_URL`
   - Create a dedicated `#ops-alerts` Discord channel with its own webhook for signal isolation from CI notifications
   - Injected into the script via an environment file at `/etc/default/disk-monitor` (`chmod 600`, same pattern as `/etc/default/webhook-deploy`)

4. **Terraform provisioning** -- added to `apps/web-platform/infra/cloud-init.yml` for new servers and via a `terraform_data` provisioner for the existing server (same pattern as `doppler_install`)

5. **Runbook** -- `knowledge-base/engineering/ops/runbooks/disk-monitoring.md` documenting the setup, alert response procedure, and how to adjust thresholds

## Technical Approach

### Architecture

The monitoring script runs directly on each Hetzner server as a systemd timer. No additional containers, services, or external accounts are required.

```text
Hetzner CX33 (web-platform)          Hetzner CX22 (telegram-bridge)
+-----------------------+             +-----------------------+
| systemd timer (5min)  |             | systemd timer (5min)  |
| disk-monitor.sh       |             | disk-monitor.sh       |
| reads /etc/default/   |             | reads /etc/default/   |
|   disk-monitor        |             |   disk-monitor        |
+----------+------------+             +----------+------------+
           |                                     |
           v                                     v
     Discord Webhook (DISCORD_OPS_WEBHOOK_URL)
           |
           v
     #ops-alerts channel
```

### Implementation Phases

#### Phase 1: Script and Systemd Units

- [ ] Create `apps/web-platform/infra/disk-monitor.sh` -- the monitoring script
  - Parse `df --output=pcent / | tail -1 | tr -d ' %'` for integer percentage
  - Parse `df --output=avail / | tail -1 | tr -d ' '` for available KB
  - Load `DISCORD_OPS_WEBHOOK_URL` from `/etc/default/disk-monitor`
  - Check separate cooldown files per threshold (`/var/run/disk-monitor-alert-80`, `/var/run/disk-monitor-alert-95`) -- skip if alerted within last 3600 seconds for that threshold
  - If usage >= 80%: POST Discord webhook with structured embed (hostname, percentage, available space, top 5 disk consumers via `timeout 10 du -sh /* 2>/dev/null | sort -rh | head -5`), `allowed_mentions: {parse: []}`
  - If usage >= 95%: POST Discord webhook with `@here` mention for critical urgency, `allowed_mentions: {parse: ["everyone"]}`
  - Always exit 0
- [ ] Create systemd unit files (embedded in cloud-init.yml via `write_files`):
  - `disk-monitor.service` -- `Type=oneshot`, `ExecStart=/usr/local/bin/disk-monitor.sh`, runs as root
  - `disk-monitor.timer` -- `OnBootSec=5min`, `OnUnitActiveSec=5min`, `Persistent=true`
- [ ] Write tests for disk-monitor.sh in `apps/web-platform/infra/disk-monitor.test.sh` (following existing ci-deploy.test.sh pattern):
  - Test: normal disk usage (below 80%) produces no output and exit 0
  - Test: 80% usage triggers Discord webhook POST (mock `curl`)
  - Test: 95% usage includes `@here` mention
  - Test: cooldown prevents duplicate alerts within 1 hour (per threshold)
  - Test: 95% alert fires even when 80% cooldown is active (separate cooldown files)
  - Test: `df` command failure exits 0 with warning to stderr
  - Test: missing webhook URL exits 0 with warning to stderr
  - Test: `curl` failure exits 0 (graceful degradation)

#### Phase 2: Doppler Secret and Terraform Provisioning

- [ ] Create a dedicated `#ops-alerts` Discord channel and webhook URL for infrastructure alerts
- [ ] Add `DISCORD_OPS_WEBHOOK_URL` to Doppler `prd` config with the new webhook URL
- [ ] Update `apps/web-platform/infra/cloud-init.yml`:
  - Add `write_files` entries for `disk-monitor.sh`, `disk-monitor.service`, `disk-monitor.timer`
  - Add `write_files` entry for `/etc/default/disk-monitor` with `DISCORD_OPS_WEBHOOK_URL` from Terraform variable
  - Add `runcmd` entries to enable the systemd timer: `systemctl daemon-reload && systemctl enable --now disk-monitor.timer`
- [ ] Add `var.discord_ops_webhook_url` to `apps/web-platform/infra/variables.tf` (sensitive string)
- [ ] Add `terraform_data.disk_monitor_install` resource to `apps/web-platform/infra/server.tf`:
  - Uses `remote-exec` provisioner to deploy the script and systemd units to the existing server
  - Triggers on `sha256(var.discord_ops_webhook_url)` (re-deploys if webhook URL changes)
  - Same SSH connection pattern as `terraform_data.doppler_install`
- [ ] Provision Doppler secret: `doppler secrets set DISCORD_OPS_WEBHOOK_URL "<url>" -p soleur -c prd`
- [ ] Add `DISCORD_OPS_WEBHOOK_URL` to Doppler `prd_terraform` config (for Terraform variable injection)

#### Phase 3: Telegram-Bridge Server (deferred -- separate issue)

The telegram-bridge CX22 server has a different Terraform structure (no `server.tf`, no SSH provisioner wired). Applying the same monitoring requires different plumbing (adding `hcloud` provider, server data source, SSH connection). This is deferred to a separate tracking issue to keep this plan focused on the web-platform server.

- [ ] Create GitHub issue to track telegram-bridge disk monitoring (milestone: "Post-MVP / Later")

#### Phase 4: Documentation and NFR Update

- [ ] Create runbook: `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`
  - Alert response procedure (what to do when you get the alert)
  - Manual cleanup commands (`docker image prune -af`, `journalctl --vacuum-size=100M`, `apt clean`)
  - How to adjust thresholds
  - How to test the alert manually (`bash /usr/local/bin/disk-monitor.sh`)
- [ ] Update `knowledge-base/engineering/architecture/nfr-register.md`:
  - NFR-002 (System-Level Monitoring): Update Compute row from "Partial | Hetzner Console" to "Partial | Hetzner Console + disk-monitor.sh (disk usage alerts at 80%/95%)"

## Alternative Approaches Considered

| Approach | Why Not |
|----------|---------|
| Better Stack Collector | Requires Docker container agent, account-level setup (source tokens, dashboards). The Collector documentation shows it is designed for Docker Compose/Kubernetes environments with full observability pipelines (eBPF, OpenTelemetry). Disproportionate for "alert me when disk is full." |
| Prometheus + node_exporter | 3 additional containers (Prometheus, node_exporter, Alertmanager or Grafana). Persistent storage for TSDB. Port exposure. Ongoing maintenance. Appropriate for 10+ servers, not 2. |
| Better Stack Uptime heartbeat | Uptime monitors check HTTP endpoints, not host metrics. Would require building a custom `/disk-health` HTTP endpoint on each server -- more moving parts than a cron script. |
| Hetzner Cloud API polling | Hetzner metrics API provides CPU/network but not disk utilization. Would require a GitHub Actions workflow to SSH in and check `df` -- adds CI minutes cost and 15-minute minimum granularity. |
| Cloud-init only (no existing server provisioner) | cloud-init runs at server creation time only. The existing CX33 server has `lifecycle { ignore_changes = [user_data] }`, so cloud-init changes do not apply to it. The `terraform_data` provisioner handles existing servers. |

## Acceptance Criteria

### Functional Requirements

- [ ] Disk usage on the web-platform deploy server (CX33) is checked every 5 minutes (telegram-bridge CX22 deferred to separate issue)
- [ ] Alert fires when disk usage exceeds 80% on any server
- [ ] Alert fires with elevated urgency (`@here`) when disk usage exceeds 95%
- [ ] Alert reaches the team via Discord webhook in an ops-alerts channel
- [ ] Cooldown prevents alert flooding (max 1 alert per hour per threshold, separate cooldown for 80% and 95%)
- [ ] Monitoring script exits 0 even on failure (no cron mail noise)
- [ ] Script gracefully handles missing webhook URL or network failure

### Non-Functional Requirements

- [ ] No additional Docker containers or external services required
- [ ] Provisioned via Terraform (reproducible for new servers)
- [ ] Webhook URL stored in Doppler (not hardcoded)
- [ ] NFR-002 (System-Level Monitoring) updated in nfr-register.md

### Quality Gates

- [ ] Shell script tests pass (disk-monitor.test.sh)
- [ ] `terraform plan` succeeds with the new variable
- [ ] Monitoring verified on live server after `terraform apply`
- [ ] Documentation complete (runbook + NFR update)

## Test Scenarios

### Unit Tests (disk-monitor.test.sh)

- Given disk usage is 50%, when disk-monitor.sh runs, then no Discord webhook is called and exit code is 0
- Given disk usage is 82%, when disk-monitor.sh runs, then a Discord webhook POST is made with usage percentage in the embed
- Given disk usage is 96%, when disk-monitor.sh runs, then a Discord webhook POST includes `@here` mention
- Given disk usage is 82% and the 80% cooldown file was written 30 minutes ago, when disk-monitor.sh runs, then no new 80% alert is sent
- Given disk usage is 82% and the 80% cooldown file was written 2 hours ago, when disk-monitor.sh runs, then a new 80% alert is sent
- Given disk usage is 96% and the 80% cooldown file was written 30 minutes ago but no 95% cooldown file exists, when disk-monitor.sh runs, then a 95% critical alert is sent (independent cooldowns)
- Given `df` command fails (filesystem error), when disk-monitor.sh runs, then a warning is logged to stderr and exit code is 0
- Given DISCORD_OPS_WEBHOOK_URL is empty, when disk-monitor.sh runs, then a warning is logged to stderr and exit code is 0
- Given curl fails (network error), when disk-monitor.sh runs, then the failure is logged and exit code is 0

### Integration Verification

- **SSH verify:** `ssh root@<server> systemctl is-active disk-monitor.timer` expects `active`
- **SSH verify:** `ssh root@<server> systemctl list-timers disk-monitor.timer --no-pager` shows next run within 5 minutes
- **SSH verify:** `ssh root@<server> journalctl -u disk-monitor.service --since '5 min ago' --no-pager` shows recent execution
- **Manual trigger:** `ssh root@<server> bash /usr/local/bin/disk-monitor.sh` -- verify Discord message appears (or verify no message if disk usage is below 80%)

## Dependencies and Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| Discord webhook URL | Webhook could be rate-limited or revoked | Cooldown mechanism limits to 1 alert/hour; graceful degradation on failure |
| SSH access to existing server | Terraform provisioner requires SSH key | Already working for `doppler_install` provisioner |
| Doppler prd config | Adding new secret requires access | Already have `DOPPLER_TOKEN_PRD_TF` in GitHub secrets for Terraform |
| Telegram-bridge server SSH | May not have SSH provisioner wired in Terraform | Phase 3 addresses this; can be deferred if SSH not available |

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Straightforward infrastructure addition. The cron + Discord pattern is well-established in this project. Key technical consideration: use systemd timers over raw crontab for better logging and management. The `terraform_data` provisioner pattern for existing servers is already proven (`doppler_install`). No architectural concerns -- this does not add services, containers, or external dependencies.

### Operations (COO)

**Status:** reviewed
**Assessment:** No new vendor or expense. Discord webhook is already provisioned (GitHub secret `DISCORD_WEBHOOK_URL` exists). A dedicated `DISCORD_OPS_WEBHOOK_URL` in Doppler prd is recommended to separate ops alerts from CI notifications. Consider creating a `#ops-alerts` Discord channel for signal isolation. No expense ledger update needed (all free-tier).

## References and Research

### Internal References

- Root cause incident: `knowledge-base/project/learnings/integration-issues/2026-04-02-docker-image-accumulation-disk-full-deploy-failure.md`
- Deploy script with disk pre-flight: `apps/web-platform/infra/ci-deploy.sh:111-117`
- Existing Docker cleanup cron: `apps/web-platform/infra/cloud-init.yml:189-196`
- Terraform provisioner pattern: `apps/web-platform/infra/server.tf:48-70` (`terraform_data.doppler_install`)
- NFR register (monitoring gaps): `knowledge-base/engineering/architecture/nfr-register.md:93-104`
- Existing deploy test pattern: `apps/web-platform/infra/ci-deploy.test.sh`
- Discord webhook usage in CI: `.github/workflows/scheduled-terraform-drift.yml:191-228`
- Expenses ledger: `knowledge-base/operations/expenses.md`

### External References

- [Discord Webhook API](https://discord.com/developers/docs/resources/webhook#execute-webhook)
- [systemd.timer documentation](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- Better Stack Collector docs (evaluated, rejected): requires Docker agent per server
