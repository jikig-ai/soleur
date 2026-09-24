---
title: "fix: dispatch the external Inngest watchdog and zot restart-loop alarm from an in-process web-server clock (GitHub cron drops runs)"
date: 2026-09-24
slug: fix-external-watchdog-dispatch-cadence
branch: feat-one-shot-8495-external-watchdog-cadence
issue: 8495
closes: 8495
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
---

# fix: reliable ~15-min cadence for the external Inngest watchdog and zot restart-loop check

## Overview

The two GitHub Actions watchdogs `scheduled-inngest-health` (declared `*/15`) and
`scheduled-zot-restart-loop` (declared hourly since #8450; the issue text still says `*/30`) are started by GitHub's best-effort `schedule`
trigger, which in practice starts them only every 2 to 7 hours. The Sentry cron monitors for both
therefore report nearly every expected check-in as missed, and a real Inngest outage (about 59
minutes on 2026-09-22) went undetected. This plan moves the clock that starts them to a reliable
source outside both GitHub cron and Inngest, and aligns the Sentry monitor configuration with the
cadence that source actually delivers.

## Research Insights

### Premise Validation (Phase 0.6)

- **#8495** is OPEN (`priority/p1-high`, `type/bug`). The premise holds. Re-measured on 2026-09-24
  with `gh run list --workflow <wf> --limit 40 --json createdAt,event`:
  - `scheduled-inngest-health.yml`: every one of the 40 runs is `event=schedule`. Consecutive gaps
    range from 2h01m to 6h53m (e.g. 06:19→13:08 on 09-21, 06:01→11:36 on 09-22, 00:42→05:28 on
    09-24). No gap comes close to the declared 15 min.
  - `scheduled-zot-restart-loop.yml`: every run is `event=schedule`. Gaps range from 2h to 7h43m
    (07:35→15:18 on 09-22).
  - **The parent brief is stale on one point.** It says zot runs `*/30`, but the workflow has been
    **hourly** (`cron: '0 * * * *'`) since #8450. Its Sentry monitor is `0 * * * *` with
    `checkin_margin_minutes = 120` (`apps/web-platform/infra/sentry/cron-monitors.tf`,
    `resource "sentry_cron_monitor" "zot_restart_loop_alarm"`). The C4 model's `*/30` comment is
    stale for the same reason.
- **#8539** is OPEN. Its comment of 2026-09-22T07:58:59Z records a scheduler outage of about 59 min
  (06:59Z–07:58Z) with no `ci/inngest-down` filing. The run list above explains why: the watchdog
  ran at 06:01Z and not again until 11:36Z, so the whole outage fell inside one gap.
  - **This plan claims only that cadence was the proximate cause.** Which issue label a run
    *inside* that window would have filed is a classifier question. With the web scheduler quiesced
    and the dedicated host not serving, the `nolive`/dedicated arms would have fired, not
    necessarily `inngest_down`.
  - That classification is covered by `inngest-dedicated-host-classify.test.sh` and is out of scope.
- **#8450** is CLOSED. It is the org concurrency-budget issue that relaxed zot to hourly, and it
  stays relevant as a budget constraint (see Infrastructure (IaC), Vendor-tier reality check).
- **The `main-health-monitor` precedent is verified.**
  - Its 40 most recent runs are all `event=workflow_dispatch`, created within 0–3 min of
    00/06/12/18 UTC. Each job's `started_at` is 2–4 s after `created_at`.
  - The dispatcher is the Inngest cron `cron-main-health-monitor`
    (`apps/web-platform/server/inngest/functions/cron-main-health-monitor.ts`,
    `cronMainHealthMonitorHandler`). It calls `mintInstallationToken` from
    `apps/web-platform/server/inngest/functions/_cron-shared.ts`, then
    `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches`.
  - **Takeaway:** a run dispatched from a reliable clock starts within seconds. GitHub drops
    `schedule` *ticks*; it does not drop `workflow_dispatch` events.
  - Job-queue waits in a 40-run sample of other recent workflows: 0 s for 39 runs, 157 s for 1.
- **The precedent does not carry over as-is to the Inngest watchdog.** It is an *Inngest* cron, and
  an Inngest cron cannot watch Inngest. This is ADR-033's anti-circularity corollary
  (`knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`,
  "Anti-circularity corollary (2026-08-03, #6808)"): *"if the thing being checked fails completely,
  can the trigger still fire?"* The precedent's **dispatch code** does carry over.

- **API contract, probed live on 2026-09-24:**
  - An unauthenticated `curl -fsS "https://api.github.com/repos/jikig-ai/soleur/actions/workflows/scheduled-inngest-health.yml/runs?per_page=3"`
    returned `total_count: 1445` with runs **newest first**. The public-repo runs list is therefore
    readable with no credential, which the discoverability test and AC11 depend on. Its `created_at`, `event`,
    `status` and `conclusion` fields are present.
  - `generateInstallationToken(installationId, { minRemainingMs?, permissions?, repositories? })`
    (`apps/web-platform/server/github-app.ts`) accepts a permission scope-down.
  - The dispatches endpoint (`POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches`,
    204 on success; https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
    is already exercised in production by `cron-main-health-monitor`.

### Property List (Phase 0.6b)

- **P1:** `scheduled-inngest-health` keeps starting about every 15 min while the Inngest scheduler
  (dedicated host 10.0.1.40, or the web unit) is down. Its trigger does not depend on the Inngest
  scheduler.
- **P2:** In steady state, `scheduled-inngest-health` starts at most about 15 min apart and
  `scheduled-zot-restart-loop` at most about 60 min apart. A clock bounds the worst-case gap, not
  GitHub's best-effort `schedule`.
- **P3:** The Sentry `scheduled-inngest-health` and `scheduled-zot-restart-loop` monitors report
  `missed` only when the trigger path is really dead. Their margins match the delivered cadence, so
  the missed-check-in page carries signal again.
- **P4:** When the new trigger itself dies, an alert fires within a bounded time, and a fallback
  still runs the watchdog.
- **P5:** No new credential custody. GitHub is reached with a GitHub App installation token, never
  a PAT (`hr-github-app-auth-not-pat`), and no App private key is copied to a new location
  (ADR-241's tiered-custody direction).
- **P6:** Nothing needs provisioning outside the repo, and anything that does is Terraform
  (`hr-all-infrastructure-provisioning-servers`). Merging deploys the fix with no human step.

### Cut List (Phase 0.6b)

- *A Better Stack uptime monitor that POSTs `workflow_dispatch`* (targets P1/P2). **Cut.**
  - It would need a static bearer token in the request header, and a static GitHub token is a PAT
    (`hr-github-app-auth-not-pat`).
  - App installation tokens expire after 1 h, so they cannot be pinned in a monitor config.
- *A Better Stack or Sentry uptime monitor pointed directly at `/hooks/inngest-liveness`* (targets
  P1). **Cut.**
  - It needs HMAC plus CF Access service-token headers, which would copy those secrets into a
    vendor.
  - It sees only an HTTP status, so it bypasses the workflow's classifier: quiesce-aware modes, the
    `nolive`/dedicated-host arms, restart dispatch, and deduplicated issue filing.
  - The result would be a second, weaker watchdog, not a trigger for the real one.
- *Retune the Sentry margins only* (targets P3 without P1/P2). **Cut.**
  - The measured worst gap is ~7 h, so the margin would have to exceed ~7 h.
  - Detection latency for a real Inngest outage would stay at ~7 h, and the 59-min outage on 09-22
    would still go unseen.
  - The brief rejects this option "unless detection latency stays acceptable". It does not.
- *Port the probe into TypeScript and run it in-process* (targets P1/P2). **Cut.** The workflow is
  1,273 lines: a classifier, restart dispatch, five deduplicated issue families, a tunnel-census job
  and the Sentry check-in. Dispatching keeps one source of truth, and only the *clock* moves.
- *A self-re-dispatching GHA chain*, where a run re-dispatches itself after a sleep (targets P2).
  **Cut.**
  - It holds a runner slot through every sleep, which works against the #8450 org budget.
  - One broken link ends the chain forever.

### Relevant files

- `.github/workflows/scheduled-inngest-health.yml`: 1,273 lines.
  - Triggers are `on.schedule '*/15 * * * *'` plus `workflow_dispatch: {}`.
  - The gate-override header for `new-scheduled-cron-prefer-inngest` is on the first line.
  - The final step, `Sentry check-in (final)`, runs `if: always()` with slug
    `scheduled-inngest-health`.
  - No step gates on `github.event_name`, so dispatched runs check in exactly as scheduled runs do.
- `.github/workflows/scheduled-zot-restart-loop.yml`: 591 lines.
  - Triggers are `on.schedule '0 * * * *'` plus `workflow_dispatch: {}`.
  - The final heartbeat uses slug `scheduled-zot-restart-loop`.
  - The header says detection is window-bound: a 3 h look-back against a 5-min emitter.
- `apps/web-platform/infra/sentry/cron-monitors.tf`:
  - `sentry_cron_monitor.scheduled_inngest_health` is `*/15`, margin 15, max_runtime 8,
    failure_issue_threshold 1.
  - `sentry_cron_monitor.zot_restart_loop_alarm` is `0 * * * *`, margin 120, max_runtime 10.
  - Both are applied on push to main by `.github/workflows/apply-sentry-infra.yml`, which plans the
    full root. There has been no `-target` allowlist since #6589.
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`,
  `describe("GHA schedule cron ↔ monitor crontab parity (#8450)")`.
  - It requires each monitor's crontab to be one of its workflow's `on.schedule` crons, for
    `scheduled-zot-restart-loop`, `scheduled-prod-version-drift` and `scheduled-inngest-health`.
  - **Consequence:** the fallback `schedule:` crons must keep their current strings. This is one of
    the load-bearing reasons they stay.
- `apps/web-platform/server/index.ts` (336 lines) is the boot sequence. `startCcIdleReaper()` is
  the precedent for an `.unref()`'d timer that starts at boot and lives as long as the process.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` provides
  `mintInstallationToken({ tokenMinLifetimeMs, permissions?, repositories? })`, `REPO_OWNER`,
  `REPO_NAME` and `redactToken`.
- `apps/web-platform/server/host-identity.ts` reads `SOLEUR_HOST_ID`, which only the deploy injects
  (`apps/web-platform/infra/ci-deploy.sh`, `-e SOLEUR_HOST_ID="$HOST_ID"` on both the canary and the
  prod `docker run`). It serves as the "running on a deployed host" predicate.
- ADR-027 (`ADR-027-process-local-state-for-runners.md`) sets a single-replica invariant for the
  web container, enforced by the pre-`docker run` assertion in `ci-deploy.sh`. The one overlap is
  the short-lived canary container (`soleur-web-platform-canary`, port 3001), which uses the same
  env file.
- ADR-143 D2 makes web-2 a standby at serving-weight 0, outside the ingress rotation.
- `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` fires only on **new**
  `.github/workflows/scheduled-*.yml` files that carry a `schedule:`/`cron:` key.
  - This plan edits two **existing** workflows, and only their header comments, so the hook does
    not fire.
  - The exemption is still justified explicitly, in Technical Approach and in the ADR.
- C4: all three files were read in full (`model.c4` 854 lines, `views.c4` 106, `spec.c4` 54).
  - The `platform.webapp.api` → `github` edges are at model.c4 L474 and L610.
  - The `github -> sentry` edge at L762 carries the C1–C6 counts (14 workflows / 8 schedule-fired /
    6 dispatch-only / 59 monitors / 15 / 44). `plugins/soleur/test/c4-count-parity.test.sh`
    derives them and currently passes 10/10.
  - The tunnel element at L254 says "*/15 connector census in scheduled-inngest-health.yml".
  - The zot comment at L730 still says `*/30`, which is stale.
  - L580 claims an `audit_github_token_use` row for "every GitHub App-token use". That is already
    false for `mintInstallationToken` callers.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md`:
  GHA `schedule` lateness has reached 339 min, so a margin sized to the nominal interval false-pages
  on a jittery cron. **This plan inverts that:** with a reliable clock, the margin can be sized to
  *dispatch + queue + runtime* rather than to GitHub's jitter.
- `knowledge-base/project/learnings/2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md`:
  a dispatch-only trigger needs no Sentry monitor of its own **if the executor workflow has one**.
  Both executors have one, so the monitors become the end-to-end liveness signal for clock, dispatch
  and run together.
- `knowledge-base/engineering/operations/post-mortems/inngest-watchdog-false-positive-unseen-6374-postmortem.md`:
  every heartbeat slug needs a matching `sentry_cron_monitor`. That is unchanged here, since no new
  slug is added.
- `knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`: use a
  single end-of-job `if: always()` heartbeat. Both workflows already do, and this plan leaves that
  alone.
- ADR-033 anti-circularity corollary: the new trigger's failure domain must not include what it
  watches.
  - The in-process clock runs on **both web hosts**: web-1 and web-2, since deploys fan out to
    `10.0.1.10,10.0.1.11`. That puts it outside the Inngest scheduler's failure domain, which is
    the dedicated host.
  - Losing a single web host is covered by the other host's clock.
  - Losing both web hosts is covered because the plan **keeps** the native `schedule:` as a
    fallback that does not depend on any web host. The Sentry monitor is the outer layer that
    reports a dead trigger.
  - See Alternative Approaches for the fully host-independent Cloudflare Worker option, and why it
    was not chosen.
- ADR-241 (`ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`): the
  `soleur-ai` App private key has three installations, two of them outside `jikig-ai`, and the repo
  is actively narrowing where that key lives. Copying it into a Cloudflare Worker secret would go
  against that direction.

### Related issues and PRs

- #8495 is the target. #8539 holds the outage evidence.
- #8450 covers the concurrency budget. #6374 is the watchdog monitor gap.
- #5542 is the original crash-loop. #6291 is the zot alarm.
- #8077 is the no-live-scheduler arm. #7230 decouples Inngest execution from web-1.
- #8595 (open) is the cadence-parity gap in the monitor registry tests.
- #8593 (open) is the unbounded `gh` enumeration gate.

### CLAUDE.md / AGENTS.md conventions in force

- `hr-all-infrastructure-provisioning-servers`
- `hr-github-app-auth-not-pat`
- `hr-observability-as-plan-quality-gate`
- `cq-silent-fallback-must-mirror-to-sentry`: a dispatch failure goes to `reportSilentFallback`.
- `cq-write-failing-tests-before`
- `hr-weigh-every-decision-against-target-user-impact`
- `wg-use-closes-n-in-pr-body-not-title-to`

## Problem Statement

GitHub Actions `schedule` is best-effort, and on this repo it drops most ticks. Both watchdogs run
every 2 to 7 hours instead of every 15 or 60 minutes. That has two consequences:

1. **A real Inngest outage can go undetected for hours.** On 2026-09-22 the scheduler was down for
   about 59 minutes, and not one watchdog run landed in that window.
2. **The Sentry alarm is now noise.** `failure_issue_threshold = 1` with a 15-min margin (inngest)
   and a 120-min margin (zot) puts both monitors in a near-permanent `missed` state. Sentry routes
   cron failures through New/ExistingHighPriorityIssueCondition, so repeats are silent (#7142), and
   the one page gets spent on jitter. A trigger that has really died then looks no different from
   the standing noise.

A side effect has gone unnoticed. The watchdog's time-based escalation windows were built around a
15-minute cadence: the 45-min give-up window on `[ci/inngest-down]` restarts, and the 45-min
persistence ceiling on `functions_query_degraded`. At a 2–7 h cadence, each of these collapses to a
single observation. Restoring the cadence brings their designed behaviour back, which is up to about
3 restart dispatches per incident before give-up (see Risks).

## Proposed Solution

> **[Updated 2026-09-24, plan v2 after plan-review.]** The DHH and code-simplicity reviewers
> independently converged on the same change, and it also dissolved Kieran's P0 and three of his
> P1s. The change replaces the self-re-arming `setTimeout` chain with a **polling loop**, cuts the
> bespoke cadence-probe script, and folds the parity guard into the existing
> `sentry-monitor-iac-parity.test.ts`. The v1 design is recorded in the git history of this file.

Add a **watchdog dispatch clock**: a small polling loop inside the web-platform Node server
process. It is armed at boot in `apps/web-platform/server/index.ts` and is **not** an Inngest
function. It runs on **every deployed web host**: web-1 and web-2 through the deploy fan-out to
`10.0.1.10,10.0.1.11`, plus the short-lived canary. Every `POLL_MS = 30_000` ms, for each table
entry, it checks whether the current wall-clock slot is due and not yet handled. If so, it runs one
**tick**:

1. It mints a GitHub App installation token, scoped `permissions: { actions: "write" }` and
   `repositories: [REPO_NAME]`. It uses the existing `mintInstallationToken`, the same credential
   path `cron-main-health-monitor` uses today.
2. It reads the workflow's newest run (`GET …/actions/workflows/{file}/runs?per_page=1`) and skips
   if **this slot already has a run**, meaning one was created at or after `slotStart − 60 s`.
3. Otherwise it sends `POST …/actions/workflows/{file}/dispatches` with `ref: main`.

| Workflow | Slug | Interval | Due at | Skip rule | Eligibility (ADR-246) |
|---|---|---|---|---|---|
| `scheduled-inngest-health.yml` | `scheduled-inngest-health` | 15 min | slot + per-slot random jitter of 30–150 s | newest run `created_at >= slotStart − 60 s` | watches the Inngest scheduler, so it cannot be scheduled by it (ADR-033 anti-circularity) |
| `scheduled-zot-restart-loop.yml` | `scheduled-zot-restart-loop` | 60 min | same | same | watches the registry the Inngest host pulls its image from at boot (#8539), so it shares that failure domain |

- **Fallback.** Both workflows keep their `schedule:` crons unchanged. That fallback does not
  depend on any web host, and the #8450 parity test requires it. If GitHub delivers a tick, the
  slot-scoped read sees that run and skips.
- **Crontabs.** The Sentry monitors keep their crontabs. Margins are re-derived for a reliable
  clock:
  - inngest-health stays at **15**, with a rewritten rationale;
  - zot goes **120 → 30**.
- **Detection.** A dead trigger now pages within interval + margin: 30 min for inngest-health, 90
  min for zot. A real Inngest outage is detected within about 15 min plus the run time.

**Why these specific choices (review findings folded in):**

- **Polling rather than a timer chain.** `setInterval(...).unref()` cannot "die", so the v1
  machinery goes away: re-arm in `finally`, the stopped flag, the early-timer guard, the boot
  catch-up, and Guard 2's chain rows.
  - The first poll after boot handles the current slot.
  - `stop()` is `clearInterval`.
  - The cost is at most one `per_page=1` read per slot per host, not one per poll: a slot is marked
    handled after its tick.
- **Slot-scoped skip, not an age window.** Found by CTO and SpecFlow. An age window of
  `interval − 3 min` would make a late GH run created at :05 suppress the :15 tick, and the :15
  Sentry slot would then miss its :30 deadline.
- **Per-slot random jitter.** Found by CTO: web-2 runs a second clock all the time. Jitter spreads
  the hosts, so the later one's read sees the earlier one's run. A true collision (both inside
  about 3 s) is estimated at about 5% of slots and yields one serialized, harmless duplicate. Two
  hosts also give **redundancy**: if one host's tick fails or that host is down, the other still
  dispatches the slot.

### Why this mechanism (option evaluation)

| Option | P1 (fires while Inngest is down) | P2 (bounded cadence) | P4 (dead trigger detected + fallback) | P5 (no new key custody / no PAT) | P6 (no human step, Terraform where infra) | Verdict |
|---|---|---|---|---|---|---|
| **A. In-process polling clock in the web server (chosen)** | Yes. It runs on web-1 and web-2, never on the dedicated Inngest host | Yes. Slot-aligned, and dispatched runs start within seconds | Yes. A second host's clock is a live backup. Sentry pages when both are dead, and the GH `schedule:` fallback stays | Yes. It reuses the App key already in the web runtime, with the token scoped to `actions:write` on one repo | Yes. It ships in the image on the normal merge deploy, and the only infra change is a Sentry margin in Terraform | **Chosen** |
| B. Cloudflare Worker cron trigger (`cloudflare_workers_script` + `cloudflare_workers_cron_trigger`) | Yes, and it is also independent of the web hosts | Yes | Yes | **No.** The Worker needs an App private key as a secret. The only key is the `soleur-ai` App's (3 installations, 2 outside the org), and ADR-241 is narrowing that key's custody. A narrow dedicated App cannot be created through Terraform | **No.** `var.cf_api_token` lacks Workers Scripts:Edit, and a new narrow CF token must be hand-minted: the `cf-cert-reissue-token.tf` header records that minting needs "API Tokens: Edit" (CF error 9109). The repo has no Workers today, so this would be a new substrate | Rejected for now. It is the upgrade path if web-host coupling ever matters (ADR-246, #7230) |
| C. Inngest cron dispatch (the `main-health-monitor` precedent) | **No.** An Inngest cron cannot fire while Inngest is down (ADR-033 anti-circularity) | Yes | Partly | Yes | Yes | Rejected for inngest-health. It would work for zot, but a second mechanism for one workflow buys nothing over A |
| D. systemd timer on a host | web/zot: yes. inngest: no | Yes | Yes | **No.** The App key would land on a host filesystem outside the app container | **No.** A host config change needs an immutable redeploy (`hr-prod-host-config-change-immutable-redeploy`) with approval gates | Rejected |
| E. Better Stack monitor as trigger or probe | Probe: yes | Yes | Yes | **No.** A static token means a PAT, and a direct probe copies the HMAC and CF Access secrets into a vendor | Yes (Terraform) | Rejected (Cut List) |
| F. Retune Sentry margins only | No change | **No.** The worst gap is ~7 h | Detection stays ~7 h | Yes | Yes | Rejected: the detection latency is not acceptable |

**The exemption from `new-scheduled-cron-prefer-inngest` / ADR-063 is explicit and narrow.** The
repo default ("new scheduled work goes on Inngest") stands. This clock covers the documented
exception class: *a watcher of the scheduling substrate, or of what the substrate depends on,
cannot be scheduled by that substrate* (ADR-033 anti-circularity). The gate-override header on the
first line of `scheduled-inngest-health.yml` already records this. ADR-246 restates it as the
table's **eligibility rule**:

- Each `WATCHDOG_DISPATCH_TABLE` entry carries a required, non-empty `eligibility` string, and
  Guard 1 fails on an empty one.
- A job with no anti-circularity argument uses the Inngest dispatch pattern (`main-health-monitor`)
  instead.

The hook itself does not fire. Both workflows already exist, and no new
`.github/workflows/scheduled-*.yml` is created.

## Technical Approach

### Architecture

```text
   ┌── web-1 AND web-2 (and a transient canary): soleur-web-platform container, one clock each ──┐
   │  startWatchdogDispatchClock()  armed iff NODE_ENV=production && SOLEUR_HOST_ID (trimmed)      │
   │  setInterval(poll, 30 s).unref()                                                              │
   │    poll (never throws): for each entry, S = slotStartAt(now, interval)                        │
   │      skip if handledSlot==S or inFlight or now < S+jitter(S) or now >= S+interval-2min        │
   │      tick(S) under ONE deadline (TICK_DEADLINE_MS = 90 s, injected timers):                  │
   │        mintInstallationToken({actions:"write"}, repositories:["soleur"])                      │
   │        GET runs?per_page=1 → skip iff created_at >= S-60 s   (read error → fail-OPEN)         │
   │        POST dispatches {ref:"main"}                                                          │
   │      finally: handledSlot=S, inFlight=false; info log {host, slot, workflow, outcome}         │
   │      failure → reportSilentFallback(op∈{mint,dedup-read,dispatch}, extra.reason) [try/catch] │
   └───────────────────────────────┬───────────────────────────────────────────────────────────────┘
                                   │ HTTPS, App installation token
                                   ▼
   GitHub Actions ── scheduled-inngest-health.yml / scheduled-zot-restart-loop.yml (logic unchanged)
        ▲  fallback: on.schedule '*/15 * * * *' and '0 * * * *' (kept byte-identical)
        └── final step: sentry-heartbeat → Sentry cron monitor → missed/error → operator page
```

**Failure-domain reasoning (ADR-033 corollary, applied per watched subject):**

| Subject goes fully down | Can a clock still fire? | What alerts |
|---|---|---|
| Inngest scheduler (dedicated host 10.0.1.40) | **Yes.** The clocks run on the web hosts | The watchdog run itself: the `nolive`/dedicated/down arms, an error check-in, and a page |
| Inngest web unit (quiesced or crashed) | **Yes** | Same |
| Zot registry host | **Yes** | The zot alarm run: a `[ci/zot-restart-loop]` issue |
| One web host (web-1 or web-2) | **Yes, from the other host** | Better Stack uptime (web-1 serves the app), while dispatch continues |
| Both web hosts | **No** | Better Stack uptime, a Sentry missed check-in within 30 min, and the GH `schedule:` fallback still runs, late |
| GitHub API / Actions | No, and the GH fallback is impaired too | Sentry missed check-in (Sentry is independent of GitHub) |

### Behaviour details (decided here so the work phase does not re-decide them)

- **Arm predicate.** The clock arms when `NODE_ENV === "production"` and `SOLEUR_HOST_ID.trim()`
  is non-empty. `ci-deploy.sh` injects `SOLEUR_HOST_ID` only into deployed prod and canary
  containers. That is why local dev, CI, vitest and `next build` never arm, and why `NODE_ENV`
  alone is not enough.
  - One boot line: `watchdog-dispatch-clock armed|disarmed reason=… host=…`.
  - If `NODE_ENV === "production"` but the clock is **disarmed**, report through
    `reportSilentFallback` with `op: "arm"` (`cq-silent-fallback-must-mirror-to-sentry`).
    `host-identity.ts` only throws lazily, on a lease call, so it does not cover this.
- **Slot math.** `slotStartAt(now, intervalMin)` is the UTC wall-clock multiple of `intervalMin`
  at or before `now`.
  - Jitter is drawn once per `(entry, slot)` from `[JITTER_MIN_MS = 30_000, JITTER_MAX_MS = 150_000]`
    through an injected `random()`.
  - **Late cutoff:** no tick starts for slot `S` once `now >= S + interval − 2 min`. A run created
    in the final 2 minutes would fall inside the next slot's 60-s tolerance and wrongly suppress
    it (Kieran P2-11). A process that boots that late in a slot has already lost that slot, and
    the other host covers it.
- **Skip rule (the dedup).** Skip iff the newest run of **any** event has
  `created_at >= S − 60_000`.
  - A run from an earlier slot, including a late GH run, never suppresses this slot.
  - A run already in this slot (from the other host, the canary, or a GH tick) always does.
  - An old run still `queued` counts as "not this slot".
  - The read is `per_page=1`, which is bounded. Because every dispatch targets `ref: main`, "newest
    run on any branch" is the right population.
- **One deadline per tick, testable with fake timers.** `withTimeout(tickBody, TICK_DEADLINE_MS)`
  is a `Promise.race` against the **injected** `setTimeout`, with `clearTimeout` in `finally` so no
  timer leaks (Kieran P1-2).
  - Octokit calls also get `request: { signal }` as belt-and-braces. The `@octokit/request` fetch
    wrapper honours it.
  - `mintInstallationToken`'s `GET /installation` has no timeout of its own. Only
    `generateInstallationToken` is bounded (`GITHUB_GENERATE_TIMEOUT_MS = 30_000`,
    `github-app.ts`), which is why the whole tick sits under one deadline.
- **Fail-open on the read, fail-safe on the dispatch.**
  - If the runs read fails, the tick dispatches anyway. A duplicate is harmless: both workflows
    declare `concurrency.group` with `cancel-in-progress: false` (pinned by Guard 1), and issue
    dedup makes them idempotent. A skipped watchdog is the defect this plan fixes.
  - Failures report through `reportSilentFallback` with `feature: "watchdog-dispatch-clock"`,
    `op ∈ {mint, dedup-read, dispatch}` and `extra: { workflow, reason: "timeout" | "http" | "throw", status? }`.
    The token is redacted with `redactToken`.
  - A failed slot is **not** retried by the same host. The other host's clock covers it, and the
    next slot re-attempts.
- **Never takes the server down.** `crash-handlers.ts` exits the process on `unhandledRejection`,
  so the error paths are fenced:
  - The poll body runs in `try/catch`.
  - Each tick is `void runTick(...).catch(logOnly).finally(clearInFlight)`.
  - `reportSilentFallback` is wrapped in its own `try/catch`.
- **Every tick logs** at info level: `{ host, slot, workflow, outcome: dispatched | skipped_slot_has_run | failed | disarmed }`.
  This is how the runbook answers "is it running?" and "which host sent this run?". The Actions
  list shows the same App bot for every host.
- **Sentry flood on a disabled workflow is bounded by design.** A disabled workflow returns 422 on
  every tick: at most 96 events a day for inngest from each host. Sentry groups them into one issue.
  The CTO suggested `mirrorWarnWithDebounce`, but its 5-min TTL is shorter than the 15-min cadence,
  so it would suppress nothing. The plan declines it and records that here.
- **Token.** `mintInstallationToken({ tokenMinLifetimeMs: 5 * 60_000, permissions: { actions: "write" }, repositories: [REPO_NAME] })`.
  `actions:write` also grants reading runs. `generateInstallationToken`'s cache key includes the
  scope (#5046).
- **Dispatch code is inlined in the clock module (about 12 lines).** `cron-main-health-monitor.ts`
  is not touched. Extracting a shared helper from a working production dispatcher buys no listed
  property.
- **Sentry margin budget (inngest).** Check-in time = slot + jitter (≤ 2.5 min) + poll granularity
  (≤ 0.5 min) + queue + runtime. The `probe` job has `timeout-minutes: 8`, and `connector_census`
  (≤ 5 min) runs in parallel. That gives ≤ 11 min plus queue against a 15-min margin, leaving about
  4 min of queue headroom. The measured queue is 0 s in 39 of 40 sampled runs and 157 s at worst.
  For zot: ≤ 13 min plus queue against 30. **These numbers go into the `cron-monitors.tf`
  rationale comments**, and the `JITTER_MAX_MS` constant's comment cites this budget.
- **Clock skew.** The hosts are NTP-synced, and Sentry and GitHub timestamps are server-side. Skew
  of a few seconds sits inside the 60-s tolerance.

### Implementation Phases

#### Phase 0: RED first (`cq-write-failing-tests-before`)

- Create `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts` (vitest, fake timers,
  injected dependencies). Every scenario in Test Scenarios §Clock is written first and must fail
  against a stub module.
- Add the Guard 1 assertions to `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`
  as a new `describe("Watchdog dispatch clock parity (#8495)")`. They fail until the table and the
  zot margin exist.

#### Phase 1: Clock module + boot wiring

- Create `apps/web-platform/server/watchdog-dispatch-clock.ts` with these exports:
  - `WATCHDOG_DISPATCH_TABLE`, as `{ workflowFile, monitorSlug, intervalMinutes, eligibility }`;
  - `slotStartAt`, `slotAlreadyHasRun`, `shouldArmWatchdogClock`;
  - `startWatchdogDispatchClock(deps?)` → `{ stop }`.

  `deps` injects `now`, `random`, `mint`, `octokitFor`, `report`, `log`, `setInterval`,
  `clearInterval`, `setTimeout` and `clearTimeout`. There is no test-only code in this module.
- Wire it into `apps/web-platform/server/index.ts`: arm after `server.listen`, and call `stop()` in
  the SIGTERM handler beside `clearInterval(ccIdleReaperTimer)`.
- **Exit:** the clock tests are GREEN.

#### Phase 2: Sentry monitors + workflow headers

- `apps/web-platform/infra/sentry/cron-monitors.tf`:
  - `zot_restart_loop_alarm.checkin_margin_minutes` 120 → **30**.
  - Rewrite both rationale comment blocks. They should state: primary trigger = the dispatch clock
    (ADR-246), GH `schedule:` = fallback, the margin-budget arithmetic above, and dead-trigger
    detection = interval + margin.
  - Crontabs are unchanged.
- Header comments only in both workflows: name the primary trigger and the fallback. **No
  functional YAML change.** The gate-override comment (`# <!-- gate-override: new-scheduled-cron-prefer-inngest -->`)
  stays as the first line, byte-identical.
- **Exit:** `sentry-monitor-iac-parity.test.ts` is fully GREEN, and
  `function-registry-count.test.ts` stays GREEN. `terraform -chdir=apps/web-platform/infra/sentry
  fmt -check` and `validate` pass.

#### Phase 3: ADR + C4 + runbooks

- Create `knowledge-base/engineering/architecture/decisions/ADR-246-watchdog-dispatch-clock-runs-in-the-web-server.md`.
  The ordinal is provisional, and `soleur:ship`'s ADR-ordinal gate re-checks it. On a renumber,
  sweep this plan and `tasks.md`.
- C4 edits (see the Architecture Decision section).
- Runbooks:
  - Add a "How the external watchdogs are triggered" subsection to
    `knowledge-base/engineering/operations/runbooks/inngest-server.md`. It answers four questions
    with commands, none of them SSH (CTO devex F3):
    1. **Is it running?** The Better Stack query `watchdog-dispatch-clock` grouped by host (through
       `scripts/betterstack-query.sh`), plus the `gh run list` cadence one-liner from AC11.
    2. **How do I stop it?** `gh workflow disable <file>` stops both the clock's dispatches (they
       422) and the fallback. A revert is the full removal.
    3. **How do I add or remove a table row?** The checklist: the table row with its
       `eligibility`, `workflow_dispatch:` plus `concurrency` with `cancel-in-progress: false` on
       the workflow, the margin rationale in `cron-monitors.tf`, the slug list in the Guard 1
       assertion, and the C4 edge prose.
    4. **Which host sent a run?** The tick logs.

    It also notes that `ci-deploy.sh`'s comment "The canary fires no crons" is no longer strictly
    true: the canary carries a clock for its few-minute life.
  - `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: fix the stale
    "`scheduled-zot-restart-loop.yml` (#6291, every 30 min)" to hourly, web-server-dispatched,
    with a pointer to the subsection above.
- **Exit:** `c4-count-parity.test.sh`, `c4-code-syntax.test.ts` and `c4-render.test.ts` are GREEN.

#### Phase 4: Verification

- Run targeted vitest in `apps/web-platform`, with
  `./node_modules/.bin/vitest run <paths>`, on:
  - `watchdog-dispatch-clock.test.ts`
  - `inngest/sentry-monitor-iac-parity.test.ts`
  - `inngest/function-registry-count.test.ts`
  - `inngest/cron-main-health-monitor.test.ts` (untouched, as a sanity check)
  - `c4-code-syntax.test.ts`
  - `c4-render.test.ts`
- Also run `bash plugins/soleur/test/c4-count-parity.test.sh` and
  `bash .claude/hooks/new-scheduled-cron-prefer-inngest.test.sh`.
- Nothing is ever dispatched from a dev machine. The clock is exercised only through injected
  dependencies.

## Files to Create

- `apps/web-platform/server/watchdog-dispatch-clock.ts`
- `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-246-watchdog-dispatch-clock-runs-in-the-web-server.md` (provisional ordinal)

## Files to Edit

- `apps/web-platform/server/index.ts`: arm after listen, stop on SIGTERM.
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`: the Guard 1 describe
  block.
- `apps/web-platform/infra/sentry/cron-monitors.tf`: zot margin 120 → 30, plus both rationale
  comments.
- `.github/workflows/scheduled-inngest-health.yml`: header comment only.
- `.github/workflows/scheduled-zot-restart-loop.yml`: header comment only.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: a new `api -> github` edge, plus
  three prose fixes located by anchor text (see ADR/C4).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: the trigger subsection.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: the stale zot cadence.
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`:
  a one-line cross-reference under the anti-circularity corollary.

## Alternative Approaches Considered

The option table under Proposed Solution is the decision record, and ADR-246 carries it.

- **Cloudflare Worker (option B)** is the named upgrade path. The trigger is **#7230** (Inngest
  execution decoupled from web-1), or a Workers substrate plus a narrow single-repo
  `actions:write` GitHub App appearing. **Work phase:** file a `deferred-scope-out` issue
  (`wg-when-deferring-a-capability-create-a`): "External (Cloudflare Worker) dispatch clock for
  watchdogs if web-host coupling matters", to be re-evaluated when #7230 lands.
- **v1 of this plan used a self-re-arming `setTimeout` chain**, and plan-review replaced it with
  polling (see the note under Proposed Solution).
- **A bespoke cadence-probe script was cut.** AC12 reads Sentry, and AC11 uses `gh run list`
  instead.
- **Other GHA-cron watchers** (e.g. `scheduled-prod-version-drift`, margin 360) are **not** added.
  They are not watchers of the scheduling substrate, so under ADR-246's eligibility rule they
  belong on the Inngest dispatch pattern (`main-health-monitor`). That is separate work, and this
  plan files nothing for it.

## User-Brand Impact

- **If this lands broken, the user experiences:** silent Inngest outages lasting hours, the same as
  today. Users' scheduled agents, reminders and crons stop firing, and nobody is paged.
  - A second failure shape is a mis-armed clock that dispatches far too often. That spams the
    watchdog, whose restart arm then targets the web-host Inngest unit. Post-cutover that unit is
    quiesced, and the restart cannot reach 10.0.1.40.
  - That shape is bounded in three ways: one handled tick per slot per host, concurrency-group
    queueing, and the watchdog's 45-min give-up window.
- **If this leaks, the user's workflow is exposed via:** a GitHub App installation token logged in
  a dispatch error.
  - The token is scoped to `actions:write` on `jikig-ai/soleur` only (`repositories: [REPO_NAME]`)
    and is redacted by `redactToken` before any log or Sentry event.
  - No user data flows through this path. The clock sends a workflow filename and `ref: main`.
- **Brand-survival threshold:** `aggregate pattern`. The harm is platform-wide detection latency,
  not one user's data. No per-PR CPO sign-off is needed.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitors scheduled-inngest-health (*/15, margin 15) and scheduled-zot-restart-loop (0 * * * *, margin 30), fed by each workflow's final sentry-heartbeat step; after this change they measure clock + dispatch + run end to end"
  cadence: "15 min (inngest-health) / 60 min (zot); a dead trigger pages within interval + margin = 30 min / 90 min"
  alert_target: "Sentry monitor-failure issue -> operator page (failure_issue_threshold = 1)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (sentry_cron_monitor.scheduled_inngest_health, sentry_cron_monitor.zot_restart_loop_alarm); clock table in apps/web-platform/server/watchdog-dispatch-clock.ts"

error_reporting:
  destination: "Sentry web-platform project via reportSilentFallback (@/server/observability), feature=watchdog-dispatch-clock, op in {arm, mint, dedup-read, dispatch}, extra.workflow, extra.reason in {timeout, http, throw}"
  fail_loud: "info log 'watchdog-dispatch-clock tick' with {host, slot, workflow, outcome} on every tick; outcome=failed plus a Sentry event per failed tick; boot line 'watchdog-dispatch-clock disarmed reason=...' plus an op=arm Sentry event when disarmed in production"

failure_modes:
  - mode: "clock disarmed in production (SOLEUR_HOST_ID missing)"
    detection: "op=arm Sentry event at boot; Sentry missed check-in within 30 min if every host is disarmed"
    alert_route: "Sentry issue + monitor-failure page"
  - mode: "dispatch returns 4xx/5xx (workflow disabled, scope wrong, GitHub API outage)"
    detection: "reportSilentFallback op=dispatch per failed tick; the other host's tick may still succeed; missed check-in if all fail"
    alert_route: "Sentry issue + monitor-failure page"
  - mode: "dedup read fails"
    detection: "reportSilentFallback op=dedup-read; the tick still dispatches (fail-open)"
    alert_route: "Sentry issue (non-paging)"
  - mode: "tick hangs"
    detection: "90 s tick deadline -> reason=timeout event; inFlight cleared so the next slot proceeds"
    alert_route: "Sentry issue"
  - mode: "one web host down"
    detection: "Better Stack uptime (web-1 serves the app); the other host keeps dispatching, so no missed check-in"
    alert_route: "Better Stack incident"
  - mode: "both web hosts down"
    detection: "Better Stack uptime; Sentry missed check-in within 30 min; GH schedule fallback still runs late"
    alert_route: "Better Stack incident + Sentry page"
  - mode: "systematic duplicate dispatches"
    detection: "tick logs show two outcome=dispatched for one {workflow, slot}; gh run list shows two workflow_dispatch runs within one slot"
    alert_route: "postmerge AC11 read; non-paging (duplicates are harmless)"

logs:
  where: "web container stdout (pino) -> journald (--log-driver journald) -> Vector -> Better Stack Logs, hosts soleur-web-1 and soleur-web-2 (web-2 ships per ADR-143 R1(c)); search 'watchdog-dispatch-clock'"
  retention: "Better Stack Logs source retention (existing web-platform source policy)"

discoverability_test:
  command: "curl -fsS --max-time 10 https://api.github.com/repos/jikig-ai/soleur/actions/workflows/scheduled-inngest-health.yml/runs?per_page=3"
  expected_output: "workflow_runs"
```

The `discoverability_test` reads the public Actions runs list, which is the signal that shows
cadence, without auth. It proves an operator can read that signal locally and without SSH. It
does not assert health: AC11 and AC12 do that after the merge.

## Encryption Posture

```yaml
at_rest:
  - store: "none introduced — the clock keeps only per-entry in-memory state (handledSlot, inFlight) and the existing in-memory installation-token cache; sentry_cron_monitor edits are configuration, not a data store"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/server/watchdog-dispatch-clock.ts performs no file/DB/queue write — its injected-deps surface is only mint, read, dispatch, report, log, timers"
    defends_against: "nothing at rest is written, so there is no at-rest artifact to seize"
    does_not_defend: "a compromised web host process can read the in-memory token (1 h lifetime, actions:write on one repo)"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: no store exists to verify"
in_transit:
  - connection: "web-platform container (web-1, web-2) -> api.github.com (existing connection class, same as cron-main-health-monitor)"
    enforced_at: "apps/web-platform/server/inngest/functions/cron-main-health-monitor.ts (Octokit default HTTPS transport, no custom agent); mirrored in watchdog-dispatch-clock.ts"
    tls: "HTTPS, TLS 1.2+ (Node default)"
    cert_verification: "on"
    does_not_defend: "a compromised web host process, or a stolen installation token used before expiry"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "No data store is introduced; the plaintext-exception row records in-memory state that every App-token caller already has"
  tracking_issue: "#8495"
  reevaluate_when: "the clock ever persists state (a durable cursor or a DB slot claim) or moves off the web hosts"
  expires_on: "2026-12-20"
```

## Guard Contract

### Guard 1 — Watchdog dispatch table ↔ workflow ↔ Sentry monitor parity

**Property.** Every entry in `WATCHDOG_DISPATCH_TABLE` meets all of the following:

- it has a non-empty `eligibility`;
- its workflow has a `workflow_dispatch` trigger, and `concurrency.group` with
  `cancel-in-progress: false`;
- its workflow's fallback `on.schedule` includes the interval's crontab;
- its `sentry-heartbeat` `monitor-slug` equals the table slug;
- the same-named `sentry_cron_monitor` has that crontab and a `checkin_margin_minutes` in
  `[MARGIN_FLOOR, intervalMinutes]`, so a dead trigger pages within `2 × interval`. `MARGIN_FLOOR`
  = 12, derived from the margin budget (jitter 2.5 + poll 0.5 + runtime 8), not arbitrary.

`scheduled-inngest-health` is additionally pinned to `intervalMinutes <= 15`, with an assertion
message that cites #8495.

**Assembly.** The chokepoint is `WATCHDOG_DISPATCH_TABLE`, the only array
`startWatchdogDispatchClock` iterates. The new describe block in
`sentry-monitor-iac-parity.test.ts` imports it and reuses that file's existing extractors
(`workflowCrons`, `monitorCrontabBySlug`, `heartbeatSlugFiles`). It reads each member's
`.github/workflows/<file>` and `cron-monitors.tf`. The pure predicate `marginWithinBudget(margin,
interval)` lives in the test file, not in production code.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `sentry_cron_monitor.zot_restart_loop_alarm.checkin_margin_minutes` back to 120 | RED |
| 2 | Empty `WATCHDOG_DISPATCH_TABLE` (own dispatch). The block asserts that the table's slugs **equal** `{scheduled-inngest-health, scheduled-zot-restart-loop}` and that `checked === table.length`, so "0 checked" cannot pass | RED |
| 3 | Append a third, non-compliant entry after the two compliant ones: `{scheduled-prod-version-drift.yml, 15, eligibility: ""}` | RED (the second member after a compliant first, plus empty eligibility) |
| 4 | Remove `workflow_dispatch:` from `scheduled-zot-restart-loop.yml` | RED |
| 5 | Set `cancel-in-progress: true` on `scheduled-inngest-health.yml` | RED |
| 6 | Change the inngest workflow's `monitor-slug:` to `scheduled-inngest-health-x` | RED (the existing #6374 block plus the new block) |
| 7 | Relax inngest to `intervalMinutes: 30`, moving its cron and monitor to `*/30` in the same diff (consistent but slower) | RED (the #8495 pin) |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Make the block's `workflowCrons` call return `[]` | RED (the crontab-membership assertion fails for every member) |
| H2 | Must-PASS: `marginWithinBudget(15, 15)` (margin equals interval, the inclusive boundary) and `marginWithinBudget(20, 30)` (non-canonical, permitted) | PASS (a predicate that rejects everything fails here) |

**Anchor.** One diff can edit all three files consistently, so the guard proves consistency. Row 7
is the anchor: the `<= 15` pin is a named assertion that cites #8495, so slowing the cadence means
deleting a reviewable line rather than moving three values. The live Sentry config is re-read at
postmerge (AC12).

### Guard 2 — A tick can never take the server down or stall the clock

**Property.** Whatever a tick does, whether it dispatches, skips, throws in mint, read or
dispatch, hangs past the deadline, or has `report` itself throw:

- no `unhandledRejection` is emitted;
- the entry's `inFlight` is cleared;
- the next due slot is ticked;
- after the tick settles, no timer is left pending except the one poll interval (no leaked
  deadline timer).

**Assembly.** The single chokepoint is `runTickSafely(entry, S)`. It is the only caller of the
tick body, and the poll loop is its only caller. It holds the `withTimeout` race, the catch, and the
`finally` that clears `inFlight` and sets `handledSlot`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `.catch` on `runTickSafely`, then inject a mint that rejects | RED: a `process.on("unhandledRejection")` spy records a call |
| 2 | Drop the try/catch around `report`, then inject a `report` that throws | RED: same spy |
| 3 | Move the `inFlight = false` from `finally` into the success path (a REORDER, not a delete), then inject a dispatch that rejects | RED: the next slot's tick never runs, and the case observes at the next due slot |
| 4 | Remove the `clearTimeout` from `withTimeout` | RED: `vi.getTimerCount()` after the tick settles is 2, not 1 |
| 5 | Poll only the first table entry (`table.slice(0, 1)`) | RED: the zot entry is never ticked (the second member) |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Never advance the fake timers (the poll would never run) | RED: the case asserts exactly 1 POST |
| H2 | Must-PASS: a tick whose dedup read throws still dispatches, and the next slot still ticks | PASS |

**Anchor.** None outside the commit. This is a behavioural property of code under test.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` (existing root; provider `jianyuan/sentry`
  pinned at `0.15.7` in `versions.tf`):
  - `sentry_cron_monitor.zot_restart_loop_alarm.checkin_margin_minutes` 120 → 30;
  - comment-only edits on `sentry_cron_monitor.scheduled_inngest_health`.
- No new resources, variables, providers or secrets. The clock reuses
  `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY`, which are already in the web runtime env from Doppler
  `prd`.

### Apply path

The apply is Terraform-only and in place, and neither path involves a human step.

- **Sentry change.** On merge to main, `.github/workflows/apply-sentry-infra.yml` applies it. It is
  push-triggered, plans the full root, and runs in `environment: infra-privileged` with a
  deployment-branch policy and no reviewer gate. There is no downtime.
- **The clock.** It ships in the web-platform image through `.github/workflows/web-platform-release.yml`
  (push on `apps/web-platform/**`), fanned out to both web hosts.
- **Merging this PR alone mutates production** through these two push-triggered workflows.

### Distinctness / drift safeguards

- The Sentry monitors exist in prd only. Deployed containers are always Doppler `prd`, because
  `ci-deploy.sh` downloads `--config prd`, and nothing else sets `SOLEUR_HOST_ID`.
- `scheduled-sentry-drift` (#6612, #8679) covers monitor drift.
- No `lifecycle.ignore_changes` is involved.

### Vendor-tier reality check

- No new Sentry monitors are added.
- GitHub Actions: inngest-health moves from about 11 to 96 runs/day, and zot from about 11 to 24.
  - Each run is short, and the repo is public, so standard-runner minutes are free.
  - Concurrency: inngest-health runs the probe (≈6 min) and the census (≈5 min) in parallel.
    96 × 11 min / 1440 ≈ 0.7 of a slot on average, plus a little for zot, against the org's 20-job
    budget (#8450). That is small next to the measured ~29 runs/h PR fan-out.

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-246** (provisional ordinal): *"Watchers of the scheduling substrate are triggered
  by an in-process web-server dispatch clock, not by Inngest or by GitHub cron alone."* Keep it
  short. It covers:
  - the decision;
  - the failure-domain table;
  - the eligibility rule: the explicit, narrow exemption from ADR-063 /
    `new-scheduled-cron-prefer-inngest`, plus the required `eligibility` field;
  - how ADR-033's anti-circularity corollary is satisfied: two web-host clocks, the native
    `schedule:` fallback, and Sentry as the outer layer;
  - the fleet-uniqueness rule in one sentence. ADR-027 is one replica per host, so a
    side-effecting in-process timer must dedup fleet-wide (here: jitter plus the slot-scoped read);
  - the rejected alternatives (the option table);
  - the reversal triggers: #7230, or a Workers substrate plus a narrow dispatch App.

  Risks (restored escalations, comment volume, the canary) stay in this plan and the PR body, not
  in the ADR.
- **Amend** ADR-033 with a single cross-reference line under the anti-circularity corollary that
  points to ADR-246.

### C4 views

All three files were read in full: `model.c4`, `views.c4` and `spec.c4`.

**Enumeration.** Everything the change touches is already modeled:

- **External actors:** none new. `publicReader` already receives the zot and inngest issue bodies.
- **External systems:** `github`, `sentry`, `betterstack` and `zotRegistry` are modeled and are
  already in the `context` and `containers` views.
- **Containers:** `platform.webapp.api` and `platform.infra.inngest` are modeled.
- **The changed relationship:** `api -> github` gains a workflow_dispatch role.

**Edits.** These are located by anchor text (`cq-cite-content-anchor-not-line-number`):

1. Add a second `api -> github` edge next to the existing edge whose description begins
   "Workstream tab: reads connected-repo issues":
   - description: "Watchdog dispatch clock (#8495, ADR-246): an in-process poll on each web host
     (not Inngest) dispatches scheduled-inngest-health.yml every 15 min and
     scheduled-zot-restart-loop.yml hourly with an actions:write App token; `schedule:` crons stay
     as fallback; check-ins still flow github -> sentry";
   - `technology "HTTPS (GitHub REST workflow dispatches, App installation token)"`.

   `views.c4` needs no change: both endpoints are already in `containers`, and `context` derives
   `platform.webapp -> github`.
2. In the `github -> sentry` edge, the sentence containing the anchor "8 GHA-`schedule:`-fired"
   gets a parenthetical: "(scheduled-inngest-health and -zot-restart-loop are also fired by the
   web server's dispatch clock, #8495)". **Every number, and the anchor phrases "8 GHA-`schedule:`-fired"
   and "and 6 `workflow_dispatch`-only", stay verbatim.** `c4-count-parity.test.sh` greps them, and
   C2/C3 are derived from `on.schedule` presence, which does not change.
3. In the tunnel element, the text "*/15 connector census in scheduled-inngest-health.yml" becomes
   "…(web-server-dispatched every 15 min, #8495; GHA cron fallback)".
4. Fix the comment "(scheduled-zot-restart-loop.yml, */30)" to "(scheduled-zot-restart-loop.yml,
   hourly, web-server-dispatched — #8495)".

The pre-existing overclaim in the `api -> supabase` edge ("every GitHub App-token use") is **not**
edited here. It was already false for every `mintInstallationToken` caller. The work phase files it
as a separate issue.

After the edits, run `plugins/soleur/test/c4-count-parity.test.sh`,
`apps/web-platform/test/c4-code-syntax.test.ts` and `apps/web-platform/test/c4-render.test.ts`.

### Sequencing

The ADR is `accepted` at merge. The decision holds as soon as the image deploys, and nothing is
gated on a soak.

## Open Code-Review Overlap

2 open scope-outs touch these files:

- **#8595** (monitor registry guard gaps: stale `NON_INNGEST_MONITORS` entries, no margin parity)
  names `sentry-monitor-iac-parity.test.ts`. **Acknowledge.**
  - Its main ask is a reverse-direction staleness check in `function-registry-count.test.ts`, which
    is a different concern.
  - Its "related gap" bullet (cron ≡ crontab plus a margin convention) is partly met, for the two
    dispatched slugs, by Guard 1, which lives in that very file.
  - The work phase leaves a one-line comment on #8595 saying so, and the issue stays open.
- **#8593** (the `gh` enumeration gate is narrower than its property) cites
  `.github/workflows/scheduled-inngest-health.yml`. **Acknowledge.** That is lint coverage in
  `components.test.ts`. This plan adds no `gh … list` enumeration, and the clock's read is REST
  `per_page=1`.

## Risks

- **Restored escalation behaviour.** At a 15-min cadence, the 45-min give-up window allows about 3
  restart dispatches per `[ci/inngest-down]` incident, as #6374 designed. Today it allows at most 1.
  - **The blast radius is small post-cutover.** The workflow's own dedicated-host arm states that
    `restart-inngest-server.yml` "is LB-routed to the web host and cannot reach 10.0.1.40".
  - **The scoped advisor's suggestion was weighed and not adopted.** It proposed moving the restart
    budget to a persisted last-restart timestamp in a separate PR first. Reasons for not adopting:
    - 45 min is the #6374 design;
    - a restart cannot reach the live scheduler;
    - a collision adds at most one restart per colliding slot.
  - The criterion stays here: if a post-merge incident shows more than about 4 restarts, the
    follow-up is exactly that change. Recorded in `decision-challenges.md`.
  - The `functions_query_degraded` 45-min persistence ceiling is also reachable again. This is
    intended.
- **Issue-comment volume during an incident.** Each run comments on its open tracker, up to 4 per
  hour for inngest-health. On 2026-09-24, zero such trackers were open across all eight labels.
  This is accepted. If it proves noisy, the follow-up is comment dedup in the workflow, not a
  slower clock.
- **Transient page at merge.** The zot margin tightens in minutes, while the image deploys in tens
  of minutes. Both monitors already sit in a standing `missed` state, and repeats are silent
  (#7142), so no new page is expected. The first dispatched runs flip them to `ok`.
- **Duplicate runs.** Up to three clocks exist (web-1, web-2 and the canary), plus GH ticks.
  - With jitter and the slot-scoped read, a collision is estimated at about 5% of slots. That
    figure is an estimate (uniform 120-s window, ~3 s visibility), not a measurement.
  - A collision yields one serialized, harmless duplicate.
  - If postmerge shows systematic duplicates, the named escalation is a DB slot claim (ADR-246).
- **GitHub API dependency.** If api.github.com is down, both the clock and the fallback fail, and
  Sentry reports missed check-ins. This is accepted.
- **Classifier coverage (out of scope).** Which label a run inside the 09-22 window would have
  filed is not changed here.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6. This one is filled (`aggregate pattern`).
- **Do not remove or reword the `schedule:` cron strings.** The #8450 parity test needs the
  monitor crontab to be among the workflow's crons, Guard 1 checks the same thing, and the C4
  C2/C3 counts are derived from `on.schedule` presence.
- **Do not reword the C4 anchor phrases.** `c4-count-parity.test.sh` greps them verbatim.
- The gate-override comment must stay the first line of both workflows, byte-identical. Header
  edits go below it.
- **The arm predicate must use `SOLEUR_HOST_ID`**, which only the deploy injects, **not**
  `NODE_ENV` alone. CI and e2e run with `NODE_ENV=production`, and a CI job that dispatched real
  workflows would be a self-inflicted storm.
- **Every error path must be fenced.** `crash-handlers.ts` exits on `unhandledRejection`, so a
  forgotten `.catch` in the clock would take down the user-facing server (Guard 2).
- **The ADR-246 ordinal is provisional.** On a renumber, run
  `grep -rn 'ADR-246' knowledge-base/project/{plans,specs}/` and sweep.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed, in two passes: a Phase 2.5 structural assessment and a plan-review devex
lens.

**Assessment.** The direction is approved. The in-process clock satisfies ADR-033's
anti-circularity rule: the watched subject is the dedicated Inngest host, and the loss of a web
host is covered by the other host's clock, the GH fallback, and Sentry. The Cloudflare Worker was
correctly rejected as the primary mechanism (custody plus a hand-minted token) and kept as the
upgrade path tied to #7230. `Closes #8495` is justified because both the deploy and the Sentry
apply run on merge.

**Findings folded in:**

- web-2 runs a second clock all the time: addressed with per-slot jitter plus the slot-scoped
  read.
- The age-based dedup caused false misses: replaced with the slot-scoped skip.
- The canary carries a clock: noted in the runbook.
- Margin arithmetic: added to the `cron-monitors.tf` rationale.
- Devex:
  - the runbook answers "running?", "stop?", "change the table?" and "which host?";
  - every tick is logged at info level;
  - the `eligibility` field is required and the "one-row change" wording is fixed;
  - there is a change-the-table checklist.

**Declined, with reasons:**

- A Flagsmith kill-switch flag. This is taste and is recorded in `decision-challenges.md`.
  `gh workflow disable` plus a revert already cover the emergency stop.
- `mirrorWarnWithDebounce` for 422 floods. Its 5-min TTL is shorter than the cadence, so it would
  suppress nothing.

**Other domains** were assessed and found not relevant:

- **Product/UX:** no user-facing surface, and the UI-surface override did not fire.
- **Legal/GDPR:** no personal data moves.
- **Operations/Finance:** no new vendor or spend.
- **Marketing/Sales/Support:** none.

**Spec-flow (Phase 3).** Its 3 P0s were all folded in: the age-window false miss, the hung call,
and the unhandled rejection. The polling redesign then made its chain-specific P1/P2s moot.

**Plan-review panel:** DHH, Kieran and code-simplicity (eng), plus CTO (devex).

- Simplification and correctness converged on the chain. Per plan-review guidance, the plan
  prefers delete over fix: the chain was replaced by polling, and the probe script was cut.
- Kieran's findings were applied: the token's repository scope, the `op` enum, the arm reporting,
  host framing, anchor citations, the late cutoff, and the concurrency estimate.

## Test Scenarios

### Clock (`apps/web-platform/test/server/watchdog-dispatch-clock.test.ts`, RED first)

- **C1 Arm predicate.**
  - `production` with host id `"  "` → disarmed, with one `op=arm` report.
  - `test` with a host id → disarmed, with no report.
  - `production` with `hetzner-123` → armed, with one interval timer.
- **C2 Slot math.**
  - `slotStartAt(:15:30.000, 15)` = `:15:00`.
  - `slotStartAt(00:00:00, 60)` = `00:00`.
- **C3 Skip, same slot.** The newest run was created at `:15:02` (a GH tick). The poll at `:15:40`,
  with jitter 30 s, makes no POST, and the outcome is `skipped_slot_has_run`.
- **C4 Regression against the age window.** The newest run was created at `:05`. The poll at
  `:15:40` makes a POST.
- **C5 Empty list.** With zero runs, the tick makes a POST.
- **C6 Read fails.** The runs read throws. The tick still makes a POST, reports `op=dedup-read`, and
  the next slot still ticks.
- **C7 Failures.** Each case must report with the token string absent from the payload (the
  `redactToken` check), clear `inFlight`, make the next slot tick, and never fire the
  `unhandledRejection` spy:
  - the mint throws (`op=mint`, `reason=throw`);
  - the dispatch returns 422 (`op=dispatch`, `reason=http`, `status=422`);
  - the dispatch never settles and the 90-s deadline is advanced (`reason=timeout`).
- **C8 Stale queued run.** The newest run is `queued` and was created 20 min ago. The tick makes a
  POST.
- **C9 Once per slot.** Five consecutive polls inside one due slot make exactly one read and at
  most one POST.
- **C10 Late cutoff.** A process that boots at `S + 13:30` on a 15-min entry does not tick slot
  `S`, and does tick `S + 15`.
- **C11 Two hosts.** Two clock instances share one fake GitHub, with jitters of 40 s and 100 s,
  and a run becomes visible 3 s after its POST. The slot gets exactly 1 POST.
- **C12 Token scope and request shape.**
  - The mint is called with `permissions: { actions: "write" }` and `repositories: ["soleur"]`.
  - The POST goes to `/repos/jikig-ai/soleur/actions/workflows/scheduled-inngest-health.yml/dispatches`
    with body `{ ref: "main" }`.
- **C13 Stop.** `stop()` → 0 timers. A tick still in flight settles without scheduling anything.

### Parity (new describe block in `sentry-monitor-iac-parity.test.ts`)

- **P1 Live repo.** Every Guard 1 property holds. The table slugs equal the expected set, and
  `checked === table.length`.
- **P2 `marginWithinBudget`.** Test the boundary cases H2 against the predicate, plus a
  must-RED case `(120, 60)`.
- **P3 The #8495 pin** holds, and its assertion message cites the issue.

### Regression

- The #8495 trigger condition is GitHub delivering `*/15` at a 2–7 h cadence. Given that condition,
  when the clock is armed, then `scheduled-inngest-health` gets one `workflow_dispatch` run per
  15-min slot. Covered by C3/C4/C9/C11 and, live, by AC11.

## Acceptance Criteria

### Pre-merge

- [ ] **AC1** Scenarios C1–C13 are written first and seen failing (RED) against a stub, then pass
  with
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/watchdog-dispatch-clock.test.ts`.
- [ ] **AC2** `./node_modules/.bin/vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts
  test/server/inngest/function-registry-count.test.ts test/server/inngest/cron-main-health-monitor.test.ts`
  passes. Guard 1 rows 1, 2, 3 and 7 were each applied once locally and observed RED. The work log
  records the four RED outputs.
- [ ] **AC3** In `apps/web-platform/infra/sentry/cron-monitors.tf`:
  - `zot_restart_loop_alarm` has `checkin_margin_minutes = 30`;
  - `scheduled_inngest_health` stays at `15`;
  - both crontabs are byte-identical to `origin/main`;
  - `terraform -chdir=apps/web-platform/infra/sentry validate` passes, and `fmt -check` is clean.
- [ ] **AC4** The C4 checks are green, and the new `api -> github` watchdog edge exists:
  - `bash plugins/soleur/test/c4-count-parity.test.sh` passes 10/10, with C1–C6 unchanged;
  - `c4-code-syntax.test.ts` passes;
  - `c4-render.test.ts` passes.
- [ ] **AC5** The workflow diffs are comment-only. This must print nothing:

  ```bash
  git diff origin/main -- .github/workflows/scheduled-inngest-health.yml .github/workflows/scheduled-zot-restart-loop.yml \
    | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*(#|$)'
  ```

  `head -1` of each file still equals `# <!-- gate-override: new-scheduled-cron-prefer-inngest -->`.
- [ ] **AC6** `ADR-246-*.md` exists with its Decision, the failure-domain table, the eligibility
  rule, Alternatives, and reversal triggers. ADR-033 carries the cross-reference. The ordinal was
  re-verified at ship.
- [ ] **AC7** `bash .claude/hooks/new-scheduled-cron-prefer-inngest.test.sh` passes.
- [ ] **AC8** The PR body is correct:
  - its first line states that merging this PR alone changes production, through
    `web-platform-release.yml` (the clock) and `apply-sentry-infra.yml` (the zot margin), with no
    dispatch;
  - it uses `Closes #8495`, not in the title;
  - it links the Cloudflare Worker `deferred-scope-out` issue, the #8595 comment, and the separate
    C4 `api -> supabase` overclaim issue.

### Post-merge (production, all API-read; `hr-no-dashboard-eyeball-pull-data-yourself`)

- [ ] **AC9** Within 30 min of `web-platform-release.yml` completing:
  `bash scripts/betterstack-query.sh` returns `watchdog-dispatch-clock armed` for both
  `soleur-web-1` and `soleur-web-2`, and no `disarmed` row.
- [ ] **AC10** At least 50 min after the deploy, the Sentry API reports the `scheduled-inngest-health`
  and `scheduled-zot-restart-loop` monitors as `ok`, and the live `zot_restart_loop_alarm` margin
  reads 30.
- [ ] **AC11** At least 50 min after the deploy, measure the gaps with:

  ```bash
  gh run list --workflow scheduled-inngest-health.yml --limit 20 --json createdAt,event \
    | jq --arg since "<deploy ISO>" '[.[] | select(.createdAt >= $since)] | sort_by(.createdAt)
        | {n: length, dispatched: map(select(.event=="workflow_dispatch")) | length,
           max_gap_min: ([range(1;length) as $i | ((.[$i].createdAt|fromdate) - (.[$i-1].createdAt|fromdate))/60] | max // 0)}'
  ```

  It must report `dispatched >= 3` and `max_gap_min <= 17`. No two `workflow_dispatch` runs may
  fall in one 15-min slot more than once.

  If AC9–AC11 fail, postmerge reopens #8495 with the output attached.
