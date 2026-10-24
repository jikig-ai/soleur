---
title: "feat: Inngest alert delivery — watched-channel routing, serving-verdict heartbeat, post-merge observability soak (epic #10390)"
date: 2026-10-24
slug: feat-inngest-alert-delivery-observability
branch: feat-one-shot-9703-inngest-alert-delivery
issue: 10390
type: enhancement
priority: p1-high
domain: engineering-ops
brand_survival_threshold: none
lane: cross-domain
---

# feat: Inngest alert delivery — watched-channel routing, serving-verdict heartbeat, post-merge observability soak

## Overview

During the 2026-10-22 dedicated-host replace, the two Better Stack heartbeat
monitors for the Inngest serving path (`soleur-inngest-server-prd`,
`soleur-inngest-consumer-prd`) missed beats and opened incidents correctly —
but their only delivery channel was an unwatched email inbox
(`email = true`, `call/sms/push = false`, `policy_id = null` — no escalation
policy on the current tier). The scheduled-inngest-health watchdog's GitHub
issues (#10853, #10854 — both OPEN) were what the operator actually saw.
Two further gaps compound this: `soleur-inngest-server-probe-prd` stayed green
through the whole outage because it measures probe-row-shipped, not the
serving verdict the probe row already carries; and no agent or scheduled
surface read the alert channels after the deploy — detection was timely,
human notice was late.

This plan implements the three-workstream arc under epic #10390:

- **WS1 — Alert routing.** A repo-side Better Stack incident mirror: a
  15-minute watchdog-dispatched workflow that reads
  `GET /api/v2/incidents?resolved=false` plus heartbeat/monitor `status` and
  files/dedupes GitHub issues (`ci/betterstack-incident`) — the channel the
  operator provably watches — with auto-resolve comments. Deliverable under
  the current tier; the Responder-seat escalation policy is named
  operator-reserved (money). Includes a Phase-0 measurement of the wired
  Slack integration's heartbeat coverage and a measured `push = true` flip.
- **WS2 — Extend #9703.** The probe-heartbeat feeder
  (`scripts/inngest-probe-heartbeat-feeder.sh`) additionally reads the newest
  fresh dedicated row's serving fields (`server_active`, `http_code`,
  `cutover_flag`) through the existing `classify_dedicated_host` verdict and
  beats `<url>/fail` on `not-serving` — the in-repo precedent used by
  `web-bash-synthetic.sh` — so serving-dead-but-probe-alive pages instead of
  reading green.
- **WS3 — Post-merge observability soak.** A new `postmerge` phase that reads
  Better Stack open incidents and `ci/*` issue classes after the deploy
  verdict (report-only, mirroring the Phase-3.5 advisory idiom), plus a
  generic `scripts/followthroughs/` soak verifier enrollable per merge, so
  post-deploy windows are actively watched.

## Problem Statement

Three independent delivery gaps on one detection surface:

1. **Routing gap (email-only).** Every `betteruptime_heartbeat` and
   `betteruptime_monitor` in `apps/web-platform/infra/` notifies
   `email = true` only; `policy_id` resolves to `null` under
   `var.betterstack_paid_tier = false`, so no escalation policy exists.
   The Oct-22 incidents fired correctly and emailed nobody who was watching.
2. **Semantics gap.** `betteruptime_heartbeat.inngest_server_probe` is fed by
   `scripts/inngest-probe-heartbeat-feeder.sh`, whose freshness check grades
   row *presence* only. The row's own fields (`server_active=active`,
   `http_code=200`, `cutover_flag=done`) went unread by the feeder, so
   `verdict: not-serving` (the #10853 shape) left the heartbeat green.
3. **Watch gap.** `soleur:postmerge` reads Sentry cron monitors and the
   `ci/inngest-down` issue label, but nothing reads Better Stack incidents or
   the wider `ci/*` issue surface after a merge — and nothing does so
   continuously. The followthrough sweeper runs daily on enrolled trackers
   only.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief/spec) | Codebase reality | Plan response |
|---|---|---|
| "`inngest-server-probe-prd` heartbeat … measures probe-row-shipped" | Confirmed — `inngest-probe-heartbeat-feeder.sh` grades freshness only; the jq selection extracts `[probe, host, dedicated, dt]` and drops message fields | WS2 extends the same jq pass to carry `server_active`, `http_code`, `cutover_flag` and routes on `classify_dedicated_host` |
| "the residual is the arming + this serving-verdict extension" | The arming already landed: `heartbeat-manifest.ts` records `FED and ARMED` (2026-10-12), `uptime-alerts.tf:527` documents the arm, `arming_pending` is already dropped. Live state must still be re-verified (the manifest itself says "live state is read from Better Stack") | Residual = serving-verdict extension + a live read-back AC; bookkeeping AC confirms manifest/runbook honesty, no re-arm work |
| "no agent or scheduled surface watched the alert channels" | Partially false — `scheduled-inngest-health.yml` files `ci/inngest-*` issues for *its own* verdicts, and the nightly heartbeat-live-reconcile diffs manifest vs live. Neither reads Better Stack *incidents*, and nothing mirrors them to issues | WS1 mirror is the new surface; WS3 adds the post-merge read |
| "Slack or GitHub-issue webhook channel" as options | A native Slack integration IS wired since #9168 (ADR-260; `GET /api/v2/slack-integrations` non-empty) and posts *all new incidents* to one channel — yet the Oct-22 heartbeat incidents still went unseen | Phase-0 measurement reads the integration + incident history to determine whether heartbeats were Slack-posted; the mirror is built regardless as the durable watched channel |
| "`inngest-server-probe.sh`" (named in brief) | No such file in the worktree; the probe emitter is the `logger -t inngest-server-probe` line in `apps/web-platform/infra/inngest-bootstrap.sh:1274` | File list names the real emitter file — but deliberately does NOT edit it (sibling collision + no new fields needed; the row already carries every field the verdict needs) |

## Research Insights

### Premise Validation (Phase 0.6)

All cited issues verified OPEN: #10390 (epic), #9703, #10853, #10854, #6645,
#10918, #10584, #10914, #6472. Sibling draft PRs #10966
(`feat-one-shot-inngest-window-prework`) and #11001 (this branch) verified
OPEN. Cited machinery verified on disk: `uptime-alerts.tf`,
`betterstack-logs-alerts.tf`, `scripts/lib/inngest-probe-row.sh`,
`scripts/inngest-probe-heartbeat-feeder.sh`, `heartbeat-manifest.ts`,
`watchdog-dispatch-table.ts`, `scheduled-inngest-health.yml`,
`scheduled-inngest-probe-heartbeat.yml`. ADR corpus checked for the proposed
mechanisms: ADR-117 (measured-beat arming), ADR-204/222 (Better Stack
capability grounds), ADR-248 (watchdog dispatch table), ADR-260 (Slack paging;
`betteruptime_outgoing_webhook` → Slack explicitly REJECTED — payload not
Slack-format-compatible), ADR-282, ADR-283. No proposed mechanism sits in a
rejected-alternatives table: the GitHub-issue mirror is a repo-side read, not
the rejected outgoing-webhook route.

### Property List (Phase 0.6b)

- **P1.** An open Better Stack incident (heartbeat or monitor) surfaces as a
  deduplicated GitHub issue/comment within ~15 min — the channel observed to
  work on Oct-22.
- **P2.** A serving-dead-but-probe-alive state alerts through the probe
  heartbeat's paging path, not only through the health watchdog's filing.
- **P3.** Post-merge verification actively reads alert channels (Better Stack
  incidents, `ci/*` issues, Sentry), including a time-windowed soak.
- **P4.** Every new scheduled surface is self-watched (dead mirror pages).
- **P5.** Zero new vendor-tier dependency: everything lands on the current
  Better Stack plan; the paid-tier arm is deferred, not required.

