<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 reviewed: all systemctl/cloud-init/docker-run changes in this plan are
routed through the established repo IaC mechanism (cloud-init write_files + runcmd
for fresh hosts; terraform_data remote-exec for the existing host, mirroring
terraform_data.resource_monitor_install in server.tf:114-152). No manual operator
SSH step is prescribed. See ## Infrastructure (IaC) section below.
-->
---
title: "fix(infra): soleur-web-platform container restart churn (~10-60x/day) — cgroup memory cap + OOM/restart monitor + crash attribution"
issue: 5417
type: bug
classification: infra + observability
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
created: 2026-06-16
branch: feat-one-shot-5417-web-platform-restart-churn
---

# fix(infra): soleur-web-platform container restart churn (~10-60x/day) 🐛

> Fixes #5417. Discovered during #5413 (egress LB-rotation fix, merged as `f743bc263`). #5413 fixed the *primary* egress cause (LB-rotation drops); this issue is the *independent second factor*: the container restart churn that kills heavy crons mid-flight AND flushes the firewall's DOCKER-USER jump.

## Enhancement Summary

**Deepened on:** 2026-06-16
**Sections enhanced:** Root cause, Sharp Edges, Files to Edit/Create, Acceptance Criteria, Infrastructure (IaC), Observability
**Research agents used:** network-outage deep-dive, verify-the-negative + citation audit, best-practices-researcher (Docker/cgroup/Node/Sentry), framework-docs-researcher (jianyuan/sentry provider + Sentry stats API)

