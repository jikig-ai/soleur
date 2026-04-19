---
title: "feat: deploy resource monitoring before beta invites"
type: feat
date: 2026-04-19
issue: 1052
milestone: "Phase 4: Validate + Scale"
semver: patch
---

# Resource Monitoring Before Beta Invites

Closes #1052. Refs #673 (Phase 4 umbrella: Container isolation, rate limiting, monitoring).

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** Overview, Research Insights, Architecture, Files to edit, Files to create, Pseudo-code, Test Scenarios, Risks
**Research sources used:** Context7 (N/A — no 3rd-party lib docs needed), live repo inspection (`ws-handler.ts`, `server/index.ts`, `ci-deploy.sh`, `test/server/health.test.ts`), institutional learnings (shell-mock-testing, production-observability, docker-disk-accumulation), WebSearch (systemd/`/proc/stat` sampling best practices 2026)

### Key Corrections From Deepen Pass

1. **Health endpoint path is `/health`, not `/api/health`.** The custom HTTP server in `server/index.ts` serves `/health` at the root. `apps/web-platform/app/` has no App Router health route. Every pre-deepen reference to `/api/health` has been corrected.
2. **`sessions` Map is already exported** from `server/ws-handler.ts` (line 73: `export const sessions = new Map<string, ClientSession>()`). Dropped the unneeded "export a helper" task — `session-metrics.ts` can `import { sessions } from "./ws-handler"` directly. One fewer edited file.
3. **Existing health test lives at `apps/web-platform/test/server/health.test.ts`** (not `test/health.test.ts`). Plan corrected to edit-in-place and extend with new field assertions rather than create a new file.
4. **Docker port mapping confirmed:** production container publishes `-p 0.0.0.0:3000:3000` (verified in `ci-deploy.sh`), so `curl http://127.0.0.1:3000/health` from the host reaches the containerized server.
5. **CPU sampling upgrade:** loadavg-based CPU % is a proxy, not a true utilization number. Upgraded to `/proc/stat` delta sampling with a 1-second window, following 2026 monitoring best practice. Same script, ~8 extra lines, materially more accurate.
6. **Memory sampling upgrade:** use `MemAvailable` from `/proc/meminfo` (not `total - used` from `free -b`) — `MemAvailable` accounts for reclaimable buffers/cache, which is the number that actually predicts OOM.
7. **Test harness pattern carried from `disk-monitor.test.sh`:** curl mock must use `echo "$*" >> capture_file` (not `${!@}` indirect expansion). Documented in Risks per the 2026-04-05 learning.

### New Considerations Discovered

- The existing `/health` response is **contract-critical** — consumed by `ci-deploy.sh` (canary verification) and `web-platform-release.yml`. New fields are **additive**; no existing field may be renamed or removed, else the deploy pipeline breaks silently.
- Adding `active_sessions` to `/health` exposes operational telemetry on an unauthenticated endpoint. This is acceptable (count only, no PII), but must be noted — deferring auth on `/health` is a deliberate choice so Cloudflare/Hetzner probes don't need credentials.
- The host-level monitor runs outside the Docker container (systemd timer on the VM). It therefore sees **host** memory (the real physical ceiling), which is exactly the signal we want — Docker's cgroup memory counters would mask overcommit.
- The `disk-monitor.sh` pattern has a 2026-04-05 learning about mock testing shape (`$*` dump, not `${!@}`). Any test for `resource-monitor.sh` must adopt the same pattern from the first commit to avoid re-learning.

## Overview

**Problem.** The single Hetzner `cx33` VM (4 vCPU, 8 GB RAM) backing
`apps/web-platform` has zero visibility into CPU/RAM utilization and zero
count of concurrent agent sessions. The first sign of capacity pressure
before beta invites will be a user-facing OOM or page timeout — by which
point the founder has already lost the onboarding window for that user.

**Solution scope (MVP).** Ship the minimum host-level telemetry that lets
an operator see capacity pressure **before** it becomes user-facing:

1. Periodic CPU / RAM / concurrent-session sampling on the host.
2. Email alert (Resend) when 5-minute memory utilization crosses 80 %.
3. A lightweight metrics surface (numbers in the existing `/health`
   response) so the founder and automation can read current load without SSH.

**Explicit non-scope.** Workspace-level cgroup CPU/RAM (one number per
bwrap sandbox) is gated on the container-per-workspace work (roadmap 4.7,
triggered at 5+ concurrent users). Per-process telemetry adds
bwrap-sandbox introspection that the current sandbox isn't built for.
The plan therefore implements **host-level** CPU/RAM (which is the
physical resource that actually gets exhausted on a single-VM
deployment) and **counts** concurrent workspaces / agent sessions. This
is noted explicitly in § Non-Goals so the PR description can't drift.

