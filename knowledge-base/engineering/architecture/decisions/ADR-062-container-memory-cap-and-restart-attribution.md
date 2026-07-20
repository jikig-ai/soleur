# ADR-062: Container memory cap + restart/OOM attribution for soleur-web-platform

- **Status:** Accepted
- **Date:** 2026-06-16
- **Deciders:** Jean (operator), CPO sign-off (single-user-incident threshold), deepen-plan review (best-practices-researcher, framework-docs-researcher)
- **Relates to:** #5417 (this change), #5413 (egress LB-rotation fix — the *primary* cause of the same outage window; merged `f743bc263`), ADR-027-process-local-state-for-runners (single-replica invariant), ADR-052 (container egress firewall / DOCKER-USER allowlist), ADR-031-sentry-as-iac

## Context

The `soleur-web-platform` Docker container restarted ~10–60×/day (06-08: 52,
06-11: 40, 06-12: 42, 06-15: 60; stable = 0–1/day, per the Sentry "Server
startup vX.Y.Z" issue, project `web-platform`, region `jikigai-eu`). Each
restart (a) kills any in-flight Claude-eval cron (≤55 min) and (b) triggers
`dockerd` to rebuild nftables on the next `docker run`, displacing the
`SOLEUR-EGRESS` jump in `DOCKER-USER` (the firewall self-heal then fires on its
1-min timer). The firewall flush is a **symptom** of the restart, not a cause.

Two facts established the root cause by config inspection (no SSH):

1. The prod container ran `docker run -d --restart unless-stopped` with **no
   `--memory` cap, no `--init`**, on an **8GB cx33** host (4 vCPU / 8GB). With no
   container memory limit, heavy concurrent Claude-eval crons drove **host** RAM
   pressure → the **host** kernel OOM-killed an arbitrary victim (which could be
   dockerd, inngest-server, or the firewall resolver — not necessarily the Node
   process) → `--restart unless-stopped` immediately restarted the container.
   This is the classic uncapped-container restart-churn signature.
2. There was **no** top-level `process.on('uncaughtException')` /
   `process.on('unhandledRejection')` handler in `server/index.ts`, so the
   *other* restart class — a thrown error that exits the process — was
   un-attributable: indistinguishable from an OOM restart in the telemetry.

`resource-monitor.sh` samples **host** RAM% only; it cannot observe the
container's `RestartCount` / `OOMKilled`. There was no container-level detector.

## Decision

Three independent deliverables (independent acceptance criteria; only A changes
cron survival and is the riskiest):

### A — Container memory cap (frequency fix)

Both `docker run` blocks in `ci-deploy.sh` carry `--memory <cap>
--memory-swap <cap> --init` from named, env-overridable constants. This converts
the unpredictable **host**-OOM into a **deterministic cgroup-OOM** that kills
only this container, sparing dockerd / inngest-server / the firewall resolver.

**Cap derivation (AC1).** No safe a-priori cap exists without a live measurement
of the concurrent-cron peak working set; a cap **below** legitimate peak would
convert host-OOM churn into cgroup-OOM churn at the same-or-higher rate (the AC2
regression). Absent a pre-merge measurement, the starting cap is derived from
the two hard constraints:

- **Deploy-window concurrency:** the canary (`--restart no`, port 3001) runs
  concurrently with live prod during the probe window, so
  `PROD_MEMORY_CAP + CANARY_MEMORY_CAP + host_overhead ≤ 8GB`.
- **Host overhead budget:** inngest-server + vector + dockerd + journald +
  firewall resolver + OS ≈ 1.3GB.

Chosen starting values: `PROD_MEMORY_CAP=4096m`, `CANARY_MEMORY_CAP=1536m`
(the canary fires no crons), `PROD_NODE_MAX_OLD_SPACE_MB=3072`. Deploy-window
peak `≈ 4096 + 1536 + 1300 = 6932m < 8GB` (≈870m slack); steady-state `≈ 4096 +
1300 = 5396m`, leaving ≈2.4GB host headroom. `--memory-swap == --memory`
disables swap growth (cloud-init configures no swap). `--max-old-space-size`
(3072) is set **below** the cgroup cap so V8 hits a clean heap-exhaustion error
before the opaque cgroup SIGKILL. `--init` (tini) reaps zombies and forwards
signals (hygiene; it does **not** change OOM semantics).

**The cap is a STARTING value, not a measured peak.** It is an
env-overridable named constant precisely so that tuning is a Doppler/deploy-env
change, not a code edit. Deliverable B's cgroup-OOM classification is the
post-merge feedback signal: if a legitimate concurrent-cron peak exceeds the
cap, the monitor pages with `class=OOM` and the operator raises
`PROD_MEMORY_CAP`. tmpfs counts against the cgroup in cgroup v2, so effective
process memory is `cap − 256m (tmpfs)`.

### B — container-restart-monitor (detector)

A new **host** systemd timer (`container-restart-monitor.{sh,service,timer}`,
modeled on `resource-monitor.sh`, 5-min cadence, always exits 0) reads
`docker inspect` `RestartCount`/`OOMKilled`/`ExitCode` and classifies:

- container-id **change** → deploy (reset baseline + rolling window, suppress
  alert) unless the fresh container already has `RestartCount>0` (immediate
  crash-loop → alert);
- **same** container-id, `RestartCount` delta in a rolling window ≥
  `RESTART_THRESHOLD` (3) over `RESTART_WINDOW_SECS` (3600) → restart-storm
  alert via a Sentry error event + Resend email, with `COOLDOWN_SECONDS` (3600);
- container absent (`docker inspect` non-zero during the deploy stop/rm window)
  → exit 0, baseline untouched (no false-healthy);
- a single recovery notification when the rolling rate returns to 0.

**OOM corroboration:** OOM is the OR of the cgroup `memory.events` `oom_kill`
counter delta (authoritative — the **only** signal that catches the
bwrap-sandboxed child-cgroup kill, a confirmed cgroup-v2 `.State.OOMKilled`
false-negative, moby#41929), `.State.ExitCode == 137`, and the journald
`oom-kill:` kernel ring — **not** `.State.OOMKilled` alone.

`cat-deploy-state.sh` exposes `restart_count`, `oom_killed`,
`container_exit_code` (a **distinct** key — never `exit_code`, which is the
load-bearing deploy-result sentinel), `restart_rate_per_hour`, and a redacted
OOM journald tail via the existing `/hooks/deploy-status` webhook (the no-SSH
surface).

### C — Crash attribution

`server/crash-handlers.ts` installs top-level `uncaughtException` /
`unhandledRejection` handlers that `Sentry.captureException` → `Sentry.close(2000)`
(close flushes **and** disables the SDK — correct for a process that will not
recover) → `process.exit(1)`. `sentry.server.config.ts` filters the auto
`OnUncaughtException`/`OnUnhandledRejection` integrations out of the defaults so
fatals report **once**. The "Server startup" event is tagged
`event_type=server-startup` for the AC12 rate-drop verification query.

### Sentry alert

`sentry_issue_alert.container_restart_burst` pages on the monitor's
host-authoritative event (`feature=container-restart-monitor`, op-scoped to
`{restart_storm, fresh_crash_loop}`; the informational `recovered` op is
excluded). It uses the proven `first_seen/reappeared/regression` + `tagged_event`
pattern — **not** an `event_frequency` condition. The monitor already does the rate
thresholding host-side, so a first-seen page on its event is both correct and simpler
than a redundant frequency condition. (Update, #6278: the pinned `jianyuan/sentry`
provider (v0.15.4 as of #6636; originally schema-verified at v0.15.0-beta2) `conditions_v2`
**does** expose `event_frequency` — schema-verified via the cached provider binary;
the first in-repo use is `zot_mirror_fallback_rate` in
`issue-alerts.tf`. The original "no verified support" framing was stale; first-seen
remains preferred *here* purely because the host does the thresholding.) The "Server
startup" event-frequency remains available for AC12 verification via the Sentry
issue stats API.

## Scope

- **dev ≠ prd.** The cap and the monitor apply to the **prd** host only — the
  dev environment has no equivalent always-on cron host. (`hr-dev-prd-distinct-supabase-projects`
  is about Supabase; the distinction here is the prd-only always-on runtime.)
- **Provisioning is dual-path (AC9):** cloud-init `write_files` + runcmd for
  fresh hosts AND `terraform_data.container_restart_monitor_install` remote-exec
  for the existing host (cloud-init does not reach it — `ignore_changes =
  [user_data]`), mirroring `terraform_data.resource_monitor_install`. The new
  SSH-provisioned resource is in `apply-web-platform-infra.yml`'s `-target=` set
  (the `terraform-target-parity` guard).
- **Single replica (ADR-027) is unchanged.** The cap does not alter the
  pre-`docker run` single-replica assertion.

## Consequences

**Positive.** The dominant win is deterministic OOM victim selection: a memory
spike now kills *this container*, not dockerd / inngest / the firewall resolver,
so the host stays coherent and the egress jump is not flushed by a host-OOM
cascade. Crash-driven restarts become attributable (Sentry fatal events). The
operator gets a no-SSH restart-rate/OOM signal (monitor + webhook fields + Sentry
alert).

**Negative / risk.** If the starting cap (4096m) is **below** the legitimate
concurrent-cron peak, the container will cgroup-OOM deterministically — a
regression that *looks* like a fix (`class=OOM` "deterministic!") while crons
still die. This is mitigated, not eliminated, by: (a) the monitor paging with
`class=OOM` so the operator sees it within minutes; (b) the cap being a one-line
env-overridable constant; (c) ≈2.4GB steady-state host headroom giving room to
raise it. The post-merge AC12 verification (Sentry "Server startup" frequency
drop to ≤1/day over 72h) confirms the fix landed; a *rise* in `class=OOM`
monitor events is the signal to raise the cap.

**Verification (post-merge, no-SSH).** Sentry issue stats API over the "Server
startup" issue (`GET /api/0/organizations/{org}/issues/{issue-id}/stats/?stat=24h`
summed over 72h) gives the deterministic rate-drop verdict; the
`cron-egress-firewall: enforcement rules were MISSING` self-heal event frequency
should drop in step (confirming the flush was a restart symptom).
