---
title: "fix: cron machinery — verify-list race false-red, queue-health scheduler-deferral pages, stale bot-PR merge stall"
type: fix
date: 2026-09-30
slug: fix-cron-machinery-monitoring-integrity
branch: feat-one-shot-9272-9273-9274-cron-machinery
issue: 9272
closes: [9272, 9273, 9274]
priority: p1-high
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: cron machinery — verify-list race false-red, queue-health scheduler-deferral pages, stale bot-PR merge stall

## Enhancement Summary

**Deepened on:** 2026-09-30
**Sections enhanced:** Proposed Solution (Fix 3 reaper design), Observability, Dependencies & Risks
**Research agents used:** inline sequential-fallback (no subagent tool in this runtime) — live REST probes (`gh api`), GitHub REST docs fetches, parity-guard source reads

### Key Improvements

1. **Reaper token grant gains `checks: "read"`** — the settle-guard's `GET /commits/{sha}/check-runs` requires it for GitHub App tokens (docs + `x-accepted-github-permissions` evidence); the plan's three-grant set would have 403'd the guard's only read.
2. **`expected_head_sha` CAS on update-branch** — the endpoint accepts it and 422s on mismatch; binds the update to the same head whose check-runs the settle-guard verified terminal.
3. **Per-sweep update cap** — live probe showed ~24 armed `soleur-ai[bot]` PRs (back to 2026-08-04), not 3–4: an uncapped first sweep would launch ~24 check-run sets into the runner pool `scheduled-actions-queue-health` measures, and every merge re-`behind`s the rest under strict up-to-date rules. Cap ≤5/sweep, oldest-first; arrival rate ~1/day so the backlog drains.
4. **Observability probe anchored** — `rg -c` on bare slugs over-counts the moment a comment repeats a resource name (the file's convention already embeds underscored names in comments); anchored to `^resource "sentry_cron_monitor" "(…)"` declarations instead, same literal `2`.

### New Considerations Discovered

- `mergeable_state` gains a fallthrough arm (unrecognized value → skip + warn) for forward-compat beyond the 8 documented states.
- REST `user.login` = `soleur-ai[bot]` (verified live on #9205) but GraphQL `author.login` = `app/soleur-ai` — the REST predicate is correct; a "fix" to `app/soleur-ai` would silently empty the reaper's population.
- The `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` marker line must survive the workflow header rewrite (the PreToolUse hook keys on it).

## Overview

Three latent cron-machinery defects produced the 2026-09-30 incident window (post-mortem exists, untracked, in the main checkout):

1. **#9272** — `verifyScheduledIssueCreated` (`apps/web-platform/server/inngest/functions/_cron-shared.ts:942`) performs a single point-in-time GitHub issues-list read. A just-filed labelled issue not yet visible in the list view is declared absent → `resolveOutputAwareOk` reports `scheduled-output-missing` → the heartbeat goes red AND the persistence gate is skipped, discarding the run's real artifacts (the 9/30 community-monitor digest was dropped despite a fully successful run; same shape 9/27).
2. **#9273** — `scheduled-actions-queue-health` pages on `missed` check-ins, but its `on.schedule '*/30'` trigger is deferred by GitHub to ~4 runs/day under org load. `checkin_margin_minutes: 30` (`apps/web-platform/infra/sentry/cron-monitors.tf:1471`) makes every deferred slot a page: ~47 pages/day while the probe's verdict is `HEALTHY` whenever it lands.
3. **#9274** — `app/soleur-ai` cron-artifact PRs (`ci/*` branches) sit open with auto-merge armed and all checks green but `mergeable_state: "behind"`; nothing updates the branch, so digests 9/27–30 never reached `main`. Verified live: PR #9205 `{auto_merge: true, user: soleur-ai[bot], head: ci/community-monitor-…}`.

One PR fixes all three and commits the incident post-mortem. `Closes #9272 #9273 #9274` in the PR body — all fixes deploy via merge-triggered pipelines (web-platform release container restart + `apply-sentry-infra.yml` on `infra/sentry/**`).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9272|9273|9274` — all OPEN, bodies confirmed. #9272's claimed code shape verified: `verifyScheduledIssueCreated` issues exactly one `client.request("GET /repos/{owner}/{repo}/issues", …)` call (`_cron-shared.ts:958`) with no retry; its only production caller is `resolveOutputAwareOk` (`_cron-shared.ts:1376`), which every output-aware cron wraps in `step.run("verify-output")`.
- #9273's claimed config verified: monitor `schedule = { crontab = "*/30 * * * *" }`, `checkin_margin_minutes = 30` (cron-monitors.tf:1470-1471); workflow `on.schedule - cron: '*/30 * * * *'` (scheduled-actions-queue-health.yml:47-48). The "missed ⇒ starvation" premise is written into both comments.
- #9274's claimed state verified live: `gh api repos/jikig-ai/soleur/pulls/9205` → `auto_merge` armed, `mergeable_state:"unknown"` (computed lazily), `user.login:"soleur-ai[bot]"`, `head:"ci/community-monitor-2026-09-29-080016"`.
- #8683 (BEHIND auto-sync merge livelock) read for context: its proposed Option A — settle before syncing — informs the reaper's settle-guard. #8683 itself is NOT in scope (it governs `plugins/soleur/scripts/sync-pr-behind.sh`, the ship-pipeline per-PR resync; this plan adds a different actor on a different population).
- Cited ADRs checked against the corpus (Phase 0.6 step 4 — mechanism-vs-ADR): ADR-033's Option-C rejection is scoped to agent-loop crons and its own 2026-06-02 scope note explicitly blesses Inngest→`workflow_dispatch` for non-agent-loop infrastructure work; the anti-circularity corollary (#6808) asks *"if the thing being checked fails completely, can the trigger still fire?"* — for queue-health the checked thing is the GitHub runner queue, and an Inngest dispatch fires from the web/Inngest substrate regardless of runner availability, so the corollary does NOT block dispatch. ADR-248's eligibility rule says a watcher that can be Inngest-scheduled uses "the Inngest dispatch pattern" (a dedicated `cron-*-dispatch.ts`, per cron-main-health-monitor), not `WATCHDOG_DISPATCH_TABLE` (reserved for watchers of the scheduling substrate itself). ADR-260/#9168 is the direct precedent for dispatch-primary + `schedule:` fallback. No ADR rejects a stale-bot-PR reaper.
- Stale claim caught and corrected: the workflow header + `model.c4` edge prose assert queue-health's native schedule is deliberate because "an Inngest dispatch would make the probe depend on liveness of the queue being measured." That conflates trigger delivery with execution substrate: the dispatch only POSTs `workflow_dispatch` (Inngest + GitHub REST, no runner needed); the executor still lands in the measured runner queue, preserving the self-referential starvation signal. The premise failed because `on.schedule` deferral made absence ambiguous — deferral is not starvation. This plan updates both comment sites and the C4 edge.

### Property List (Phase 0.6b)

- **P1** — A just-filed labelled issue that becomes list-visible within ~30 s is credited as producer output (no false red, no discarded artifacts).
- **P2** — List-view lag stays measurable when a retry recovers (non-paging warn marker).
- **P3** — `scheduled-actions-queue-health` does not page when the only anomaly is `on.schedule` deferral.
- **P4** — True runner starvation still pages (missed check-in when no executor can land; `UNDER_ASSIGNED` verdict on landed runs unchanged).
- **P5** — `soleur-ai[bot]` PRs with auto-merge armed do not sit `mergeable_state:"behind"` for >~3 h unactioned; digests land on `main` daily again.
- **P6** — A bot PR unmergeable for reasons `update-branch` cannot fix (conflict, failing checks, review gate) produces a loud signal instead of silent stall.
- **P7** — The 2026-09-30 incident record ships with the remediation (post-mortem committed, not left untracked in the main checkout).

### Mechanism Check & Cut List (Phase 0.6b)

| Proposed mechanism | Property bought | Already covered on main? |
|---|---|---|
| Bounded retry in `verifyScheduledIssueCreated` + `scheduled-output-late-visible` warn | P1, P2 | No — the single read is the defect. Keep. |
| Inngest dispatch for queue-health (`cron-actions-queue-health-dispatch`) | P3 | Pattern exists on main (`cron-supabase-watchdog-dispatch.ts`, ADR-260) — adopt it rather than inventing. |
| Widen `checkin_margin_minutes` 30→60 | P3 headroom for probe's own queue wait | Margin-widen-ALONE to ≥13 h would be needed to silence measured 12 h deferral gaps (03:11→15:15Z) — that delays true-starvation paging unacceptably; dispatch-primary + 60 is the honest shape. Keep 60. |
| New `cron-bot-pr-reaper` Inngest cron | P5, P6 | No existing scheduled bot-PR sweeper (grep: `update-branch`/`mergeable_state` hits only `sync-pr-behind.sh`, worktree-scoped, and read-only `github-read-tools.ts`). Keep. |
| Post-mortem file commit + field updates | P7 | Untracked in main checkout today. Keep. |

**Cuts:** merge-queue (#4856) — correctly deferred by #9274 itself (bigger lift, blocked on #5840); `WATCHDOG_DISPATCH_TABLE` row for queue-health — ineligible per ADR-248 (queue-health does not watch the Inngest substrate); margin-only fix — measured insufficient.

### Relevant Files & Conventions

- `apps/web-platform/server/inngest/functions/_cron-shared.ts:942-997` — `verifyScheduledIssueCreated`; `:1343-1447` — `resolveOutputAwareOk`; `:328-348` — `mintInstallationToken` (least-privilege `permissions`/`repositories`); `:367+` — `postSentryHeartbeat`; `:364` — `sleep` helper already exists.
- `apps/web-platform/server/inngest/functions/cron-supabase-watchdog-dispatch.ts` — the dispatch-function template (actions:write-scoped token, `"cron-dispatch"` account lane, `retries: 1`, redacted `reportSilentFallback` on dispatch failure).
- `apps/web-platform/server/inngest/cron-manifest.ts` — `EXPECTED_CRON_FUNCTIONS` (watchdog manifest; manual-trigger allowlist derives from it automatically via `manualTriggerEventFor`).
- `apps/web-platform/app/api/inngest/route.ts` — serve registration (count currently **70**, asserted by `function-registry-count.test.ts`).
- `apps/web-platform/server/inngest/execution-placement.ts` + `routine-metadata.ts` — required per-function rows.
- `apps/web-platform/test/server/inngest/cron-shared.test.ts:288-447` — existing `verifyScheduledIssueCreated` describe (injectable octokit seam already exists).
- `apps/web-platform/test/server/inngest/cron-supabase-watchdog-dispatch.test.ts` + `supabase-watchdog-workflow-parity.test.ts` — test shapes to mirror for the new dispatcher.
- `plugins/soleur/test/c4-count-parity.test.sh` — derives monitor/emitter counts and asserts `model.c4` prose matches (monitor 60→61, webapp-emitted 44→45 when the reaper monitor lands).
- `apps/web-platform/infra/sentry/cron-monitors.tf:1443-1476` — `scheduled_actions_queue_health` + its design comment; `:1494-1504` — the `scheduled_supabase_watchdog` precedent block (30-min margin, dispatch-primary).
- Learnings: `2026-06-02-auto-merge-livelock-fast-moving-main.md` (never auto-update a branch on every BEHIND — the reaper must settle-guard and bound its update rate); `2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md` (#8076 — the retry's effective population is the shared helper's caller set, reached by editing the helper once); `2026-09-24-a-reliable-dispatch-clock-still-waits-in-the-runner-queue.md` (queue margins must be measured on the population they govern — the dispatched-cohort p90 ~20 min queue wait is already recorded in cron-monitors.tf's header).
- Post-mortem source (untracked, main checkout): `/data/git-repositories/jikig-ai/soleur/knowledge-base/engineering/operations/post-mortems/cron-monitors-paged-falsely-community-monitor-verify-race-queue-health-scheduler-deferral-2026-09-30-postmortem.md`.

### Deepen-pass verification ledger (2026-09-30, sequential-fallback — no subagent tool in this runtime)

Every load-bearing claim re-verified live:

- **Code anchors:** `verifyScheduledIssueCreated` at `_cron-shared.ts:942` (single `client.request("GET /repos/{owner}/{repo}/issues", …)` ~:958, injectable `octokit` seam), sole caller `resolveOutputAwareOk` at `:1376` passing `{label, sinceIso: runStartedAt, octokit}` — additive optional args are memoization-safe; `sleep` helper at `:364`; `mintInstallationToken` at `:328` (`tokenMinLifetimeMs` required, `permissions`/`repositories` optional); `postSentryHeartbeat` at `:367` — signature `{ok, sentryMonitorSlug, cronName, logger}` (**no `checkInId` param exists** — the earlier task note citing `crypto.randomUUID()` was stale; corrected in tasks.md). `manualTriggerEventFor` (`cron-manifest.ts:89`) derives `cron/<name>.manual-trigger`; the allowlist maps `EXPECTED_CRON_FUNCTIONS` — registration in the manifest auto-covers the manual-trigger event.
- **Precedent mirror verified:** `cron-supabase-watchdog-dispatch.ts` read in full — the plan's mirror claims (concurrency lanes `{fn:1, "cron-dispatch":1}`, `retries: 1`, `actions:write`-scoped mint, token-mint failure OUTSIDE the try → propagates → `retries` + middleware, redacted `reportSilentFallback` inside) all match.
- **Registration surfaces:** `route.ts` (count 70 asserted at `function-registry-count.test.ts:235`), `cron-manifest.ts:29` (`EXPECTED_CRON_FUNCTIONS`), `execution-placement.ts` (`portable` rows exist), `routine-metadata.ts` (`manualTrigger: "confirm"` precedent at :94) — `routine-metadata-parity.test.ts` asserts keys ≡ served set, so all four edits are load-bearing.
- **Parity gates (read at source):** `sentry-monitor-iac-parity.test.ts` — `marginWithinBudget` binds ONLY `WATCHDOG_DISPATCH_TABLE` members (pinned to `{scheduled-inngest-health, scheduled-zot-restart-loop}`); queue-health is not a member, and 60 is incidentally the inclusive `MAX_MARGIN_MINUTES` ceiling anyway. Crontab↔workflow-cron parity (#8450) requires the monitor's crontab ∈ the workflow's parsed `schedule:` — kept `*/30` on both. `SLUG_RE` requires kebab-case `SENTRY_MONITOR_SLUG = "scheduled-bot-pr-reaper"` matching tf `name = "scheduled-bot-pr-reaper"`. `c4-count-parity.test.sh` derivations: C2 "9 schedule-fired" unchanged (queue-health keeps parsed `schedule:`), C3 "6 dispatch-only" unchanged (not dispatch-only — has schedule), C4 monitors 60→61, C5 "16 check in from here" unchanged (reaper slug lives in code, not a workflow `monitor-slug:`), C6 webapp 44→45.
- **Workflow state:** `scheduled-actions-queue-health.yml` — `on:` has `schedule: '*/30 * * * *'` + `workflow_dispatch` (:44-48), `concurrency.cancel-in-progress: false` already set (:53, required so dispatch + deferred schedule-fire queue rather than cancel), `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` marker at :1 must survive the comment rewrite.
- **Live state:** all three issues OPEN; PR #9205 REST-verified `{user:"soleur-ai[bot]", mergeable_state:"behind", auto_merge armed}`; ~24 armed bot PRs open (oldest 2026-08-04) — fed the per-sweep cap; labels `action-required`/`domain/engineering`/`follow-through` exist; `allow_update_branch: true` on repo.
- **Docs-verified:** update-branch endpoint = `PUT /repos/{o}/{r}/pulls/{n}/update-branch`, App grant = head-repo `contents:write`, accepts `expected_head_sha` (422 CAS), returns 202 async; `GET …/check-runs` needs `checks:read` for App tokens (`status` filter `queued|in_progress|completed`, `filter=latest` default — the settle-guard should read latest). `mergeable_state` documented enum = {behind, blocked, clean, dirty, draft, has_hooks, unknown, unstable} — table covers all 8 + fallthrough.
- **ADRs read:** ADR-033 Option-C rejection is agent-loop-scoped (scope note 2026-06-02 explicitly blesses Inngest→`workflow_dispatch` for infra crons; anti-circularity corollary #6808 passes — the dispatch needs no runner); ADR-248 eligibility → dedicated `cron-*-dispatch` not `WATCHDOG_DISPATCH_TABLE`; ADR-260/#9168 is the direct dispatch-primary precedent.
- **Post-mortem:** exists untracked in main checkout (9151 B, `status: open`, TBD fields + Actor-keyed timeline — matches Phase-4 task shape).
- **Negative-claim audit:** "no user data touched" (reads PR metadata only) ✓; "single point-in-time read" (one request, no retry) ✓; "only production caller is resolveOutputAwareOk" ✓ (other hits are comments); "no existing scheduled bot-PR sweeper" ✓ (`update-branch`/`mergeable_state` greps hit only `sync-pr-behind.sh` + read tools).
- **Trigger checks:** 4.5 network-outage — the single pattern hit was `504` inside line-range `:1494-1504` (false positive, no network work); 4.55 downtime — no reboot/DDL/deploy-class operations (tf edits retune a monitor + add one resource of an existing class; deploy rides normal merge-triggered restart).

## Problem Statement

The monitoring layer is paging on non-incidents while real artifacts silently die:

- **False-red verify (data loss + page):** one REST list read ~6 s after `gh issue create` raced the label-filtered index on 9/30 (and 9/27). Each false negative costs a page AND the day's digest — the persistence gate keys on the heartbeat.
- **Scheduler-deferral pages (alert fatigue):** `*/30` on.schedule delivery measured at ~4 runs/day; the previous day's `ok` check-ins were at 15:15/20:05/23:50Z — a ~12 h gap a 30-min margin can never absorb. ~47 missed-checkin pages/day trains the operator to ignore the one monitor that catches merge-blocking runner starvation.
- **Stalled bot PRs (silent artifact loss):** `update-branch` exists (`gh pr update-branch` / `PUT /repos/{o}/{r}/pulls/{n}/update-branch`) but no actor calls it for unattended bot PRs; digests 9/27–30 sat `behind` forever while every monitor stayed green.

## Proposed Solution

### Fix 1 — bounded retry in `verifyScheduledIssueCreated` (#9272)

Extend `verifyScheduledIssueCreated` args with `maxAttempts?: number` (default `3`), `retryDelayMs?: number` (default `12_000`), and `feature?: string`. Wrap the list read in a bounded loop: return `true` on the first read that credits output; sleep `retryDelayMs` between attempts via the file's existing `sleep` helper; return `false` after the last empty read (true-absence path unchanged — `resolveOutputAwareOk` still emits `scheduled-output-missing`). On success at attempt >1, emit `warnSilentFallback` with `op: "scheduled-output-late-visible"` (warn level, non-paging — keeps the lag measurable). A *thrown* request still propagates immediately — retry covers the empty-read race only, preserving the `verify-output-failed` fallback contract. `resolveOutputAwareOk` passes `feature: cronName` through.

Cost: worst case ~24 s + 3 reads, once per day per cron — trivial per the issue's own sizing. The retry lives inside the existing `step.run("verify-output")` call sites with no step-id or return-shape change (boolean in, boolean out — no memoization compatibility concern, cf. sharp edge on step return shapes).

### Fix 2 — dispatch-primary trigger + margin headroom for queue-health (#9273)

- New `apps/web-platform/server/inngest/functions/cron-actions-queue-health-dispatch.ts`, a byte-faithful structural mirror of `cron-supabase-watchdog-dispatch.ts`: `{ cron: "*/30 * * * *" }` + manual-trigger event, `mintInstallationToken({ permissions: { actions: "write" }, repositories: [REPO_NAME], … })`, `POST /repos/{o}/{r}/actions/workflows/scheduled-actions-queue-health.yml/dispatches` on `ref: "main"`, `concurrency: [{scope:"fn",limit:1},{scope:"account",key:'"cron-dispatch"',limit:1}]`, `retries: 1`, redacted `reportSilentFallback` on failure. Header comment documents the ADR-248 eligibility argument (dispatch path is runner-queue-independent: Inngest scheduler + GitHub REST fire regardless of runner assignment; the executor still requires a runner from the measured pool, preserving the self-referential starvation signal) — satisfying the corollary test "if the checked thing fails completely, the trigger still fires".
- `.github/workflows/scheduled-actions-queue-health.yml`: keep `schedule: '*/30 * * * *'` + `workflow_dispatch` unchanged (schedule becomes the documented FALLBACK, byte-identical for the #8450 cadence-parity guard — monitor crontab must remain one of the workflow's crons). Rewrite the header design comment to record the dispatch-primary arrangement and the deferral-as-confounder lesson, replacing the now-falsified "must NOT depend on the Inngest dispatch chain" framing — **the `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` marker line stays** (the PreToolUse hook keys on it; dropping it re-arms the deny path for this file).
- `cron-monitors.tf` `scheduled_actions_queue_health`: `checkin_margin_minutes 30 → 60` and rewrite the margin comment — with dispatch-primary the dominant delay is the probe's own runner-queue wait (dispatched-cohort p90 ~20 min, measured 2026-09-24 and recorded in this file's header + `sentry-monitor-iac-parity.test.ts`'s `QUEUE_ALLOWANCE_MINUTES`) + ~5 min runtime + ≤2 min jitter; 60 covers ~2× p90. **True starvation still pages:** (a) a run that cannot get a runner never checks in → `missed` after margin; (b) a landed run during partial under-assignment still returns `UNDER_ASSIGNED` → `status=error` heartbeat → page. Documented residual: during an Inngest-substrate outage the `schedule:` fallback alone (~4×/day under deferral) will miss slots — accepted, because an Inngest outage is itself paged by `scheduled_inngest_health` and the missed check-in stays loud rather than silent.
- Registration surface: `route.ts` import + array, `cron-manifest.ts`, `execution-placement.ts` (`portable` — host-free), `routine-metadata.ts` (`manualTrigger: "confirm"`), `function-registry-count.test.ts` count 70→72 and its comment ledger. No `SENTRY_MONITOR_SLUG` (dispatch functions carry none — scheduler liveness rides `cron-inngest-cron-watchdog`; end-to-end liveness is the queue-health monitor itself).

### Fix 3 — `cron-bot-pr-reaper` (#9274)

New pure-Inngest sweep (no GHA executor — a mechanical REST loop does not need an ephemeral runner; ADR-033 makes Inngest the single scheduling substrate and the prefer-inngest hook denies new `schedule:` workflows anyway):

- Schedule `{ cron: "17 */2 * * *" }` + manual-trigger event. Worst-case `behind` stall ≈ 2 h sweep + ~15 min check cycle → satisfies "not `behind` longer than N hours" with N≈2.5–3.
- Token: `mintInstallationToken({ permissions: { contents: "write", pull_requests: "write", issues: "write", checks: "read" }, repositories: [REPO_NAME] })` — `contents:write` is the load-bearing grant (docs, verified 2026-09-30: "a request on behalf of a GitHub App must have permissions to write the contents of the head repository" — same-repo `ci/*` heads make the repo-scoped grant sufficient; `allow_update_branch: true` confirmed live on the repo via `gh api repos/jikig-ai/soleur`); `pull_requests:write` covers the PR-surface reads+update belt; `issues:write` for the tracking issue; **`checks: "read"` for the settle-guard's `GET /commits/{sha}/check-runs`** — that endpoint requires `checks:read` for App tokens (verified against the docs permission table; a token without it 403s, which would silently disable the settle-guard — the deepen-pass addition).
- Steps: `mint-installation-token` → `list-open-bot-prs` (`GET /repos/{o}/{r}/pulls?state=open&per_page=100`, filter `user.login === "soleur-ai[bot]"` AND `auto_merge != null` — covers `ci/*` cron-artifact PRs AND `soleur/inngest-pin-*` bot PRs, the same stall class; drafts are excluded defensively; **REST `user.login`, not GraphQL `author.login`** — REST returns `soleur-ai[bot]`, GraphQL returns `app/soleur-ai`; verified live on #9205 via `gh api`) → per-PR `read-state` (`GET /pulls/{n}` for fresh `mergeable_state`/`mergeable`/`head.sha`; `"unknown"` gets ONE re-read ~15 s later inside the step, then skip-and-log) → act per state:

| `mergeable_state` | Action |
|---|---|
| `behind` | Settle-guard first: `GET /repos/{o}/{r}/commits/{head.sha}/check-runs` — if any check run is `queued`/`in_progress`, skip this sweep (prevents the #8683/#4774 churn class: never cancel an in-flight verdict). Otherwise `PUT /repos/{o}/{r}/pulls/{n}/update-branch` **with `expected_head_sha` set to the settle-guarded `head.sha`** — a 422 sha-mismatch means the head moved mid-sweep: skip quietly, next sweep re-evaluates (a head the guard never saw must not be updated); other failures → `reportSilentFallback` op `bot-pr-update-failed`. |
| `dirty` (conflict) | `reportSilentFallback` op `bot-pr-unmergeable` + tracking issue (below) — update-branch cannot fix a conflict. |
| `blocked` | Same alert arm — required review/check gate a bot cannot self-satisfy. |
| `unstable` | Same alert arm — checks ran red on the current head; needs investigation, not another sync. |
| `clean` | Skip — armed auto-merge will fire (or already did). |
| `unknown` | One re-read after ~15 s; still unknown → skip + `logger.warn`. |
| `draft` / `has_hooks` | Skip — not mergeable by construction / not a real state for this repo's checks flow. |
| *(any other value)* | Skip + `logger.warn` — forward-compat fallthrough for states outside the documented 8; never assume an unknown state is updatable. |

- **Per-sweep update cap (deepen addition).** Live probe 2026-09-30: ~24 open `soleur-ai[bot]` PRs carry armed auto-merge (oldest 2026-08-04), not the 3–4 recent digests the issue names. Two consequences: (a) an uncapped first sweep fires ~24 `update-branch` calls → ~24 check-run sets land in the runner pool `scheduled-actions-queue-health` itself measures (self-inflicted load on the instrument being fixed); (b) under strict up-to-date rules every merge re-`behind`s the rest, so draining N PRs is O(N²) merge commits. Cap update-branch calls per sweep at **5, oldest-first** — arrival rate is ~1 digest/day so the backlog drains in ~5 sweeps and stays drained. Ancient PRs that turned `dirty`/`unstable` during their stall land in the alert arm naturally, which is correct: a months-old artifact is a judgment call, not a sync.

- Alert vehicle: dedup-by-title tracking issue `[ci/bot-pr-reaper] bot PRs unmergeable without intervention` with labels `action-required` + `domain/engineering` (both verified to exist via `gh label list`), body listing `#N — head — state` per stuck PR; comment-updated each sweep while non-empty, self-closed when the set drains (the queue-health `ci/actions-queue-health` convention). Only bot-generated strings (PR number, `ci/*` head ref, state enum) reach the issue/extra — no attacker-writable fields like PR titles.
- Churn bound: at most one `update-branch` per PR per 2-h sweep, **≤5 update-branch calls per sweep total**, and none while checks are in flight — the anti-livelock discipline from `2026-06-02-auto-merge-livelock-fast-moving-main.md` (a monitor updating on every BEHIND actively fed the loop; a 2-h settle-guarded cadence cannot).
- Own liveness: `SENTRY_MONITOR_SLUG = "scheduled-bot-pr-reaper"` + `postSentryHeartbeat` at the terminal step + new `sentry_cron_monitor` resource `scheduled_bot_pr_reaper` (crontab `17 */2 * * *` mirroring the function schedule, `checkin_margin_minutes = 30` per the Inngest-fired cohort convention, `max_runtime_minutes = 10`, `failure_issue_threshold = 1`, `timezone = "UTC"`).

### Fix 4 — commit the post-mortem

Copy the post-mortem verbatim from the main checkout into `knowledge-base/engineering/operations/post-mortems/` (same filename), then update the fields this PR discharges: `status: open → resolved` (recovery verified by the follow-through probe below), `incident_pr` → this PR's number (filled at PR-open), `recovery_at`/`incident_window` end → merge date, Resolution + Root-Cause 5-Whys + Lessons sections summarizing the three defects, and the Action Items table `#9272/#9273/#9274` rows → shipped-in-this-PR. Keep the Actor-keyed timeline table byte-shape intact (the redaction sentinel scans it).

## Technical Considerations

- **In-flight Inngest runs:** `verifyScheduledIssueCreated` keeps a boolean contract and `resolveOutputAwareOk` adds only optional args — a run memoized on old code resumes safely on new (no step id or return-shape change).
- **Merge-mutates-production question (sharp edge):** merging this PR alone DOES mutate production on two rails — `apply-sentry-infra.yml` auto-applies `infra/sentry/**` on push to main (margin + new monitor go live) and `web-platform-release.yml` restarts the app container on `apps/web-platform/**` merge (new crons register, verify retry ships). The PR body's first line states this.
- **`gh` vs REST:** the reaper uses Octokit REST (`PUT …/pulls/{n}/update-branch` — the same endpoint `gh pr update-branch` wraps, verified via `gh pr update-branch --help` 2026-09-30) rather than shelling out — pure-TS keeps it unit-testable on the existing `probeRequestSpy`/`Octokit`-mock seams.
- **Test runner commands:** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/<file>.test.ts`; typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no `npm run -w` — repo has no workspaces field).

## Implementation Phases

### Phase 1 — #9272 verify retry (contract first)

1.1 RED tests in `cron-shared.test.ts`: (a) first read `[]`, second read populated → `true` + `warnSilentFallback` spy called with `op:"scheduled-output-late-visible"`; (b) all reads `[]` → `false`, request called exactly `maxAttempts` times, no warn; (c) first read populated → `true`, exactly 1 request, no warn; (d) `retryDelayMs: 0` injected in all cases. Confirm RED.
1.2 Implement the retry loop + `feature`/`maxAttempts`/`retryDelayMs` args in `verifyScheduledIssueCreated`; pass `feature: cronName` from `resolveOutputAwareOk`.
1.3 GREEN.

### Phase 2 — #9273 dispatch-primary queue-health

2.1 `cron-actions-queue-health-dispatch.ts` (mirror supabase-watchdog-dispatch).
2.2 Registration: route.ts, cron-manifest.ts, execution-placement.ts, routine-metadata.ts.
2.3 Workflow header comment rewrite (dispatch-primary + schedule-fallback design).
2.4 `cron-monitors.tf`: margin 30→60 + comment rewrite.
2.5 Unit test `cron-actions-queue-health-dispatch.test.ts` mirroring the supabase-dispatch suite (dispatch POST shape, narrowed-token assertion, error → `reportSilentFallback` + `{ok:false}`).

### Phase 3 — #9274 bot-PR reaper

3.1 `cron-bot-pr-reaper.ts` per the decision table above.
3.2 Registration (same four files as Phase 2).
3.3 `scheduled_bot_pr_reaper` monitor resource in `cron-monitors.tf`.
3.4 Unit test `cron-bot-pr-reaper.test.ts`: bot/behind → update-branch called; settle-guard skips on in-flight checks; dirty/blocked/unstable → alert arm, no update; clean/draft/unknown handling; dedup-issue create/update/close.

### Phase 4 — records

4.1 Copy post-mortem into worktree KB + update discharged fields.
4.2 `model.c4` `github -> sentry` edge: rewrite the `-actions-queue-health` clause (dispatch-primary like the supabase-watchdog entry), update counts (60→61 monitors, 44→45 webapp-emitted; the `9 GHA-schedule:-fired` and `6 workflow_dispatch`-only enumerations are unchanged — queue-health stays in the schedule-fired group by parsed `on:` shape, and the reaper monitor posts from webapp). Run `bash plugins/soleur/test/c4-count-parity.test.sh` + the two C4 vitest files.
4.3 `function-registry-count.test.ts` count 70→72 + comment ledger.
4.4 Follow-through enrollment (per Phase 2.9.1): `scripts/followthroughs/cron-machinery-soak-9272.sh` — exits 0 when (a) Sentry shows zero `scheduled-output-missing` for `scheduled-community-monitor` over the soak window while ≥1 digest issue/day landed, (b) queue-health monitor shows no `missed` check-ins over the soak window, (c) zero open `soleur-ai[bot]` PRs have been `behind` >24 h — tracker issue comment `<!-- soleur:followthrough script=scripts/followthroughs/cron-machinery-soak-9272.sh earliest=<deploy+3d> secrets=SENTRY_AUTH_TOKEN GH_TOKEN -->` + `follow-through` label, mirroring `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh` with `start=` pinned strictly after deploy.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-actions-queue-health-dispatch.ts`
- `apps/web-platform/server/inngest/functions/cron-bot-pr-reaper.ts`
- `apps/web-platform/test/server/inngest/cron-actions-queue-health-dispatch.test.ts`
- `apps/web-platform/test/server/inngest/cron-bot-pr-reaper.test.ts`
- `scripts/followthroughs/cron-machinery-soak-9272.sh`
- `knowledge-base/engineering/operations/post-mortems/cron-monitors-paged-falsely-community-monitor-verify-race-queue-health-scheduler-deferral-2026-09-30-postmortem.md` (committed copy of the untracked main-checkout file)

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` (retry loop + args; `resolveOutputAwareOk` passes `feature`)
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` (retry regression tests)
- `.github/workflows/scheduled-actions-queue-health.yml` (header design comment only — `on:` block unchanged)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (margin 30→60 + comments; new `scheduled_bot_pr_reaper` resource)
- `apps/web-platform/app/api/inngest/route.ts` (+2 registrations)
- `apps/web-platform/server/inngest/cron-manifest.ts` (+2)
- `apps/web-platform/server/inngest/execution-placement.ts` (+2 `portable` rows)
- `apps/web-platform/server/inngest/routine-metadata.ts` (+2 rows)
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (70→72 + ledger)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (edge prose + counts)

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| Margin-widen alone to ≥13 h for #9273 | Measured deferral gaps reach ~12 h (9/29–30 evidence); a 13-h margin silences deferral AND delays true-starvation paging to ~13.5 h — the monitor becomes an archive, not an alarm. |
| Reduce workflow cadence (e.g. `*/4h`) + moderate margin | Still depends on the substrate being measured (GHA `schedule:`); sparse schedules defer less but the failure shape stays identical — the signal remains confounded in the same direction. |
| `WATCHDOG_DISPATCH_TABLE` row | ADR-248 eligibility reserves the clock for watchers of the scheduling substrate itself; queue-health watches GHA runners, so it uses the Inngest dispatch pattern. |
| Extend `sync-pr-behind.sh` for the reaper | It syncs `$PWD`'s branch inside a worktree — wrong substrate for unattended server-side sweeps; its callers are ship-pipeline fences, not a scheduler. #8683's settle-before-sync logic is adopted as the reaper's settle-guard instead. |
| Fold reaper into an existing daily cron | Daily cadence violates the "N hours" acceptance; single-purpose function matches the fleet convention. |
| Merge queue (#4856) | Solves ordering at a much bigger lift; blocked on #5840. The reaper is the honest interim measure the issue asks for; it composes with a merge queue later. |

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — the blast radius is the operator's own cron-alert channel and bot-PR flow. A buggy verify retry could red-flag healthy crons (same failure shape as today, not worse); a buggy reaper could call update-branch on the wrong PR — bounded by the `soleur-ai[bot]` + `auto_merge armed` predicate and the settle-guard.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data touched — the sweep reads PR metadata and writes merge commits on same-repo bot branches under a narrowed App token (`contents`/`pull_requests`/`issues: write` + `checks: read`, repo-scoped).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the sensitive-path matches (apps/web-platform/server/**, apps/*/infra/**) are cron-internal machinery — no user-facing product surface, no user data flows through the changed code paths.`

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitors: scheduled-community-monitor (verify path), scheduled-actions-queue-health (missed + error arms), scheduled-bot-pr-reaper (new), plus cron-inngest-cron-watchdog covering both new functions' registration"
  cadence: "community-monitor daily ~08:00Z; queue-health */30 (dispatch-primary); reaper 17 */2 * * *"
  alert_target: "operator email via sentry_alert cron_monitor_failure issue-alert route"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (scheduled_actions_queue_health + scheduled_bot_pr_reaper); apps/web-platform/infra/sentry/cron-monitor-alerts.tf (route)"
error_reporting:
  destination: "Sentry web-platform project via SENTRY_DSN (reportSilentFallback / warnSilentFallback)"
  fail_loud: "scheduled-output-missing (error, unchanged true-absence path); bot-pr-update-failed / bot-pr-unmergeable (error + action-required issue); dispatch failure via redacted reportSilentFallback"
failure_modes:
  - mode: "issues-list index lag returns empty on first read but populated on retry"
    detection: "scheduled-output-late-visible warn event carrying attempt count"
    alert_route: "Sentry warning stream (non-paging)"
  - mode: "probe cannot land: dispatch path down AND schedule fallback deferred"
    detection: "scheduled-actions-queue-health missed check-in past the 60-min margin"
    alert_route: "Sentry cron issue → email"
  - mode: "bot PR unmergeable (conflict / review gate / failing checks)"
    detection: "bot-pr-unmergeable reportSilentFallback + [ci/bot-pr-reaper] action-required issue"
    alert_route: "Sentry error + action-required issue"
  - mode: "reaper itself stops firing"
    detection: "scheduled-bot-pr-reaper missed check-in"
    alert_route: "Sentry cron issue → email"
logs:
  where: "pino stdout → Better Stack shared source (fn=cron-bot-pr-reaper / cron-actions-queue-health-dispatch / verify markers)"
  retention: "Better Stack warehouse retention (fleet standard)"
discoverability_test:
  command: rg -c '^resource "sentry_cron_monitor" "(scheduled_bot_pr_reaper|scheduled_actions_queue_health)"' apps/web-platform/infra/sentry/cron-monitors.tf
  expected_output: "2"
```

## Encryption Posture

```yaml
at_rest: []
in_transit:
  - connection: "web-1 Inngest worker -> api.github.com REST (dispatch POST, pulls/update-branch, check-runs, issues)"
    enforced_at: "apps/web-platform/server/inngest/functions/_cron-shared.ts — Octokit/fetch defaults over existing createProbeOctokit/mintInstallationToken path"
    tls: "https TLS 1.2+"
    cert_verification: on
    does_not_defend: "a minted installation token's misuse within its narrowed grant; token is short-lived and repo-scoped"
    disclosed_as: "not-publicly-claimed"
  - connection: "web-1 Inngest worker -> Sentry ingest (heartbeat + silent-fallback events)"
    enforced_at: "apps/web-platform/server/inngest/functions/_cron-shared.ts postSentryHeartbeat"
    tls: "https TLS 1.2+"
    cert_verification: on
    does_not_defend: "event content itself — bounded by formatTailForSentry redaction upstream"
    disclosed_as: "not-publicly-claimed"
```

No new persistent store and no new connection class — the `.tf` edit retunes an existing monitor and adds one resource of an existing class on the existing jianyuan/sentry provider (60 sibling monitors already applied; no new provider or tier gate).

## Architecture Decision (ADR/C4)

**ADR: none new.** The dispatch-primary trigger for queue-health is consistent with ADR-033's Option-C scope note (Inngest→`workflow_dispatch` is the correct shape for non-agent-loop scheduled work), ADR-248's eligibility rule (watcher not on the scheduling substrate → dedicated Inngest dispatch cron), and ADR-260/#9168 (the supabase-watchdog precedent that made the same reversal two days ago). The falsified premise lives in the workflow header, the tf comment, and the `model.c4` edge — all corrected in this PR, so the record stays accurate without a new ordinal.

**C4 views — `model.c4` `github -> sentry` edge (in-scope task):** rewrite the `-actions-queue-health` enumeration clause to describe dispatch-primary + `schedule:` fallback (mirroring the `scheduled-supabase-watchdog` sub-clause already in this edge) and update the derived counts this edge states: `Of 60 cron monitors` → `Of 61`, `44 from webapp` → `45` (new `scheduled-bot-pr-reaper` monitor). The `9 GHA-schedule-fired` and `6 workflow_dispatch-only` counts are unchanged — queue-health keeps its `schedule:` fallback (stays in the parsed-schedule group, like supabase-watchdog) and the reaper emits from webapp, not a workflow. Enumerated per the completeness mandate: external actors — none new (the reaper acts as the already-present `soleur-ai[bot]` identity via the existing App-token mechanism, not a new actor class); external systems — GitHub and Sentry already modelled; containers — Inngest function instances are not individually modelled (the model carries `inngest` the container + edge classes, not per-cron nodes); relationships — the new API calls (workflow_dispatch POST, pulls/update-branch, check-runs, issues) fold into the existing `api -> github` edges (App installation token, HTTPS REST) and the check-in into the existing `github -> sentry`/`webapp -> sentry` edges — no new edge direction introduced; cardinality prose updated per `c4-count-parity.test.sh`.

**Sequencing:** the post-mortem `status` flips to `resolved` in this PR; the soak's `earliest` is deploy+3d via the follow-through enrollment.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no mention of any file in `## Files to Edit` / `## Files to Create` (checked 2026-09-30).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. (Headless pipeline context: domain-leader fan-out runs inline; no UI-surface files in either Files list → Product/UX mechanical override does not fire → tier NONE.)

## Acceptance Criteria

- [ ] `verifyScheduledIssueCreated` credits a just-filed labelled issue that becomes list-visible on a retry within the bounded window (default 3 attempts, ~12 s apart), and emits `scheduled-output-late-visible` at warn level on a retry-recovered read
- [ ] A run whose issue never appears still produces `scheduled-output-missing` + red heartbeat exactly as today (true-absence unchanged), with exactly `maxAttempts` list reads
- [ ] `scheduled-actions-queue-health` receives check-ins on a ~30-min cadence driven by `cron-actions-queue-health-dispatch` (registered in route.ts + cron-manifest + execution-placement + routine-metadata), with `schedule: '*/30 * * * *'` retained as documented fallback
- [ ] `checkin_margin_minutes = 60` on `scheduled_actions_queue_health`; the monitor comment documents what still pages (missed past margin = both triggers failed; `UNDER_ASSIGNED` on a landed run = partial starvation)
- [ ] `cron-bot-pr-reaper` runs every 2 h; any open `soleur-ai[bot]` PR with armed auto-merge and `mergeable_state = "behind"` whose head checks are terminal gets `PUT …/update-branch` carrying `expected_head_sha` (422 sha-mismatch → quiet skip); stuck states (`dirty`/`blocked`/`unstable`) or update failures surface via `reportSilentFallback` + a dedup-by-title `action-required` issue; no PR receives more than one update per sweep, no more than 5 updates fire per sweep (oldest-first), and none while checks are in flight
- [ ] `scheduled_bot_pr_reaper` Sentry monitor exists in `cron-monitors.tf` (crontab `17 */2 * * *`, margin 30, max_runtime 10)
- [ ] Function registry: route.ts count 72 (asserted by `function-registry-count.test.ts`), `EXPECTED_CRON_FUNCTIONS` includes both new ids
- [ ] Post-mortem committed under `knowledge-base/engineering/operations/post-mortems/` with status resolved and action items discharged to this PR
- [ ] `model.c4` `github -> sentry` prose updated (queue-health clause + counts); `bash plugins/soleur/test/c4-count-parity.test.sh` green
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` green
- [ ] Follow-through enrolled: `scripts/followthroughs/cron-machinery-soak-9272.sh` + tracker directive + `follow-through` label

## Test Scenarios

- **Given** the list read returns `[]` on attempt 1 and the labelled issue on attempt 2, **when** `verifyScheduledIssueCreated` runs with `retryDelayMs: 0`, **then** it returns `true`, calls `request` exactly twice, and emits `scheduled-output-late-visible` once.
- **Given** every attempt returns `[]`, **then** returns `false` after exactly `maxAttempts` reads and emits no late-visible warn (true-absence path feeds `scheduled-output-missing` upstream).
- **Given** a populated first read, **then** exactly one request and no warn.
- **Given** the octokit request throws on attempt 1, **then** the error propagates without further reads (verify-output-failed fallback preserved).
- **Dispatch:** mocked Octokit records `POST …/workflows/scheduled-actions-queue-health.yml/dispatches` with `ref:"main"` and `actions:write`-scoped mint; a thrown dispatch → `reportSilentFallback` + `{ok:false}`.
- **Reaper:** fixture PR set covering every `mergeable_state` arm in the decision table; assert update-branch invoked only for `behind`+terminal-checks, alert arm for `dirty`/`blocked`/`unstable`, skips for `clean`/`draft`/`unknown`-after-reread; non-bot or unarmed PRs ignored; issue create/update/close on the stuck set.
- **IaC:** `terraform validate` on the sentry root after the margin + new resource edits (CI leg plans the same root; `fmt -check` clean).
- **Parity:** `function-registry-count.test.ts`, `sentry-monitor-iac-parity.test.ts`, `c4-count-parity.test.sh`, `supabase-watchdog-workflow-parity.test.ts` all green.

## Success Metrics

- Zero `scheduled-output-missing` events whose labelled issue exists (the 9/27 + 9/30 shapes) — soak probe (a).
- `scheduled-actions-queue-health` missed-checkin pages drop from ~47/day to ~0; every `ok`/`error` check-in reflects a real probe run — soak probe (b).
- Daily digests land on `main` again; no `soleur-ai[bot]` PR stays `behind` >24 h — soak probe (c).

## Dependencies & Risks

- **Inngest outage couples queue-health to a second substrate:** accepted — `scheduled_inngest_health` already pages that class, and the `schedule:` fallback still delivers ~4×/day (missed check-ins during that window are loud, not silent).
- **Update-branch permission scope — RESOLVED at deepen (2026-09-30):** `PUT /pulls/{n}/update-branch` on behalf of a GitHub App requires write access to the head repository's contents — `contents:write` covers same-repo `ci/*` heads (`hr-verify-repo-capability-claim-before-assert` satisfied against the live docs). Token mints `{contents, pull_requests, issues}: write` **plus `checks: read`** — the settle-guard's `GET …/check-runs` 403s without it (App-token requirement per the checks endpoint docs; the un-granted read would have silently disabled the guard). `allow_update_branch: true` confirmed on the repo.
- **mergeable_state lazily computed:** `"unknown"` on first read is normal — the re-read + skip arm handles it; a state that never resolves is logged, not looped on.
- **`scheduled-output-late-visible` is a NEW op slug:** adding it darkens nothing (pure addition); any future Sentry alert filtering `op IS_IN` lists is unaffected.
- **Two new Inngest functions register at deploy:** `web-platform-release.yml` container restart performs registration — no separate operator step (per the automation-feasibility gate).
- **Post-merge (operator) steps: none.** All changes deploy via merge-triggered pipelines; the soak closes via the follow-through sweeper, not a human calendar.

## References & Research

- Issues: #9272, #9273, #9274 (open, fetched 2026-09-30); context #8683 (BEHIND livelock — settle-guard adopted), #5139 (tri-state output-verify — related, untouched), #4856 (merge queue — deferred), #8076 (caller-population lesson), #8495/ADR-248 (dispatch clock + measured queue stats), #9168/ADR-260 (dispatch-primary precedent), #8578 (queue-health origin).
- Post-mortem (committed by this PR): `knowledge-base/engineering/operations/post-mortems/cron-monitors-paged-falsely-community-monitor-verify-race-queue-health-scheduler-deferral-2026-09-30-postmortem.md`.
- Learnings: `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md`, `knowledge-base/project/learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`, `knowledge-base/project/learnings/integration-issues/2026-09-24-a-reliable-dispatch-clock-still-waits-in-the-runner-queue.md`.
- Follow-through convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`; sibling probe `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`.