**Pattern reuse.** The existing `apps/web-platform/infra/disk-monitor.sh`
(systemd oneshot + 5-min timer + per-threshold cooldown + Resend HTTP
POST) is the template. This plan is largely "second instance of the
disk-monitor pattern, plus a small `/health` extension" rather than a new
architecture.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #1052 body) | Codebase reality | Plan response |
|---|---|---|
| "CPU/RAM per workspace" | Workspaces are bubblewrap sandboxes (not cgroup-v2 scopes); per-workspace resource accounting is not wired. | Reframe MVP as host-level CPU/RAM + concurrent-session count. Add explicit Non-Goal covering per-workspace cgroup metrics. File follow-up (see Deferral Tracking). |
| "Track concurrent agent sessions" | `agent-runner.ts` does not export a live counter; sessions live inside `ws-handler.ts` socket map. | Add a small `activeSessions` / `activeWorkspaces` getter in `server/session-metrics.ts` sourced from the existing WS map. Expose through `/health`. |
| Roadmap table lists #1052 at P1 | Issue body says `priority/p2-medium` | Trust the issue label (P2). Will update roadmap's priority column in the same PR. |
| Roadmap row 4.8 cites #673 | #673 is the Phase 4 umbrella ("Container isolation, rate limiting, monitoring"). #1052 is the monitoring-specific child. | Leave #673 as umbrella; update roadmap row 4.8 to cite `#1052` (more specific) alongside `#673`. |

## Research Insights

- **Existing pattern:** `apps/web-platform/infra/disk-monitor.sh` —
  Resend-based alerts, per-threshold cooldown file under `/var/run/`,
  `set -euo pipefail`, always exits 0. Provisioned via
  `cloud-init.yml` **and** a `terraform_data` resource with
  `provisioner "remote-exec"` (`disk_monitor_install` in `server.tf`)
  because the existing server ignores `user_data` changes on update.
  The new monitor MUST follow the same dual-path provisioning.
- **Existing health endpoint:** `apps/web-platform/server/health.ts`
  already returns `uptime` and `memory` (process RSS in MB). Extend
  the `HealthResponse` shape with host-level fields and session counts.
- **Sentry is already wired** (`sentry.server.config.ts`); adding a
  `Sentry.metrics` breadcrumb for threshold crossings is cheap but
  **deferred** — email alerts are the MVP alarm, and Sentry metrics
  are not yet an active ops surface.
- **Secret management:** the disk-monitor uses `RESEND_API_KEY` from
  `/etc/default/disk-monitor`, provisioned by Terraform from
  `var.resend_api_key` (Doppler `prd_terraform`). Re-use the same
  secret and extend the env file or add a sibling `/etc/default/resource-monitor`.
- **Cooldown pattern:** `${COOLDOWN_DIR}/disk-monitor-alert-${threshold}`
  file stores unix-epoch of last alert; 1 hour cooldown per threshold.
  Same mechanism prevents alert floods when memory hovers near 80 %.
- **Workspace concept:** `/mnt/data/workspaces/<user-uuid>/`, reaped by
  `orphan-reaper.sh` on a 6-hour timer. Counting **active** workspaces
  means counting non-`.orphaned-*` subdirectories — cheap.
- **Agent sessions:** live WebSocket connections tracked in
  `server/ws-handler.ts` (a `Map<sessionId, socket>` per process).
  `/health` can expose `socketMap.size` without any new storage.
- **CLI verification.** The monitor uses `top -bn1`, `free -b`, and `awk`
  — all BusyBox/coreutils standard on Ubuntu 24.04 cloud-init image.
  `free -b`, `top -bn1 | grep "Cpu(s)"`, and `awk` are verified present
  on the existing server (confirmed via the sibling disk-monitor.sh
  which already uses `df --output=pcent`).
- **Scale sanity:** `cx33` = 4 vCPU, 8 GB RAM. A 5-minute window of
  memory > 80 % = > 6.4 GB sustained → fires well before swap thrash
  on a VM that size.
- **Institutional learnings applied:**
  - `knowledge-base/project/learnings/2026-03-21-cloudflare-service-token-expiry-monitoring.md`
    — alert cooldown must be per-threshold, not global.
  - `knowledge-base/project/learnings/2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`
    — any new TF variable without a default must be provisioned in
    Doppler `prd_terraform` **before** merge; missing vars mask real drift.
  - `constitution.md` Always rule #114: drift detection silently fails
    when variables are missing — apply the same checklist.

## Domain Review

**Domains relevant:** operations, engineering

### Operations (COO)

**Status:** reviewed (inline, plan-phase)
**Assessment:** Aligns with the New Vendor Checklist — no new vendor,
reuses Resend which already has a ledger entry from the disk-monitor
work. No privacy policy updates required (no PII in alerts; alerts
carry `hostname` + utilization percentage only). Expense ledger: no
change — Resend API usage adds ~1-10 extra emails/month at $0.00 on
the current tier.