### Cut List (Phase 0.6b)

- `betteruptime_policy` arm → property P1 — **cut**: requires the Responder
  seat ($29–34/mo, declined at ADR-260); recorded as operator-reserved
  (money), not built.
- `betteruptime_outgoing_webhook` → Slack → cut: ADR-260 already rejected it
  (payload not Slack-format-compatible).
- Slack integration re-wire → cut pending measurement: already wired since
  #9168 and posts all incidents to one channel; Phase 0 measures whether
  heartbeat incidents reached it before deciding anything further.
- A second dedicated heartbeat for serving verdicts → property P2 — **cut**:
  the existing heartbeat + `/fail` arm buys the same property with no new
  manifest row, no second feeder, no second arming window.
- ship Phase-7 polling edits → property P3 — **cut**: `plugins/soleur/skills/
  ship/SKILL.md` is in sibling worktree #10966's diff; the soak lands in
  `postmerge` + followthrough machinery instead.
- New Terraform root → **cut**: reuses `apps/web-platform/infra` and
  `apps/web-platform/infra/sentry` per `hr-every-new-terraform-root-must-include-an`.

### Repo findings

- `GET https://uptime.betterstack.com/api/v2/incidents?resolved=false` lists
  open incidents (filterable by `heartbeat_id`/`monitor_id`); heartbeat
  objects carry `status` (`up|down|paused|pending`). Read with
  `BETTERSTACK_API_TOKEN_READONLY` (GET-only repo secret — cannot pause, edit,
  or delete; can read heartbeat ping URLs, so treat output as
  beat-capability-bearing — never echo raw).
- Prior art for reading the incidents API safely:
  `scripts/followthroughs/send-failed-alert-probe-8097.sh` (paged read,
  projection to `{id,name,cause,started_at,resolved_at}`, public-comment
  discipline — every printed line is republished by the sweeper).
- Issue-filing pattern (dedupe by title + comment-or-create + label-create):
  `scheduled-inngest-health.yml` lines ~523–695 (`gh label create` …
  `gh issue list --label` … `gh issue comment|create`); the
  `apply-delivery-gap-follower.yml` + `scripts/apply-delivery-gap.sh` pair is
  the small-footprint sibling (workflow_run follower, DETECTION ONLY,
  deduplicated filing).
- `classify_dedicated_host` (`scripts/inngest-dedicated-host-classify.sh`)
  already computes `healthy | stopped-by-brake | not-serving |
  probe-unavailable` from exactly the fields the probe row carries —
  `server_active`, `http_code`, `cutover_flag`. Sourced by
  scheduled-inngest-health.yml and unit-tested; reuse it, do not re-parse.
- `/fail` beat precedent: `apps/web-platform/infra/web-bash-synthetic.sh:135`
  (`target="${URL%/}/fail"` — a verified FAIL pings for an immediate
  incident rather than alarming through grace).
- Watchdog dispatch: `apps/web-platform/server/watchdog-dispatch-table.ts`
  (ADR-248) — new rows need `schedule:` fallback + `workflow_dispatch` only +
  `cancel-in-progress: false` concurrency + eligibility text; pinned by
  `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`
  and `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts`.
- Sentry cron monitor for a new watchdog workflow follows
  `sentry_cron_monitor.scheduled_inngest_probe_heartbeat`
  (`sentry/cron-monitors.tf:1083`). Margin math: interval + margin ≤
  MAX_MARGIN_MINUTES parity ceiling; runner-queue allowance ~41 min measured
  (zot watchdog p90). New monitors land unrouted (two-PR rule, sentry README
  §186 — routing is a follow-up PR via `alert-reference.json` detectorIds).
- `scheduled-inngest-health.yml` already has `issues: write`; the new mirror
  workflow needs the same + `contents: read` only. GitHub-issue filing under
  `github.token` does not recurse (issues are not workflow triggers).
- Skill surface for WS3: `plugins/soleur/skills/postmerge/SKILL.md` — Phase
  3.5's inngest-down advisory (`gh issue list --label ci/inngest-down`) is the
  cheap-read idiom to extend; Phase 6 comment + Phase 7 report vocab carry
  new status lines.
- Followthrough enrollment: `<!-- soleur:followthrough script=…
  earliest=… secrets=… -->` directive on a `follow-through`-labeled tracker;
  `scheduled-followthrough-sweeper.yml` runs `scripts/followthroughs/<x>.sh`
  daily. Soak scripts never get GH_TOKEN (they never file issues).
- Sibling-collision surface (draft PR #10966,
  `feat-one-shot-inngest-window-prework`, retiring LUKS cutover machinery from
  the Inngest bootstrap image — different deliverable, same subsystem):
  `apps/web-platform/infra/{inngest-bootstrap.sh, betterstack-logs-alerts.tf,
  inngest-luks-cutover.*, inngest-redis-luks.test.sh, server.tf, inngest.test.sh,
  journald-config.test.sh, ci-deploy.test.sh}`,
  `plugins/soleur/skills/ship/SKILL.md`,
  `scripts/lib/inngest-probe-row.test.sh`, plus
  `build-inngest-*.yml`/`apply-deploy-pipeline-fix.yml` workflows. **This plan
  touches none of those paths** — the verdict fields already exist in the
  emitted row, so no emitter edit is needed.

### Institutional learnings applied

- `2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md` —
  `paused`/`pending` heartbeat status routes to TRANSIENT-equivalent, never a
  failure verdict.
