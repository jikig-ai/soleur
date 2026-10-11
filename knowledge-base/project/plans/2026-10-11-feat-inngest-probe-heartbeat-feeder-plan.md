---
title: "observability(infra): wire the feeder for betteruptime_heartbeat.inngest_server_probe"
date: 2026-10-11
slug: inngest-probe-heartbeat-feeder
branch: feat-one-shot-9703-inngest-heartbeat-feeder
issue: 9703
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# observability(infra): wire the feeder for `betteruptime_heartbeat.inngest_server_probe` (Ref #9703)

## Enhancement Summary

**Deepened on:** 2026-10-11
**Research and review agents used:** repo-research-analyst, learnings-researcher, DHH / Kieran / code-simplicity plan review, CTO (devex), observability-coverage-reviewer, security-sentinel, architecture-strategist, spec-flow-analyzer, test-design-reviewer, git-history-analyzer; live read-only probes of Better Stack (heartbeat state, token scopes) and the Logs warehouse (48 h probe cadence).

### Key improvements folded in
1. The feeder uses the **read-only** Better Stack token (`BETTERSTACK_API_TOKEN_READONLY`, verified to return the heartbeat `url` attribute), so GET-only is enforced by capability, not by a static scan. Writes live only in the separately authorized arming command, which reads the write token from Doppler locally.
2. The arming command is now a **self-rolling-back compound command**: id resolved by name and asserted, state-gated on `paused`, unpause confirmed by read-back, a `trap` rollback with three verified retries, a 4500 s wall-clock deadline (a 15-minute rollback margin), and a token-shape guard.
3. **Stage 3 is split**: 3a (one-line record PR dropping `arming_pending`, right after read-back, re-arming the reconcile's `fed-but-paused` alarm) and 3b (deletions, gated mechanically on the read-back). This closes the "re-paused after arming reads as success" window.
4. The verifier's verdict line carries **funnel counts** (`rows_total / rows_probe / rows_host / rows_dedicated`, `newest_dt`) so each competing cause is distinguishable from one log line; helper and curl stderr are never relayed, and the workflow keeps only lines that match the marker shapes.
5. The harness follows the sibling `inngest-luks-property-8296.test.sh` conventions: a strict curl stub with a refusal log, a private `PATH`, committed scratch-copy mutation runs with a landing check, `MIN_PASSES` plus a conservation check instead of an exact case literal.
6. The ADR-248 eligibility argument is restated honestly (shared failure domain, same class as the zot row; the load-bearing reason is the credentialed bash pipeline), with an ADR-248 amendment for the third row and its run-count delta.
7. Measured, read-only: 48 dedicated probe rows in 48 h, consecutive gaps 3599–3650 s, no gaps at the hot/archive seam in that series.

### New considerations discovered
- Repo write access already confers access to every repo secret (a branch workflow can read them), so "runs only from main" was not a control; the real mitigation is the read-only token.
- A Sentry `error` check-in means "withheld", not "feeder broken"; pre-arm it reaches an unrouted monitor only.
- `fresh_heartbeat_paused` exits 0 by design, so a re-pause after arming is invisible to the feeder; the nightly reconcile is the net once `arming_pending` is gone.

## Overview

`betteruptime_heartbeat.inngest_server_probe` (live id 504655, `soleur-inngest-server-probe-prd`,
period 3600 / grace 1800, paused; read back read-only on 2026-10-11) is the dead-man's-switch
sibling of `logtail_exploration_alert.inngest_luks_wrong_volume`, which reads a silent probe
pipeline as healthy (`on_missing_data = "treat_as_zero"`). It has no feeder, so it is inert. Since
2026-10-09 the plaintext backstop is destroyed and `hcloud_volume.inngest_redis_luks` is the sole
copy of the store, so this heartbeat is the only dead-probe tripwire besides the daily
`inngest-luks-property-8296.sh` follow-through probe, which the issue says stays until this feeder
is armed.

This plan delivers it in separately-gated stages. Only Stage 1 is executed by this pipeline run:

| Stage | What | Production writes | Who/when |
|---|---|---|---|
| 1. Code PR (this run) | repo-side verifier script + its harness, a clock-dispatched workflow, the Sentry liveness monitor (declared, unrouted), the manifest row flip, parity-test and doc updates, and one repo secret copied from Doppler (Phase 0) | None against Better Stack. Merging this PR alone does three things in production: (i) `apply-sentry-infra.yml` creates one Sentry cron monitor; (ii) because the diff touches `apps/web-platform/infra/**`, `apply-web-platform-infra.yml` also fires on push — its `-target` plan covers resources this diff does not change, so the expected plan for the heartbeat and its Doppler secret is no-op; (iii) the web release that carries the new dispatch-table row starts clock-dispatched runs of the new workflow, which beat nothing while the heartbeat is paused. `uptime-alerts.tf` is NOT edited | ships through merge |
| 2. Arming | unpause the heartbeat, watch `status` reach `up`, roll back to paused if it never does | YES: Better Stack API writes (PATCH `paused`) plus one GitHub workflow dispatch | one compound command, shown in full and authorized as a unit before it runs; named in `## Arming Procedure`; nothing executes it in this run |
| 3a. Record PR | drop `arming_pending` from the manifest row (re-arms the reconcile's `fed-but-paused` alarm); docs say "armed" only now | None | immediately after Stage 2's read-back shows `paused=false status=up` |
| 3b. Cleanup PR | delete the superseded 8296 probe and every row naming it, route the Sentry monitor, close #9703 explicitly | None against Better Stack | after 3a merges and a mechanical read-back gate passes (Phase 7) |

Target: Stage 1 merged and Stage 2 done before **2026-10-22**, the issue's own re-evaluation date. If the date passes unarmed: the 8296 probe stays (it is the only reporter until then), #9703 gets a dated re-evaluation comment, and every doc keeps the wording "inert until armed" — nothing in the repo may read as protection that does not exist.

### The design in one paragraph

A bash verifier `scripts/inngest-probe-heartbeat-feeder.sh` queries the Better Stack Logs warehouse
through `scripts/betterstack-query.sh`, selects probe rows with the shared predicate in
`scripts/lib/inngest-probe-row.sh` (emitter + anchored marker + `host_role=dedicated` + host
isolation), and takes the newest by `dt`. If that row is no older than **4500 s**, it resolves the
heartbeat's ping URL by exact name from the Better Stack uptime API (GET only, read-only token) and
beats it, unless the heartbeat is still paused, in which case it reports `fresh_heartbeat_paused`
and beats nothing. Exit 0 means exactly `{beat, fresh_heartbeat_paused}`; every other outcome
withholds the beat and exits non-zero. A new workflow `scheduled-inngest-probe-heartbeat.yml` runs it
every **15 minutes**, dispatched by the web server's watchdog dispatch clock (ADR-248, new
`WATCHDOG_DISPATCH_TABLE` row) with a `schedule:` fallback, and posts a Sentry cron check-in (`ok`
iff the verifier exited 0). `period`/`grace` are **not** changed: the 15-minute cadence meets the
5400 s beat budget with the measured dispatch variance, so nothing is written to Better Stack at merge.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality (evidence) | Plan response |
|---|---|---|
| (c) "observe one real beat land in Better Stack, then unpause (the #6210 discipline — verify a ping arrives BEFORE unpausing)" | A paused heartbeat exposes no usable ping timestamp; `updated_at` does not move on a beat while paused (`apps/web-platform/infra/arm-heartbeats.sh` header; ADR-117; learning `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`). The only measurement is unpause, watch `status` reach `up`, roll back before the first absence alert. (`#6210` as cited in the repo's DP-10 comments is a repo shorthand; the arm-then-unpause lineage is ADR-117 / #6540.) | Arming is "unpause + wall-clock-bounded poll + automatic rollback" (`## Arming Procedure`). Pre-arm evidence is the verifier's `verdict=fresh_heartbeat_paused` line: it proves freshness and URL resolution, not a landed beat |
| (b) "`feeder.kind` from `none` to … `cron`/`timer` + file evidence, or `external-probe` with the workflow evidence" | `external-probe` is an `Arming` value (already set on the row), not a `Feeder.kind`; `Feeder` is `cron\|timer\|none` and the `cron` arm carries only `{kind, evidence}` (`plugins/soleur/lib/heartbeat-manifest.ts`). `heartbeat-reprovision-parity.test.ts` pins evidence to the on-host timer-enable construct or a `/etc/cron.d` drop-in, under `apps/web-platform/infra/` | Flip to `kind: "cron"` with workflow evidence (dropping `url_secret`/`tracking_issue`, which belong to the `none` arm) and relax that one test regex to admit `.github/workflows/<x>.yml` + `bash scripts/<x>.sh` |
| "trigger options: `watchdog-dispatch-table.ts` + scheduled workflow + `sentry_cron_monitor`, or the daily follow-through sweeper if period/grace are re-sized" | GitHub `schedule:` delivered one run every 2–7 h on this repo (ADR-248, #8495). The sweeper treats exit 0 as "close the tracker" and runs only for open directive-bearing issues | Watchdog table row. Sweeper rejected (see Alternatives) |
| "mirror the freshness predicate in `inngest-luks-property-8296.sh`" | That script's `STALE_SECS=10800` (3 h) is sized for a daily notify-only probe; a 3 h bound lets a dead probe keep the heartbeat fed for 3 h | Mirror the selection (host, emitter, marker, role, newest-by-dt, future-slack) but derive the bound from the beat budget: 4500 s |
| "`inngest-luks-property-8296.sh` was enrolled on #8285, which closes now" | #8285 is already CLOSED (2026-10-10); the enrolment is marked #8296 inside #8285's body, and the live directive now sits in #9703's body (the sweeper has commented NOT YET exit 2 on #9703 since 2026-10-10T20:30Z) | Nothing to move; Stage 3b removes the directive from #9703 before deleting the script |
| Deletion list names `scripts/lib/inngest-probe-row.test.sh` "references" | It carries the script in `MUST_FIND` (red if the file disappears) | Stage 3b edits `MUST_FIND`; Stage 1 adds the new verifier to it |

## Research Insights

### Premise Validation (Phase 0.6)

- #9703 is OPEN; #8516's PR #9699 is MERGED; #9877 (PR B, backstop retire) is MERGED. No cited blocker is closed or stale.
- On `origin/main` (47c38a19da): `scripts/betterstack-query.sh`, `scripts/lib/inngest-probe-row.sh`,
  `scripts/followthroughs/inngest-luks-property-8296.sh`, `apps/web-platform/infra/uptime-alerts.tf`,
  `plugins/soleur/lib/heartbeat-manifest.ts` (row `inngest_server_probe`, `feeder.kind = "none"`,
  `arming_pending.tracking_issue = 9703`) all exist. Live read-back (read-only GET) shows the heartbeat present, paused, 3600/1800, and its `url` attribute matches `^https://uptime\.betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]+$` (tested without printing the value), with the read-only token as well as the write token.
- ADR corpus check of the proposed mechanism: ADR-117 (executable arming) and ADR-248 (dispatch clock eligibility) govern; neither rejects a workflow feeder.
- **ADR-248 eligibility, stated honestly.** The feeder does not watch the Inngest scheduler's execution (probe-emitter, Vector or sink failures leave Inngest able to fire a cron). It watches something the substrate depends on: the probe attests the LUKS volume that holds Inngest's store. That is the "something that substrate depends on" clause and the same shared-failure-domain class as the zot row, which the repo labels weak as an anti-circularity argument. The load-bearing reasons are the ADR-033 I7 carve-out (a credentialed bash pipeline that stays in an ephemeral runner) and the fact that this is the substrate's own durability tripwire. The `eligibility` string and the workflow header say exactly that, not "the scheduler's own host".
- Better Stack API facts (KB-documented and re-read live): heartbeat attributes carry `status`, `paused`, `period`, `grace`, `updated_at`, `url`; PATCH `{"paused": bool}` is the only arm/disarm write used here. NOT documented anywhere: the response to a beat sent to a paused heartbeat, and whether a period/grace update resets state. This design depends on neither (it never beats while paused and never edits period/grace).
- Measured (read-only, 2026-10-11): `scripts/betterstack-query.sh --since 48h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 5000`, filtered with the shared predicate to host `soleur-inngest` / `soleur-inngest-prd` / `host_role=dedicated`: 48 rows, consecutive `dt` gaps min 3599 s, median 3607 s, max 3650 s, none above 3700 s. The newest row was 9 minutes old at read time. A live hot/archive-seam sample is taken by the Phase 6 soak below.

### Property List (Phase 0.6b)

1. A beat reaches Better Stack only while a fresh `host_role=dedicated` probe row is confirmed in the warehouse.
2. The beat cadence satisfies the 5400 s budget under the measured dispatch variance.
3. The feeder's own liveness and every withheld verdict are visible without SSH, before and after arming.
4. The manifest declares the feeder executably, bound to this specific heartbeat (ADR-117).
5. Arming is a measured, rollback-guarded write that is authorized separately from the code.
6. The superseded 8296 probe and every row naming it are deleted once arming is confirmed.

### Cut List (Phase 0.6b)

| Mechanism | Property | What already covers it |
|---|---|---|
| New ADR | — | An amendment to ADR-117 (workflow feeder as a third evidence class) and a short ADR-248 amendment for the third row |
| New `github_actions_secret` publishing the heartbeat URL, or a URL repo secret set at arm time | 1 | URL is resolved at run time from the uptime API with a read-only token (see Alternatives for why a secret set at arm time is rejected) |
| New arming script or arming workflow | 5 | One-time operation: a single compound command (wall-clock bounded, trap-rolled-back) in the runbook; `arm-heartbeats.sh` keeps serving the recurring push-apply case |
| Widening `period`/`grace` | 2 | 15-minute cadence meets the budget; also avoids an unmeasured Better Stack state reset and a merge-time write |
| `Feeder.kind = "workflow"` type | 4 | Flip to `cron` and relax one test regex |
| Verifier dry-run mode and `dry_run` dispatch input | 1, 3 | Pre-arm every real run already takes the no-write `fresh_heartbeat_paused` path |
| An `EXPECT_ARMED` / `paused_overdue` verifier mode | 3 | Stage 3a drops `arming_pending` right after read-back, which re-arms the reconcile's `fed-but-paused` alarm |
| Opening a GitHub tracker issue on a withheld verdict | 3 | Sentry check-in `error` + the heartbeat's own absence page once armed |
| Shared extraction of the freshness predicate into `scripts/lib/` | 1 | The 8296 probe is deleted in Stage 3b; the duplication is bounded |

### Institutional learnings applied

- `2026-07-16-the-fix-for-an-inert-monitor-…`: paused monitors record no beats, so arm-and-watch with rollback; never claim "armed" in docs/ADRs before the arm step has run.
- `2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md`: `ignore_changes=[paused]` plus a hard-coded arm list leaves members permanently paused; here the arm is a one-time named procedure and the manifest keeps `arming_pending` until read-back.
- `2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md` and the margin budget in `sentry-monitor-iac-parity.test.ts`: margin floor = ceil(12 clock + 30 queue + max_runtime), ceiling 60.
- `2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md` and the sweeper contract: do not enrol the feeder as a follow-through (exit 0 closes a tracker); the verifier lives outside `scripts/followthroughs/`.
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`: PR body and commits use `Ref #9703` only.
- #8659 (open code-review): a suite that installs its own EXIT trap after sourcing `plugins/soleur/test/test-helpers.sh` leaks a sandbox; the new harness lives under `scripts/` and sources no helper, so it carries its own cleanup trap.
- ADR-117 / #7587: an arming deadline is wall clock (`$SECONDS`), not a sleep tally, and the rollback must sit well inside `period + grace`.

### Precedent diff (deepen Phase 4.4)

| Aspect | Precedent | This plan |
|---|---|---|
| Workflow shape, rc-as-data, Sentry final step | `.github/workflows/scheduled-zot-restart-loop.yml` | Same shape; the zot template's `printf '%s\n' "$out"` before `strip_log_injection` is NOT copied (see Phase 2) |
| Probe-row selection and freshness | `scripts/followthroughs/inngest-luks-property-8296.sh` | Same selection and prologue; bound derived (4500 s), exit contract differs (0/3/4/64/78) |
| Heartbeat arming | `apps/web-platform/infra/arm-heartbeats.sh` (`arm_one`, `hb_patch_paused`, wall-clock deadline, token-shape guard) | Same sequence as a one-time compound command; helpers mirrored, not sourced |
| Scheduled-work substrate | ADR-033 (Inngest first) with the ADR-248 table as the sanctioned exception | Table row with the honest eligibility string; `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` header as in the zot workflow |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing customer-visible. The failure shapes are
  an alert that never comes (feeder beats spuriously while the probe is dead, so a store off its
  encrypted device goes unpaged) or a false "dead probe" email to ops@ (feeder under-beats once
  armed). Both are internal observability faults; the heartbeat ships and stays paused until a
  separately authorized arm.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no customer data path. The
  heartbeat URL is a bearer ping endpoint (leak enables beat forgery = denial of one alarm). The
  feeder authenticates to the uptime API with the **read-only** token, so a leak of that token can
  read heartbeat URLs (beat forgery across the account's heartbeats) but cannot pause, delete or
  edit anything. Repo write access already confers access to every repo secret through a branch
  workflow, so this adds no capability class; the read-only scope bounds the blast radius. The
  write token stays in Doppler and is read only inside the separately authorized arming command.
- **Brand-survival threshold:** none
- scope-out: `threshold: none, reason: alerting-only plumbing with no data store, auth path or customer surface; the sensitive-path contacts (apps/web-platform/server/watchdog-dispatch-table.ts, apps/web-platform/infra/sentry/*.tf) are a dispatch-table row and a cron-monitor declaration that existing parity tests gate`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "wire the heartbeat feeder" | Phases 1–3 (verifier, workflow, table row, Sentry monitor) | mapped |
| 2 | "arm betteruptime_heartbeat.inngest_server_probe" | `## Arming Procedure` (Stage 2, authorized as a unit, not executed here) | mapped |
| 3 | "repo-side verifier on a reliable trigger, reusing scripts/betterstack-query.sh + scripts/lib/inngest-probe-row.sh, mirroring the freshness predicate in scripts/followthroughs/inngest-luks-property-8296.sh" | Phase 1 | mapped |
| 4 | "do NOT extend that script to push" | Phase 1 creates a new script; the 8296 script is untouched until Stage 3b | mapped |
| 5 | "the beat budget (period 3600 + grace 1800 => beat at least every 5400 s; a daily feeder requires widening period in the same change)" | `## Beat Budget` (15-minute cadence; period/grace unchanged) | mapped |
| 6 | "the heartbeat-manifest.ts row update" | Phase 4 | mapped |
| 7 | "the probe re-homing/deletion list that applies once armed" | Phase 7 (Stage 3a/3b, separate PRs) | mapped |
| 8 | "split the work into (1) a code PR that wires the feeder + manifest update and ships through merge, and (2) a separate arming step … name the exact commands (plan/read-back/apply) but nothing executes them" | Stage table + `## Arming Procedure` | mapped |
| 9 | "any feeder must be reachable from Better Stack/Sentry without SSH" | `## Observability` | mapped |
| 10 | "Out of scope: web-2 workspaces volume, git_data volume, rehearsal volume, ADR-198 baked credentials." | no file in those surfaces is touched | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/inngest-probe-heartbeat-feeder.sh` | "repo-side verifier on a reliable trigger" | asked |
| watchdog table row + workflow | "`watchdog-dispatch-table.ts` (ADR-248) + a scheduled workflow" | asked |
| Sentry cron monitor `scheduled-inngest-probe-heartbeat` | "a `sentry_cron_monitor` (apps/web-platform/infra/sentry root — mind its two-PR rule)" | asked |
| manifest row flip | "update the `heartbeat-manifest.ts` row" | asked |
| 4500 s bound instead of 8296's 10800 s | "mirror the freshness predicate" | inferred — justification: the issue's budget (5400 s) is unreachable with a 3 h bound; the predicate is mirrored, the constant is derived |
| 15-minute cadence | "Beat budget: period = 3600 + grace = 1800 ⇒ the feeder must sustain a beat at least every 5400 s" | asked (derived) |
| no-beat-while-paused rule | "observe one real beat land … then unpause" | inferred — justification: the response to a beat sent to a paused heartbeat is undocumented, so the feeder never depends on it |
| read-only token as a repo secret (Phase 0) | "Never print secrets" | inferred — justification: removes the account-wide write token from a 96-runs-a-day workflow at the cost of one `gh secret set` copy from Doppler |
| harness suite `scripts/inngest-probe-heartbeat-feeder.test.sh` and the Phase 6 read-only soak | "CI is the authority for the full test battery" | inferred — justification: cq-write-failing-tests-before and the Guard Contract require the suite; the soak measures the hot/archive seam that fixtures cannot |
| ADR-117 and ADR-248 amendments, runbook section, C4 clauses | "Plan must follow hr-observability-as-plan-quality-gate" | inferred — justification: wg-architecture-decision-is-a-plan-deliverable; the evidence-shape change and third table row must not leave recorded architecture stale |
| Stage 3a record PR | "keep `arming_pending` until armed" | asked (the issue's own task d, split out so the reconcile alarm re-arms immediately) |
| Stage 3b cleanup | "the probe re-homing/deletion list that applies once armed" | asked |

### Split Assessment

- Subsystems touched: 5 — `scripts/`, `.github/workflows/`, `apps/web-platform/` (server + infra/sentry + test), `plugins/soleur/`, `knowledge-base/`
- Planned files: ~23 (Stage 1) | Estimated changed lines: ~850 (about 500 are the new harness)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — Stage 1 (this PR) / Stage 3a / Stage 3b. Stage 1 stays ONE PR on purpose: its pieces are mutually tripwired (the manifest row reds when a feeder lands unreconciled; the table row reds without its monitor; the monitor reds without its routing-map entry), so a smaller PR would land red.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed (CTO devex review during plan-review: design sound, no disqualifier; its P1s on the arming command and R1 polling are applied)
**Assessment:** Pure infra/observability. Risks named and handled in-plan: beat-budget math under dispatch variance, a spurious-beat failure suppressing the alarm (single beat call site, host/emitter/role isolation, fixtures for each), credential scope (read-only token), and the ADR-248 eligibility argument (restated as shared failure domain). No product, marketing, legal, finance, sales or support surface. The GDPR gate does not fire: no schema, auth flow, API route or personal-data processing is added, and none of the (a)–(d) cross-controller triggers apply (the warehouse rows carry host/mount fields only).

## Architecture Decision (ADR/C4)

### ADR

Amendments, not a new ADR (no new substrate or trust boundary):

- **ADR-117 (executable heartbeat arming)** — append a short dated amendment worded as a **third evidence class** (ADR-117 names exactly two legal feeder shapes, so this is not a relaxed regex): a heartbeat's feeder may be a clock-dispatched GitHub Actions workflow (`kind: "cron"`, `evidence.file` a workflow under `.github/workflows/`, `evidence.pattern` the `bash scripts/<x>.sh` run line), bound to the heartbeat by name in the verifier, asserted by the feeder's harness, and required to be a `WATCHDOG_DISPATCH_TABLE` row or carry a `schedule:` trigger; and "fed" is not "armed" (the verifier deliberately beats nothing while the heartbeat is paused). Do NOT state the heartbeat is armed (it is not until Stage 2).
- **ADR-248 (watchdog dispatch clock)** — append a dated amendment: a third row (`scheduled-inngest-probe-heartbeat.yml`, 15 min), the honest eligibility class (shared failure domain, like zot), and the run-count delta (+96 runs/day against the org's job budget; the queue figures in the beat budget were measured before this load, so re-measure after merge with the command in `cron-monitors.tf`). The ADR's "two workflows" context sentences stay as history; the amendment supersedes them.

### C4 views

Read all three `.c4` files. Enumeration against the completeness rubric: (a) external human actors — none new; (b) external systems — Better Stack, Sentry, GitHub Actions and the web hosts' dispatch clock are all modeled; (c) containers/data stores — none new; (d) actor-to-surface relationships — none change. Edits, then `bash scripts/regenerate-c4-model.sh`:

- `inngestRedis`: the clause "`betteruptime_heartbeat.inngest_server_probe` (uptime-alerts.tf — born paused; its feeder + arming are tracked on #9703)" becomes: fed by the feeder workflow, arming still tracked on #9703 (not armed yet).
- `api -> github` (line ~691): names "scheduled-inngest-health.yml every 15 min and scheduled-zot-restart-loop.yml hourly" — add the third workflow unconditionally; the new row falsifies the sentence whatever the count gate says.
- `github -> sentry`: the embedded workflow/monitor counts (today 17 workflows, 11 schedule-fired, 64 monitors, 19 from GitHub, 45 from the web app per the parity gate). Take the exact numbers from the failure output of `bash plugins/soleur/test/c4-count-parity.test.sh`; do not hand-derive them.
- `github -> betterstack`: only if `c4-model-freshness.test.sh` demands it.

The `model.c4` description that mentions `inngest-luks-property-8296.sh` is edited in Stage 3b, not here.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf`: new `sentry_cron_monitor.scheduled_inngest_probe_heartbeat` (`name = "scheduled-inngest-probe-heartbeat"`, `crontab = "*/15 * * * *"`, `checkin_margin_minutes = 60`, `max_runtime_minutes = 6`, thresholds 1/1, UTC). Margin 60 is the parity ceiling and covers the measured tail (12 clock + 40.6 queue + 6 runtime = 58.6 min), so a slow runner queue does not file a missed check-in while the heartbeat is still safe. A dead trigger pages within 15 + 60 = 75 min.
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: add the label to `local.cron_monitor_alert_unrouted` with a `"<reason> (#9703)"` value (two-PR rule; routing is Stage 3b).
- Better Stack: **no** `.tf` change. `uptime-alerts.tf` is deliberately not touched (including comments) so Stage 1 cannot change the heartbeat object or its Doppler secret; its stale "feeder deliberately not in this PR" comment is refreshed in Stage 3b. `doppler_secret.inngest_server_probe_heartbeat_url` keeps zero consumers and is intentionally retained (deleting it is a destroy-apply for no benefit; a later host-side feeder could use it).
- No new provider, no new Terraform variable. The single new credential is one repo secret, `BETTERSTACK_API_TOKEN_READONLY`, copied once from the existing Doppler `prd_terraform` value (Phase 0). Precedent: `BETTERSTACK_API_TOKEN` and `BETTERSTACK_QUERY_*` are repo secrets set the same way; this is a GitHub write, not a Better Stack write, and is read back with `gh secret list`.

### Apply path

(a) cloud-init/host: none. (b)/(c): none. The Sentry root applies automatically on push to `main` through `apply-sentry-infra.yml` (full-root plan, no allow-list edit). That is the repo's standard IaC delivery for this vendor and is a Sentry write, not a Better Stack write. The web server release that carries the new table row follows the normal `web-platform-release.yml` path. Expected downtime: none.

**Does merging THIS alone mutate production?** Yes, in exactly the three ways in the Stage table, and not in any Better Stack way. Derivation: `apply-sentry-infra.yml` `paths:` covers the whole `infra/sentry/**` tree and plans the full root; `apply-web-platform-infra.yml` `on.push.paths` is `apps/web-platform/infra/**` (with only the rehearsal and root-key roots negated), so an edit to `infra/sentry/*.tf` or to `infra/inngest-server-probe-heartbeat.test.sh` fires it, and its `-target` allow-list plus the state-gated `arm-heartbeats.sh` chain neither contain nor arm `inngest_server_probe`. The PR's own CI infra plan must show no change to `betteruptime_heartbeat.inngest_server_probe` or `doppler_secret.inngest_server_probe_heartbeat_url`; if it shows any, stop. The PR body's first line states this answer.

### Host fan-out

None. No `terraform_data` SSH provisioner under `apps/web-platform/infra/` is touched; no fleet sibling classification applies.

### Distinctness / drift safeguards

No `dev != prd` surface. The heartbeat keeps `ignore_changes = [paused]`; nothing in Stage 1 edits the resource. A recreated heartbeat is born `paused = true` with a new URL; the verifier resolves the URL by name on every run, so a URL change is harmless, and the retained Doppler URL secret (`ignore_changes = [value]`) would go stale — name resolution is the authority. The nightly `heartbeat-live-reconcile` keeps the row exempt from `fed-but-paused` through `arming_pending` until Stage 3a removes it.

### Vendor-tier reality check

`betteruptime_heartbeat.inngest_server_probe` already exists with `policy_id` gated on `var.betterstack_paid_tier`; nothing here creates a tier-gated Better Stack object. Sentry cron monitors are already used at scale; one more is within the existing org usage pattern.

## Beat Budget

| Quantity | Value | Source |
|---|---|---|
| Pages when no beat for | `period + grace` = 5400 s (90 min) | `uptime-alerts.tf` |
| Dispatch slot | 15 min (UTC wall-clock multiple) | new `intervalMinutes` |
| Worst clock delay in a slot | 12 min | `CLOCK_DELAY_MINUTES` in `sentry-monitor-iac-parity.test.ts` |
| Measured runner queue, max | 40.6 min (2438 s) on the zot watchdog over 40 runs, 2026-09-24 (the parity test's `QUEUE_ALLOWANCE_MINUTES` is 30; this budget uses the observed max) | `sentry-monitor-iac-parity.test.ts` comments |
| Verifier runtime | 2 min typical; job `timeout-minutes: 6` | workflow |
| Worst consecutive-beat gap, all slots delivered | 15 + (12 + 40.6 + 2) minus 0.5 = about 69 min | below 90 |
| Worst gap with ONE whole slot lost | 30 + 54.6 = about 85 min | below 90, with 5 min of slack |
| Two slots lost | about 100 min | pages — a true "feeder dark" |
| Freshness withheld for N consecutive slots (ingest lag pushes the newest row past 4500 s) | the lag adds directly to the gap; with an 85 min worst gap this already pages, which is the right answer for lag beyond 75 min | pages — a true "pipeline degraded" |
| Rejected: 60-min slots | 60 + 54.6 = 115 min worst; any two consecutive queue delays differing by 30 min break the budget, and the measured p90 is 20 min | false pages |

Slack is thin on purpose and stated plainly: 40.6 min is an observed maximum over 40 runs, not a bound, and one lost slot plus a queue spike beyond it pages falsely. That is accepted: a page after a lost slot plus an extreme queue is a "the feeder path is degraded" finding, the Guard 1 Anchor test reds first if the cadence constants are weakened, and if false pages appear the one-line fallback is a 30-minute `grace` widening, to be measured before use because Better Stack's state-reset semantics on a period/grace update are undocumented. Manual workflow dispatches inside a slot make the clock skip that slot, so they consume the one slot of tolerance: do not stack manual runs, and expect the arming command's forced dispatch to cost one slot (the first post-arm gap is the "one slot lost" case; read back a second `verdict=beat` before Stage 3a).

Detection latency for a dead probe: the last good row is at `D`; the verifier keeps beating while the newest row is at most 4500 s old, so the last beat lands in `[D, D + 75 min + one slot]` and the heartbeat pages 90 min after it: between about 1.5 h and about 3 h after the probe's last emission. This is accepted as a latency trade; the wrong-volume alert itself is unchanged and still pages on a wrong-volume row at its own cadence.

Why 4500 s: the probe emits hourly (`OnUnitActiveSec=1h`, `AccuracySec=1min`, `inngest-bootstrap.sh`); measured consecutive gaps are 3599–3650 s, so a healthy row's age at check time ranges 0 to about 3650 s plus ingest lag (observed 1275 s and 3244 s on 2026-10-10). 4500 s leaves about 14 min of slack and still means one skipped emission starts the clock. It is a named constant with a boundary test at 4500/4501. Clock skew between the host-stamped `dt` and the runner clock eats the same slack; the harness carries a ±120 s skew fixture.

## Implementation Phases

Phases 0–6 are Stage 1 (this PR, executed by the work skill). Phase 7 is Stages 3a/3b. `## Arming Procedure` is Stage 2 and is not a work-skill phase.

### Phase 0 — Credential prerequisite (GitHub write, no Better Stack write)

Provision the repo secret from the existing Doppler value without printing it: `doppler secrets get BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform --plain | gh secret set BETTERSTACK_API_TOKEN_READONLY --repo jikig-ai/soleur`, then read back with `gh secret list --repo jikig-ai/soleur | awk '{print $1}' | grep -x BETTERSTACK_API_TOKEN_READONLY`. If the secret is absent when the workflow runs, the verifier reports `beat_failed reason=api_token_unset` (exit 4) rather than guessing.

### Phase 1 — Verifier script (TDD: harness first)

1. Write `scripts/inngest-probe-heartbeat-feeder.test.sh` first (cases in `## Test Scenarios`; modelled on `scripts/followthroughs/inngest-luks-property-8296.test.sh`), watch it fail, then write `scripts/inngest-probe-heartbeat-feeder.sh`.
2. Script contract (mirrors 8296's prologue, trap and clock handling; the only accepted argument is `--selftest`):
   - `--selftest`: placed BEFORE any dependency on `$GITHUB_WORKSPACE`, `BETTERSTACK_*` or `doppler` (Check 10 runs it under `env -i` with a minimal `PATH`): load the shared predicate (below), run `inngest_probe_row_selftest`, print `inngest-probe-feeder: selftest=ok` and exit 0, or print `FAILED` and exit 3. No network, no credentials. Any other argument is exit 64.
   - xtrace refusal (`rc 78`) when `-x` is on and any `BETTERSTACK_*` credential is set. An EXIT trap rewrites any status outside `{0,3,4,64,78}` to 3 with `verdict=trap_remapped`: a fall-off that exits 0 would post a Sentry `ok` for a run that decided nothing (8296 pinned the same lesson).
   - Load the shared predicate exactly per the lib's LOAD CONTRACT (`unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER`; `_ipr_lib="${INNGEST_PROBE_ROW_LIB:-$REPO_ROOT/scripts/lib/inngest-probe-row.sh}"`; source + `declare -F` + `inngest_probe_row_selftest`; failure arm `verdict=query_failed reason=selector_unavailable lib=…`, exit 3).
   - Clock: `INNGEST_FEEDER_NOW` (ISO-8601 UTC) for the harness; set-but-malformed is exit 3, never a wall-clock fallback.
   - Query: `scripts/betterstack-query.sh --since 2h --grep "$INNGEST_PROBE_MARKER" --limit 500` (the default archive arm is kept: the hot window alone is about 40 min and cannot see an hourly row; `--limit` keeps the newest rows because the helper orders its inner query by `dt` descending). The verifier sorts by `dt` itself and does not depend on the helper's row order; the 2 h window must stay above 4500 s plus ingest lag. The helper's stdout is captured; its stderr goes to a temp file and is NEVER relayed (its `--fail-with-body` error bodies can carry a credential-bearing message): only `reason=helper_status status=<n> class=<auth|http|decode> body_len=<n>` is emitted.
   - Select with `select(inngest_probe_row)` and `host == "soleur-inngest" and host_name == "soleur-inngest-prd"` and FIRST `host_role=` token `== "dedicated"`; normalise `dt` (`T` to space); newest by `dt`; unusable `dt` or `dt` more than 300 s in the future is a withhold; age above 4500 s is a withhold (`producer_silent`). Every verdict line carries the funnel counts `rows_total rows_probe rows_host rows_dedicated` and `newest_dt` (counts and a timestamp, never payload).
   - Resolve the heartbeat: GET `https://uptime.betterstack.com/api/v2/heartbeats?per_page=250` with the bearer from `BETTERSTACK_API_TOKEN_READONLY` passed through `curl --disable --noproxy '*' --config -` (never on argv), after a token-shape check (`^[A-Za-z0-9._~+/=-]{20,}$`, mirroring `betterstack-query.sh`'s credential guard) so no quote or newline can add curl directives. curl and jq stderr on the API and beat paths go to `/dev/null`. Select by exact `attributes.name == "soleur-inngest-server-probe-prd"`; zero or more than one match is `beat_failed` (exit 4). One page of 250 is enough today; more than 250 heartbeats fails safe as `beat_failed` (add a one-line comment; follow `pagination.next` if the account grows). The `url` must match `^https://uptime\.betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]+$` (also the injection guard for the curl config) or the run is `beat_failed`. `attributes.paused` must be the JSON boolean `true` or `false`; absent, null or a string is `beat_failed`.
   - If `attributes.paused == true`: `verdict=fresh_heartbeat_paused`, exit 0, no beat.
   - Else beat: `curl --disable --noproxy '*' -fsS --max-time 15 -w '%{http_code}' --config -` with the URL on stdin; no redirect following, and success is a 2xx code only (a 3xx passes `-f`, so the code is checked); print `verdict=beat http=<code> age_s=<n> newest_dt=<dt>` (exit 0); anything else is `beat_failed reason=http_status` (exit 4). The URL is never printed, so no `::add-mask::` line is needed (emitting one would put the URL on stdout).
   - Every marker line is `inngest-probe-feeder: verdict=<v> <k=v …>`; withheld verdicts add one `CANNOT BEAT:` sentence naming the cause and stating that it says nothing about the store.
3. The beat call is the **single** call site that can reach the heartbeat URL, and it sits after every freshness and resolution check (Guard 1).

### Phase 2 — Workflow

`.github/workflows/scheduled-inngest-probe-heartbeat.yml`, modelled on `scheduled-zot-restart-loop.yml`:

- Header carries `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` plus the honest eligibility argument (depends-on / shared failure domain like zot; the credentialed bash pipeline that stays in an ephemeral runner is the load-bearing reason).
- `on:` exactly `schedule` (`cron: '*/15 * * * *'`, the fallback) and `workflow_dispatch: {}`; top-level `concurrency: { group: scheduled-inngest-probe-heartbeat, cancel-in-progress: false }`; `permissions: contents: read`.
- One job, `runs-on: ubuntu-24.04`, `timeout-minutes: 6`, pinned `actions/checkout` SHA, `persist-credentials: false`.
- Step "Verify freshness and beat": env from repo secrets (`BETTERSTACK_QUERY_*`, `BETTERSTACK_API_TOKEN_READONLY`); `rc=0; out="$(bash scripts/inngest-probe-heartbeat-feeder.sh 2>&1)" || rc=$?` (the verifier's exit is DATA — the `|| rc=$?` capture is mandatory because Actions runs `bash -e`). Keep ONLY lines matching `^inngest-probe-feeder: ` or `^CANNOT BEAT: ` from `$out`, run `strip_log_injection` on each surviving line, and print those; drop everything else (unlike the zot template, the raw blob is never echoed: a line beginning `::` would run as a workflow command, and `strip_log_injection` on the whole blob fuses lines). Map `rc` to `::notice::` / `::error::` annotations built from the surviving verdict token; write `exit_code` to `$GITHUB_OUTPUT`. The step never exits non-zero.
- Final step `uses: ./.github/actions/sentry-heartbeat` with `monitor-slug: scheduled-inngest-probe-heartbeat`, `status: ${{ steps.feeder.outputs.exit_code == '0' && 'ok' || 'error' }}`, `if: always()`, `continue-on-error: true`. A Sentry `error` means "withheld or failed", not "feeder broken".

### Phase 3 — Dispatch table row and Sentry monitor

- `apps/web-platform/server/watchdog-dispatch-table.ts`: add `{ workflowFile: "scheduled-inngest-probe-heartbeat.yml", monitorSlug: "scheduled-inngest-probe-heartbeat", intervalMinutes: 15, eligibility: "<honest shared-failure-domain argument>" }`.
- `sentry-monitor-iac-parity.test.ts`: the hard-coded expected slug set gains the new slug; no other literal changes (the margin test derives from the constants).
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts`: add the slug (with a one-line why) to `NON_INNGEST_MONITORS`.
- `cron-monitors.tf` + `cron-monitor-alerts.tf` per `## Infrastructure (IaC)`.
- Re-read the `inngest-server.md` runbook checklist ("How the external watchdogs are triggered", step 4) and satisfy each item it lists that this plan has not.

### Phase 4 — Manifest row flip and its parity tests

- `plugins/soleur/lib/heartbeat-manifest.ts`, row `inngest_server_probe`: `feeder: { kind: "cron", evidence: { file: ".github/workflows/scheduled-inngest-probe-heartbeat.yml", pattern: "bash scripts/inngest-probe-heartbeat-feeder.sh" } }` (the `none` arm's `url_secret` and `tracking_issue` are dropped; they do not exist on the `cron` arm); keep `arming: "external-probe"`, `paused: true`, `arming_pending: { tracking_issue: 9703 }`; rewrite the row comment and `exempt_reason` to say the feeder exists and arming is pending, keeping `arming_pending` within the 30-line window section (h) greps. The pattern must appear once in the workflow, on the `run:` line, and not be repeated in annotation text.
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`: relax the evidence-shape assertion to a two-arm alternation — the existing timer-enable / `cron.d` arm keeps requiring `apps/web-platform/infra/`; the new arm requires file `^\.github/workflows/[\w.-]+\.yml$` AND pattern `^bash scripts/[\w.-]+\.sh$`. Keep the bounded-hit assertion (1–2 hits).
- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` section (h) and its header comment (which still says `feeder.kind = "none"`): assert `kind: "cron"`, the workflow `evidence.file` and `evidence.pattern`, and `arming_pending`, instead of `kind: "none"` + `url_secret`; section (h) keeps three assertions, so `EXPECTED_PASSES` stays 21 (set it to the measured count if that changes).
- `scripts/lib/inngest-probe-row.test.sh`: add `scripts/inngest-probe-heartbeat-feeder.sh` to `MUST_FIND` (so discovery cannot silently drop the new consumer); the census auto-checks the load contract.

### Phase 5 — Registration, docs, C4

- `scripts/test-all.sh`: `run_suite "scripts/inngest-probe-heartbeat-feeder" bash scripts/inngest-probe-heartbeat-feeder.test.sh`; regenerate `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` with the repo's `--write` generators (see `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`) and add any row `scripts/test-affected-kb-consumers.baseline.txt` requires for the new suite.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: add the feeder to the external-watchdog section and place the `## Arming Procedure` command there as its durable home (no SSH step), so the procedure outlives the plan file.
- ADR-117 and ADR-248 amendments; `model.c4` edits then `bash scripts/regenerate-c4-model.sh`; run `bash plugins/soleur/test/c4-count-parity.test.sh` and copy the counts it demands.

### Phase 6 — Verify and ship

- Targeted suites only (see `## Acceptance Criteria`).
- **Read-only soak (measures the hot/archive seam fixtures cannot):** with the heartbeat still paused, run `doppler run -p soleur -c prd_terraform -- bash scripts/inngest-probe-heartbeat-feeder.sh` (that config already carries the `BETTERSTACK_QUERY_*` and `BETTERSTACK_API_TOKEN_READONLY` values) every 5 minutes for 90 minutes under the Monitor tool (an until-loop, never a foreground sleep); every run must end `verdict=fresh_heartbeat_paused`, and the newest-row age is recorded across the hour so rows aged 40–75 minutes are shown to be visible. The heartbeat is paused, so nothing is written. Record the result in the PR body. If any run withholds on `producer_silent` while rows exist, raise the bound or require two consecutive misses before the plan proceeds.
- PR body: first line is the "does merging this alone mutate production?" answer (see `## Infrastructure (IaC)` and the Acceptance Criteria), then `Ref #9703` (no closing keyword), a `## Changelog` section, a "Production writes" paragraph stating that Stage 1 writes nothing to Better Stack, mentions the one GitHub repo-secret copy, and that arming is a separately authorized step tracked on #9703, and the closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Comment on #9703 recording that Stages 3a/3b and the Sentry routing PR are the remaining tracked work (the issue stays open with its existing 8296 follow-through directive, so the deferral is visible and dated by its 2026-10-22 trigger).

### Phase 7 — Stage 3a and 3b (separate PRs; detail belongs to their own plans)

- **3a (record PR, immediately after Stage 2's read-back):** remove `arming_pending` from the manifest row and update the ADR amendments and C4 clause to say armed. This re-arms the nightly reconcile's `fed-but-paused` alarm, which is the net if anything re-pauses the heartbeat (a paused heartbeat reports `fresh_heartbeat_paused` with exit 0, so the verifier itself would not alert).
- **3b gate (mechanical, read-only; all must hold before any deletion):** the P3 read-back shows `up / paused=false`; the last four completed workflow runs spanning at least 45 minutes each log `verdict=beat`; one nightly `heartbeat-live-reconcile` run after 3a is clean.
- **3b order constraint:** remove the `<!-- soleur:followthrough script=… -->` directive from #9703's body FIRST (`gh issue edit`), so the sweeper never points at a deleted script. A directive removed before arming leaves no tripwire; that is why the gate comes first.
- **3b content:** delete the 8296 probe and harness and every registration row naming it (`test-all.sh`, `suite-durations.tsv`, `suite-shard-legs.tsv`, the two `test-affected-kb-consumers.baseline.txt` rows, the `MUST_FIND` entry); edit the prose references (`encryption-posture-ledger.json` `live_verification`, `inngest-luks-cutover-6894.md`, `inngest-server.md`, `model.c4` + regenerate, comment-only edits in `betterstack-logs-alerts.tf` and `uptime-alerts.tf` whose push-apply plan must show "No changes"); route the monitor (two-PR rule): move `scheduled_inngest_probe_heartbeat` from `cron_monitor_alert_unrouted` into `sentry_alert.cron_monitor_failure.monitor_ids` and regenerate `alert-reference.json` per the sentry root README.
- After merge, `gh issue close 9703 --comment <read-back evidence>` (explicit close; no closing keyword anywhere).

## Arming Procedure (Stage 2 — NOT executed by this pipeline)

This is a production write to Better Stack. The command below is shown in full and authorized as a unit before it runs; a menu answer or an earlier approval does not authorize it (`hr-menu-option-ack-not-prod-write-auth`). It is one compound command on purpose: the unpause and its rollback live in the same shell under a `trap`, so an interrupted session still rolls back. No dashboard step and no SSH step. The write token is read inside `doppler run` and sent through `curl --config -`; nothing below prints it or the heartbeat URL. Run it through the Monitor tool (an until-loop), never as a foreground call: it can legitimately run for up to 75 minutes. Expect the forced dispatch to cost one slot of beat-budget tolerance (read back a second `verdict=beat` before Stage 3a).

**Preconditions (read-only; stop on any miss):**

```bash
# P1  Stage 1 is on main, the monitor exists, and the clock has been dispatching the workflow
git fetch -q origin main && git log origin/main --oneline -1 -- scripts/inngest-probe-heartbeat-feeder.sh
gh run list --workflow=scheduled-inngest-probe-heartbeat.yml --status completed --limit 4 --json databaseId,event,createdAt \
  --jq '.[] | [.databaseId, .event, .createdAt] | @tsv'
# expect: four rows, event=workflow_dispatch, createdAt spacing about 15 minutes, spanning at least 45 minutes

# P2  EVERY one of those four runs reports freshness and the paused state, and the Sentry check-in was delivered
for RID in $(gh run list --workflow=scheduled-inngest-probe-heartbeat.yml --status completed --limit 4 --json databaseId --jq '.[].databaseId'); do
  gh run view "$RID" --log > /tmp/run-$RID.log
  grep 'inngest-probe-feeder: verdict=' /tmp/run-$RID.log | tail -1
  grep 'sentry-heartbeat:' /tmp/run-$RID.log | tail -1
  rm -f /tmp/run-$RID.log
done
# expect: verdict=fresh_heartbeat_paused on all four, and a 2xx status on every sentry-heartbeat line
# (a step that never exits non-zero concludes 'success' even when it withheld, so conclusion alone proves nothing)

# P3  live heartbeat state (the URL attribute is deliberately not selected)
hb() { doppler run -p soleur -c prd_terraform --silent -- bash -c '
  [[ "$BETTERSTACK_API_TOKEN" =~ ^[A-Za-z0-9._~+/=-]{20,}$ ]] || { echo "token shape refused" >&2; exit 78; }
  printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
hb "https://uptime.betterstack.com/api/v2/heartbeats?per_page=250" \
  | jq -r '.data[] | select(.attributes.name=="soleur-inngest-server-probe-prd") | [.id, .attributes.status, (.attributes.paused|tostring), (.attributes.period|tostring), (.attributes.grace|tostring)] | @tsv'
# expect: 504655  paused  true  3600  1800
```

**Arm — ONE compound command (WRITE; poll deadline 4500 s wall clock, leaving a 15-minute rollback margin inside `period + grace`):**

```bash
set -uo pipefail
EXPECT_ID=504655; NAME=soleur-inngest-server-probe-prd; BASE=https://uptime.betterstack.com/api/v2/heartbeats
hb() { doppler run -p soleur -c prd_terraform --silent -- bash -c '
  [[ "$BETTERSTACK_API_TOKEN" =~ ^[A-Za-z0-9._~+/=-]{20,}$ ]] || { echo "token shape refused" >&2; exit 78; }
  printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
patch() { hb -X PATCH -H 'Content-Type: application/json' --data-binary "{\"paused\":$1}" "$BASE/$HB" | jq -e ".data.attributes.paused == $1" >/dev/null; }
rollback() {  # runs on EXIT, INT, TERM, HUP; three attempts, each confirmed by read-back
  trap - EXIT INT TERM HUP
  for t in 1 2 3; do patch true && { echo "ROLLED BACK (paused=true read back)"; exit 1; }; sleep 5; done
  echo "ROLLBACK FAILED - pause heartbeat $HB now; Better Stack pages within 5400 s of the unpause"; exit 2
}
HB=$(hb "$BASE?per_page=250" | jq -r --arg n "$NAME" '[.data[] | select(.attributes.name==$n)] | if length==1 then .[0].id else empty end')
[ "$HB" = "$EXPECT_ID" ] || { echo "heartbeat id '$HB' is not the expected $EXPECT_ID (or not unique): refusing"; exit 3; }
[ "$(hb "$BASE/$HB" | jq -r '.data.attributes.status')" = "paused" ] || { echo "heartbeat is not paused: refusing a second arm"; exit 3; }
trap rollback EXIT INT TERM HUP
patch false || { echo "unpause not confirmed by read-back"; exit 1; }     # exit fires the rollback trap
gh workflow run scheduled-inngest-probe-heartbeat.yml --ref main          # force one real beat now
SECONDS=0
while [ "$SECONDS" -lt 4500 ]; do
  s=$(hb "$BASE/$HB" | jq -r '.data.attributes.status')
  echo "$(date -u +%H:%M:%S) elapsed=${SECONDS}s status=$s"
  if [ "$s" = "up" ]; then trap - EXIT INT TERM HUP; echo "ARMED: status=up after ${SECONDS}s"; exit 0; fi
  sleep 30
done
echo "arm failed: status never reached up in ${SECONDS}s"; exit 1       # exit fires the rollback trap
```

**Read-back (READ):** repeat P3 and expect `504655  up  false  3600  1800`; re-run the P2 loop on the next completed runs and expect `verdict=beat http=2xx`, then a second `verdict=beat` one slot later. The next nightly `heartbeat-live-reconcile` markers (`SOLEUR_HEARTBEAT_RECONCILE_*`) must stay clean. Only then start Stage 3a. If the command rolled back, read the newest completed run's `verdict=` line: `fresh_heartbeat_paused` after the unpause means that run predates it, `beat_failed` means the feeder cannot deliver, and any withheld verdict means the probe pipeline itself is dark (the finding this heartbeat exists for). Arming a second time is refused by the state gate; to retry after a rollback, simply re-run (the heartbeat is paused again).

## Observability

```yaml
liveness_signal:
  what: "betteruptime_heartbeat.inngest_server_probe pages when no beat arrives within period+grace (5400 s); the feeder beats only when it confirms a fresh host_role=dedicated SOLEUR_INNGEST_SERVER_PROBE row (age <= 4500 s) in the Better Stack Logs warehouse. Pre-arm, the feeder's own liveness is the Sentry cron monitor scheduled-inngest-probe-heartbeat plus the per-run verdict line (pre-arm the covering signal for the store itself is the daily 8296 follow-through probe)"
  cadence: "every 15 min, dispatched by the web server watchdog clock (ADR-248) with a */15 schedule fallback; Sentry margin 60 min"
  alert_target: "Better Stack email (ops@ via team_name 'Your team'; betteruptime_policy.uptime when var.betterstack_paid_tier) once armed; Sentry issue on the monitor (unrouted until Stage 3b; emails after it)"
  configured_in: ".github/workflows/scheduled-inngest-probe-heartbeat.yml, scripts/inngest-probe-heartbeat-feeder.sh, apps/web-platform/server/watchdog-dispatch-table.ts, apps/web-platform/infra/sentry/cron-monitors.tf, apps/web-platform/infra/uptime-alerts.tf (heartbeat), plugins/soleur/lib/heartbeat-manifest.ts"
error_reporting:
  destination: "Sentry cron monitor scheduled-inngest-probe-heartbeat (check-in ok iff verifier exit 0; error means withheld or failed, not feeder broken) and the workflow run log (::error:: / ::notice:: annotations, one 'inngest-probe-feeder: verdict=' marker per run)"
  fail_loud: "exit 0 is exactly {beat, fresh_heartbeat_paused}; every withheld or failed outcome exits non-zero and posts a Sentry error check-in; a dead feeder is a missed Sentry check-in and, once armed, an absent beat"
failure_modes:
  - mode: "probe emitter dead, Vector journald-allowlist regression, sink outage, or ingest lag beyond 75 min (no fresh dedicated row)"
    detection: "verifier withholds the beat (verdict=no_rows or producer_silent) and the same line carries rows_total/rows_probe/rows_host/rows_dedicated/newest_dt/age_s, so an empty warehouse, a host/role filter drop and a stale-but-present row are told apart -> workflow run log ::error:: (layer 6) and Sentry monitor error check-in (Sentry monitor); once armed the Better Stack heartbeat pages 90 min after the last beat"
    alert_route: "Better Stack heartbeat email (vendor absence alarm, the inngest-heartbeat class) + Sentry issue"
  - mode: "warehouse unreadable (credential, helper, malformed response)"
    detection: "verdict=query_failed reason=<…> class=<auth|http|decode> body_len=<n> in the workflow run log (layer 6; helper stderr is never relayed); Sentry monitor error check-in"
    alert_route: "Sentry issue; heartbeat page if it persists past 90 min once armed"
  - mode: "beat cannot be delivered (heartbeat missing/ambiguous, token unset, URL refused, non-2xx)"
    detection: "verdict=beat_failed reason=<…> with ::error:: in the workflow run log (layer 6); Sentry monitor error check-in"
    alert_route: "Sentry issue; heartbeat page once armed"
  - mode: "feeder dispatch dark (clock down on both hosts, workflow disabled, GitHub outage)"
    detection: "Sentry monitor missed check-in within interval + margin = 75 min (Sentry monitor); the watchdog clock's own SOLEUR_WATCHDOG_DISPATCH markers (Better Stack Logs, vector layer)"
    alert_route: "Sentry issue; heartbeat page once armed (a true 'feeder dark' finding)"
  - mode: "spurious beat (feeder beats while the probe is dead)"
    detection: "prevented by construction and pinned by committed mutation runs and fixtures; at runtime every beat line carries age_s, newest_dt and the funnel counts, so the workflow run log (layer 6) shows exactly which row justified it; the nightly heartbeat-live-reconcile classifies the row against the manifest"
    alert_route: "CI red on the harness; workflow run log; reconcile issue/marker"
  - mode: "heartbeat unpaused while unfed (arming gone wrong) or re-paused after arming"
    detection: "arming: the compound command's own stdout (ROLLED BACK / ROLLBACK FAILED, read through the Monitor tool; a command-output signal, not one of the seven layers) plus the Better Stack page at 5400 s as the backstop; re-pause after arming: fresh_heartbeat_paused in the workflow run log (layer 6) and the nightly reconcile fed-but-paused class once Stage 3a drops arming_pending"
    alert_route: "Better Stack heartbeat email; reconcile issue/marker"
logs:
  where: "GitHub Actions run log of scheduled-inngest-probe-heartbeat.yml (verdict markers and counts; no URL, token or row payload); Sentry cron check-in history"
  retention: "GHA run retention (repo default); Sentry monitor history per org plan"
discoverability_test:
  command: "bash scripts/inngest-probe-heartbeat-feeder.sh --selftest"
  expected_output: "selftest=ok"
```

The selftest (no network, no credentials, under a second, placed before every environment dependency so it also passes under `env -i`) loads the shared predicate and runs its own selftest. The LIVE signal, which does need credentials, is read without SSH by the commands in `## Arming Procedure` (P2 for the verdict lines, P3 for the heartbeat state). No `credentials_required` is declared on purpose: declaring it would move the repo-global `BASELINE_DECLARED_PROBES` ratchet, a file every sibling plan also edits.

Observability layers cited (hr-observability-layer-citation): layer 6 (workflow-run log, `::error::` annotations) for every verifier verdict; the Sentry cron monitor and the Better Stack heartbeat are the asynchronous no-SSH sinks; the dispatch clock's own markers are layer 3 (vector → Better Stack Logs). No Inngest function, pino logger or host-side code is added, so layers 1–2, 4–5 and 7 do not apply. The feeder runs on a GitHub-hosted runner, a surface the operator cannot inspect interactively; the verdict marker carries every discriminating field (`age_s`, `limit_s`, funnel counts, `newest_dt`, `reason`, `http`) in one line, so each competing cause is distinguishable from the log alone.

## Network-Outage Deep-Dive (deepen Phase 4.5)

The plan text matches the trigger words `timeout` (`timeout-minutes`, `--max-time`) but diagnoses no network outage and adds no SSH or provisioner dependency, so the L3→L7 checklist is applied as a verification of the new paths, not as an outage hypothesis list. L3 firewall: the feeder and arming call public HTTPS endpoints (`uptime.betterstack.com`, the Logs warehouse host, Sentry ingest) from GitHub-hosted runners or the operator machine; no allow-list is involved. L3 DNS/routing: the read-only calls in this session resolved and returned 200. L7 TLS: curl defaults, certificate verification on, no `-k`. L7 application: every call has `--max-time`; a failure is a named verdict, not a hang.

## Encryption Posture

```yaml
at_rest:
  mechanism: "no new persistent store: a workflow, a script, a dispatch-table row and a Sentry monitor declaration. The only retained artifacts are GitHub Actions run logs and Sentry check-in history, which carry verdict markers, ages and counts, never row payloads, tokens or the heartbeat URL"
  evidence: "scripts/inngest-probe-heartbeat-feeder.sh prints only marker lines; the harness asserts the URL, bearer and helper error text never appear in stdout/stderr"
  defends_against: "no storage is introduced, so nothing sensitive is persisted by this change"
  does_not_defend: "the heartbeat URL still lands in terraform.tfstate and Doppler soleur/prd via the existing resources (unchanged); a runner compromise during a run can read the in-memory URL and read-only token; the repo secret BETTERSTACK_API_TOKEN_READONLY is stored by GitHub's secret store, outside this repo's control"
  disclosed_as: "existing heartbeat-URL disclosure class (same as doppler_secret.inngest_heartbeat_url_prd); the new repo secret is the same class as the existing BETTERSTACK_* repo secrets"
  live_verification: "unavailable: no store is introduced; the harness's no-secret-in-output assertion is the check"
in_transit:
  tls: "all four connections are HTTPS: Logs warehouse (ClickHouse HTTP via betterstack-query.sh, Basic auth, --fail-with-body), Better Stack uptime API (bearer), the heartbeat beat, the Sentry check-in"
  cert_verification: "on (curl defaults; betterstack-query.sh unsets SSLKEYLOGFILE and CA-substitution variables; nothing here passes -k/--insecure)"
  does_not_defend: "a beat carries no payload and proves only that the verifier ran; a leaked URL allows beat forgery (alarm suppression), not data read"
  disclosed_as: "same vendor heartbeat push path every sibling heartbeat uses"
# no exception block — no plaintext mechanism and no cert_verification: off row
```

## Guard Contract

### Guard 1 — `scripts/inngest-probe-heartbeat-feeder.sh` beat gate and its harness `scripts/inngest-probe-heartbeat-feeder.test.sh`

**Property.** A request reaches the heartbeat URL only when the newest `host_role=dedicated` probe row from host `soleur-inngest` / `soleur-inngest-prd` — selected by the shared emitter-plus-anchored-marker predicate — is at most 4500 s old and not future-dated, and the heartbeat resolves uniquely, is unpaused, and has a strictly shaped Better Stack ping URL.

**Assembly.** The property quantifies over: the warehouse selection (host, host_name, emitter, anchored marker, first `host_role=` token, newest-by-`dt` with `T`/space normalised), the freshness and future-slack constants, the helper's argv (`--since 2h --limit 500`; the stub ignores `--grep` by design, as the sibling's does, so the predicate and not the helper's LIKE filter is what the fixtures test), the heartbeat resolution (exact name, cardinality 1, `paused` as a JSON boolean, URL shape), and the ONE beat call site. Structural chokepoint: the beat `curl` appears exactly once in the script and every path to it passes the verdict function. The harness runs the script with a PRIVATE `PATH` (a bin dir holding only the stub `curl`, the stub helper and symlinks to the tools the script needs) plus a canary that fails if `curl` resolves outside it, and the `curl` stub models exactly two shapes — the API GET (`--disable --noproxy '*' --config -`, bearer on stdin) and the beat (`-fsS --max-time 15 -w %{http_code} --config -`, URL on stdin) — and refuses any other invocation with rc 64 and a refusal log that every fixture asserts is empty. A beat is counted as any `curl` call that is not the API GET; the unconditional-beater is therefore caught even if it changes shape.

**Mutation matrix.**

| # | Edit under test | Must drive the guard |
|---|-----------------|----------------------|
| M1 | raise the bound by one second (age 4501 s must withhold, 4500 s must beat) | RED — boundary pair of fixtures |
| M2 | drop the `host` filter, or the `host_name` filter, separately | RED — one fixture per field: fresh row from another host, stale dedicated row |
| M3 | replace the shared predicate with a substring match on the marker | RED — fixture: fresh `doppler`-emitter row quoting the marker, stale probe row |
| M4 | drop the first-`host_role=` rule or the `dedicated` filter | RED — fixtures: fresh `host_role=web` probe row newer than a stale dedicated one; first token `web` with a second token `dedicated` must withhold |
| M5 | select the first row instead of newest-by-`dt` | RED — fixtures: a stale dedicated row ordered before a fresh one, and a fresh row first with a future-dated newest row after it |
| M6 | call the beat before the freshness verdict (reorder, not delete) | RED — every withheld-path fixture asserts zero beat calls in the stub log (observed during the run, not after it) |
| M7 | ignore `paused == true` | RED — fixtures: fresh row with a paused heartbeat asserts no beat and `verdict=fresh_heartbeat_paused`; `paused` absent, null or the string `"false"` is `beat_failed` |
| M8 | accept zero or two heartbeats with the name, or match by prefix | RED — fixtures: name absent; two entries (second member after a compliant first); a `…-prd-old` prefix decoy |
| M9 | loosen the URL shape check | RED — fixtures: a `url` on another host; `http://`; a trailing path or `?query`; `uptime.betterstack.com.evil.example`; a quote or newline |
| M10 | print the resolved URL, bearer or helper error text, or put either secret on argv | RED — secret-sentinel fixtures grep stdout, stderr and the call log's argv, including a stub helper that prints a username-bearing error body |
| M11 | change `--since 2h` to a shorter window, or drop `--limit` | RED — the stub asserts the exact helper argv |

Every non-beat verdict fixture asserts both the exit status AND the exact `verdict=` token, and a generic invariant asserts exit 0 if and only if the verdict is `beat` or `fresh_heartbeat_paused`. The exit-token allowlist `{0,3,4,64,78}`, a literal trailing `exit 3`, exactly one trap statement, and no `exec` or `kill` are static scans, as in the sibling (replacing any test seam for "injected unexpected status").

**Harness rows.** (a) Mutation proof is committed, not narrated: M1–M7 run as scratch-copy mutants with a landing check (the edit must change a line inside the beat-gate region, because the API GET and the beat share flags and a file-wide first-match substitution would edit the API call), a known-positive and a known-negative run of the detector first, and rc 1 as "caught" versus anything else as "instrument error", ported from `inngest-luks-property-8296.test.sh`; M8–M11 are covered by their fixtures. (b) The suite asserts a `MIN_PASSES` floor plus `passes + fails == cases` conservation (the sibling's convention, which survives legitimate edits) and a floor of beat-call assertions; a stub `curl` that returns success for anything cannot satisfy the refusal-log and exact-shape assertions. (c) Must-PASS non-canonical inputs: a row whose `dt` uses `T` instead of a space; a row whose message carries a second `host_role=` token after the first (first-wins); extra unknown fields; a probe row followed by a doppler-quoting row of newer `dt` (the quoting row is set aside, the probe row decides); a row `dt` skewed by ±120 s against the pinned clock; a future-slack pair at 300 s (accepted) and 301 s (withheld); `--selftest` run under `env -i`.

**Anchor.** The 4500 s bound and the 15-minute slot are cross-checked against values this diff does not own: the suite parses `period`/`grace` from `apps/web-platform/infra/uptime-alerts.tf` and the slot from the `watchdog-dispatch-table.ts` row selected BY `workflowFile` (never by position), reads the clock/queue constants from named variables with a comment citing `sentry-monitor-iac-parity.test.ts`, and asserts `2 × slot + (12 + 41 + 2) min < (period + grace)/60`, so weakening the cadence or shrinking the heartbeat budget alone turns it RED; `inngest-server-probe-heartbeat.test.sh` independently pins `period = 3600` / `grace = 1800`, so a diff that edits both files must also edit that second suite.

### Guard 2 — feeder-evidence binding: `heartbeat-reprovision-parity.test.ts` (relaxed arm) + the harness's wiring assertions

**Property.** The manifest's claim that `inngest_server_probe` is fed refers to a workflow that is clock-dispatched, runs the verifier on a `run:` line, reports the verifier's exit code to Sentry, and whose verifier resolves exactly this heartbeat by its `.tf` name.

**Assembly.** The manifest row (`evidence.file`, `evidence.pattern`); the workflow file's parsed `run:` steps and its `exit_code` output and `status` expression; the verifier's literal heartbeat name; `betteruptime_heartbeat.inngest_server_probe`'s `name` in `uptime-alerts.tf`; the `WATCHDOG_DISPATCH_TABLE` row for this `workflowFile`; the Sentry monitor slug in `cron-monitors.tf` and the workflow's `sentry-heartbeat` step. Members are enumerated through the parsed YAML and the parsed `.tf` blocks, not through prose; the existing sentry parity suite already owns the trigger, concurrency and slug checks, so this guard does not restate them.

**Mutation matrix.**

| # | Edit under test | Must drive the guard |
|---|-----------------|----------------------|
| G1 | change the verifier's heartbeat-name literal | RED — name equals the `.tf` `name` |
| G2 | turn the workflow's `bash scripts/inngest-probe-heartbeat-feeder.sh` into an `echo` of that text (pattern present, not on a `run:` command) | RED — the harness asserts the pattern sits on a parsed `run:` line |
| G3 | relaxed regex admits a non-workflow, non-infra path (`scripts/x.yml`) or a free-form pattern | RED — the new regex arm is shape-bound on both file and pattern |
| G4 | drop the `|| rc=$?` capture, or invert the `status` expression so a failed run posts `ok` | RED — parsed-YAML assertions on the step's `run:` text and the `status:` expression |
| G5 | delete the workflow's row from `WATCHDOG_DISPATCH_TABLE` while the workflow keeps only `schedule:` | RED — the harness asserts a table row exists for the workflow |

**Harness rows.** Suite mutation: `checkFeeders` is exercised with a synthetic manifest row whose evidence is a workflow and whose pattern is absent (must report the "survives only in a comment / absent" violation) — a regex relaxed to match everything would not. Must-PASS non-canonical: a synthetic row using a *different* workflow filename and script name of the allowed shapes passes, proving the arm is a shape and not the single literal.

**Anchor.** The heartbeat's `.tf` name and the monitor slug live outside the files this change authors (`uptime-alerts.tf`, `cron-monitors.tf` are pinned by their own suites); renaming the heartbeat in a diff that also edits the verifier still reds `inngest-server-probe-heartbeat.test.sh` and the live reconcile's `absent-live` class.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Extend `inngest-luks-property-8296.sh` to push | Rejected | The issue's instruction; it never exits 0/1 by design and dies with its tracker |
| Daily follow-through sweeper + widen `period` (e.g. 86400/7200) | Rejected | Sweeper schedule delivers one run per 2–7 h; exit 0 closes a tracker; widening turns "one skipped emission" into a day of blindness and writes to Better Stack at merge |
| Host-side push inside `inngest-server-probe.sh` | Rejected | Cannot see Vector-allowlist or sink failures; needs an OCI re-bake and `inngest-host-replace` (#6780) |
| Inngest cron function | Rejected | Would put warehouse-read credentials into the web app runtime, and the sanctioned exception is the dispatch table with its honest eligibility string |
| `schedule:`-only workflow, or 60-minute dispatch slots | Rejected | `schedule:` delivers one run per 2–7 h (ADR-248); 60-minute slots give a ~115 min worst gap against 90 |
| URL as a repo secret set at arm time (no uptime API in the feeder) | Rejected | Arming becomes two writes in two systems with an ordering hazard (beating a paused heartbeat, the undocumented response), the pre-arm run can no longer prove the URL resolves, and the URL lives in a second store that drifts if the heartbeat is recreated |
| Feeder with the write token `BETTERSTACK_API_TOKEN` (what the sweeper holds) | Rejected | The feeder needs GET only; the read-only token is verified to return the heartbeat `url`, so capability replaces a static scan |
| Read the read-only token from Doppler in the workflow | Rejected | Needs `DOPPLER_TOKEN` (all of `prd_terraform`) in a 96-runs-a-day workflow for one narrow token |
| URL via `DOPPLER_TOKEN_PRD`, or a new Terraform `github_actions_secret` | Rejected | Broad production-config credential for one URL; or a new resource plus a `-target` line and a merge-time apply |
| Add `inngest_server_probe` to `arm-heartbeats.sh`'s chain | Rejected | It would auto-arm on the first push-apply after merge, bypassing the per-command authorization; its helpers are the model for the compound arming command |
| Beat while paused (to "measure" pre-arm) | Rejected | The response is undocumented and `updated_at` does not move; no measurement results |
| Verifier `EXPECT_ARMED` / `paused_overdue` mode | Rejected | Stage 3a drops `arming_pending` right after read-back, re-arming the reconcile alarm with no new verifier state |

## Files to Edit

- `plugins/soleur/lib/heartbeat-manifest.ts` — row flip (Phase 4)
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` — evidence-shape arm
- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — section (h) and its header comment
- `apps/web-platform/server/watchdog-dispatch-table.ts` — third row
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` — expected slug set
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — `NON_INNGEST_MONITORS`
- `apps/web-platform/infra/sentry/cron-monitors.tf` — new monitor
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — unrouted entry
- `scripts/lib/inngest-probe-row.test.sh` — `MUST_FIND`
- `scripts/test-all.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/test-affected-kb-consumers.baseline.txt` — registration
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — watcher entry and the durable arming procedure
- `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md`, `ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md` — amendments
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ regenerated `model.likec4.json`) — the forced clauses and counts

## Files to Create

- `scripts/inngest-probe-heartbeat-feeder.sh`
- `scripts/inngest-probe-heartbeat-feeder.test.sh`
- `.github/workflows/scheduled-inngest-probe-heartbeat.yml`

Not edited, deliberately: `apps/web-platform/infra/uptime-alerts.tf`, `apps/web-platform/infra/betterstack-logs-alerts.tf`, `.github/workflows/apply-web-platform-infra.yml`, `apps/web-platform/infra/arm-heartbeats.sh`, `scripts/followthroughs/inngest-luks-property-8296.sh` (until Stage 3b).

## Open Code-Review Overlap

- #8659 (`scripts/test-all.sh`, EXIT-trap sandbox leak in suites that source `test-helpers.sh`): **Acknowledge** — different concern; the new harness sources no helper and installs its own cleanup trap.
- #7942 (`scripts/test-all.sh`, `*.mutation.sh` batteries run in no gate): **Acknowledge** — the new suite is a plain `*.test.sh` registered with `run_suite`; the mutation runs live inside it, no `.mutation.sh` file is added.
- #8595 (`sentry-monitor-iac-parity.test.ts`, `NON_INNGEST_MONITORS` staleness + cadence parity): **Acknowledge** — this plan adds one entry to each list and the new row is covered by the existing per-row cadence assertions; the reverse-direction staleness guard stays its own cycle.

## Acceptance Criteria

### Pre-merge (PR, Stage 1)

- [ ] `gh secret list` shows `BETTERSTACK_API_TOKEN_READONLY` (Phase 0), provisioned without printing the value.
- [ ] `bash scripts/inngest-probe-heartbeat-feeder.test.sh` passes (`MIN_PASSES` floor, conservation check, empty curl refusal log); the committed scratch-copy mutation runs M1–M7 are RED against their mutants with the landing check green.
- [ ] `bash scripts/lib/inngest-probe-row.test.sh` passes (the census classifies the new verifier; `MUST_FIND` includes it).
- [ ] `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` passes (row is `kind: "cron"`, `arming_pending` kept).
- [ ] `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts plugins/soleur/test/heartbeat-live-reconcile.test.ts` passes; G1–G5 demonstrated RED.
- [ ] `cd apps/web-platform && npx vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts test/server/inngest/function-registry-count.test.ts test/server/inngest/sentry-cron-monitor-routing-parity.test.ts test/server/watchdog-dispatch-clock.test.ts test/server/inngest/execution-placement.test.ts` passes.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash plugins/soleur/test/c4-model-freshness.test.sh` pass after `bash scripts/regenerate-c4-model.sh`.
- [ ] `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py --changed` pass; `terraform fmt -check` and `terraform validate` pass in `apps/web-platform/infra/sentry` (CI is the authority for the full battery).
- [ ] The diff contains no edit to `uptime-alerts.tf`, `betterstack-logs-alerts.tf` or `apply-web-platform-infra.yml`: `git diff origin/main --name-only -- apps/web-platform/infra .github/workflows/apply-web-platform-infra.yml | grep -v '^apps/web-platform/infra/sentry/'` prints only `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh`. (The pathspec is exact because `*` in a git pathspec crosses `/` and would also match the sentry root.)
- [ ] The PR's CI infra plan shows no change to `betteruptime_heartbeat.inngest_server_probe` or `doppler_secret.inngest_server_probe_heartbeat_url` (read it from the plan-only run; stop and surface any diff).
- [ ] The PR body's FIRST line answers "does merging this alone mutate production?": "Merging creates one Sentry cron monitor via apply-sentry-infra.yml, fires apply-web-platform-infra.yml with no Better Stack change in its plan, and starts clock-dispatched runs of the new workflow that beat nothing while the heartbeat is paused. It writes nothing to Better Stack."
- [ ] `env -i PATH=/usr/bin:/bin bash scripts/inngest-probe-heartbeat-feeder.sh --selftest` prints `inngest-probe-feeder: selftest=ok` and finishes inside the 15 s Check 10 cap with no credentials set.
- [ ] The beat call site appears exactly once in the script, after the verdict logic; the curl stub's refusal log is empty in every fixture; neither the URL, the bearer nor helper error text is ever printed or placed on argv (harness-asserted).
- [ ] The Phase 6 read-only soak result (90 minutes, 5-minute cadence, every run `fresh_heartbeat_paused`, newest-row age series recorded) is in the PR body.
- [ ] PR body: `Ref #9703` only (no closing keyword), `## Changelog`, a "Production writes" paragraph, the arming procedure linked, and ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; commits carry the `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` trailer.

### Post-merge (read-only, run by the agent; no go-ahead needed)

- [ ] `apply-sentry-infra.yml` run for the merge SHA is green and the monitor exists (`gh run list --workflow=apply-sentry-infra.yml --limit 3`).
- [ ] `apply-web-platform-infra.yml` run for the merge SHA is green and its plan shows no Better Stack change.
- [ ] Once the web release carrying the table row has deployed, the Arming Procedure's P1/P2 loop passes: four completed `workflow_dispatch` runs about 15 minutes apart, each with `verdict=fresh_heartbeat_paused` and a 2xx `sentry-heartbeat:` line (no manual dispatches: they consume a slot's tolerance).
- [ ] The heartbeat is still `paused=true` (P3 read-back) — Stage 1 must not have changed it.

### Stage 2, 3a and 3b (separate, tracked on #9703)

- [ ] Arming per `## Arming Procedure`, authorized as one unit; read-back shows `up / paused=false` and two consecutive `verdict=beat`.
- [ ] Stage 3a record PR merged; Stage 3b gate passes; Stage 3b PR per Phase 7; #9703 closed explicitly with the read-back evidence.

## Test Scenarios

Harness fixtures (stubbed `scripts/betterstack-query.sh` and `curl` in a fake tree with a private `PATH`; the verifier resolves its repo from its own location, as 8296's harness does):

1. Fresh dedicated row (age 60 s), heartbeat unpaused → `verdict=beat http=200`, exit 0, exactly one beat call, none of URL/bearer in output or argv.
2. Age 4500 s → beat; age 4501 s → `producer_silent`, exit 3, zero beat calls.
3. No rows; only other-host rows (one fixture per `host`, `host_name`); only `host_role=web` rows; first token `web` with a second `dedicated`; only doppler-emitter rows quoting the marker → withheld, correct reason tokens and funnel counts. The stub returns all rows regardless of `--grep`, so these fixtures test the predicate.
4. Newest-by-`dt` with a future-dated (more than 300 s) newest row → `row_unusable field=dt_future`; the 300 s / 301 s boundary pair; unparseable `dt` → `field=dt`; ±120 s skew rows.
5. Warehouse failures: secret unset, helper missing, helper non-zero (with a username-bearing error body that must not appear anywhere), malformed body, selector lib missing/selftest fail → `query_failed reason=<each>`, exit 3.
6. Heartbeat paused → `fresh_heartbeat_paused`, exit 0, zero beat calls; `paused` absent, null or `"false"` → `beat_failed`.
7. Heartbeat absent, duplicated, prefix decoy, URL on another host / `http://` / path / query / lookalike host / quote or newline, API unreadable, token unset or malformed shape → `beat_failed`, exit 4, zero beat calls.
8. Beat returns 500, 302, or curl fails → `beat_failed reason=http_status`, exit 4.
9. xtrace with a credential set → exit 78; malformed `INNGEST_FEEDER_NOW` → exit 3; any argument other than `--selftest` → exit 64; `--selftest` with no credentials and under `env -i` → `inngest-probe-feeder: selftest=ok`, exit 0, zero network calls, and with `INNGEST_PROBE_ROW_LIB=/dev/null` → exit 3 (a lib that defines nothing fails the selftest).
10. Static: the workflow's `run:` line carries the manifest evidence pattern; the workflow's step captures with `|| rc=$?` and its `status` expression reads the exit code; the heartbeat-name literal equals the `.tf` name; a table row exists for the workflow; the budget inequality (Guard 1 Anchor); exit-token allowlist, single trap, no `exec`/`kill`.
11. Boundary pair and the "second member after a compliant first" cases from the Guard 1 matrix.

## Risks and Sharp Edges

- **Beat-to-paused semantics are unknown.** The verifier never beats while paused, so the first beat Better Stack ever sees from this feeder is the one the arming command forces; its `status=up` is the measurement.
- **Ordering at merge.** The Sentry monitor is created by the push-apply; the clock dispatches only after the web release deploys the table row. A missed check-in in the gap opens one unrouted Sentry issue (no email). The check-in call itself cannot create a monitor and runs under `continue-on-error`, so the gap is harmless. Expected, not a defect.
- **Unrouted monitor.** Until Stage 3b routes it, a withheld verdict reaches Sentry only as an issue, not an email. Pre-arm the covering signal for the store is the daily 8296 probe; post-arm the heartbeat's own page covers a dark pipeline. Routing is in Phase 7 and is on the #9703 checklist, not a silent deferral.
- **A paused heartbeat after arming is silent in the feeder** (exit 0, `fresh_heartbeat_paused`). The net is the nightly `heartbeat-live-reconcile` `fed-but-paused` class, re-armed by Stage 3a immediately after the read-back; the Stage 3b gate refuses to delete the 8296 probe until that is in place.
- **Credential scope.** The feeder holds the read-only token (cannot write); repo write access already exposes every repo secret through a branch workflow, so the read-only scope is the mitigation, not "runs only from main" (only `schedule` is main-only; a branch can run a `workflow_dispatch` copy). The arming command reads the write token from Doppler locally and shape-checks it before it reaches a curl config.
- **Hot/archive seam.** If the newest hourly row is momentarily invisible at the seam, the verifier sees the previous hour's row (about 2 h old) and withholds for those slots. The Phase 6 soak measures this; one lost slot is tolerated, more would page.
- **Inngest-host failure domains.** A fully dark Inngest host also stops the probe, so this heartbeat pages (correct) while `inngest_prd` and `inngest_consumer` heartbeats page too; the verdict marker distinguishes "probe dark" from "feeder dark".
- **C4 counts are gated, not guessed.** Run `c4-count-parity.test.sh` and copy its numbers; a hand-derived count is the same class as a stale embedded count the gate exists to catch.
- **A plan whose `## User-Brand Impact` section is empty, holds only filler text, or omits the threshold fails `deepen-plan` Phase 4.6;** this plan declares `none` with a scope-out bullet because the diff touches `apps/web-platform/server/` and `apps/web-platform/infra/`.
- **Do not pin or edit** the Inngest volume attachment, never touch web-1's LUKS volume 106443278, never reboot or replace a host from this work; none is in scope and none is needed.
- **Read back any file a probing loop edited** before committing; do not rebase after an attestation names commit ids.
- **Arming prose must not claim "armed".** Docs, the ADR amendments and the manifest comment say "fed; arming pending on #9703" until the Stage 2 read-back exists and Stage 3a lands.