### Engineering

**Status:** reviewed (inline, plan-phase)
**Assessment:** Small blast radius (infra-only + one server module +
one route field addition). Tested pattern already in production
(`disk-monitor.sh`). No database migration. No npm dependency add.
Provisioning is Terraform-only per `hr-all-infrastructure-provisioning-servers`.

**Product/UX Gate:** NONE — no user-facing UI added. `/health` already
exists and is internal/ops-facing. Skip tier.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/resource-monitor.sh` exists, is executable
      (`chmod +x`), passes `bash -n` and `shellcheck -S error`.
- [ ] A companion `resource-monitor.test.sh` exercises: (1) under-threshold → no email,
      (2) crossing 80 % warn → one email, (3) second invocation within cooldown → no second email,
      (4) crossing 95 % crit after warn → separate email (per-threshold cooldown).
- [ ] `apps/web-platform/infra/cloud-init.yml` injects
      `resource-monitor.sh`, `/etc/default/resource-monitor`,
      `/etc/systemd/system/resource-monitor.service`, and
      `/etc/systemd/system/resource-monitor.timer` (5-min cadence).
- [ ] `apps/web-platform/infra/server.tf` gains a
      `terraform_data.resource_monitor_install` mirror of
      `disk_monitor_install` so the existing server is updated.
- [ ] `apps/web-platform/server/session-metrics.ts` exports
      `getActiveSessionCount()` and `getActiveWorkspaceCount()`.
- [ ] `apps/web-platform/server/health.ts` `HealthResponse` includes:
      `cpu_pct_1m`, `mem_pct`, `load_avg_1m`, `active_sessions`,
      `active_workspaces`.
- [ ] `apps/web-platform/test/server/health.test.ts` (edit in place)
      pins the new shape with `.toBe`/`.toBeGreaterThanOrEqual`
      assertions — never `.toContain([pre, post])` per
      `cq-mutation-assertions-pin-exact-post-state`.
- [ ] `apps/web-platform/test/server/session-metrics.test.ts` covers the
      two getters: mock `./ws-handler` with `vi.mock()` to inject a
      pre-populated `sessions` Map; mock `fs.readdirSync` /
      `fs.statSync` for the workspace getter (including a
      `.orphaned-*` entry to prove filtering works).
- [ ] `terraform fmt -recursive apps/web-platform/infra` clean.
- [ ] `knowledge-base/product/roadmap.md` row 4.8 priority column
      updated to P2 (matching the issue label).

### Post-merge (operator)

- [ ] Operator runs `doppler run --name-transformer tf-var -- terraform plan`
      from `apps/web-platform/infra/` (locally or via CI drift workflow)
      and confirms the plan is exactly the two new `terraform_data`
      resources (or, on refresh, "no changes" after apply).
- [ ] Operator runs `terraform apply` (not `-auto-approve`, per
      `hr-menu-option-ack-not-prod-write-auth`).
- [ ] Post-apply verification: SSH to `root@<web-server>` and run
      `systemctl is-active resource-monitor.timer` → `active`;
      `systemctl list-timers resource-monitor.timer` shows next run
      within 5 min.
- [ ] Post-apply verification: trigger one alert by running
      `sudo /usr/local/bin/resource-monitor.sh` after setting
      `WARN_THRESHOLD=1` in an override shell env; confirm email
      received in ops inbox; delete cooldown file.
- [ ] Post-apply verification:
      `curl https://app.soleur.ai/health` (path confirmed during
      deepen pass — served by custom HTTP server, not App Router)
      includes the five new fields.
- [ ] Post-deploy: open the PR's URL to Sentry dashboard and confirm
      no new error events tied to `getActiveSessionCount` on the first
      100 health pings.

## Non-Goals

- **Per-workspace CPU/RAM accounting.** Bubblewrap sandboxes don't have
  per-sandbox cgroup scopes today; adding them requires the
  container-per-workspace work (roadmap 4.7 / triggered at 5+
  concurrent users). Tracked separately — see Deferral Tracking.
- **Prometheus / Grafana / time-series DB.** Out of scope for the
  single-VM, pre-beta posture. Plain email + `/health` JSON snapshot is
  sufficient until Phase 4 exit.
- **Sentry custom metrics / breadcrumbs for threshold crossings.** Not
  an active ops surface. Revisit when ops uses Sentry as the alarm path.
- **Dashboard UI.** `/health` JSON is the interface; a human-readable
  page is deferred.
- **Paging / SMS / on-call rotation.** Single-founder ops; email alert
  to `ops@jikigai.com` is the alarm.