- `2026-06-12-detector-cron-must-route-its-own-self-failure-ops` — a new
  detector needs its own self-failure route (the mirror's Sentry monitor).
- `2026-07-17-live-reconcile-observability-job-copy-fidelity-ssrf` — live
  reads of Better Stack need pinned endpoints and token-on-stdin curl
  (`--config -`), never bearer on argv (#7797 xtrace refusal pattern).
- `send-failed-alert-probe-8097.sh` — public-comment discipline: issue bodies
  are public; incident objects must be projected, never pasted raw.
- `2026-09-18-a-plan-prescribed-probe-must-be-portable` — probe commands must
  run in the preflight sandbox (allowlisted verbs, 15 s cap, no ssh).
- #9168 measured-flip convention: vendor-attribute flips are measured on ONE
  resource at apply with a documented revert path (the `push = true` arm).

### External references

- Better Stack uptime API: `GET /api/v2/incidents` (resolved/acknowledged/
  heartbeat_id filters), `GET /api/v2/heartbeats` (`status` attribute),
  `GET /api/v2/monitors`, `GET /api/v2/slack-integrations`.
- Better Stack Slack docs: the basic single-channel integration "posts all
  new incidents" to one channel; per-monitor scoping requires escalation
  policies (paid). Free tier includes "Slack & e-mail alerts" +
  single-channel Slack integration.
- ADR-260: Slack = primary wake path since #9168; Responder seat declined and
  re-evaluated only "if the Slack channel proves insufficient".

## Hypotheses

Triggered by the `SSH` substring in the brief's constraints ("no SSH as
primary debug path", "runs WITHOUT SSH") — the gate matches on constraint
language, not on a connectivity symptom. This plan diagnoses no network
outage; the L3→L7 layers are opted out with artifacts:

1. **L3 firewall allow-list.** Opted out: no sshd/firewall hypothesis is
   proposed; every verification path in this plan is a GitHub Actions run or a
   vendor API GET. [artifact: plan's `## Observability` discoverability_test]
2. **L3 DNS/routing.** Opted out: same reason — no host-connectivity claim.
3. **L7 TLS/proxy.** Opted out: no HTTPS-path symptom under diagnosis; the
   Better Stack API reads are pinned to `uptime.betterstack.com` with
   `--noproxy '*'` parity per `inngest-probe-heartbeat-feeder.sh:119-121`.
4. **L7 application.** Opted out: the Oct-22 incident's journal evidence is
   already the probe row itself (`SOLEUR_INNGEST_SERVER_PROBE …
   server_active=activating http_code=000` — #10853 body).

## Proposed Solution

### WS1 — Better Stack incident mirror (the delivery gap)

**Phase 0 (measurement, in this PR's first commits):** with
`BETTERSTACK_API_TOKEN_READONLY`, record in the PR body:

1. `GET /api/v2/slack-integrations` — is an integration connected, and does
   its config scope heartbeats? (Basic integration posts *all* incidents; a
   null/unexpected answer changes the WS1 framing, not the build.)
2. `GET /api/v2/incidents?from=2026-10-22&until=2026-10-23` — the Oct-22
   heartbeat incidents: delivery metadata where exposed, to state whether
   Slack was posted-and-missed vs never-posted.
3. `GET /api/v2/heartbeats` — confirm the status vocabulary on live objects
   (`up|down|paused|pending`) for the mirror's mapping table.

**The mirror:** `scripts/betterstack-incident-mirror.sh` (new, tested) +
`.github/workflows/scheduled-betterstack-incident-mirror.yml` (new) + a
`WATCHDOG_DISPATCH_TABLE` row (`intervalMinutes: 15`; eligibility clause 1 —
it watches the paging substrate whose outages include Inngest's own, so it
cannot be Inngest-scheduled) + `sentry_cron_monitor.scheduled_betterstack_incident_mirror` (self-watch; margin per the parity
budget) + the workflow's terminal `sentry-heartbeat` check-in step.

Per 15-minute run:

1. `GET /api/v2/incidents?resolved=false&per_page=50` — project each incident
   to `{id, name, cause, started_at, monitor/heartbeat id}`; treat pagination
   like the feeder (fail-safe if `pagination.next` present: annotate, still
   process page 1).
2. For each open incident: dedupe by title `[ci/betterstack-incident]
   <monitor-or-heartbeat-name>` — comment if a same-titled issue is open
   (with incident id + `started_at`), else create with labels
   `ci/betterstack-incident`, `action-required`,
   `priority/p1-high`. Body names the monitor, the incident id, the
   cause, the run URL, and the vendor incident URL — never raw payloads.
3. For each open mirror-filed issue whose incident no longer appears in the
   open list (or whose heartbeat `status` reads `up`): comment
   "resolved upstream at <ts>" — auto-close only issues this mirror filed
   (marker in body), never human-filed ones (the #10918 title-confusion
   class: dedupe keys on the exact title AND the body's incident-id marker,
   never title alone).
4. Read failure (auth, network, malformed) → error Sentry check-in +
   `::error::` — the mirror is fail-loud about itself, silent about nothing.
5. A `paused`/`pending` heartbeat that was never armed is not an incident —
   the reconcile job owns manifest-vs-live drift; the mirror reads incidents
   and armed-monitor status only.

**Secondary arm (measured, same PR):** flip `push = true` on
`betteruptime_heartbeat.inngest_prd` and `.inngest_consumer` — the #9168
measured-flip convention (one apply measures acceptance; revert to
`push = false` in a follow-up if the vendor refuses or no-ops). Documented
as secondary: it needs the operator's Better Stack mobile app installed and
watched, which the plan cannot guarantee — the mirror is the deliverable.

**Operator-reserved (named, not built):** the Responder-tier escalation
policy (`betterstack_paid_tier = true` arm) — a money decision per the
rulings contract, tracked by ADR-260's revisit condition.

### WS2 — serving-verdict extension (#9703 residual)

Extend `scripts/inngest-probe-heartbeat-feeder.sh` chokepoint 1
(`check_freshness`) so the jq pass also extracts `server_active`,
`http_code`, `cutover_flag` from the newest fresh dedicated row (the row
already selected for freshness — one read, two properties), then source
`scripts/inngest-dedicated-host-classify.sh` and route:

| verdict | action |
|---|---|
| `healthy` | beat (unchanged path) |
| `not-serving` | beat `${HB_URL%/}/fail` (immediate incident; verdict marker `not_serving` + funnel counts) |
| `stopped-by-brake` | beat normally — deliberate state; the health watchdog owns its issue class (#10853 shape). Beat continues because the *probe pipeline* is alive, which is what this switch measures. |
| `probe-unavailable` | withhold, exit 3 `CANNOT BEAT` (existing contract — a missing signal must not read as a working one) |

Exit-contract additions: `/fail` delivery failure exits 4 (`beat_failed`,
same as the normal beat). New verdict markers: `beat` (unchanged),
`fail_beat` (new — `/fail` delivered), `fresh_heartbeat_paused` (unchanged).
The workflow's Sentry check-in `status:` expression gains `fail_beat` as an
`ok`-class verdict only when the `/fail` POST itself returned 2xx (the beat
was *delivered* — the incident it opens is the intended outcome, not a
feeder error); update the `case "$rc"` annotation block to annotate
`not_serving` distinctly.

Test updates: `scripts/inngest-probe-heartbeat-feeder.test.sh` gains fixtures —
(a) fresh dedicated row with `server_active=inactive http_code=000` →
`/fail` POST to the pinned URL-suffix path, no normal beat; (b) `healthy`
row → normal beat, no `/fail`; (c) `stopped-by-brake` row → normal beat;
(d) row with unparseable fields → withhold; (e) mutation: `/fail` POST
non-2xx → exit 4; (f) dispatch: feeder that never reaches `beat_once` exits
non-zero (anti-vacuity, already-shaped per existing contract).

`heartbeat-manifest.ts`: no structural change (feeder evidence unchanged),
but the `inngest_server_probe` row's comment gains the serving-verdict
semantics sentence (what a beat now certifies: fresh row AND serving
verdict, else `/fail`). Live-state AC: read-back `GET` on the heartbeat
(`paused=false status=up`) — the manifest's own "live state is read from
Better Stack" discipline.

### WS3 — post-merge observability soak

1. **`postmerge` Phase 3.9 "Alert-channel sweep"** (report-only, mirrors the
   Phase-3.5 advisory idiom): after the deploy verdict, (a) `gh issue list`
   over `ci/` labels for issues opened since the merge SHA's commit
   timestamp — including but not limited to `ci/inngest-*`, reported
   verbatim; (b) Better Stack `GET /api/v2/incidents?resolved=false`
   projected to `{id,name,started_at}` when `BETTERSTACK_API_TOKEN_READONLY`
   is available via Doppler `prd_terraform`, else `SKIPPED` with the
   graceful-degradation vocabulary; (c) one summary line each in the Phase-6
   issue comment and Phase-7 report (`Alert-channel sweep: <clean|verbatim
   rows|SKIPPED>`).
2. **Generic soak verifier** `scripts/followthroughs/post-deploy-incident-soak.sh`
   (new): exit 0 iff zero *new* Better Stack incidents and zero *new*
   `ci/` issues appeared in the window `[deploy_ts, deploy_ts + Nh]`;
   TRANSIENT on any read failure or missing liveness proof (the sweeper's
   convention); enrolled per-merge on the tracker via the
   `<!-- soleur:followthrough … -->` directive with `earliest=<deploy+1d>`.
   Ships with a usage note in
   `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
   (the soak-trigger table) so the next plan reuses it rather than inventing
   a third shape.
3. The WS1 mirror is the continuous surface; WS3's sweep + soak are the
   point-read and time-windowed complements — the plan notes the boundary so
   review does not double-count coverage.

## Alternative Approaches Considered

| Alternative | Why not chosen |
|---|---|
| Paid-tier escalation policy (`betteruptime_policy` arm) | Requires the Responder seat the operator declined at ADR-260 ($29–34/mo); recorded operator-reserved (money), with ADR-260's revisit condition as the trigger |
| `betteruptime_outgoing_webhook` → Slack | Rejected by ADR-260: raw webhook payloads are not Slack-format-compatible |
| Mirror job inside `scheduled-inngest-probe-heartbeat.yml` | The feeder's ADR-248 eligibility clause 2 and its Sentry monitor are scoped to beating the dead-probe heartbeat; a generic incident mirror is a different property and would blur both the eligibility grant and the check-in semantics |
| Mirror step inside `scheduled-inngest-health.yml` | Inngest-scoped name/permissions for a cross-subsystem property; conflates the liveness watchdog's failure domain with the alert channel's |
| Second heartbeat for serving verdicts | One monitor's `/fail` arm carries the same property with no second feeder, manifest row, or arming window |
| Emitter change in `inngest-bootstrap.sh` (new `verdict=` field) | Unneeded — the row already carries every field `classify_dedicated_host` consumes; the file is also inside sibling #10966's diff surface |
| Defer WS3 soak to ship Phase 7 | `ship/SKILL.md` is inside sibling #10966's diff surface; postmerge + followthrough covers the same property without the collision |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is
operator-facing observability; the failure mode is a *missed* page (the same
status quo the plan removes) or a false page during a real outage, which
erodes operator trust in the alarm channel.

**If this leaks, the user's [data / workflow / money] is exposed via:** no
user-data surface — the mirror reads Better Stack incident metadata
(monitor names, timestamps, causes) and writes GitHub issues on a private
repo; heartbeat ping URLs are projected OUT of every printed line
(beat-capability-bearing). Worst-case exposure is monitor naming in a
private-repo issue.

**Brand-survival threshold:** none

- `threshold: none, reason:` operator-facing alerting plumbing only — no
  user-facing artifact, no regulated-data surface, no prod-data mutation;
  the one production-adjacent verb is a GET on a read-only vendor token.

## Files to Create

| File | Purpose |
|---|---|
| `scripts/betterstack-incident-mirror.sh` | WS1 core: read open incidents + armed heartbeat/monitor status, file/dedupe/resolve `ci/betterstack-incident` issues |
| `scripts/betterstack-incident-mirror.test.sh` | Behavioral harness: fake curl/jq/gh on PATH, fake clock; fixture corpus for open/resolved/auth-fail/paginated/duplicate-title cases |
| `.github/workflows/scheduled-betterstack-incident-mirror.yml` | 15-min runner: watchdog-dispatch primary + `schedule:` fallback + `workflow_dispatch`, `cancel-in-progress: false`, terminal sentry-heartbeat step, gate-override comment per ADR-248 |
| `scripts/followthroughs/post-deploy-incident-soak.sh` | WS3 generic soak verifier for the followthrough sweeper |
| `scripts/followthroughs/post-deploy-incident-soak.test.sh` | Harness for the soak script (TRANSIENT on read failure, `paused`/`pending` tolerated, window pinned past deploy) |
| `knowledge-base/engineering/architecture/decisions/ADR-297-betterstack-incident-mirror-github-issues.md` | **Provisional ordinal** — the channel-choice decision record (GitHub-issue mirror over paid escalation / outgoing webhook); renumber per ship's ADR-Ordinal Collision Gate and sweep all planning refs |

## Files to Edit

| File | Edit |
|---|---|
| `apps/web-platform/server/watchdog-dispatch-table.ts` | WS1 row: `scheduled-betterstack-incident-mirror.yml`, slug `scheduled-betterstack-incident-mirror`, `intervalMinutes: 15`, eligibility clause-1 text |
| `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` | Expected-slug/queue-allowance/crontab-parity assertions for the new row (the suite derives most checks from the table — add only where its cohort enumerations name workflows) |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | `sentry_cron_monitor.scheduled_betterstack_incident_mirror` + margin comment (lands unrouted per the two-PR rule — routing is follow-up) |
| `apps/web-platform/infra/sentry/alert-reference.json` | only if the parity/README flow requires regenerating for the new monitor (follow the sentry README §186 two-PR rule exactly) |
| `scripts/inngest-probe-heartbeat-feeder.sh` | WS2: serving-field extraction in the existing jq pass + `classify_dedicated_host` routing + `/fail` beat arm + `fail_beat` verdict marker |
| `scripts/inngest-probe-heartbeat-feeder.test.sh` | WS2 fixtures (a)–(f) above |
| `.github/workflows/scheduled-inngest-probe-heartbeat.yml` | `status:` expression admits `fail_beat`; `case` annotations name `not_serving` distinctly; header comment updated |
| `plugins/soleur/lib/heartbeat-manifest.ts` | `inngest_server_probe` row comment: beat now certifies fresh row AND serving verdict |
| `plugins/soleur/skills/postmerge/SKILL.md` | WS3 Phase 3.9 (alert-channel sweep) + Phase-6/7 report lines + Graceful Degradation note |
| `apps/web-platform/infra/inngest.tf` | `push = true` on `betteruptime_heartbeat.inngest_prd` + `.inngest_consumer` with the #9168 measured-flip comment |
| `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` | Soak-trigger table row for `post-deploy-incident-soak.sh` |
| `knowledge-base/engineering/architecture/diagrams/{model,views}.c4` | `github` external-system edge `betterstack -> github actions -> github issues` for the mirror (checked against all three .c4 files per the completeness mandate) |
| `scripts/test-all.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` | register the two new suites |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Add a watched delivery channel for these heartbeat incidents — evaluate escalation-policy arm vs a Slack or GitHub-issue webhook channel — so heartbeat incidents surface where the operator actually looks." [brief WS1] | WS1 mirror (files: `betterstack-incident-mirror.sh`, workflow, dispatch row, sentry monitor) + measured `push` flip + Slack coverage measurement | mapped |
| 2 | "the plan must pick a route deliverable under the current tier or name the tier decision explicitly as an operator-reserved item" [brief WS1] | GitHub-issue mirror (current-tier deliverable); Responder escalation named operator-reserved | mapped |
| 3 | "the issue's dead-probe verifier machinery … should also report serving verdicts so a serving-dead-but-probe-alive state alerts" [brief WS2] | WS2 feeder extension (`inngest-probe-heartbeat-feeder.sh` + `classify_dedicated_host` + `/fail` beat) | mapped |
| 4 | "implement improvements to Soleur skills (postmerge phases, ship Phase 7 polling, and/or scheduled watchdog machinery like scheduled-inngest-health.yml) so merges/deploys are followed by an active observability soak — Better Stack incidents, ci/inngest-* GitHub issues, Sentry — rather than passive reliance on email" [brief WS3] | postmerge Phase 3.9 + `post-deploy-incident-soak.sh` + WS1 mirror (continuous arm) | mapped |
| 5 | "avoid its file surface and note it in the plan" [brief, sibling #10966] | Research Insights sibling-collision list; file list contains zero sibling paths | mapped |
| 6 | "the plan should consult" #6645, #10918, #10584, #10914, #6472 [brief] | Open Code-Review Overlap + per-issue dispositions below | mapped |
| 7 | "plans touching production code/infra need a ## Observability block with discoverability_test.command that runs WITHOUT SSH" [brief] | `## Observability` below | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `betterstack-incident-mirror.sh` + workflow + dispatch row | "a GitHub-issue webhook channel … so heartbeat incidents surface where the operator actually looks" | asked |
| `sentry_cron_monitor.scheduled_betterstack_incident_mirror` | "every failure mode needs an observability-layer citation" + self-watch convention (dead detector pages) | inferred — a detector with no self-failure route is the `2026-06-12-detector-cron` learning's exact defect class |
| `push = true` measured flip | "evaluate … a Slack or GitHub-issue webhook channel" — push is the third free-tier channel; measured on one arm per #9168 | inferred — cheap measured arm of the same ask; revertible |
| Slack coverage measurement (Phase 0) | "evaluate escalation-policy arm vs a Slack or GitHub-issue webhook channel" | asked |
| feeder `/fail` verdict arm | "report serving verdicts so a serving-dead-but-probe-alive state alerts" | asked |
| postmerge Phase 3.9 | "postmerge phases … an active observability soak" | asked |
| `post-deploy-incident-soak.sh` | "an active observability soak" | asked |
| ADR-297 + C4 views | "alert routing" is a channel-boundary decision a future engineer would be surprised to find undocumented (ADR-260 precedent) | inferred — `wg-architecture-decision-is-a-plan-deliverable` |
| heartbeat-manifest.ts comment update | — | inferred — keeps the executable manifest's semantics honest after the beat's meaning changes (the manifest is the repo's anti-fiction device, #6537) |
| followthrough-convention.md row | — | inferred — the convention file is the registry a generic soak script must land in to be discoverable |
| suite registration rows (test-all.sh, suite-durations.tsv, suite-shard-legs.tsv) | — | inferred — unregistered suites never run; the registration set is the repo's suite-discovery contract |

### Split Assessment

- Subsystems touched: 4 — `scripts`, `.github/workflows`, `apps/web-platform` (server + infra), `plugins/soleur` (lib + skills)
- Planned files: ~19 | Estimated changed lines: ~750 (new script ~300 + test ~250 + workflow ~110 + feeder delta ~80 + small edits)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — marginally under thresholds; cohesive arc. The sentry-monitor *routing* half (detectorIds in `alert-reference.json`) is the one mechanical follow-up the two-PR rule may force.

## Observability

```yaml
liveness_signal:
  what: "scheduled-betterstack-incident-mirror run (15-min watchdog dispatch; Sentry cron check-in per run) + the mirror's own filings"
  cadence: "every 15 min (watchdog clock primary, schedule: fallback)"
  alert_target: "sentry_cron_monitor.scheduled_betterstack_incident_mirror -> Sentry issue (unrouted at first apply — two-PR rule; routing is the follow-up PR)"
  configured_in: "apps/web-platform/server/watchdog-dispatch-table.ts; .github/workflows/scheduled-betterstack-incident-mirror.yml; apps/web-platform/infra/sentry/cron-monitors.tf"
error_reporting:
  destination: "Sentry cron check-in error status + ::error:: annotation + ci/betterstack-incident GitHub issues for the mirrored incidents themselves"
  fail_loud: "yes — read failures exit non-zero and check in error; a silent mirror is the defect class this plan exists to close"
failure_modes:
  - mode: "Better Stack API unreadable (auth/network/5xx)"
    detection: "mirror step non-zero + Sentry check-in error"
    alert_route: "Sentry issue on the mirror's cron monitor"
  - mode: "mirror workflow dead (dispatch clock + fallback both dark)"
    detection: "missed Sentry check-in beyond interval+margin"
    alert_route: "Sentry cron monitor missed-check-in issue"
  - mode: "feeder withholds/beat-fails (WS2: not-serving rows or dead probe)"
    detection: "existing verdict= markers + heartbeat incident"
    alert_route: "heartbeat incident -> WS1 mirror -> GitHub issue (and email/Slack as wired)"
  - mode: "dedupe files under a wrong title (the #10918 class)"
    detection: "incident-id marker in issue body keys dedupe, never title alone; mirror-filed issues carry a machine marker"
    alert_route: "new issue per distinct incident id"
  - mode: "push flip refused by vendor (422/no-op)"
    detection: "apply-time error or post-apply attribute read-back"
    alert_route: "per-merge apply run red / measured revert to push=false"
logs:
  where: "GitHub Actions run logs (mirror workflow, feeder workflow); filed issue comments carry projected incident metadata"
  retention: "GHA default retention; issues are permanent"
discoverability_test:
  command: "bash scripts/betterstack-incident-mirror.sh --selftest"
  expected_output: "betterstack-incident-mirror selftest: ok"
```

## Encryption Posture

```yaml
at_rest:
  - store: "GitHub issue bodies (mirror filings, on jikig-ai/soleur private repo)"
    mechanism: "GitHub platform encryption at rest"
    evidence: "vendor platform default; contents are projected incident metadata only (no credentials, no ping URLs — the projection is the control)"
    defends_against: "leak of beat-capability URLs or tokens into issue text"
    does_not_defend: "a GitHub/org compromise; monitor-name enumeration is accepted (private repo)"
    disclosed_as: "vendor platform default for a private repo"
    live_verification: "issue bodies carry only {id,name,cause,started_at} + run/vendor URLs — asserted by the mirror's projection tests"
in_transit:
  - connection: "GHA runner -> uptime.betterstack.com (GET /api/v2/incidents, /heartbeats)"
    tls: "yes"
    cert_verification: on
    does_not_defend: "a stolen BETTERSTACK_API_TOKEN_READONLY replayed from elsewhere — bounded by read-only scope (cannot pause/edit/delete; can read ping URLs, which is why output is projected)"
    disclosed_as: "HTTPS vendor API, token on curl stdin config (never argv)"
  - connection: "GHA runner -> api.github.com (gh issue list/comment/create)"
    tls: "yes"
    cert_verification: on
    does_not_defend: "a workflow-file write on a pushed branch reaching github.token — bounded by permissions block (contents:read, issues:write)"
    disclosed_as: "GitHub Actions github.token"
  - connection: "GHA runner -> sentry ingest (check-in)"
    tls: "yes"
    cert_verification: on
    does_not_defend: "a forged ok check-in — same posture as every sibling watchdog workflow"
    disclosed_as: "Sentry check-in endpoint (public key only)"
exception: absent
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — one
  `sentry_cron_monitor` resource. Providers: `jianyuan/sentry` (already
  declared in the sentry root). No new providers, no new root.
- `apps/web-platform/infra/inngest.tf` — `push = true` attribute flips on two
  existing `betteruptime_heartbeat` resources (measured arm; documented
  revert).
- Sensitive variables: none new. `BETTERSTACK_API_TOKEN_READONLY` already
  exists as a repo Actions secret (read by the feeder workflow); the mirror
  workflow consumes the same secret — no new Doppler secret resource, no
  manual secret mutation.

### Apply path

(b) `terraform apply` via the existing per-merge apply workflow for the
sentry root (`apply-sentry-infra.yml` — see #6472 note below) and the
web-platform root (`apply-web-platform-infra.yml`). No host replace, no
cloud-init, no `terraform_data` SSH fan-out — the mirror is a repo-side GHA
surface. Expected downtime/blast-radius: none (a new monitor + two boolean
flips).

### Host fan-out

None — no `terraform_data` SSH provisioners touched.

### Distinctness / drift safeguards

- `dev != prd`: the mirror reads the prd Better Stack account read-only; the
  sentry monitor lands in the existing prd sentry root.
- `sentry_cron_monitor` lands unrouted per the two-PR rule — a missed
  check-in opens a Sentry issue but emails nobody until the routing PR;
  acceptable because the workflow also `::error::`s and the incidents it
  mirrors file GitHub issues regardless.
- **#6472 acknowledged:** `detect-changes` is blind to
  `apps/web-platform/infra/sentry/**` — the PR body records the interim
  mitigation (`terraform validate` + `terraform fmt -check` on
  `apps/web-platform/infra/sentry/` run explicitly, output pasted). Not
  folded in: #6472 is a CI-behavior change a CTO ruling (D-4) ordered ahead
  of the required-check work.
- `push = true` flips carry the #9168 measured-flip comment; a vendor refusal
  reverts to `push = false` in the same PR.

### Vendor-tier reality check

- `betteruptime_policy` stays `count = var.betterstack_paid_tier ? 1 : 0` —
  untouched. The mirror requires nothing the current tier lacks (read-only
  API + existing Slack integration + GitHub issues). `push = true` is the
  only tier-uncertain attribute, and it is the measured arm by design.

## Architecture Decision (ADR/C4)

- `### ADR` — create **ADR-297 (provisional)** via `soleur:architecture`:
  "Better Stack incidents mirror to deduplicated GitHub issues via a
  repo-side watchdog workflow; Responder-tier escalation deferred
  (operator-reserved); `push = true` measured on the two inngest heartbeats."
  Alternatives to record: paid escalation policy, outgoing webhook → Slack
  (ADR-260's rejection stands), in-place mirror inside an existing watchdog.
  Renumber per `soleur:ship`'s ADR-Ordinal Collision Gate; on renumber,
  `grep -rn 'ADR-297' knowledge-base/project/{plans,specs}/` and sweep all
  planning refs in the same edit.
- `### C4 views` — Container view: the mirror adds a
  `betterstack -> github actions` read edge and a
  `github actions -> github issues` write edge. Checked all three files
  (`model.c4`, `views.c4`, `spec.c4`): `slack` exists as an external system
  (ADR-260); `github`/`betterstack` elements exist; the incident-mirror edge
  is not yet modeled. Element+relationship additions land in this PR; run
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- `### Sequencing` — ADR authored `status: adopting`? No — the channel is
  live on merge; author as accepted-on-merge (no soak-gated state change).

## Guard Contract

### Guard 1 — Mirror filing correctness (`betterstack-incident-mirror.test.sh`)

**Property.** Every open Better Stack incident produces exactly one open
`ci/betterstack-incident` issue keyed on the incident id marker; a resolved
incident resolves only its own mirror-filed issue; a read failure always
exits non-zero (never a silent green).

**Assembly.** The single filing chokepoint in
`scripts/betterstack-incident-mirror.sh` (all `gh issue` writes flow through
it) + the projection function + the dedupe matcher (title AND body
incident-id marker) + the exit-contract trap.

**Mutation matrix.**

| # | Edit | Must drive |
|---|---|---|
| 1 | Mirror exits 0 having read an empty incident list while the fixture presents one open incident (guard's own dispatch) | RED |
| 2 | Two open incidents on DIFFERENT heartbeats (second member after a compliant first) | two distinct issues — RED if only one filed |
| 3 | Reorder: resolve an incident BEFORE its filing pass in the same run (order/lifetime property — moved, not deleted) | no issue created for it / resolved comment only — RED if filed open |
| 4 | A human-filed same-title issue with no incident-id marker (the #10918 class) | left untouched; a new mirror issue filed — RED if commented/closed |
| 5 | `gh issue list` returns transport failure mid-run | exit non-zero — RED if 0 |
| 6 | `pagination.next` non-null | annotation emitted + page-1 processed — RED if silently ignored |
| 7 | Harness: the fake `gh` records argv; assert a filing reaches `gh issue create` with the exact labels set (must-PASS differs from canonical in label ORDER only — permitted) | PASS proves non-vacuous harness |

**Anchor.** The fixture corpus is independent of the .tf files: incident
names are synthesized per test (cq-test-fixtures-synthesized-only); a renamed
heartbeat still flows through `name` fields read live, not constants.

### Guard 2 — Feeder verdict routing (`inngest-probe-heartbeat-feeder.test.sh`)

**Property.** The beat sent is a function of the newest fresh dedicated
row's serving verdict: `not-serving` → `/fail`, `healthy`/`stopped-by-brake`
→ normal beat, `probe-unavailable` → withhold; no path reaches the ping URL
that did not pass both chokepoints.

**Assembly.** The one `beat_once` call site + the verdict routing added to
`check_freshness`'s jq selection + the `classify_dedicated_host` source
contract (load or fail-closed, same census shape as the probe-row lib).

**Mutation matrix.**

| # | Edit | Must drive |
|---|---|---|
| 1 | Fresh dedicated row `server_active=inactive http_code=000` | `/fail` POST observed, normal beat absent — RED if normal beat sent |
| 2 | Fresh row `server_active=active http_code=200` followed by a second row `cutover_flag=rolled-back` (second member) | two normal beats, zero `/fail` — RED on any `/fail` |
| 3 | Reorder: `not-serving` row older than a `healthy` row in the same window (newest wins) | normal beat — RED if `/fail` sent on the stale verdict |
| 4 | `/fail` POST answered 500 | exit 4 — RED if 0 or silent retry to normal beat |
| 5 | `classify_dedicated_host` fails to load (substitute seam) | exit 3 `selector_unavailable`-class — RED if beat sent |
| 6 | Harness: `beat_once` stub records target URL suffix; a fixture where the row is healthy asserts suffix absent (must-PASS differing in verdict, permitted by contract) | PASS proves the harness sees both arms |

**Anchor.** The classifier is shared with scheduled-inngest-health.yml —
its own suite (`inngest-dedicated-host-classify.test.sh`) pins the verdict
vocabulary; the feeder's fixtures reference the vocabulary, never restate it.

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` against every
planned file. Matches (all via the `scripts/followthroughs/` directory
prefix and one via `sentry-monitor-iac-parity.test.ts`):

| Issue | Planned file touched | Disposition |
|---|---|---|
| #10464 / #10463 / #10462 (zot fill-rate probe review trio) | `scripts/followthroughs/` prefix match only — different scripts | **Acknowledge** — unrelated suite; no shared file |
| #8800 (census sandbox write-through) | `scripts/followthroughs/` prefix | **Acknowledge in design** — new suites keep the fixture-isolation contract (synthesized fixtures only, `cq-test-fixtures-synthesized-only`) |
| #8659 (33 suites leak incident sandbox via composed EXIT trap) | `scripts/followthroughs/` prefix | **Acknowledge in design** — the new scripts' EXIT traps follow the single-trap contract, mirroring the feeder's shape |
| #8435 (follow-through probe evidence) | `scripts/followthroughs/` prefix | **Acknowledge** — convention precedent, not a conflict |
| #8595 (NON_INNGEST_MONITORS stale entries + cadence parity) | `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` | **Acknowledge** — the new dispatch-table row must satisfy whatever cadence-parity shape #8595 lands; the plan's monitor keeps `*/15` parity between workflow cron and monitor crontab by construction |

Adjacent (non-code-review) context issues the brief names, with dispositions:

| Issue | Relationship | Disposition |
|---|---|---|
| #6645 (heartbeat live-reconcile mismatch) | Adjacent — reconcile reads manifest-vs-live config drift; the mirror reads incident state | **Acknowledge** — different property; comment on the issue naming the new mirror so future triage routes incident-vs-config correctly |
| #10918 (escalation FAIL filed under wrong title) | Same filing-pattern class — title-keyed dedupe confusion | **Acknowledge in design** — the mirror's dedupe keys on an incident-id body marker, never title alone; its own two failure classes (incident vs mirror-degraded) get distinct titles |
| #10584 (plugin_seed_copy_failed alert gap) | Same alert-routing family — log alerts (`logtail_exploration_alert`) are Telemetry objects, not uptime incidents; the `/api/v2/incidents` read does NOT cover them | **Defer** — needs a Telemetry-alerts read (different API surface); file a re-evaluation note on #10584 naming the mirror as the pattern to copy for Telemetry alerts |
| #10914 (git-data alert routing — sibling pattern) | Sibling routing arc (Sentry paging rule + monitor routing, two-PR rule) | **Acknowledge** — consistent shapes; the mirror's sentry monitor lands unrouted per the same two-PR rule #10914 navigates |
| #6472 (detect-changes blind to infra/sentry) | Our sentry-root edit rides the blind gate | **Acknowledge** — interim mitigation (explicit `terraform validate`/`fmt` on the sentry root in PR body); not folded (CTO D-4 ordering) |
| #9705 (dead-probe heartbeat evidence) | #9703 sibling | **Acknowledge** — WS2's live read-back AC doubles as evidence; comment cross-reference |

## Implementation Phases

### Phase 1 — Measurement + mirror core (WS1)

1. Phase-0 measurements (record in PR body): `slack-integrations`,
   Oct-22 incident list, heartbeat status vocabulary.
2. `scripts/betterstack-incident-mirror.sh` + `.test.sh` (TDD per
   `cq-write-failing-tests-before`; xtrace refusal + TLS-subversion
   prologue + token-on-stdin parity with the feeder; projection discipline
   per `send-failed-alert-probe-8097.sh`).
3. Workflow + `watchdog-dispatch-table.ts` row + parity-test cohort updates.
4. `sentry_cron_monitor.scheduled_betterstack_incident_mirror`.

### Phase 2 — Serving verdict (WS2)

5. Feeder extension + harness fixtures (a)–(f); workflow `status:`/annotation
   updates; manifest comment; runbook one-liner in `inngest-server.md`
   "Arming the probe heartbeat" (beat now certifies serving verdict).
6. `push = true` measured flip on the two heartbeats in `inngest.tf`.

### Phase 3 — Post-merge soak + records (WS3)

7. `postmerge` Phase 3.9 + report lines.
8. `post-deploy-incident-soak.sh` + harness + followthrough-convention row.
9. ADR-297 (provisional) + `model.c4`/`views.c4` edges.
10. Comments: cross-reference notes on #6645/#10584/#9705.

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1: `scripts/betterstack-incident-mirror.sh --selftest` prints
  `betterstack-incident-mirror selftest: ok` (the discoverability probe;
  no network, no credentials).
- [ ] FR-2: With a fixture open incident on `soleur-inngest-consumer-prd`,
  the mirror creates exactly one `[ci/betterstack-incident]` issue carrying
  labels `ci/betterstack-incident`, `action-required`, `priority/p1-high`
  and an incident-id marker in the body; a second run comments instead of
  duplicating.
- [ ] FR-3: A mirror-filed issue whose incident leaves the open set gets a
  resolved comment; a human-filed same-title issue without the marker is
  untouched.
- [ ] FR-4: `scheduled-betterstack-incident-mirror.yml` carries `schedule:`
  fallback + `workflow_dispatch` only, `cancel-in-progress: false`, a
  `WATCHDOG_DISPATCH_TABLE` row (`intervalMinutes: 15`, non-empty
  eligibility), and a terminal `sentry-heartbeat` step naming
  `scheduled-betterstack-incident-mirror`.
- [ ] FR-5: `sentry_cron_monitor.scheduled_betterstack_incident_mirror`
  exists in `cron-monitors.tf` with margin ≤ the parity ceiling and the
  unrouted landing noted.
- [ ] FR-6: The feeder beats `<url>/fail` (and only that) when the newest
  fresh dedicated row classifies `not-serving`; normal beat on
  `healthy`/`stopped-by-brake`; exit 3 withhold on `probe-unavailable`.
- [ ] FR-7: `inngest.tf` flips `push = true` on `inngest_prd` and
  `inngest_consumer` with the measured-flip comment (revert path named).
- [ ] FR-8: `postmerge` documents Phase 3.9 with both report lines
  (`Alert-channel sweep: …`) in the Phase-6 comment template and Phase-7
  report block.
- [ ] FR-9: `post-deploy-incident-soak.sh` exits 0 iff zero new incidents and
  zero new `ci/` issues in `[deploy_ts, +Nh]`; TRANSIENT on read failure;
  registered in `scripts/test-all.sh` + the two TSVs.
- [ ] FR-10: ADR-297 (provisional) exists and `model.c4`/`views.c4` carry the
  mirror edges; `c4-code-syntax` + `c4-render` suites green.

### Non-Functional Requirements

- [ ] NFR-1: No file inside sibling #10966's diff surface is edited
  (`inngest-bootstrap.sh`, `betterstack-logs-alerts.tf`, `server.tf`,
  `ship/SKILL.md`, `inngest-luks-cutover.*`, `scripts/lib/inngest-probe-row.test.sh`,
  `inngest.test.sh`, `journald-config.test.sh`, `ci-deploy.test.sh`,
  `build-inngest-*.yml`, `apply-deploy-pipeline-fix.yml`).
- [ ] NFR-2: No new secrets or Doppler writes; the mirror consumes the
  existing `BETTERSTACK_API_TOKEN_READONLY` repo secret.
- [ ] NFR-3: Every credentialed curl keeps the repo shape — `--config -`
  stdin, `--disable --noproxy '*'`, xtrace refusal, no token on argv.
- [ ] NFR-4: No `betteruptime_policy` or paid-tier resource is created;
  `var.betterstack_paid_tier` is untouched.

### Quality Gates

- [ ] QG-1: New suites registered in `scripts/test-all.sh`,
  `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`; each named
  in an `AFFECTED_*_PATHS`-reachable registration (per the #7243 edge).
- [ ] QG-2: `terraform validate` + `terraform fmt -check` on
  `apps/web-platform/infra/sentry/` run explicitly and pasted in the PR
  body (the #6472 interim mitigation).
- [ ] QG-3: Guard Contract mutation matrices both executed RED before green
  (harness run order: mutations first, then the suite).
- [ ] QG-4: PR body carries the Phase-0 measurement outputs
  (slack-integrations, Oct-22 incidents, status vocabulary).
- [ ] QG-5: Live read-back after merge: `GET /api/v2/heartbeats` shows
  `inngest_server_probe` `paused:false status:up` and both inngest
  heartbeats' `push` attribute state — recorded in the postmerge comment.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/observability tooling
change. Semantic sweep of all 8 domains: Engineering-internal (alerting,
workflows, Terraform) only; no user-facing surface (no `.tsx`/`page.tsx`/
layout file in Files to Create/Edit — the mechanical UI-surface override
does not fire, so the Product/UX Gate is NONE); no regulated-data surface
(GDPR gate silent — no schema/migration/auth/API-route/.sql edit, none of
the (a)–(d) expansion triggers: no LLM processing of operator data, no
`single-user incident` threshold, no cron reading `learnings/`/`specs/`, no
new distribution surface); no finance/legal/marketing/sales/support
implications.

## Enhancement Summary (deepen-plan pass)

Executed inline on the Devin harness (no subagent spawn — all halt gates and
the review fan-out ran sequentially in this process; `Reviewed-Coverage:
sequential-fallback`).

### Gate verdicts

- 4.4 precedent-diff (scheduled-work pattern): new workflow conforms to the
  ADR-248 shape (schedule fallback + workflow_dispatch + concurrency
  `cancel-in-progress:false` + dispatch-table row + terminal
  sentry-heartbeat) — PASS.
- 4.5 network-outage deep-dive: not triggered — no `provisioner`,
  `remote-exec`, or `connection {}` block in any planned resource.
- 4.55 downtime/cutover: not triggered — no availability-affecting operation
  (monitor resource + two boolean attribute flips + repo-side workflow).
- 4.6 user-brand impact: PASS (`none` + reason bullet present).
- 4.7 observability: PASS — 5-field schema; `discoverability_test.command`
  first token `bash` (allowlisted), repo-relative `--selftest`, literal
  `expected_output`, no `ssh`, ≤15 s shape.
- 4.8 PAT-shaped variable: PASS — no new TF variable or PAT-minting default.
- 4.9 UI wireframe: not triggered — no UI surface.
- 4.10 encryption posture: PASS — `at_rest`/`in_transit` populated; no
  `exception` block required (all TLS, no plaintext exception).
- 4.11 guard contract: PASS — 2 guards, each with Property/Assembly/≥3-row
  mutation matrix + harness row + anchor.
- 4.12 scope check: PASS — exactly one `## Scope Check`; every ask mapped;
  no `status: BLOCKED`.

### Deepen-pass corrections applied

- `## Domain Review` section added (missed on first pass).
- Code-review overlap results persisted (7 matches: 6 prefix-level
  acknowledgments + #8595 cadence-parity constraint carried into FR-4).
- No load-bearing correction requiring `tasks.md` re-propagation.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Mirror: open incident → one issue; rerun → comment not create; resolved →
  resolve-comment; human same-title → untouched; pagination.next →
  annotated; API 401 → non-zero + error check-in; empty set → exit 0 with
  an explicit `no_incidents` marker (never a bare 0).
- Feeder: fixtures (a)–(f) in Guard 2's matrix.
- Soak: window pinned strictly after deploy; `paused`/`pending` monitor →
  TRANSIENT-equivalent (not FAIL); liveness-absent → TRANSIENT.

### Regression Tests

- `heartbeat-manifest.ts` parity suite unchanged-green (no row added).
- `sentry-monitor-iac-parity.test.ts` green with the new table row.
- The feeder's existing exit-contract fixtures stay green.

### Edge Cases

- Incident on a `paused` heartbeat (armed-then-paused drift) — appears in
  `resolved=false` reads only while open; the mirror reports what the API
  reports, and the reconcile owns config drift.
- >50 open incidents (page cap): annotated, page-1 processed, never a
  silent drop (the feeder's page-1 discipline).
- Issue-title collision with a renamed monitor: incident-id marker is the
  dedupe key; the title is display-only.

### Integration Verification (for `soleur:qa`)

- `bash scripts/betterstack-incident-mirror.sh --selftest`
- `bash scripts/lib/inngest-probe-row.sh --selftest` (unchanged contract)
- `bun test apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`

## Success Metrics

- Any Better Stack incident on an armed monitor/heartbeat produces a
  deduplicated GitHub issue ≤ 20 min after `started_at`.
- The next `not-serving` dedicated-host state opens a heartbeat incident via
  `/fail` (vendor-side), mirrored to an issue by WS1 — two watched surfaces.
- `soleur:postmerge` reports the alert-channel state on every merge, and a
  soak can be enrolled with one directive line on the merge tracker.

## Dependencies & Prerequisites

- `BETTERSTACK_API_TOKEN_READONLY` repo secret (exists — feeder consumes it).
- Watchdog dispatch clock (ADR-248) delivering the 15-min slot.
- Sibling #10966 merge order: prefer merging this AFTER #10966 lands or
  rebase — the file sets are disjoint by construction (NFR-1), so order is
  preference, not requirement.
- #9703 stays open until the WS2 arm lands; this plan's PR body carries
  `Ref #9703` and `Closes` only where the issue's own tasks are completed
  (check (d)'s "remove arming_pending" — already done; WS2 is beyond the
  issue's letter, so `Ref` not `Closes`).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| Slack already covers heartbeats and the mirror duplicates noise | Measurement first; the mirror dedupes and is the durable channel even when Slack fires (a read-only issue is cheap; a missed page is not) |
| `push = true` refused at apply | #9168 measured-flip convention: revert to `false` in-PR, note in manifest comment |
| Mirror files during an ongoing incident storm | Dedupe by incident id; comments on subsequent runs; `action-required` label only on create |
| Feeder `/fail` arm pages on a deliberate `stopped-by-brake` | Brake rows keep normal beat (verdict table); the health watchdog owns brake filings |
| Mirror's own Sentry monitor unrouted at first apply (two-PR gap) | Documented; the workflow `::error::`s and files issues regardless; routing PR follows the sentry README §186 flow |
| Incident-id marker forgery | Mirror-filed issues carry `<!-- betterstack-incident id=<n> -->`; resolve path requires BOTH marker match AND incident absence — a forged marker can only suppress its own resolution |

## Resource Requirements

~19 files, ~750 lines. No new vendor accounts, no secrets, no host changes,
no paid features.

## Future Considerations

- Telemetry (`logtail_exploration_alert`) incident mirroring — a different
  API surface; #10584 is the tracker, named in this plan's deferral note.
- Responder-tier escalation — operator-reserved (money; ADR-260 revisit
  condition).
- Routing the mirror's own Sentry monitor (second PR per the two-PR rule).

## Documentation Plan

- `inngest-server.md` runbook: "Arming the probe heartbeat" gains the
  serving-verdict sentence + `/fail` semantics.
- `followthrough-convention.md`: soak-trigger row for the new script.
- ADR-297 (provisional) + C4 model/views updates (in-scope deliverables).
- Mirror workflow header comment carries the ADR-248 gate-override
  justification (the `new-scheduled-cron-prefer-inngest` lint shape).

## References & Research

### Internal References

- `apps/web-platform/infra/{inngest.tf,uptime-alerts.tf,alerts-github-webhook.tf}`
- `apps/web-platform/infra/sentry/{cron-monitors.tf,README.md}`
- `scripts/{inngest-probe-heartbeat-feeder.sh,inngest-dedicated-host-classify.sh,
  betterstack-query.sh,lib/inngest-probe-row.sh,
  followthroughs/send-failed-alert-probe-8097.sh}`
- `apps/web-platform/server/watchdog-dispatch-table.ts`
- `plugins/soleur/lib/heartbeat-manifest.ts`
- `.github/workflows/{scheduled-inngest-health.yml,
  scheduled-inngest-probe-heartbeat.yml,apply-delivery-gap-follower.yml,
  scheduled-followthrough-sweeper.yml,post-merge-monitor.yml}`
- `plugins/soleur/skills/postmerge/SKILL.md`
- ADR-117, ADR-204, ADR-222, ADR-248, ADR-260, ADR-282
- `knowledge-base/engineering/operations/runbooks/{app-database-readiness-alarm.md,
  inngest-server.md,followthrough-convention.md,betterstack-log-query.md}`

### External References

- Better Stack uptime API docs: `/api/v2/incidents`, `/api/v2/heartbeats`,
  `/api/v2/monitors`, `/api/v2/slack-integrations`
- Better Stack Slack integration docs (basic single-channel posts all
  incidents; scoping requires escalation policies = paid)
- Better Stack heartbeat `/fail` URL suffix (signaled-failure beats; in-repo
  precedent `web-bash-synthetic.sh:135`)

### Related Work

- #10390 (epic), #9703, #9705, #10853, #10854, #6645, #10918, #10584, #10914,
  #6472, #9168, ADR-260; sibling draft PR #10966
  (`feat-one-shot-inngest-window-prework` — LUKS cutover retirement, disjoint
  file set), draft PR #11001 (this branch).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the
  threshold fails deepen-plan Phase 4.6 — filled above (`none` + reason
  bullet).
- `discoverability_test.command` must be an allowlisted probe verb, ≤15 s,
  no `ssh`, literal `expected_output` — the `--selftest` form chosen here is
  the repo's own idiom (`inngest-probe-row.sh --selftest` precedent).
- New workflow-YAML suites under `plugins/soleur/test/` need
  `AFFECTED_*_PATHS` registration — the mirror harness lives under
  `scripts/` (sh) beside its subject, matching the feeder's own placement,
  not `plugins/soleur/test/`.
- `decision-challenges.md` table format is machine-gated — rows use
  `pending - assumed:` per the technical-ruling contract for runs without
  agent-spawn; `technical-ruling-gate.sh` should be run at ship time.
- Vendor-behavior claims are measured, not asserted (Phase-0 items; the
  #9545/PR #10349 "fixtures from my model" edge).
- Diff-scope discipline: the file list above is the whole plan — pipeline-
  generated artifacts (`specs/<branch>/session-state.md`, INDEX.md) are
  expected additions outside it.
