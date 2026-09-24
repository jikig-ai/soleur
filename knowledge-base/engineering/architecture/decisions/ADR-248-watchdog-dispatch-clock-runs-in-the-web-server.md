---
title: "Watchers of the scheduling substrate are dispatched by an in-process web-server clock"
status: accepted
date: 2026-09-24
---

## Context

Two GitHub Actions workflows watch things Inngest depends on: `scheduled-inngest-health.yml`
(the external Inngest watchdog, `*/15`) and `scheduled-zot-restart-loop.yml` (the zot registry
alarm, hourly; the dedicated Inngest host pulls its image from zot at boot, #8539). Both were
triggered only by GitHub Actions `schedule:`, which is best-effort. On this repo it delivered
one run every 2–7 hours for both crons (#8495, measured with `gh run list` on 2026-09-24).
Their Sentry monitors were therefore permanently `missed`, and repeats are silent (#7142), so
the alarm could no longer separate a real outage from GitHub dropping ticks. On 2026-09-22 the
dedicated Inngest scheduler was down for about 59 minutes and nothing filed: the whole outage
fell inside one gap between runs.

`main-health-monitor.yml` shows the fix: its runs are started by `workflow_dispatch`, and the
RUN is created within seconds of every dispatch — GitHub drops `schedule` ticks, not
dispatches. The run's JOBS still wait in the org runner queue like any other job (#8450's
concurrency budget): measured on the last 40 runs of each watchdog (job `started_at −
created_at`, 2026-09-24), median ~30 s, p90 ~20 min, max ~40 min.
Its dispatcher is an Inngest cron, which these two workflows cannot use: a watcher of Inngest
cannot be scheduled by Inngest (ADR-033, anti-circularity corollary).

## Decision

The web-platform Node server runs a **watchdog dispatch clock**
(`apps/web-platform/server/watchdog-dispatch-clock.ts`). It is not an Inngest function.

- Every 30 s it checks each row of `WATCHDOG_DISPATCH_TABLE`
  (`server/watchdog-dispatch-table.ts`). When a UTC slot (15 or 60 min) is due, after a
  per-slot random jitter of 30–120 s, it mints a GitHub App installation token scoped to
  `actions: write` on `jikig-ai/soleur` only. It reads the workflow's recent runs on `main`
  and sends `POST …/dispatches {ref: "main"}` unless the newest run that could have covered
  the slot (event `schedule` or `workflow_dispatch`, not cancelled/skipped/startup-failed) was
  created at or after the slot start.
- It arms only when `NODE_ENV=production` and `SOLEUR_HOST_ID` is set. Only `ci-deploy.sh`
  sets that variable, so the clock runs on each deployed web host and never in CI, e2e or dev.
- Each workflow keeps its `schedule:` cron as a **fallback**. The Sentry monitor margins are
  budgeted for the clock PLUS the measured runner queue: inngest-health margin 45 (was 15),
  zot 60 (was 120). The margin bounds only dead-trigger detection (clock dark on both hosts
  and no GitHub tick): interval + margin = 60 / 120 min. A real outage pages as soon as a run
  executes and posts `?status=error` — slot + ~4 min + queue + runtime, typically ~10 min and
  ~30 min at p90 — independent of the margin. `sentry-monitor-iac-parity.test.ts` enforces
  the budget.
- The workflows tolerate a repeat run in one slot (a host collision, estimated ~5–10% of
  slots, or a late fallback tick): tracker create-or-comment lookups LIST by label rather than
  search (GitHub issue search lags a just-created issue), and the auto-restart step skips when
  a dispatched restart is queued, running or under 12 min old.
- A tick is bounded at 90 s and fenced three times (inner catch, an outer catch that emits
  `tick_escaped`, fail-open reporting), because `crash-handlers.ts` exits the process on an
  unhandled rejection. Every tick emits a WARN `SOLEUR_WATCHDOG_DISPATCH` marker.
- The clock must never import `server/inngest/`. `watchdog-dispatch-clock.test.ts` walks its
  transitive value imports and fails if any module under that tree is reachable.

### Eligibility rule (the exemption from ADR-033's scheduled-work pattern)

The repo default stands: new scheduled work goes on Inngest, and the
`new-scheduled-cron-prefer-inngest` hook enforces it. A workflow may be added to
`WATCHDOG_DISPATCH_TABLE` **only** when it watches the scheduling substrate, or something that
substrate depends on, so that it cannot be scheduled by that substrate. Each row carries a
required, non-empty `eligibility` string that states this argument, and
`sentry-monitor-iac-parity.test.ts` fails on an empty one. A scheduled job without that argument
uses the Inngest dispatch pattern (`cron-main-health-monitor`) instead.

### Failure domains

| Subject goes fully down | Can a clock still fire? | What alerts |
|---|---|---|
| Inngest scheduler (dedicated host) or the web Inngest unit | Yes: the clocks run on the web hosts | The watchdog run itself, and its Sentry check-in |
| Zot registry host | Yes | The zot alarm run |
| web-1 app container (also Inngest's execution host, via `sdk_url`) | Yes, from web-2 | Better Stack uptime; web-2 keeps dispatching |
| web-2 | Yes, from web-1 | web-2's absence-alerted Better Stack heartbeats (ADR-143 R1(a)) cover the HOST only; a crashed web-2 app container is visible only as that host's missing `SOLEUR_WATCHDOG_DISPATCH` rows, while web-1 carries the clock alone |
| Both web hosts | No | Better Stack uptime; Sentry missed check-in within 60 min; the `schedule:` fallback still runs, late |
| GitHub API / Actions | No, and the fallback is impaired too | Sentry missed check-in (Sentry does not depend on GitHub) |

This satisfies ADR-033's corollary test ("if the thing being checked fails completely, can the
trigger still fire?") for both watched subjects. The corollary itself argued for a native
`schedule:`; #8495 is the measurement that a native `schedule:` alone does not fire either, so
the clock is the primary trigger and `schedule:` stays behind it.

### Fleet rule (ADR-068, ADR-027)

Every deployed web host runs the same image, so each runs its own copy of every in-process
timer started at boot (this ADR states the rule; ADR-068 established the multi-host fleet it
applies to). A timer whose external side effect is not idempotent per slot must deduplicate
across the fleet. Here that is the per-slot jitter plus the slot-scoped read; a collision
(both hosts inside the read's visibility lag, ~5–10% of slots) yields one extra queued run,
which both workflows tolerate (`cancel-in-progress: false`, label-listed tracker dedup, the
restart dedup). Host clocks are not explicitly NTP-provisioned by the web cloud-init; skew
beyond the 30-s minimum jitter would only produce duplicate runs, never a missed slot. Under ADR-027 this is Bucket B,
duplicate-tolerant. The rule is about timers with EXTERNAL side effects: `ccIdleReaper` acts on
process-local state, and `stuckActiveReaper` writes shared rows through an RPC whose updates are
conditional on the row still being stuck, so a second host's pass finds nothing to change.
Neither is non-compliant.

### Why the clock does not join the ADR-078 cron drain

A tick is bounded at 90 s and spawns no child process. A tick killed by a container swap is
covered by the other host, and the new container's first poll re-reads the current slot.

## Considered Options

| Option | Verdict |
|---|---|
| **In-process polling clock in the web server** | **Chosen.** Fires while Inngest is down, reuses the App key already in the web runtime with a narrower token, and ships with the normal deploy. The only infra change is a Sentry margin in Terraform. |
| Cloudflare Worker cron trigger | Rejected for now. The Worker would need the GitHub App private key as a secret (the App has installations outside the org, and ADR-241 is narrowing that key's custody), plus a hand-minted Cloudflare token with Workers edit rights. It is the upgrade path; see the reversal triggers. |
| Inngest cron dispatch (the `main-health-monitor` pattern) | Rejected: an Inngest cron cannot fire while Inngest is down. |
| systemd timer on a host | Rejected: puts the App key on a host filesystem, and a host config change needs an immutable redeploy. |
| Better Stack monitor as trigger or probe | Rejected: a static token means a PAT, or copying the watchdog's HMAC and Access secrets into a vendor. |
| Retune Sentry margins only | Rejected: the measured worst gap is about 7 h, so detection would stay that slow. |

## Consequences

- inngest-health goes from about 5–8 to 96 runs a day, and zot from about 5–8 to 24 (plus the
  late fallback ticks and ~5–10% collision duplicates). Each run is a few minutes on a
  standard runner (public repo, no minute cost); averaged over the day that is well under one
  concurrent job of the org's 20-job budget (#8450), whose queue is dominated by PR fan-out.
  The restart arm can again fire up to about three times per incident inside its 45-min
  give-up window, which is the #6374 design; the restart dedup keeps a same-slot repeat run
  from adding a fourth.
- The short-lived canary container also carries a clock for its few minutes of life (it gets
  the same `SOLEUR_HOST_ID`). Its slot-scoped read keeps it from double-dispatching, but Vector
  does not ship the canary's logs, so a run it dispatches shows in `gh run list` with no marker,
  and its Sentry reports carry the same `host_id` as that host's prod container. The
  "canary fires no crons" comment in `ci-deploy.sh` is now stale and was deliberately NOT edited
  here: `ci-deploy.sh` is a hashed `triggers_replace` input of the host provisioner
  (`server.tf`), so even a comment edit re-provisions live hosts.
- The margins assume the clock. Rolling the web image back to before #8495 returns both
  workflows to GitHub's 2–7 h cadence and both monitors page as missed; restore the pre-#8495
  margins (inngest 15, zot 120) with it.

## Reversal triggers

Re-derive this decision if any of these happens:

- Inngest function execution is decoupled from web-1 (#7230).
- A Workers substrate and a narrow single-repo `actions: write` GitHub App appear, which removes
  the Worker's key-custody objection.
- `var.web_hosts` drops to a single host. The one remaining clock would then sit inside the
  Inngest execution container, and the Cloudflare Worker becomes the default.

**Relates to:** ADR-027, ADR-033, ADR-068, ADR-078, ADR-143 D2, ADR-241.