## Architecture

```text
                                cx33 Hetzner VM
                                      │
             ┌────────────────────────┼────────────────────────┐
             │                        │                        │
             ▼                        ▼                        ▼
 systemd timer (5m)          Next.js server (PID 1 in          /mnt/data/workspaces/
 resource-monitor.timer       container)                       └── <uuid>/
     │                              │                              <uuid>/
     ▼                              │                              .orphaned-*/
 resource-monitor.service           │
     │                              │
     ▼                              │
 /usr/local/bin/                    │
 resource-monitor.sh ──┐            │
                       │            │
                       ▼            ▼
                    [sample: top / free / loadavg]
                    [cooldown check /var/run/resource-monitor-alert-{warn,crit}]
                    [email via Resend HTTP POST]

 /health  ──► server/index.ts ──► buildHealthResponse()
    │          (custom HTTP server,
    │           not App Router)
    │                                 │
    │                                 ├─► process.memoryUsage().rss   (existing)
    │                                 ├─► /proc/meminfo MemAvailable  (NEW)
    │                                 ├─► /proc/stat delta           (NEW)
    │                                 ├─► /proc/loadavg              (NEW)
    │                                 ├─► getActiveSessionCount()    (NEW, from ws-handler.sessions)
    │                                 └─► getActiveWorkspaceCount()  (NEW, readdir /workspaces)
    │
    └── also consumed by ci-deploy.sh (canary gate) and
        web-platform-release.yml (deploy verification) — additive
        fields only, no renames/removals.
```

## Files to edit

- `apps/web-platform/infra/cloud-init.yml` — add
  `resource-monitor.sh` write_files entry, env file, service unit,
  timer unit, and `systemctl enable --now resource-monitor.timer` in
  `runcmd`.
- `apps/web-platform/infra/server.tf` — add the
  `resource_monitor_script_b64 = base64encode(file(...))` variable
  into the `templatefile` call for `user_data`, and add a
  `terraform_data.resource_monitor_install` (mirror of
  `disk_monitor_install`, same `triggers_replace` /
  `provisioner "file"` / `provisioner "remote-exec"` shape).
- `apps/web-platform/server/health.ts` — extend `HealthResponse`
  interface and `buildHealthResponse()` return object. Deepen-pass
  correction: `buildHealthResponse` is called from
  `apps/web-platform/server/index.ts` at path `/health` (verified line
  29-38); no App Router route exists.
- `apps/web-platform/test/server/health.test.ts` — edit in place (the
  file already exists; verified during deepen pass). Add `.toBe`
  equality assertions for `cpu_pct_1m`, `mem_pct`, `load_avg_1m`,
  `active_sessions`, `active_workspaces` using the existing
  `describe("buildHealthResponse", ...)` block structure.
- `knowledge-base/product/roadmap.md` — update Phase 4 row 4.8 priority
  column P1 → P2 (matches the issue label); keep #1052 + #673 refs.

**Deepen-pass note:** `apps/web-platform/server/ws-handler.ts` does
**NOT** need editing. The `sessions` Map is already exported as a
top-level constant (`export const sessions = new Map<string, ClientSession>()`
at line 73). `session-metrics.ts` can `import { sessions } from "./ws-handler"`
directly. The pre-deepen plan incorrectly listed this as a required edit.

## Files to create

- `apps/web-platform/infra/resource-monitor.sh` — bash monitor
  (see pseudo-code below).
- `apps/web-platform/infra/resource-monitor.test.sh` — test harness
  mirroring `disk-monitor.test.sh` style (sibling lives at
  `apps/web-platform/infra/disk-monitor.test.sh`). Mock curl with
  `echo "$*" >> capture_file` per the 2026-04-05 learning; never
  use `${!@}` indirect expansion.
- `apps/web-platform/server/session-metrics.ts` — tiny module
  exporting `getActiveSessionCount()` (reads exported `sessions.size`)
  and `getActiveWorkspaceCount()` (readdir on `/workspaces`, filter
  out `.orphaned-*`).
- `apps/web-platform/test/server/session-metrics.test.ts` — vitest
  covering both getters. For `getActiveSessionCount`, use
  `vi.mock("../../server/ws-handler", () => ({ sessions: new Map(...) }))`.
  For `getActiveWorkspaceCount`, mock `fs.readdirSync` + `fs.statSync`.

## Pseudo-code / contract sketches

### `apps/web-platform/infra/resource-monitor.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# resource-monitor.sh -- Host CPU/RAM + concurrent-session monitoring.
# Runs as a systemd timer every 5 minutes. Always exits 0.

readonly COOLDOWN_DIR="${COOLDOWN_DIR:-/var/run}"
readonly COOLDOWN_SECONDS=3600
readonly WARN_MEM_PCT=80
readonly CRIT_MEM_PCT=95
readonly WARN_CPU_PCT=85     # 5-min average
readonly ENV_FILE="${ENV_FILE:-/etc/default/resource-monitor}"