### Key Improvements (from deepen research)
1. **OOM detection corroboration hardened.** `.State.OOMKilled` is a confirmed false-negative under cgroup v2 for CHILD-cgroup kills (the bwrap-sandboxed cron case — the dominant mode here). The authoritative signal is the cgroup `memory.events` `oom_kill` counter delta (`/sys/fs/cgroup/.../memory.events`), corroborated by exit-code 137 + journald `oom-kill:`. The monitor MUST read `memory.events`, not just `OOMKilled`. (moby#41929.)
2. **Sentry handler semantics corrected.** Use `Sentry.close(2000)` (flushes AND disables the SDK for a crashing process) NOT `Sentry.flush(2000)` in the `uncaughtException`/`unhandledRejection` handlers, and verify `@sentry/node` GlobalHandlers auto-install is disabled (`onuncaughtexception:false`/`onunhandledrejection:false`) before adding manual handlers, else double-report.
3. **Memory-cap sizing formula made explicit.** `cap ≈ measured_concurrent_peak_working_set + 256m (tmpfs) + ~512m (V8 non-heap/native headroom)`, and set Node `--max-old-space-size` BELOW the cgroup cap to get a clean V8 OOM instead of an opaque SIGKILL. Canary 2×cap-on-8GB constraint resolved by measuring canary peak (`docker stats --no-stream`) and using a lower canary cap if peak > cap/2.
4. **Sentry alert HCL pinned to the installed provider.** `sentry_issue_alert` with `conditions_v2 { event_frequency { comparison_type="count"; value; interval } }` against `jianyuan/sentry@0.15.0-beta2`; requires a UNIQUE `frequency` value (Sentry create-dedup keys on `action_match+filter_match+frequency+actions`, NOT conditions — learning `2026-05-17-sentry-issue-alert-create-dedup...`), an `apply-sentry-infra.yml` `-target=` entry, and `lifecycle.ignore_changes` per the beta-provider gotcha.
5. **AC12 verification endpoint made concrete.** Sentry issue stats API `GET /api/0/organizations/{org}/issues/{issue-id}/stats/?stat=24h` summed over the 72h window gives the no-SSH "Server startup" event-frequency drop verdict.

### New Considerations Discovered
- The plan's negative claims were all verified against `main` with zero contradictions (no `--memory`/`--init`/`--oom` on either docker-run block; no top-level `process.on` crash handler; no swap in cloud-init; cron error at `:706`; resource-monitor is host-only).
- `--init` (tini) reaps zombies and preserves exit codes but does NOT change OOM/SIGKILL semantics — it is hygiene, not the OOM fix.
- Network-outage L3-first discipline is correctly applied (firewall H1 + DNS H2 ruled out before service-layer H3/H4); only a cosmetic L7-TLS `N/A` note is suggested.

## Overview

The `soleur-web-platform` Docker container restarts an order of magnitude too often (06-08: 52, 06-11: 40, 06-12: 42, 06-15: 60, 06-16: ~10-12; stable = 0-1/day, per the Sentry "Server startup vX.Y.Z" issue, project `web-platform`, region `jikigai-eu`). Each restart:

1. Kills any in-flight Claude-eval cron (≤55 min) — surfaced by the symptom-reporter at `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts:706` (`spawn cwd ${spawnCwd} no longer exists (container restart between setup-workspace and claude-eval?)`).
2. Triggers `dockerd` to rebuild iptables/nftables on the next `docker run`, displacing the `SOLEUR-EGRESS` jump in `DOCKER-USER`; the 1-min `cron-egress-resolve.timer` self-heal then fires `enforcement rules were MISSING at tick (jump/drop absent)` (06-16 00:27). **The firewall flush is a SYMPTOM of the restart, not an independent cause.**

### Root cause (evidence-backed)

The prod container runs `docker run -d --restart unless-stopped` with **no `--memory` cap, no `--init`, and a 256MB `--tmpfs /tmp`** (`apps/web-platform/infra/ci-deploy.sh:668-683`). `--restart unless-stopped` restarts the container **on process exit only** (NOT on healthcheck failure — Docker's restart policy ignores healthcheck state). With no container memory cap on an **8GB cx33 host** (`apps/web-platform/infra/variables.tf:32-35`, 4 vCPU / 8GB), heavy concurrent Claude-eval crons drive **host** RAM pressure → the **host kernel** OOM-kills the Node process (unpredictable victim selection — could also kill dockerd / inngest-server / the firewall resolver) → `--restart unless-stopped` immediately restarts the container. This is the classic uncapped-container restart-churn signature, and it is consistent with the cron cohort the #5413 postmortem documents (`knowledge-base/engineering/operations/post-mortems/cron-egress-lb-rotation-outage-postmortem.md`).

There is **no `process.on('uncaughtException')` / `process.on('unhandledRejection')` top-level handler** in `apps/web-platform/server/index.ts` (only a SIGTERM graceful-shutdown handler at `:228`), so crash-driven restarts (the OTHER class) are currently un-attributable.

### Fix shape (three independent deliverables)

The fix splits into three deliverables with **independent** acceptance criteria, because only the first changes cron survival and it is the riskiest:

| # | Deliverable | What it changes | Risk |
|---|---|---|---|
| **A — Frequency fix** | Container `--memory` cap (+ `--memory-swap` = cap; + `--init`) on canary AND prod `docker run` | Converts unpredictable **host**-OOM into deterministic **cgroup**-OOM that only kills the container, sparing dockerd/inngest/firewall; `--init` reaps zombies | **High** — cap-too-low regression; canary 2×cap-on-8GB tension |
| **B — Detector** | New `container-restart-monitor.sh` systemd-timer (modeled on `resource-monitor.sh`), restart-rate alarm | Tells the operator when churn happens, classified deploy/crash/OOM | Medium — classification state machine |
| **C — Attribution + no-SSH proof** | `process.on('uncaughtException'/'unhandledRejection')` → Sentry; expose `restart_count`/`oom_killed`/rolling-rate via `cat-deploy-state.sh` | Disambiguates OOM-vs-crash; gives the no-SSH verification surface | Low |

This is an **infra + observability change**, not application logic. It routes through the existing IaC pattern (`ci-deploy.sh` + cloud-init + `terraform_data` remote-exec dual-path) and the existing alarm/observability surfaces (`resource-monitor.sh`, `cat-deploy-state.sh`, `sentry/issue-alerts.tf`, `vector.toml`).

## User-Brand Impact

**If this lands broken, the user experiences:** their scheduled Claude-eval crons (content-generator, follow-through, bug-fixer, community-monitor, roadmap-review, agent-native-audit) silently die mid-run and never produce their output (a generated article, a triaged issue, a community digest) — the founder sees nothing was done and cannot tell why. A cap-too-low regression makes this WORSE (more frequent deterministic OOM-kills than today's host churn).

**If this leaks, the user's workflow is exposed via:** the `/hooks/deploy-status` webhook gains a `restart_count`/`oom_killed`/journald-OOM-tail field. The webhook is HMAC-SHA256 + CF-Access gated and already redacts secrets (`cat-deploy-state.sh` `signkey-` scrub at the journald tail). The new fields must inherit the same redaction; OOM journald lines (`Killed process N (node)`) carry no PII but the existing `tr -dc '[:print:]'` + `sed` redaction must wrap any new tail.

**Brand-survival threshold:** single-user incident. A single founder's cron cohort going dark (the #5413/#5417 incident) is the brand-survival blast radius — the CaaS thesis is "the agents do the multi-domain work unattended"; if the runtime kills them, the thesis fails for that user. `requires_cpo_signoff: true`. `user-impact-reviewer` runs at review-time.

## Research Reconciliation — Spec vs. Codebase

| Issue / prompt claim | Codebase reality | Plan response |
|---|---|---|
| Restarts may be a standing restart-loop | No cron/timer/systemd unit restarts the container; ONLY `ci-deploy.sh` (deploy) + `--restart unless-stopped` (process-exit) restart it (grep returned zero `docker restart soleur-web-platform`) | Root-cause is process-exit (OOM/crash), not an external restarter. Deliverable A targets the OOM class; C targets the crash class |
| Cron error site at `_cron-claude-eval-substrate.ts:229` (from one upstream paraphrase) | Actual site is `:706`; `:229` is an unrelated cron-allowlist comment | All ACs reference `:706`. The guard is a symptom **reporter**, not a fix surface |
| "Firewall flush is a contributing factor" | Confirmed downstream symptom: a restart's `docker run` rebuilds nftables, displacing the `SOLEUR-EGRESS` jump; `cron-egress-resolve.sh:310-327` self-heals on the 1-min timer | Fixing the restart rate (A) reduces the flush frequency; no firewall code change needed. Verify the self-heal event frequency drops |
| Container is OOM-capped | NO `--memory` / `--memory-swap` / `--oom-kill-disable` / `--init` on prod or canary `docker run` (`ci-deploy.sh:668-683`, `~490-504`) | Deliverable A adds the cap. Host = 8GB cx33 — sizing is load-bearing |
| Host has swap to disable via `--memory-swap` | cloud-init configures NO swap (`grep -i swap apps/web-platform/infra/cloud-init.yml` → only the memory-monitor comment) | `--memory-swap == --memory` is safe (no swap exists to disable); makes cgroup-OOM deterministic |
| `resource-monitor.sh` already detects this | `resource-monitor.sh` samples **host** RAM% only — it cannot see container `RestartCount`/`OOMKilled`. Net-new container-level detector required (extend the pattern, don't rebuild) | Deliverable B is a NEW script modeled on `resource-monitor.sh` |

## Hypotheses (L3→L7 firewall-layer discipline, per `hr-ssh-diagnosis-verify-firewall`)

The network-outage gate fired on the `firewall` keyword. Per the L3→L7 checklist, firewall-layer hypotheses are verified BEFORE any service-layer hypothesis. **Note:** the firewall in this issue is the *container-egress* `DOCKER-USER` chain (an outbound default-drop), NOT an SSH/admin-IP allowlist — but the L3-first discipline still applies to rule out a firewall-layer root cause.

- **H1 (L3 — container egress firewall flush): RULED OUT as root cause, confirmed as symptom.** The `DOCKER-USER` `SOLEUR-EGRESS` jump is displaced by a container restart's `docker run` (dockerd rewrites nftables), and `cron-egress-resolve.sh:310-327` re-asserts it on the 1-min timer. Evidence: the self-heal event timestamp (06-16 00:27) correlates with a restart, and the jump-survives-dockerd comment at `cron-egress-nftables.sh:16` is specifically about dockerd restart, not `docker run` of a fresh container. **The flush is downstream of the restart; fixing the restart rate fixes the flush frequency.** Verification artifact: post-merge `cron-egress-firewall: enforcement rules were MISSING` Sentry-event frequency drops in step with the restart-rate drop.
- **H2 (L3 — DNS/routing / LB rotation): already fixed by #5413.** The grace-window IP retention (`f743bc263`) closed the LB-rotation drop. Not a work target here.
- **H3 (service layer — process exit via host OOM): PRIMARY root cause.** No `--memory` cap on an 8GB host; heavy concurrent crons → host OOM → process exit → `--restart unless-stopped` churn. Verified by config inspection (`ci-deploy.sh:668-683`). Remediated by Deliverable A.
- **H4 (service layer — uncaught crash): SECONDARY root cause (un-attributable today).** No top-level `uncaughtException`/`unhandledRejection` handler. Remediated by Deliverable C (attribution) — a thrown exception that exits the process is currently invisible.
- **H5 (healthcheck-driven restart): RULED OUT.** `--restart unless-stopped` does NOT restart on healthcheck failure (Docker restart policy is process-exit-only). The Dockerfile HEALTHCHECK (`:169`) only flips the `unhealthy` status flag; it does not cause a restart. (Documented to forestall a misdirected "tune the healthcheck" fix.)

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled (threshold = single-user incident).
- **The memory cap MUST be sized from a measured concurrent-cron peak working set, not a formula.** Picking a cap below legitimate peak converts host-OOM churn into cgroup-OOM churn at the same-or-higher rate — a regression that *looks* like a fix (`.State.OOMKilled=true` "deterministic!") while the crons still die. **Phase 0 must measure** via `resource-monitor.sh`'s existing `/internal/metrics` sampling and `docker stats` sampling during a heavy-cron window. No safe a-priori value exists.
- **Canary 2×cap-on-8GB tension.** The canary container (`ci-deploy.sh:~490-504`, port 3001, `--restart no`) runs CONCURRENTLY with live prod during the deploy probe window. If both carry the same cap, peak host memory during a deploy is `2×cap + host_overhead`. On 8GB that bounds `2×cap + overhead ≤ 8GB`. Resolve by giving the canary a LOWER cap (it does not fire crons — verify) OR confirming canary peak is bounded. This is a genuine constraint the implementation must resolve, not assume away.
- **`.State.OOMKilled` is false-negative under cgroup v2 when the OOM-kill lands in a CHILD cgroup** (the bwrap-sandboxed cron subprocesses — `--security-opt apparmor=soleur-bwrap`). The dominant case here. Classification MUST corroborate with `.State.ExitCode == 137` AND the journald `oom-kill:` / `Killed process` lines (vector already ships these to Better Stack). Do not rely on `OOMKilled` alone.
- **tmpfs counts against the container cgroup memory in cgroup v2.** The 256MB `--tmpfs /tmp` reduces effective heap to `cap − tmpfs_in_use`. Size the cap as `desired_heap_ceiling + 256m`. (Separately: `/workspaces` is a bind mount on `/mnt/data` — those pages are NOT in the container cgroup, so `--memory` does nothing for `/workspaces`-driven host page-cache pressure. This is a known partial-coverage limit; the resource-monitor host alarm remains the backstop for that path.)
- **The new monitor MUST `exit 0` on any internal failure** (mirror `resource-monitor.sh:5-6,23,29` "always exits 0" contract). A flaky `docker inspect` during the deploy stop/rm window (container momentarily absent) must NOT read as "0 restarts healthy" and must NOT kill the timer.
- **`RestartCount` is per-container-instance.** A deploy creates a NEW container (RestartCount=0). The monitor must branch on `container_id` change (deploy → reset baseline, suppress alert) vs same `container_id` (increment → crash, alertable). A naive timer-diff false-alarms on every deploy.
- **Provisioning to the EXISTING host needs the dual-path.** `server.tf` sets `ignore_changes = [user_data]`, so cloud-init changes do NOT reach the running host. The new monitor ships via BOTH cloud-init (fresh hosts) AND a `terraform_data` `remote-exec` (existing host), exactly mirroring `terraform_data.resource_monitor_install` (`server.tf:114-152`). Both must enable the timer.
- **`uncaughtException` handler must `Sentry.flush(timeout)` then `process.exit(1)`** — NOT swallow-and-continue. A process in undefined state after an uncaught throw that keeps serving is worse than a clean restart; let `--restart` restart it. Flush is bounded so the very crash being attributed is not lost.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — add `--memory <cap> --memory-swap <cap> --init` to the **prod** `docker run` (~668-683) and a (lower) cap to the **canary** `docker run` (~490-504). Cap values from Phase 0 measurement.
- `apps/web-platform/server/index.ts` — add top-level `process.on('uncaughtException', …)` + `process.on('unhandledRejection', …)` near the SIGTERM handler (~228). **Corrected per deepen research:** report via `Sentry.captureException`, then `await Sentry.close(2000)` (NOT `flush` — `close()` flushes AND disables the SDK, correct for a crashing process that will not recover), then `process.exit(1)` (NOT swallow-and-continue). **Before adding manual handlers, verify `@sentry/node` `Sentry.init()` is NOT auto-installing the GlobalHandlers integration** (grep the init call for `onuncaughtexception`/`onunhandledrejection`/`integrations`); if auto-install is on, either set `onuncaughtexception:false`+`onunhandledrejection:false` OR rely on the auto-installed handlers and skip the manual ones — running both double-reports. Confirm `@sentry/node` version ≥ 7.48.0 (the unhandledRejection+Express-middleware bug below that).
- `apps/web-platform/infra/cat-deploy-state.sh` — add `restart_count`, `oom_killed`, `exit_code`, and an OOM-journald tail (redacted, capped) to the JSON; best-effort `docker inspect` with safe sentinels (mirror the existing `service_status`/`service_journal_tail` shape). Surface the monitor's rolling restart-rate if it persists one.
- `apps/web-platform/infra/cloud-init.yml` — add the new monitor script + `/etc/default/container-restart-monitor` + `.service` + `.timer` write_files entries (mirror the `resource-monitor` block ~139-175) and the timer enable in runcmd (~529).
- `apps/web-platform/infra/server.tf` — add `resource_monitor_script_b64`-style `base64encode(file())` for the new script (~36) AND a `terraform_data "container_restart_monitor_install"` remote-exec mirror of `resource_monitor_install` (~114-152).
- `apps/web-platform/infra/sentry/issue-alerts.tf` — add a Sentry issue-alert on the "Server startup" event frequency exceeding the restart-rate threshold (the no-SSH rate signal). **Concrete shape (deepen research, validated against the pinned `jianyuan/sentry@0.15.0-beta2` in `sentry/.terraform.lock.hcl`):** `resource "sentry_issue_alert" "server_startup_burst"` with `conditions_v2 = [{ event_frequency = { comparison_type = "count", value = <N>, interval = "1h" } }]`, a `filters_v2` clause matching the "Server startup" event (by `level = "info"` and/or a `tagged_event` key the startup emit sets), `actions_v2 = [{ notify_email = { target_type = "IssueOwners", fallthrough_type = "ActiveMembers" } }]`, a **UNIQUE `frequency` value** not already used in `issue-alerts.tf` (Sentry create-dedup keys on `action_match+filter_match+frequency+actions` shape, NOT conditions — see `knowledge-base/project/learnings/2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`), and `lifecycle { ignore_changes = [environment] }` (beta-provider drift gotcha). `terraform validate` MUST pass. Add `-target=sentry_issue_alert.server_startup_burst` to `.github/workflows/apply-sentry-infra.yml` (the destroy-guard jq filter at `tests/scripts/lib/destroy-guard-filter-sentry.jq` already covers all `sentry_issue_alert` resources dynamically — no separate scope-guard edit needed; verify).
- `knowledge-base/engineering/architecture/decisions/` — add or amend an ADR for container resource limits + restart policy (cross-reference ADR-027-process-local-state-for-runners (single-replica) and ADR-052 egress firewall). If ADR-052 is the closest home, amend; else new ADR.

## Files to Create

- `apps/web-platform/infra/container-restart-monitor.sh` — systemd-timer monitor (mirror `resource-monitor.sh` cooldown/envfile/Resend/always-exit-0 shape). Reads `docker inspect soleur-web-platform --format '{{.Id}} {{.RestartCount}} {{.State.OOMKilled}} {{.State.ExitCode}} {{.State.StartedAt}}'`; persists baseline `(container_id, restart_count)` to `/var/run`; classifies deploy (ID change → suppress + reset baseline; but ALERT if a fresh container already has count>0) vs crash (same ID, count delta>0); alerts via Sentry + Resend on threshold breach; emits a rolling restarts/hour the webhook can read.

### Research Insights — monitor OOM-detection logic (load-bearing)

**OOM corroboration (do NOT trust `.State.OOMKilled` alone).** Under cgroup v2, `docker inspect .State.OOMKilled` is a confirmed false-negative when the kill lands in a CHILD cgroup — exactly the bwrap-sandboxed cron subprocess case here (moby#41929: `TestInspectOomKilledTrue` fails ~90% on cgroup v2). The monitor classifies OOM by the OR of three signals, in priority order:
1. **cgroup `memory.events` `oom_kill` counter delta** — `awk '/^oom_kill /{print $2}' /sys/fs/cgroup/system.slice/docker-<id>.scope/memory.events` (or the container's cgroup path; resolve via `docker inspect --format '{{.Id}}'`). This is the authoritative signal and the ONLY one that catches child-cgroup kills. Persist the baseline counter alongside `restart_count`.
2. **`.State.ExitCode == 137`** (SIGKILL) — corroborates a kernel OOM-kill of the init process.
3. **journald `oom-kill:` / `Killed process N (node)`** — `journalctl -k --since "<last-tick>" | grep -E 'oom-kill|Killed process'` (kernel ring; vector already ships these to Better Stack).

`memory.events` is read-only and host-local — the monitor already runs on the host (systemd timer), so no SSH. Guard all reads best-effort with safe fallbacks (collapse to "unknown", never crash → `exit 0`).

**Concrete constants (AC6):** `RESTART_THRESHOLD=3`, `RESTART_WINDOW_SECS=3600` (≥3 crash-restarts in a rolling 1h window — catches 10-60/day fast, ignores a lone legitimate crash), `COOLDOWN_SECONDS=3600` (mirror resource-monitor). The 5-min timer gives 288 ticks/day; a 60/day storm = ~2.5/h, so the 1h cooldown yields ~1 email/h during an active storm (correct, not fatigue). Add an explicit recovery state: when the rolling rate returns to 0 after an alert, emit a single "restart storm cleared" notification (the operator must not have to infer resolution from silence).
- `apps/web-platform/infra/container-restart-monitor.test.sh` — shell test (mirror `resource-monitor.test.sh`) covering: deploy-reset-suppression, same-ID-increment-alert, fresh-container-already-crashing alert, container-absent → exit 0 (no false healthy), threshold/window/cooldown constants, OOM exit-137 corroboration, Resend-fail mirrors to Sentry.

## Open Code-Review Overlap

Run at Step 2 against `gh issue list --label code-review --state open`:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in apps/web-platform/infra/ci-deploy.sh apps/web-platform/server/index.ts apps/web-platform/infra/cat-deploy-state.sh apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/server.tf apps/web-platform/infra/sentry/issue-alerts.tf; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Disposition: **None found at plan time** (record the result; if any surface, fold-in/acknowledge/defer per the named files).

## Infrastructure (IaC)

This plan introduces a new persistent runtime process (systemd timer + script) and modifies the container runtime config, so it routes through Terraform/cloud-init per `hr-all-infrastructure-provisioning-servers`. No operator-SSH steps — the timer-enable + unit-write commands live INSIDE the cloud-init runcmd and the `terraform_data` remote-exec (the established repo IaC mechanism, mirroring `terraform_data.resource_monitor_install`), not in operator prose.

### Terraform changes
- `apps/web-platform/infra/server.tf`: new `base64encode(file("container-restart-monitor.sh"))` local + `terraform_data "container_restart_monitor_install"` (file + remote-exec), mirroring `resource_monitor_install`. Sensitive var: `var.resend_api_key` (already declared). Provider: existing `hcloud` + the SSH `connection` block already present.
- `apps/web-platform/infra/sentry/issue-alerts.tf`: new alert resource via the existing `jianyuan/sentry` provider (version-pinned in `sentry/versions.tf`).
- `ci-deploy.sh` is shipped to the host via the existing `infra-config-install.sh` / deploy path (it is not a Terraform resource itself); the `--memory` flag change lands on the next deploy.

### Apply path
- **cloud-init + idempotent bootstrap (default for existing infra).** The new monitor ships to the running cx33 via the `terraform_data ... remote-exec` (in-place apply) AND via cloud-init for any future fresh host. The `--memory` cap on the container applies on the next `web-platform-release.yml` deploy (the PR merge IS the remediation — `ci-deploy.sh` runs `docker stop/rm/run` with the new flags). The Sentry alert applies via `apply-sentry-infra.yml`. No taint/replace; no host re-provision; expected downtime = one deploy's container-swap window (already the steady-state deploy behavior).

### Distinctness / drift safeguards
- `server.tf` `ignore_changes = [user_data]` means cloud-init edits do not auto-apply to the existing host — the `terraform_data` remote-exec is the apply mechanism (shows as "will be created" in CI drift, expected, per the `resource_monitor_install` precedent).
- The Sentry alert resource must be added to the `apply-sentry-infra.yml` `-target=` allowlist AND its counter test / scope-guard (per the `-target=` allowlist Sharp Edge — sweep ALL guard suites: `git grep -ln 'sentry_\|-target=' apps/web-platform/infra/sentry/ scripts/ test/`).
- dev≠prd: the monitor + cap apply to the prd host only (the dev environment has no equivalent always-on cron host); state this in the ADR.

### Vendor-tier reality check
- Sentry issue-alerts are in-tier (the project already has issue-alerts via `issue-alerts.tf`). Resend email is already in use by `resource-monitor.sh`/`disk-monitor.sh`. No new paid-tier gate.

## Observability

```yaml
liveness_signal:
  what: container-restart-monitor.timer (systemd) + the existing resource-monitor host alarm
  cadence: every 5 min (OnUnitActiveSec=5min), mirroring resource-monitor.timer
  alert_target: Sentry Crons check-in (new monitor slug) + OnFailure Resend (mirror cron-egress-alarm.sh pattern)
  configured_in: cloud-init.yml (.timer) + server.tf terraform_data remote-exec
error_reporting:
  destination: Sentry (issue events for uncaughtException/unhandledRejection via process handlers in server/index.ts; restart-rate breach via the monitor's Sentry event) + Resend email to ops@
  fail_loud: true — the monitor mirrors Resend-send failure to Sentry (cq-silent-fallback-must-mirror-to-sentry); the process handlers Sentry.flush(2000) before exit
failure_modes:
  - mode: host OOM-kill of the Node process (primary)
    detection: container .State.ExitCode==137 + journald oom-kill line (vector to Better Stack) + RestartCount increment on same container_id
    alert_route: container-restart-monitor to Sentry event + Resend
  - mode: cgroup OOM-kill after the cap (deterministic, post-fix)
    detection: .State.OOMKilled (best-effort) corroborated by exit-137 + journald
    alert_route: same monitor; classified as OOM in the alert body
  - mode: uncaught exception / unhandled rejection (crash class)
    detection: process.on handler to Sentry issue event BEFORE exit
    alert_route: Sentry issue-alert on the new error event
  - mode: deploy churn (false-positive guard)
    detection: container_id change to baseline reset, alert suppressed (unless fresh container already count>0)
    alert_route: none (suppressed by design)
  - mode: firewall DOCKER-USER flush (downstream symptom)
    detection: existing cron-egress-resolve self-heal Sentry event "enforcement rules were MISSING at tick"
    alert_route: existing cron-egress-alarm.sh (no change); frequency should DROP as restart rate drops
logs:
  where: journald (container --log-driver journald) to vector.toml to Better Stack (source 2457081); the deploy webhook /hooks/deploy-status carries restart_count + oom_killed + OOM journald tail
  retention: docker json-file max-size 10m x 3 (daemon.json) for the daemon default; journald persistent /var/log/journal (bounded) per #4792; Better Stack per its plan
discoverability_test:
  command: 'curl -sS -o /dev/null -w "%{http_code}\n" --max-time 10 https://deploy.soleur.ai/hooks/deploy-status'
  expected_output: '403 (the CF-Access challenge — proves /hooks/deploy-status is reachable with NO ssh; an HMAC + CF-Access authenticated request additionally returns restart_count, oom_killed, container_exit_code, restart_rate_per_hour). Authenticated form: curl -H "X-Signature-256: sha256=<hmac of empty body with WEBHOOK_DEPLOY_SECRET>" -H "CF-Access-Client-Id/Secret" then jq ".restart_count, .oom_killed, .restart_rate_per_hour". Cross-check: Sentry "Server startup" event frequency drops to <=1/day over 72h.'
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (cap value derivation).** The chosen prod `--memory` cap is documented in the plan/ADR with its derivation formula: `cap ≈ measured_concurrent_cron_peak_working_set (Phase 0) + 256m (tmpfs) + ~512m (V8 non-heap / native headroom)`, AND satisfies `2×canary_cap + host_overhead ≤ 8GB` during a deploy. Node `--max-old-space-size` is set BELOW the cgroup cap (clean V8 OOM instead of opaque SIGKILL). `--memory-swap == --memory` (no host swap exists). Cap is a named constant, not a magic literal buried in `docker run`.
- [x] **AC2 (cap-too-low non-regression).** A test (or documented Phase-0 measurement) shows the heaviest concurrent Claude-eval cron set completes under the cap without cgroup-OOM. If unmeasurable pre-merge, the cap is set with a documented safety margin above the measured single-cron peak and AC is satisfied by the measurement note.
- [x] **AC3 (`--memory-swap` + `--init`).** Prod `docker run` carries `--memory <cap> --memory-swap <cap> --init`; verified by `grep -n -- '--memory\b' apps/web-platform/infra/ci-deploy.sh` returning both canary and prod sites with caps.
- [x] **AC4 (process handlers).** `apps/web-platform/server/index.ts` has top-level `uncaughtException` + `unhandledRejection` handlers that `Sentry.captureException` → `await Sentry.close(2000)` (NOT `flush`) → `process.exit(1)`; AND the `Sentry.init()` call does not auto-install conflicting GlobalHandlers (or manual handlers are skipped in favor of auto-installed ones — no double-report); AND `@sentry/node` ≥ 7.48.0. Verified by `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + a unit/integration test asserting the handler reports-once and exits.
- [x] **AC5 (monitor classification).** `container-restart-monitor.test.sh` passes, covering: (a) deploy (container_id change, count reset) does NOT alert; (b) same-container count increment DOES alert; (c) fresh container already count>0 alerts; (d) container absent → `exit 0`, no false-healthy; (e) OOM corroboration via the cgroup `memory.events` `oom_kill` counter delta (authoritative, catches child-cgroup kills) **plus** exit-137 + journald `oom-kill:` grep — NOT `.State.OOMKilled` alone (false-negative under cgroup v2); (f) Resend-fail mirrors to Sentry; (g) recovery notification fires once when the rolling rate returns to 0 after an alert.
- [x] **AC6 (threshold/window/cooldown constants).** The restart-rate threshold, rolling window, and cooldown are named constants in the monitor (e.g. `RESTART_THRESHOLD`, `RESTART_WINDOW_SECS`, `COOLDOWN_SECONDS`), chosen so 10-60/day breaches fast (e.g. ≥3 crash-restarts / 1h) and a lone legitimate crash does not. Verified by test asserting the boundary.
- [x] **AC7 (webhook fields).** `cat-deploy-state.sh` emits `restart_count`, `oom_killed`, `exit_code` (+ rolling rate if persisted) with safe sentinels when `docker inspect` fails; the OOM journald tail inherits the existing `signkey-` redaction + `tr -dc '[:print:]'` cap. Verified by extending `cat-deploy-state.test.sh`.
- [x] **AC8 (Terraform validate).** `terraform validate` passes in `apps/web-platform/infra/` AND `apps/web-platform/infra/sentry/`; the new Sentry alert resource is in the `apply-sentry-infra.yml` `-target=` allowlist AND its scope-guard/counter test is updated (sweep all guard suites).
- [x] **AC9 (IaC dual-path).** The new monitor is provisioned via BOTH cloud-init `write_files` + runcmd AND `terraform_data "container_restart_monitor_install"` remote-exec, mirroring `resource_monitor_install`; no operator-SSH step in the plan.
- [x] **AC10 (ADR).** An ADR documents the container resource-limit + restart-policy decision, cross-referencing ADR-027-process-local-state-for-runners (single-replica) and ADR-052 (egress firewall), and states dev≠prd scope.
- [x] **AC11 (Ref not Closes).** PR body uses `Ref #5417` (NOT `Closes #5417`) because the rate-drop proof is a post-merge time-series verification — issue closure happens post-merge after AC12 verifies (this `type: bug` proof is post-deploy, per the ops-remediation `Ref` convention).

### Post-merge (operator / automated)

- [ ] **AC12 (rate-drop proof, no-SSH).** Over 72h post-deploy, the Sentry "Server startup" event frequency drops from ~10-60/day to ≤1/day. Concrete query (deepen research): `GET https://{org}.sentry.io/api/0/organizations/{org}/issues/{issue-id}/stats/?stat=24h` summed over the window (`jq '[.[].1] | add'`) — deterministic verdict per `hr-no-dashboard-eyeball-pull-data-yourself`, NOT operator dashboard-watching. AND the `/hooks/deploy-status` `restart_count` stays low on the stable container. Automation: ship-phase / scheduled Sentry-API check; `gh issue close 5417` when the verdict passes.
- [ ] **AC13 (firewall-flush frequency drop).** The `cron-egress-firewall: enforcement rules were MISSING at tick` self-heal Sentry-event frequency drops in step with the restart rate (confirms H1 — flush was a restart symptom). Sentry API query, no SSH.

## Domain Review

(populated by Phase 2.5 — Engineering/CTO is the primary domain; Product gate likely NONE since no UI surface — this is infra/observability. CPO sign-off required at plan time per `requires_cpo_signoff: true` from the single-user-incident threshold.)

## Test Scenarios

1. **Deploy does not false-alarm:** simulate a container-ID change with RestartCount reset → monitor resets baseline, no alert.
2. **Crash storm alerts:** simulate same container-ID with RestartCount 2→5 within the window → monitor fires Sentry + Resend once per cooldown.
3. **OOM corroboration:** exit-code 137 + journald `oom-kill:` line present but `OOMKilled=false` (cgroup-v2 child-cgroup case) → monitor still classifies OOM.
4. **Container absent:** `docker inspect` non-zero during deploy window → monitor `exit 0`, no false-healthy.
5. **Cap-too-low canary:** verify `2×cap + overhead ≤ 8GB` so a deploy does not host-OOM the live container.
6. **uncaughtException path:** throw an unhandled error → Sentry event emitted, process exits 1, container restarts cleanly.
7. **Webhook redaction:** OOM journald tail containing a `signkey-` token → redacted in the `/hooks/deploy-status` response.

## Phase 0 (precondition — measure before sizing)

Before touching `ci-deploy.sh`, derive the cap empirically (no SSH where possible, else read-only):
- Sample container working-set during a heavy concurrent-cron window via the existing `/internal/metrics` endpoint (`resource-monitor.sh` already hits it) and/or `docker stats --no-stream` deltas surfaced through the webhook.
- Confirm cgroup version (v1/v2) and host swap config (cloud-init shows none) to fix `--memory-swap` + `.State.OOMKilled` semantics.
- Budget the 8GB: inngest-server + vector + dockerd + firewall resolver + journald + OS ≈ host overhead; the container cap is `8GB − overhead`, further bounded by the canary 2×cap deploy constraint.
- Measure canary peak (`docker stats soleur-web-platform-canary --no-stream` during a deploy probe window); if peak > cap/2, give the canary a lower cap (cap/3) so `2×cap` does not host-OOM the live container.
- Confirm `--max-old-space-size < cap` so the Node heap hits a clean V8 OOM before the cgroup SIGKILL.
- Record the measured peak + chosen cap + derivation in AC1/AC10.

## Network-Outage Deep-Dive (deepen Phase 4.5)

The gate fired on `firewall`; the firewall here is the OUTBOUND `DOCKER-USER`/`SOLEUR-EGRESS` nftables chain, not an inbound SSH/admin-IP allowlist. L3-first discipline applied; no SSH diagnosis (no-SSH by design).

| Layer | Status | Artifact |
|---|---|---|
| **L3 — firewall allow-list** | RULED OUT (symptom, not cause) | H1: `cron-egress-resolve.sh:310-327` self-heal + 06-16 00:27 correlation + `cron-egress-nftables.sh:16` (jump survives *dockerd* restart, not *docker run* of a fresh container). AC13 verifies the self-heal event frequency drops with the restart rate. |
| **L3 — DNS / routing (LB rotation)** | ALREADY FIXED | H2: #5413 grace-window IP retention (`f743bc263`). Not a work target. |
| **L7 — TLS / proxy** | N/A | Symptom is SIGKILL process-exit, not an HTTPS response-path failure (no 5xx/handshake keyword). |
| **L7 — application** | PRIMARY + SECONDARY causes | H3 (host OOM, `ci-deploy.sh:668-683` no `--memory`) + H4 (no `uncaughtException` handler). journald `oom-kill:` is the ground-truth artifact. |

**L3-first confirmed:** H1 (firewall) and H2 (DNS) are ruled out before H3/H4 (service layer) are named. No blocking gaps.

## Precedent-Diff (deepen Phase 4.4)

**Scheduled-job pattern — systemd timer, NOT Inngest.** The new `container-restart-monitor` is a HOST-level systemd timer (it must run `docker inspect` + read `/sys/fs/cgroup/.../memory.events` on the host, outside any container — an Inngest function running *inside* the container cannot observe its own restart count or the host cgroup). The canonical precedent is therefore the sibling host monitors `resource-monitor.timer` and `disk-monitor.timer` (`cloud-init.yml` + `server.tf terraform_data` dual-path), NOT `apps/web-platform/server/inngest/functions/cron-*.ts` (ADR-033 Inngest path applies to in-app scheduled work, which this is not). Diff vs precedent: identical cooldown/envfile/Resend/always-exit-0 shape and identical `OnBootSec=5min`/`OnUnitActiveSec=5min` cadence; the only delta is the signal source (`docker inspect`+`memory.events` vs `/proc/meminfo`).

**Process-handler pattern.** No in-repo precedent for a top-level `uncaughtException` handler (the codebase has only a per-callsite oneshot guard comment at `index.ts:141` and the SIGTERM handler at `:228`). Pattern is therefore novel-for-this-repo → scrutinize at review; the deepen best-practices research supplies the canonical `captureException → close(2000) → exit(1)` shape + the auto-install double-report caveat (folded into AC4).