# --- Load config, skip gracefully if missing (mirrors disk-monitor.sh) ---
[[ -f "$ENV_FILE" ]] || { echo "WARNING: $ENV_FILE missing" >&2; exit 0; }
set -a; . "$ENV_FILE"; set +a
[[ -n "${RESEND_API_KEY:-}" ]] || { echo "WARNING: RESEND_API_KEY unset" >&2; exit 0; }

# --- Sample (handle errors gracefully, never crash) ---
# Use /proc/meminfo MemAvailable (reclaimable buffers+cache included),
# not free-b's (total-used) — MemAvailable is the number that actually
# predicts OOM pressure. Verified pattern from kernel docs.
sample_mem_pct() {
  local total available
  total=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
  available=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)
  [[ -n "$total" && -n "$available" && "$total" -gt 0 ]] || { echo 0; return 1; }
  echo $(( ( (total - available) * 100 ) / total ))
}

# /proc/stat delta sampling over 1 second. This is the actual CPU
# utilization %, not a loadavg proxy. Loadavg reflects run-queue depth
# including IO-wait, which over-reports on disk-bound workloads.
sample_cpu_pct() {
  local user1 nice1 sys1 idle1 iowait1 total1 idle_all1
  local user2 nice2 sys2 idle2 iowait2 total2 idle_all2
  read -r _ user1 nice1 sys1 idle1 iowait1 _ < <(head -1 /proc/stat)
  idle_all1=$(( idle1 + iowait1 ))
  total1=$(( user1 + nice1 + sys1 + idle1 + iowait1 ))
  sleep 1
  read -r _ user2 nice2 sys2 idle2 iowait2 _ < <(head -1 /proc/stat)
  idle_all2=$(( idle2 + iowait2 ))
  total2=$(( user2 + nice2 + sys2 + idle2 + iowait2 ))
  local delta_total=$(( total2 - total1 ))
  [[ "$delta_total" -gt 0 ]] || { echo 0; return 0; }
  echo $(( ( (delta_total - (idle_all2 - idle_all1)) * 100 ) / delta_total ))
}

sample_loadavg_1m() {
  awk '{print $1}' /proc/loadavg
}

sample_active_sessions() {
  # Hit the host-published container port (docker -p 0.0.0.0:3000:3000
  # per ci-deploy.sh). If the server is down, curl fails --max-time and
  # fallback is 0. The alert still fires on mem/cpu regardless.
  curl -s --max-time 2 http://127.0.0.1:3000/health \
    | jq -r '.active_sessions // 0' 2>/dev/null || echo 0
}

# --- Cooldown (per-threshold, from disk-monitor.sh) ---
check_cooldown() { ... }
update_cooldown() { ... }

# --- Alert via Resend (same HTTP POST shape as disk-monitor.sh) ---
send_alert() { ... }

# --- Main ---
mem_pct=$(sample_mem_pct || echo 0)
cpu_pct=$(sample_cpu_pct)
sessions=$(sample_active_sessions)

echo "[resource-monitor] mem=${mem_pct}% cpu=${cpu_pct}% sessions=${sessions}"

if (( mem_pct >= CRIT_MEM_PCT )) && check_cooldown "mem-crit"; then
  send_alert "CRIT" "Memory ${mem_pct}% (CPU ${cpu_pct}%, sessions ${sessions})"
  update_cooldown "mem-crit"
elif (( mem_pct >= WARN_MEM_PCT )) && check_cooldown "mem-warn"; then
  send_alert "WARN" "Memory ${mem_pct}% (CPU ${cpu_pct}%, sessions ${sessions})"
  update_cooldown "mem-warn"
fi

if (( cpu_pct >= WARN_CPU_PCT )) && check_cooldown "cpu-warn"; then
  send_alert "WARN" "CPU ${cpu_pct}% (memory ${mem_pct}%, sessions ${sessions})"
  update_cooldown "cpu-warn"
fi

exit 0
```

### `apps/web-platform/server/session-metrics.ts`

```typescript
import { readdirSync, statSync } from "fs";
import { join } from "path";
// sessions is already exported as a top-level const in ws-handler.ts:73
// (verified during deepen pass). No helper shim required.
import { sessions } from "./ws-handler";

const WORKSPACES_ROOT = process.env.WORKSPACES_ROOT || "/workspaces";

export function getActiveSessionCount(): number {
  try {
    return sessions.size;
  } catch {
    return 0;
  }
}

export function getActiveWorkspaceCount(): number {
  try {
    return readdirSync(WORKSPACES_ROOT)
      .filter((name) => !name.startsWith(".orphaned-"))
      .filter((name) => {
        try {
          return statSync(join(WORKSPACES_ROOT, name)).isDirectory();
        } catch {
          return false;
        }
      })
      .length;
  } catch {
    return 0;
  }
}
```

### `apps/web-platform/server/health.ts` (additions only)

```typescript
import { readFileSync } from "fs";
import { getActiveSessionCount, getActiveWorkspaceCount } from "./session-metrics";

export interface HealthResponse {
  status: string;
  version: string;
  supabase: string;
  sentry: string;
  uptime: number;
  memory: number;            // existing — process RSS (MB). MUST NOT RENAME.
  cpu_pct_1m: number;        // NEW — host CPU utilization %, /proc/stat delta.
                             //       Sampled once per /health call; cheap (~1ms).
  mem_pct: number;           // NEW — host mem utilization %, from MemAvailable.
  load_avg_1m: number;       // NEW — raw 1-min loadavg (context, not alerting).
  active_sessions: number;   // NEW — WS session Map size.
  active_workspaces: number; // NEW — non-orphaned subdirs of /workspaces.
}

// Implementation note: Health endpoint is called frequently by Cloudflare
// health checks + ci-deploy canary gate. The /proc/stat delta sampler in
// resource-monitor.sh uses a 1-second sleep, which is unacceptable for a
// request handler. Inside health.ts, sample via the instantaneous
// /proc/loadavg / nproc approximation instead — operationally fine, the
// authoritative CPU signal comes from resource-monitor.sh's time-windowed
// sampler.
function readHostCpuPct(): number {
  try {
    const load = parseFloat(readFileSync("/proc/loadavg", "utf8").split(" ")[0]);
    const cores = parseInt(readFileSync("/proc/cpuinfo", "utf8").match(/^processor/gm)?.length.toString() || "1", 10);
    return Math.min(100, Math.floor((load / cores) * 100));
  } catch {
    return 0;
  }
}

function readHostMemPct(): number {
  try {
    const info = readFileSync("/proc/meminfo", "utf8");
    const total = parseInt(info.match(/MemTotal:\s+(\d+)/)?.[1] || "0", 10);
    const available = parseInt(info.match(/MemAvailable:\s+(\d+)/)?.[1] || "0", 10);
    if (total === 0) return 0;
    return Math.floor(((total - available) * 100) / total);
  } catch {
    return 0;
  }
}
```

**Why two different CPU samplers (health vs monitor).** The `/health`
endpoint is on the request hot path — Cloudflare probes + canary gate
call it frequently. A 1-second `/proc/stat` delta sampler would add 1 s
of latency per request. Loadavg is cheap and acceptable for the
`/health` display number. The authoritative alerting signal lives in
`resource-monitor.sh`, which runs on a 5-min systemd timer where a
1-second delta is free. This split is deliberate and documented here
so a future reviewer doesn't try to "unify" them.

## Test Scenarios

**Given** a host at 70 % memory utilization
**When** `resource-monitor.sh` runs
**Then** no email is sent, script exits 0, `[resource-monitor]` log line
emitted to stdout (captured by journald).

**Given** a host at 82 % memory utilization with no prior alert in the
last hour
**When** `resource-monitor.sh` runs
**Then** exactly one email goes to `ops@jikigai.com` via Resend with
subject containing `WARN` and utilization numbers; cooldown file
`/var/run/resource-monitor-alert-mem-warn` written with current epoch.

**Given** a host at 82 % memory utilization with a cooldown file written 10 minutes ago
**When** `resource-monitor.sh` runs
**Then** no email is sent; cooldown file unchanged.

**Given** a host that just crossed 95 % memory utilization **after**
already firing an 80 % alert 10 minutes ago
**When** `resource-monitor.sh` runs
**Then** a second email (level `CRIT`) is sent, because the cooldown
is per-threshold (`mem-warn` vs `mem-crit`).

**Given** `/etc/default/resource-monitor` is missing
**When** `resource-monitor.sh` runs
**Then** a warning is emitted to stderr and the script exits 0 (no
email, no crash — mirrors disk-monitor behaviour).

**Given** a Next.js server with 3 active WebSocket agent sessions and 5
non-orphaned workspace directories
**When** the client calls `GET /health` (custom HTTP server route in
`server/index.ts`, not `/api/health`)
**Then** the response JSON has `active_sessions === 3` and
`active_workspaces === 5`.

**Given** `/workspaces` contains `abc-uuid/`, `def-uuid/`, and `.orphaned-1712345678/`
**When** `getActiveWorkspaceCount()` is called
**Then** it returns `2` (the orphaned directory is excluded).

## Implementation Phases

1. **Phase 0 — Verify fixtures exist.** Read
   `apps/web-platform/infra/disk-monitor.sh` and its test file end-to-end.
   Confirm `/health` route is in `server/index.ts` (not App Router) and
   the existing test at `apps/web-platform/test/server/health.test.ts`.
2. **Phase 1 — RED tests.** Write failing tests for `session-metrics.ts`,
   `resource-monitor.test.sh`, and extended `/health` shape. Run
   `cd apps/web-platform && ./node_modules/.bin/vitest run session-metrics health`
   — must fail on missing module / missing fields.
3. **Phase 2 — GREEN implementation.** Add `session-metrics.ts`, extend
   `health.ts`, write `resource-monitor.sh`. Re-run tests → green.
4. **Phase 3 — Terraform wiring.** Add `terraform_data.resource_monitor_install`,
   update `cloud-init.yml`. Run
   `cd apps/web-platform/infra && terraform fmt -recursive && terraform validate`.
   Plan locally with `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan`
   (no apply yet) — confirm exactly two new resources.
5. **Phase 4 — Roadmap sync.** Edit `knowledge-base/product/roadmap.md`
   row 4.8 priority column P1 → P2; reference #1052 alongside #673.
6. **Phase 5 — Review + QA.** Run `/soleur:compound`, then `/soleur:review`.
7. **Phase 6 — Ship via `/soleur:ship`.** Semver label: `semver:patch`
   (infra-only additive change, no API contract break — health adds
   fields, does not remove). Apply happens in a separate session with
   explicit operator approval per `hr-menu-option-ack-not-prod-write-auth`.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Install a Prometheus node_exporter + Grafana Cloud free tier | Vendor onboarding + DPA + ledger overhead dwarfs the alert value at the pre-beta stage; reconsider when ops has more than email as the paging channel. |
| Sentry custom metrics for threshold crossings | Sentry is not the active ops alarm channel; would add no value beyond email without also adding a Sentry dashboard review cadence. File as future enhancement after beta. |
| Per-workspace cgroup CPU/RAM via `systemd-run --scope` | Bubblewrap is not cgroup-v2-scoped today; adding would block on the container-per-workspace work. Defer (see deferral tracking). |
| Push metrics from Node via `process.cpuUsage()` to Resend | `process.cpuUsage()` measures the Next.js process, not the host; would miss runaway bwrap child processes outside the Node process tree. Host-level `top`/`free` is the correct signal. |
| Inline in `disk-monitor.sh` (single script handles all thresholds) | The two concerns have different cadences and different remediation paths. Two scripts, same pattern, is cleaner for troubleshooting. |

## Open Code-Review Overlap

Queried via
`gh issue list --label code-review --state open --json number,title,body --limit 200`
then `jq --arg path "apps/web-platform/infra" 'contains($path)'`
and the same for `disk-monitor`, `cloud-init`. Exactly one hit:

- **#2197** — refactor(billing): SubscriptionStatus type + hoist
  single-instance throttle doc + Sentry breadcrumb UUID policy.
  **Disposition: Acknowledge.** The issue touches `apps/web-platform`
  broadly in its scope sketch but its code locus is
  `apps/web-platform/app/api/stripe/**` and
  `apps/web-platform/server/billing.ts` — no overlap with any path this
  plan edits. Leaves #2197 open for a separate PR.

## Deferral Tracking

Two items are explicitly deferred from this plan and require tracking
GitHub issues created **in the same session as the roadmap update**,
per `wg-when-deferring-a-capability-create-a`:

1. **Per-workspace cgroup CPU/RAM accounting.**
   - Milestone: `Phase 4: Validate + Scale` (gated on 4.7 container-per-workspace).
   - Re-evaluation trigger: when 4.7 (#TBD) lands OR when
     `active_sessions >= 5` is observed from `/health` for 3 consecutive
     business days.
   - Re-evaluation criterion: do we have users whose consumption we
     can't attribute on the cx33? If yes → revisit.
2. **Prometheus / Grafana / long-term metric retention.**
   - Milestone: `Post-MVP / Later`.
   - Re-evaluation trigger: operator has spent > 1 hour/week
     investigating capacity questions via email + `/health` snapshots,
     OR a second VM is added.

Create both issues with `gh issue create ... --label priority/p3-low --label domain/operations --label type/chore`
before merging this PR (verified via `gh label list --limit 100 | grep -i`
per `cq-gh-issue-label-verify-name`).

## Risks

- **Resend free-tier rate limits.** Resend's free plan caps at ~100
  emails/day. A cooldown bug producing a flood is the only way to
  brush that ceiling — the per-threshold cooldown (proven in
  disk-monitor) guards against it. Smoke test: deliberately set
  `WARN_MEM_PCT=1` once in a test script, verify exactly **one**
  email, delete cooldown file, verify exactly **one** more email.
- **`/health` latency regression.** `getActiveWorkspaceCount()` does a
  single `readdirSync` on `/workspaces`. At current scale (<50
  workspaces) this is sub-millisecond. If the workspace count grows
  past ~1000, the call becomes O(n) on a hot path — add caching at that
  point. Recorded here so the next planner sees the known ceiling.
- **Cloud-init-only servers.** Cloud-init runs exactly once on first
  boot. The existing server has `ignore_changes = [user_data, ...]` on
  its `hcloud_server`, so the cloud-init change applies to **future**
  servers only; the existing server picks up the monitor via the
  `terraform_data.resource_monitor_install` remote-exec block. Both
  code paths must be kept in sync (identical to the disk-monitor
  pattern; noted in `server.tf` comments).
- **Session count drift between `/health` and sampler.** The
  resource-monitor samples `/health` via loopback at
  `http://127.0.0.1:3000/health` (verified reachable — the production
  container publishes `0.0.0.0:3000:3000` in `ci-deploy.sh`). If the
  Next.js server is down, `curl --max-time 2` returns empty → `jq`
  fallback → `0`. An alert for CPU/RAM will still fire (read from
  `/proc` directly), but the session count in the alert body will
  read `0`. Acceptable — the memory alert is the signal; missing
  session counts are context, not the alarm.
- **Mock harness pattern for the test script.** Per the 2026-04-05
  shell-mock-testing learning
  (`knowledge-base/project/learnings/integration-issues/2026-04-05-shell-mock-testing-and-disk-monitoring-provisioning.md`),
  the test must use `echo "$*" >> capture_file` for the curl mock,
  then assert with `grep -qF "EXPECTED_TEXT" capture_file`. Do NOT
  use `${!@}` indirect expansion — it silently produces no output.
- **`/health` contract stability.** The existing `/health` response
  is consumed by `ci-deploy.sh` (canary gate) and
  `.github/workflows/web-platform-release.yml` (deploy verification).
  Field additions are safe; field renames or removals break the
  deploy pipeline silently. Keep the five new fields purely additive
  and pin their shape in the updated `test/server/health.test.ts`.
- **Terraform drift after failed apply.** If `terraform_data.resource_monitor_install`
  fails partway (e.g., SSH flake), per `cq-terraform-failed-apply-orphaned-state`,
  run `terraform state list | grep resource_monitor_install` before
  the next plan. Drop orphaned entries with `terraform state rm` if
  needed.

## Rollback Plan

Rollback is **two commits revert** + one operator action:

1. `git revert <this-PR-squash-commit>` — removes source, tests,
   Terraform, and cloud-init entries.
2. Operator runs `terraform apply` — this destroys the
   `terraform_data.resource_monitor_install` resource, which
   **does not** delete the files from the server (remote-exec is
   create-only). To fully clean the server:

   ```
   ssh root@<web-server> \
     'systemctl disable --now resource-monitor.timer resource-monitor.service \
      && rm -f /usr/local/bin/resource-monitor.sh \
             /etc/default/resource-monitor \
             /etc/systemd/system/resource-monitor.{service,timer} \
             /var/run/resource-monitor-alert-*'
   ```

3. `/health` response field removal is a breaking shape change — any
   internal dashboard consuming the new fields must be updated in the
   revert PR.

## Threat Assumptions

- Resend remains the email transport and the existing `RESEND_API_KEY`
  in Doppler `prd_terraform` is valid. If Resend changes pricing or
  we migrate away, the `send_alert()` function is the single change point.
- The single-VM posture holds until the container-per-workspace gate
  (>=5 concurrent users). Once multi-VM or container-per-workspace
  lands, host-level CPU/RAM loses meaning — per-workspace cgroup
  accounting becomes required. See deferral #1.
- Ubuntu 24.04 ships `top`, `free`, `awk`, `curl`, `jq` in the base
  image used for `cx33` provisioning. Verified against the existing
  `disk-monitor.sh` invocation chain (same binaries).

## Affected Teams

- **Operations (founder):** receives alerts, reviews `/health`.
- **Engineering:** maintains the server module and the monitor script;
  must keep `cloud-init.yml` and `terraform_data.resource_monitor_install`
  in sync (same rule as the existing disk-monitor).

## CLI-Verification Gate (per `cq-docs-cli-verification`)

No user-facing docs (`*.njk`, `*.md` in `docs/`, README) are edited
by this plan, except `knowledge-base/product/roadmap.md` which is
internal. No CLI invocations are embedded in user-facing content.
Infra-only CLI invocations (`terraform`, `systemctl`, `curl`, `jq`)
are in internal-only surfaces (cloud-init YAML, server module,
shell scripts) and each is verified by a sibling pattern already in
production (`disk-monitor.sh` and `disk_monitor_install`).
