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

## Overview

`betteruptime_heartbeat.inngest_server_probe` (live id 504655, `soleur-inngest-server-probe-prd`,
period 3600 / grace 1800, paused; read back read-only on 2026-10-11) is the dead-man's-switch
sibling of `logtail_exploration_alert.inngest_luks_wrong_volume`, which reads a silent probe
pipeline as healthy (`on_missing_data = "treat_as_zero"`). It has no feeder, so it is inert. Since
2026-10-09 the plaintext backstop is destroyed and `hcloud_volume.inngest_redis_luks` is the sole
copy of the store, so this heartbeat is the only dead-probe tripwire besides the daily
`inngest-luks-property-8296.sh` follow-through probe, which the issue says stays until this feeder
is armed.

This plan delivers it in three separately-gated stages. Only Stage 1 is executed by this pipeline run:

| Stage | What | Production writes | Who/when |
|---|---|---|---|
| 1. Code PR (this run) | repo-side verifier script + its harness, a clock-dispatched workflow, the Sentry liveness monitor (declared, unrouted), the manifest row flip, parity-test and doc updates | None against Better Stack. Merging this PR alone does three things in production: (i) `apply-sentry-infra.yml` creates one Sentry cron monitor; (ii) because the diff touches `apps/web-platform/infra/**`, `apply-web-platform-infra.yml` also fires on push — its `-target` plan covers resources this diff does not change, so the expected plan for the heartbeat and its Doppler secret is no-op; (iii) the web release that carries the new dispatch-table row starts clock-dispatched runs of the new workflow, which beat nothing while the heartbeat is paused. `uptime-alerts.tf` is NOT edited | ships through merge |
| 2. Arming | unpause the heartbeat, watch `status` reach `up`, roll back to paused if it never does | YES: Better Stack API writes (PATCH `paused`) plus one GitHub workflow dispatch | one compound command, shown in full and authorized as a unit before it runs; named in `## Arming Procedure`; nothing executes it in this run |
| 3. Cleanup PR | delete the superseded 8296 probe and every row naming it, drop `arming_pending`, route the Sentry monitor, close #9703 explicitly | None against Better Stack | after Stage 2's read-back shows `paused=false status=up` |

Target: Stage 1 merged and Stage 2 done before **2026-10-22**, the issue's own re-evaluation date.

### The design in one paragraph

A bash verifier `scripts/inngest-probe-heartbeat-feeder.sh` queries the Better Stack Logs warehouse
through `scripts/betterstack-query.sh`, selects probe rows with the shared predicate in
`scripts/lib/inngest-probe-row.sh` (emitter + anchored marker + `host_role=dedicated` + host
isolation), and takes the newest by `dt`. If that row is no older than **4500 s**, it resolves the
heartbeat's ping URL by exact name from the Better Stack uptime API (GET only) and beats it, unless
the heartbeat is still paused, in which case it reports `fresh_heartbeat_paused` and beats nothing.
Exit 0 means exactly `{beat, fresh_heartbeat_paused}`; every other outcome withholds the beat and
exits non-zero. A new workflow `scheduled-inngest-probe-heartbeat.yml` runs it every **15 minutes**,
dispatched by the web server's watchdog dispatch clock (ADR-248, new `WATCHDOG_DISPATCH_TABLE` row)
with a `schedule:` fallback, and posts a Sentry cron check-in (`ok` iff the verifier exited 0).
`period`/`grace` are **not** changed: the 15-minute cadence meets the 5400 s beat budget with the
measured dispatch variance, so nothing is written to Better Stack at merge.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality (evidence) | Plan response |
|---|---|---|
| (c) "observe one real beat land in Better Stack, then unpause (the #6210 discipline — verify a ping arrives BEFORE unpausing)" | A paused heartbeat exposes no usable ping timestamp; `updated_at` does not move on a beat while paused (`apps/web-platform/infra/arm-heartbeats.sh` header; ADR-117; learning `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`). The only measurement is unpause, watch `status` reach `up`, roll back before the first absence alert | Arming is "unpause + wall-clock-bounded poll + automatic rollback" (`## Arming Procedure`). Pre-arm evidence is the verifier's `verdict=fresh_heartbeat_paused` line: it proves freshness and URL resolution, not a landed beat |
| (b) "`feeder.kind` from `none` to … `cron`/`timer` + file evidence, or `external-probe` with the workflow evidence" | `external-probe` is an `Arming` value (already set on the row), not a `Feeder.kind`; `Feeder` is `cron\|timer\|none` and the `cron` arm carries only `{kind, evidence}` (`plugins/soleur/lib/heartbeat-manifest.ts`). `heartbeat-reprovision-parity.test.ts` pins evidence to the on-host timer-enable construct or a `/etc/cron.d` drop-in, under `apps/web-platform/infra/` | Flip to `kind: "cron"` with workflow evidence (dropping `url_secret`/`tracking_issue`, which belong to the `none` arm) and relax that one test regex to admit `.github/workflows/<x>.yml` + `bash scripts/<x>.sh` |
| "trigger options: `watchdog-dispatch-table.ts` + scheduled workflow + `sentry_cron_monitor`, or the daily follow-through sweeper if period/grace are re-sized" | GitHub `schedule:` delivered one run every 2–7 h on this repo (ADR-248, #8495). The sweeper treats exit 0 as "close the tracker" and runs only for open directive-bearing issues | Watchdog table row. Sweeper rejected (see Alternatives) |
| "mirror the freshness predicate in `inngest-luks-property-8296.sh`" | That script's `STALE_SECS=10800` (3 h) is sized for a daily notify-only probe; a 3 h bound lets a dead probe keep the heartbeat fed for 3 h | Mirror the selection (host, emitter, marker, role, newest-by-dt, future-slack) but derive the bound from the beat budget: 4500 s |
| "`inngest-luks-property-8296.sh` was enrolled on #8285, which closes now" | The directive is already in #9703's body (the sweeper has commented NOT YET exit 2 on #9703 since 2026-10-10T20:30Z) | Nothing to move; Stage 3 removes the directive from #9703 before deleting the script |
| Deletion list names `scripts/lib/inngest-probe-row.test.sh` "references" | It carries the script in `MUST_FIND` (red if the file disappears) | Stage 3 edits `MUST_FIND`; Stage 1 adds the new verifier to it |

## Research Insights

### Premise Validation (Phase 0.6)

- #9703 is OPEN; #8516's PR #9699 is MERGED; #9877 (PR B, backstop retire) is MERGED. No cited blocker is closed or stale.
- On `origin/main` (47c38a19da): `scripts/betterstack-query.sh`, `scripts/lib/inngest-probe-row.sh`,
  `scripts/followthroughs/inngest-luks-property-8296.sh`, `apps/web-platform/infra/uptime-alerts.tf`,
  `plugins/soleur/lib/heartbeat-manifest.ts` (row `inngest_server_probe`, `feeder.kind = "none"`,
  `arming_pending.tracking_issue = 9703`) all exist. Live read-back (read-only GET) shows the heartbeat present, paused, 3600/1800, and its `url` attribute matches `^https://uptime\.betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]+$` (tested without printing the value).
- ADR corpus check of the proposed mechanism: ADR-117 (executable arming) and ADR-248 (dispatch clock
  eligibility) govern; neither rejects a workflow feeder. ADR-248's eligibility rule is met: the
  watched thing (the dedicated Inngest host's probe pipeline) is the scheduling substrate's own host,
  so an Inngest cron cannot be its scheduler (ADR-033 anti-circularity).
- Better Stack API facts (KB-documented): heartbeat attributes carry `status`, `paused`, `period`,
  `grace`, `updated_at`, `url`; PATCH `{"paused": bool}` is the only arm/disarm write used here.
  NOT documented anywhere: the response to a beat sent to a paused heartbeat, and whether a
  period/grace update resets state. This design depends on neither (it never beats while paused and
  never edits period/grace).

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
| New ADR | — | An amendment to ADR-117 (workflow feeder evidence); a third row of the ADR-248 table needs only its `eligibility` string and the workflow header |
| New `github_actions_secret` publishing the heartbeat URL, or a URL repo secret set at arm time | 1 | URL is resolved at run time from the uptime API with the existing `BETTERSTACK_API_TOKEN` repo secret (see Alternatives for why a secret set at arm time is rejected) |
| New arming script or arming workflow | 5 | One-time operation: a single compound command (wall-clock bounded, self-rolling-back) in the runbook; `arm-heartbeats.sh` keeps serving the recurring push-apply case |
| Widening `period`/`grace` | 2 | 15-minute cadence meets the budget; also avoids an unmeasured Better Stack state reset and a merge-time write |
| `Feeder.kind = "workflow"` type | 4 | Flip to `cron` and relax one test regex |
| Verifier dry-run mode and `dry_run` dispatch input | 1, 3 | Pre-arm every real run already takes the no-write `fresh_heartbeat_paused` path |
| Opening a GitHub tracker issue on a withheld verdict | 3 | Sentry check-in `error` + the heartbeat's own absence page once armed |
| Shared extraction of the freshness predicate into `scripts/lib/` | 1 | The 8296 probe is deleted in Stage 3; the duplication is bounded |

### Institutional learnings applied

- `2026-07-16-the-fix-for-an-inert-monitor-…`: paused monitors record no beats, so arm-and-watch with rollback; never claim "armed" in docs/ADRs before the arm step has run.
- `2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md`: `ignore_changes=[paused]` plus a hard-coded arm list leaves members permanently paused; here the arm is a one-time named procedure and the manifest keeps `arming_pending` until read-back.
- `2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md` and the margin budget in `sentry-monitor-iac-parity.test.ts`: margin floor = ceil(12 clock + 30 queue + max_runtime), ceiling 60.
- `2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md` and the sweeper contract: do not enrol the feeder as a follow-through (exit 0 closes a tracker); the verifier lives outside `scripts/followthroughs/`.
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`: PR body and commits use `Ref #9703` only.
- #8659 (open code-review): a suite that installs its own EXIT trap after sourcing `plugins/soleur/test/test-helpers.sh` leaks a sandbox; the new harness lives under `scripts/` and sources no helper, so it carries its own cleanup trap.
- ADR-117 / #7587: an arming deadline is wall clock (`$SECONDS`), not a sleep tally, and the rollback must sit inside `period + grace - 40`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing customer-visible. The failure shapes are
  an alert that never comes (feeder beats spuriously while the probe is dead, so a store off its
  encrypted device goes unpaged) or a false "dead probe" email to ops@ (feeder under-beats once
  armed). Both are internal observability faults; the heartbeat ships and stays paused until a
  separately authorized arm.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no customer data path. The
  heartbeat URL is a bearer ping endpoint (leak enables beat forgery = denial of one alarm); the
  feeder resolves it at run time, never prints it, and keeps it off argv. The repo secret
  `BETTERSTACK_API_TOKEN` it uses is the same account-wide token the follow-through sweeper already
  holds; the feeder uses it for GET only (harness-asserted), in a job holding `contents: read` and
  running only from `main`. A read-only token exists in Doppler (`BETTERSTACK_API_TOKEN_READONLY`) but
  not as a repo secret, and reaching it from CI would need the broader `DOPPLER_TOKEN`; the narrower
  exposure is the existing repo secret.
- **Brand-survival threshold:** none
- scope-out: `threshold: none, reason: alerting-only plumbing with no data store, auth path or customer surface; the sensitive-path contacts (apps/web-platform/server/watchdog-dispatch-table.ts, apps/web-platform/infra/sentry/*.tf) are a dispatch-table row and a cron-monitor declaration that existing parity tests gate`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "wire the heartbeat feeder" | Phases 1–3 (verifier, workflow, table row, Sentry monitor) | mapped |
| 2 | "arm betteruptime_heartbeat.inngest_server_probe" | `## Arming Procedure` (Stage 2, authorized as a unit, not executed here) | mapped |
| 3 | "repo-side verifier on a reliable trigger, reusing scripts/betterstack-query.sh + scripts/lib/inngest-probe-row.sh, mirroring the freshness predicate in scripts/followthroughs/inngest-luks-property-8296.sh" | Phase 1 | mapped |
| 4 | "do NOT extend that script to push" | Phase 1 creates a new script; the 8296 script is untouched until Stage 3 | mapped |
| 5 | "the beat budget (period 3600 + grace 1800 => beat at least every 5400 s; a daily feeder requires widening period in the same change)" | `## Beat Budget` (15-minute cadence; period/grace unchanged) | mapped |
| 6 | "the heartbeat-manifest.ts row update" | Phase 4 | mapped |
| 7 | "the probe re-homing/deletion list that applies once armed" | Phase 7 (Stage 3, separate PR) | mapped |
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
| harness suite `scripts/inngest-probe-heartbeat-feeder.test.sh` | "CI is the authority for the full test battery" | inferred — justification: cq-write-failing-tests-before and the Guard Contract require the suite |
| ADR-117 amendment, runbook section, C4 clause | "Plan must follow hr-observability-as-plan-quality-gate" | inferred — justification: wg-architecture-decision-is-a-plan-deliverable; the evidence-shape change must not leave recorded architecture stale |
| Stage 3 plan (deletions, routing PR, directive removal) | "the probe re-homing/deletion list that applies once armed" | asked |

### Split Assessment

- Subsystems touched: 5 — `scripts/`, `.github/workflows/`, `apps/web-platform/` (server + infra/sentry + test), `plugins/soleur/`, `knowledge-base/`
- Planned files: ~22 (Stage 1) | Estimated changed lines: ~750 (about 450 are the new harness)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — Stage 1 (this PR) / Stage 3 (post-arm cleanup PR). Stage 1 stays ONE PR on purpose: its pieces are mutually tripwired (the manifest row reds when a feeder lands unreconciled; the table row reds without its monitor; the monitor reds without its routing-map entry), so a smaller PR would land red.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed (CTO devex review during plan-review: design sound, no disqualifier; its P1s on the arming command and R1 polling are applied below)
**Assessment:** Pure infra/observability. Risks named and handled in-plan: beat-budget math under dispatch variance, a spurious-beat failure suppressing the alarm (single beat call site, host/emitter/role isolation, fixtures for each), the credential shared with the sweeper (GET-only assertion), and the ADR-248 eligibility argument. No product, marketing, legal, finance, sales or support surface. The GDPR gate does not fire: no schema, auth flow, API route or personal-data processing is added, and none of the (a)–(d) cross-controller triggers apply (the warehouse rows carry host/mount fields only).

## Architecture Decision (ADR/C4)

### ADR

Amendment, not a new ADR (no new substrate or trust boundary):

- **ADR-117 (executable heartbeat arming)** — append a short dated amendment (three lines): a heartbeat's feeder may be a clock-dispatched GitHub Actions workflow (`kind: "cron"`, `evidence.file` a workflow under `.github/workflows/`, `evidence.pattern` the `bash scripts/<x>.sh` run line), bound to the heartbeat by name in the verifier and asserted by the feeder's harness; and "fed" is not "armed" (the verifier deliberately beats nothing while the heartbeat is paused). Do NOT state the heartbeat is armed (it is not until Stage 2).
- The third `WATCHDOG_DISPATCH_TABLE` row needs no ADR-248 edit: ADR-248's own eligibility rule is satisfied by the row's `eligibility` string, which `sentry-monitor-iac-parity.test.ts` requires non-empty.

### C4 views

Read all three `.c4` files. Enumeration against the completeness rubric: (a) external human actors — none new; (b) external systems — Better Stack, Sentry, GitHub Actions and the web hosts' dispatch clock are all modeled; (c) containers/data stores — none new; (d) actor-to-surface relationships — none change. Edit only what is falsified or gated, then regenerate `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`:

- `inngestRedis`: the clause "`betteruptime_heartbeat.inngest_server_probe` (uptime-alerts.tf — born paused; its feeder + arming are tracked on #9703)" becomes: fed by the feeder workflow, arming still tracked on #9703 (not armed yet).
- `github -> sentry`: the embedded workflow/monitor counts. Take the exact numbers from the failure output of `bash plugins/soleur/test/c4-count-parity.test.sh`, which is the gate; do not hand-derive them.
- Further prose (`api -> github` dispatched-workflow list, `github -> betterstack`) only if `c4-model-freshness.test.sh` or the count gate demands it.

The `model.c4` description that mentions `inngest-luks-property-8296.sh` is edited in Stage 3, not here.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf`: new `sentry_cron_monitor.scheduled_inngest_probe_heartbeat` (`name = "scheduled-inngest-probe-heartbeat"`, `crontab = "*/15 * * * *"`, `checkin_margin_minutes = 60`, `max_runtime_minutes = 6`, thresholds 1/1, UTC). Margin 60 is the parity ceiling and covers the measured tail (12 clock + 40.6 queue + 6 runtime = 58.6 min), so a slow runner queue does not file a missed check-in while the heartbeat is still safe.
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: add the label to `local.cron_monitor_alert_unrouted` with a `"<reason> (#9703)"` value (two-PR rule; routing is Stage 3).
- Better Stack: **no** `.tf` change. `uptime-alerts.tf` is deliberately not touched (including comments) so Stage 1 cannot change the heartbeat object or its Doppler secret; its stale "feeder deliberately not in this PR" comment is refreshed in Stage 3.
- No new provider, no new sensitive variable, no new secret: the verifier uses repo secrets that already exist (`BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD`, `BETTERSTACK_API_TOKEN`, `SENTRY_INGEST_DOMAIN/PROJECT_ID/PUBLIC_KEY`).

### Apply path

(a) cloud-init/host: none. (b)/(c): none. The Sentry root applies automatically on push to `main` through `apply-sentry-infra.yml` (full-root plan, no allow-list edit). That is the repo's standard IaC delivery for this vendor and is a Sentry write, not a Better Stack write. The web server release that carries the new table row follows the normal `web-platform-release.yml` path. Expected downtime: none.

**Does merging THIS alone mutate production?** Yes, in exactly the three ways in the Stage table, and not in any Better Stack way. Derivation: `apply-sentry-infra.yml` `paths:` covers the whole `infra/sentry/**` tree and plans the full root; `apply-web-platform-infra.yml` `on.push.paths` is `apps/web-platform/infra/**` (with only the rehearsal and root-key roots negated), so an edit to `infra/sentry/*.tf` or to `infra/inngest-server-probe-heartbeat.test.sh` fires it, and its `-target` allow-list plus the state-gated `arm-heartbeats.sh` chain neither contain nor arm `inngest_server_probe`. The PR's own CI infra plan must show no change to `betteruptime_heartbeat.inngest_server_probe` or `doppler_secret.inngest_server_probe_heartbeat_url`; if it shows any, stop. The PR body's first line states this answer.

### Host fan-out

None. No `terraform_data` SSH provisioner under `apps/web-platform/infra/` is touched; no fleet sibling classification applies.

### Distinctness / drift safeguards

No `dev != prd` surface. The heartbeat keeps `ignore_changes = [paused]`; nothing in Stage 1 edits the resource. The nightly `heartbeat-live-reconcile` keeps the row exempt from `fed-but-paused` through `arming_pending` until Stage 3 removes it (removal before arming would page the reconcile).

### Vendor-tier reality check

`betteruptime_heartbeat.inngest_server_probe` already exists with `policy_id` gated on `var.betterstack_paid_tier`; nothing here creates a tier-gated Better Stack object. Sentry cron monitors are already used at scale; one more is within the existing org usage pattern.

## Beat Budget

| Quantity | Value | Source |
|---|---|---|
| Pages when no beat for | `period + grace` = 5400 s (90 min) | `uptime-alerts.tf` |
| Dispatch slot | 15 min (UTC wall-clock multiple) | new `intervalMinutes` |
| Worst clock delay in a slot | 12 min | `CLOCK_DELAY_MINUTES` in `sentry-monitor-iac-parity.test.ts` |
| Measured runner queue, max | 40.6 min (2438 s) on the two existing watchdogs, 2026-09-24 | `sentry-monitor-iac-parity.test.ts` comments |
| Verifier runtime | 2 min typical; job `timeout-minutes: 6` | workflow |
| Worst consecutive-beat gap, all slots delivered | 15 + (12 + 40.6 + 2) minus 0.5 = about 69 min | below 90 |
| Worst gap with ONE whole slot lost | 30 + 54.6 = about 85 min | below 90, with 5 min of slack |
| Two slots lost | about 100 min | pages — a true "feeder dark" |
| Rejected: 60-min slots | 60 + 54.6 = 115 min worst; any two consecutive queue delays differing by 30 min break the budget, and the measured p90 is 20 min | false pages |

Slack is thin on purpose and stated plainly: 40.6 min is an observed maximum over 40 runs, not a bound, and one lost slot plus a queue spike beyond it pages falsely. That is accepted: a page after a lost slot plus an extreme queue is a "the feeder path is degraded" finding, the Guard 1 Anchor test reds first if the cadence constants are weakened, and if false pages appear the one-line fallback is a 30-minute `grace` widening, to be measured before use because Better Stack's state-reset semantics on a period/grace update are undocumented. Manual workflow dispatches inside a slot make the clock skip that slot, so they consume the one slot of tolerance: do not stack manual runs.

Detection latency for a dead probe: the last good row is at `D`; the verifier keeps beating while the newest row is at most 4500 s old, so the last beat lands in `[D, D + 75 min + one slot]` and the heartbeat pages 90 min after it: between about 1.5 h and about 3 h after the probe's last emission. This is accepted as a latency trade; the wrong-volume alert itself is unchanged and still pages on a wrong-volume row at its own cadence.

Why 4500 s: the probe emits hourly (`OnUnitActiveSec=1h`, `AccuracySec=1min`); a healthy row's age at check time ranges 0 to about 3660 s plus ingest lag (observed 1275 s and 3244 s on 2026-10-10). 4500 s leaves about 14 min of slack and still means one skipped emission starts the clock. It is a named constant with a boundary test at 4500/4501.

## Implementation Phases

Phases 1–6 are Stage 1 (this PR, executed by the work skill). Phase 7 is Stage 3. `## Arming Procedure` is Stage 2 and is not a work-skill phase.

### Phase 1 — Verifier script (TDD: harness first)

1. Write `scripts/inngest-probe-heartbeat-feeder.test.sh` first (cases in `## Test Scenarios`), watch it fail, then write `scripts/inngest-probe-heartbeat-feeder.sh`.
2. Script contract (mirrors 8296's prologue, trap and clock handling; the only accepted argument is `--selftest`):
   - `--selftest`: load the shared predicate (below), run `inngest_probe_row_selftest`, print `inngest-probe-feeder selftest: ok` and exit 0, or print `FAILED` and exit 3. No network, no credentials. Any other argument is exit 64.
   - xtrace refusal (`rc 78`) when `-x` is on and any `BETTERSTACK_*` credential is set. An EXIT trap rewrites any status outside `{0,3,4,64,78}` to 3 with `verdict=trap_remapped`: a fall-off that exits 0 would post a Sentry `ok` for a run that decided nothing (8296 pinned the same lesson).
   - Load the shared predicate exactly per the lib's LOAD CONTRACT (`unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER`; `_ipr_lib="${INNGEST_PROBE_ROW_LIB:-$REPO_ROOT/scripts/lib/inngest-probe-row.sh}"`; source + `declare -F` + `inngest_probe_row_selftest`; failure arm `verdict=query_failed reason=selector_unavailable lib=…`, exit 3).
   - Clock: `INNGEST_FEEDER_NOW` (ISO-8601 UTC) for the harness; set-but-malformed is exit 3, never a wall-clock fallback.
   - Query: `scripts/betterstack-query.sh --since 2h --grep "$INNGEST_PROBE_MARKER" --limit 500` (the default archive arm is kept: the hot window alone is about 40 min and cannot see an hourly row). The verifier sorts by `dt` itself and does not depend on the helper's row order; the 2 h window must stay above 4500 s plus ingest lag.
   - Select with `select(inngest_probe_row)` and `host == "soleur-inngest" and host_name == "soleur-inngest-prd"` and FIRST `host_role=` token `== "dedicated"`; normalise `dt` (`T` to space); newest by `dt`; unusable `dt` or `dt` more than 300 s in the future is a withhold; age above 4500 s is a withhold (`producer_silent`).
   - Resolve the heartbeat: GET `https://uptime.betterstack.com/api/v2/heartbeats?per_page=250` with the bearer passed through `curl --disable --noproxy '*' --config -` (never on argv; token shape-checked first). Select by exact `attributes.name == "soleur-inngest-server-probe-prd"`; zero or more than one match is `beat_failed` (exit 4). One page of 250 is enough today; more than 250 heartbeats fails safe as `beat_failed` (add a one-line comment; follow `pagination.next` if the account grows). The `url` must match `^https://uptime\.betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]+$` (also the injection guard for the curl config) or the run is `beat_failed`.
   - If `attributes.paused == true`: `verdict=fresh_heartbeat_paused`, exit 0, no beat.
   - Else beat: `curl --disable --noproxy '*' -fsS --max-time 15 -w '%{http_code}' --config -` with the URL on stdin; no redirect following, and success is a 2xx code only (a 3xx passes `-f`, so the code is checked); print `verdict=beat http=<code>` (exit 0); anything else is `beat_failed reason=http_status` (exit 4). The URL is never printed, so no `::add-mask::` line is needed (emitting one would put the URL on stdout).
   - Every marker line is `inngest-probe-feeder: verdict=<v> <k=v …>`; withheld verdicts add one `CANNOT BEAT:` sentence naming the cause and stating that it says nothing about the store.
3. The beat call is the **single** call site that can reach the heartbeat URL, and it sits after every freshness and resolution check (Guard 1).

### Phase 2 — Workflow

`.github/workflows/scheduled-inngest-probe-heartbeat.yml`, modelled on `scheduled-zot-restart-loop.yml`:

- Header carries `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` plus the ADR-248 eligibility argument (the watched host is the Inngest scheduler's own host; the work is a credentialed bash pipeline).
- `on:` exactly `schedule` (`cron: '*/15 * * * *'`, the fallback) and `workflow_dispatch: {}`; top-level `concurrency: { group: scheduled-inngest-probe-heartbeat, cancel-in-progress: false }`; `permissions: contents: read`.
- One job, `runs-on: ubuntu-24.04`, `timeout-minutes: 6`, pinned `actions/checkout` SHA, `persist-credentials: false`.
- Step "Verify freshness and beat": env from repo secrets (`BETTERSTACK_QUERY_*`, `BETTERSTACK_API_TOKEN`); `rc=0; out="$(bash scripts/inngest-probe-heartbeat-feeder.sh 2>&1)" || rc=$?` (the verifier's exit is DATA — the `|| rc=$?` capture is mandatory because Actions runs `bash -e`); echo the output through `strip_log_injection`; map `rc` to `::notice::` / `::error::` annotations; write `exit_code` to `$GITHUB_OUTPUT`. The step never exits non-zero.
- Final step `uses: ./.github/actions/sentry-heartbeat` with `monitor-slug: scheduled-inngest-probe-heartbeat`, `status: ${{ steps.feeder.outputs.exit_code == '0' && 'ok' || 'error' }}`, `if: always()`, `continue-on-error: true`.

### Phase 3 — Dispatch table row and Sentry monitor

- `apps/web-platform/server/watchdog-dispatch-table.ts`: add `{ workflowFile: "scheduled-inngest-probe-heartbeat.yml", monitorSlug: "scheduled-inngest-probe-heartbeat", intervalMinutes: 15, eligibility: "<argument>" }`.
- `sentry-monitor-iac-parity.test.ts`: the hard-coded expected slug set gains the new slug; no other literal changes (the margin test derives from the constants).
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts`: add the slug (with a one-line why) to `NON_INNGEST_MONITORS`.
- `cron-monitors.tf` + `cron-monitor-alerts.tf` per `## Infrastructure (IaC)`.
- Re-read the `inngest-server.md` runbook checklist ("How the external watchdogs are triggered", step 4) and satisfy each item it lists that this plan has not.

### Phase 4 — Manifest row flip and its parity tests

- `plugins/soleur/lib/heartbeat-manifest.ts`, row `inngest_server_probe`: `feeder: { kind: "cron", evidence: { file: ".github/workflows/scheduled-inngest-probe-heartbeat.yml", pattern: "bash scripts/inngest-probe-heartbeat-feeder.sh" } }` (the `none` arm's `url_secret` and `tracking_issue` are dropped; they do not exist on the `cron` arm); keep `arming: "external-probe"`, `paused: true`, `arming_pending: { tracking_issue: 9703 }`; rewrite the row comment and `exempt_reason` to say the feeder exists and arming is pending, keeping `arming_pending` within the 30-line window section (h) greps.
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`: relax the evidence-shape assertion to a two-arm alternation — the existing timer-enable / `cron.d` arm keeps requiring `apps/web-platform/infra/`; the new arm requires file `^\.github/workflows/[\w.-]+\.yml$` AND pattern `^bash scripts/[\w.-]+\.sh$`. Keep the bounded-hit assertion (1–2 hits).
- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` section (h): assert `kind: "cron"`, the workflow `evidence.file` and `evidence.pattern`, and `arming_pending`, instead of `kind: "none"` + `url_secret`; section (h) keeps three assertions, so `EXPECTED_PASSES` stays 21 (set it to the measured count if that changes).
- `scripts/lib/inngest-probe-row.test.sh`: add `scripts/inngest-probe-heartbeat-feeder.sh` to `MUST_FIND` (so discovery cannot silently drop the new consumer); the census auto-checks the load contract.

### Phase 5 — Registration, docs, C4

- `scripts/test-all.sh`: `run_suite "scripts/inngest-probe-heartbeat-feeder" bash scripts/inngest-probe-heartbeat-feeder.test.sh`; regenerate `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` with the repo's `--write` generators (see `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`) and add any row `scripts/test-affected-kb-consumers.baseline.txt` requires for the new suite.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: add the feeder to the external-watchdog section and place the `## Arming Procedure` command there as its durable home (no SSH step), so the procedure outlives the plan file.
- ADR-117 amendment; `model.c4` edits then `bash scripts/regenerate-c4-model.sh`; run `bash plugins/soleur/test/c4-count-parity.test.sh` and copy the counts it demands.

### Phase 6 — Verify and ship

Targeted suites only (see `## Acceptance Criteria`). PR body: first line is the "does merging this alone mutate production?" answer (see `## Infrastructure (IaC)` and the Acceptance Criteria), then `Ref #9703` (no closing keyword), a `## Changelog` section, a "Production writes" paragraph stating that Stage 1 writes nothing to Better Stack and that arming is a separately authorized step tracked on #9703, and the closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Comment on #9703 recording that the Sentry routing PR and Stage 3 are the remaining tracked work (the issue stays open with its existing 8296 follow-through directive, so the deferral is visible and dated by its 2026-10-22 trigger).

### Phase 7 — Stage 3 cleanup PR (separate PR, after Stage 2's read-back; detail belongs to that PR's own plan)

- Order constraint: remove the `<!-- soleur:followthrough script=… -->` directive from #9703's body FIRST (`gh issue edit`), so the sweeper never points at a deleted script.
- Delete the 8296 probe and harness and every registration row naming it (`test-all.sh`, `suite-durations.tsv`, `suite-shard-legs.tsv`, the two `test-affected-kb-consumers.baseline.txt` rows, the `MUST_FIND` entry); edit the prose references (`encryption-posture-ledger.json` `live_verification`, `inngest-luks-cutover-6894.md`, `inngest-server.md`, `model.c4` + regenerate, comment-only edits in `betterstack-logs-alerts.tf` and `uptime-alerts.tf` whose push-apply plan must show "No changes").
- `heartbeat-manifest.ts`: remove `arming_pending` (this re-arms the nightly reconcile's `fed-but-paused` alarm for the row, which is the safety net if anything re-pauses the heartbeat after arming: a paused heartbeat reports `fresh_heartbeat_paused` with exit 0, so the verifier itself would not alert).
- Route the monitor (two-PR rule): move `scheduled_inngest_probe_heartbeat` from `cron_monitor_alert_unrouted` into `sentry_alert.cron_monitor_failure.monitor_ids` and regenerate `alert-reference.json` per the sentry root README.
- After merge, `gh issue close 9703 --comment <read-back evidence>` (explicit close; no closing keyword anywhere).

## Arming Procedure (Stage 2 — NOT executed by this pipeline)

This is a production write to Better Stack. The command below is shown in full and authorized as a unit before it runs; a menu answer or an earlier approval does not authorize it (`hr-menu-option-ack-not-prod-write-auth`). It is one compound command on purpose: the unpause and its rollback live in the same shell, so a slow or absent human cannot leave the heartbeat unpaused and unfed past its first absence alert. No dashboard step and no SSH step. The token is read inside `doppler run` and sent through `curl --config -`; nothing below prints it or the heartbeat URL. Run it through the Monitor tool (an until-loop), never as a foreground call: it can legitimately run for up to ~90 minutes.

**Preconditions (read-only; stop on any miss):**

```bash
# P1  Stage 1 is on main and the clock has been dispatching the workflow
git fetch -q origin main && git log origin/main --oneline -1 -- scripts/inngest-probe-heartbeat-feeder.sh
gh run list --workflow=scheduled-inngest-probe-heartbeat.yml --status completed --limit 8 --json event,conclusion,createdAt \
  --jq '.[] | [.event, .conclusion, .createdAt] | @tsv'
# expect: at least two rows with event=workflow_dispatch and conclusion=success

# P2  the newest completed run reports freshness and the paused state (no beat is sent while paused)
RID=$(gh run list --workflow=scheduled-inngest-probe-heartbeat.yml --status completed --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RID" --log | grep 'inngest-probe-feeder: verdict=' | tail -1
# expect: verdict=fresh_heartbeat_paused

# P3  live heartbeat state (the URL attribute is deliberately not selected)
hb() { doppler run -p soleur -c prd_terraform --silent -- bash -c \
  'printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
hb "https://uptime.betterstack.com/api/v2/heartbeats?per_page=250" \
  | jq -r '.data[] | select(.attributes.name=="soleur-inngest-server-probe-prd") | [.id, .attributes.status, (.attributes.paused|tostring), (.attributes.period|tostring), (.attributes.grace|tostring)] | @tsv'
# expect: 504655  paused  true  3600  1800
# (the repo secret BETTERSTACK_API_TOKEN the feeder uses and the Doppler prd_terraform value this reads are the same token; confirm with the P3 result before arming)
```

**Arm — ONE compound command (WRITE; deadline 5300 s wall clock = `period + grace - 100`, inside the first absence alert):**

```bash
HB=504655; BASE=https://uptime.betterstack.com/api/v2/heartbeats
hb() { doppler run -p soleur -c prd_terraform --silent -- bash -c \
  'printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
hb -X PATCH -H 'Content-Type: application/json' --data-binary '{"paused":false}' "$BASE/$HB" | jq -r '.data.attributes | "unpaused status=\(.status) paused=\(.paused)"'
gh workflow run scheduled-inngest-probe-heartbeat.yml --ref main          # force one real beat now
SECONDS=0; up=0
while [ "$SECONDS" -lt 5300 ]; do
  s=$(hb "$BASE/$HB" | jq -r '.data.attributes.status')
  echo "$(date -u +%H:%M:%S) elapsed=${SECONDS}s status=$s"
  [ "$s" = "up" ] && { up=1; break; }
  sleep 30
done
if [ "$up" -ne 1 ]; then
  hb -X PATCH -H 'Content-Type: application/json' --data-binary '{"paused":true}' "$BASE/$HB" | jq -r '.data.attributes | "ROLLED BACK status=\(.status) paused=\(.paused)"'
  echo "arm failed: status never reached up in ${SECONDS}s"; exit 1
fi
```

**Read-back (READ):** repeat P3 and expect `504655  up  false  3600  1800`; then re-run the P2 lines on the next completed run and expect `verdict=beat http=2xx`. The next nightly `heartbeat-live-reconcile` markers (`SOLEUR_HEARTBEAT_RECONCILE_*`) must stay clean. Only then start Stage 3. If the command rolled back, read the newest completed run's `verdict=` line: `fresh_heartbeat_paused` after the unpause means that run predates it, `beat_failed` means the feeder cannot deliver, and any withheld verdict means the probe pipeline itself is dark (the finding this heartbeat exists for).

## Observability

```yaml
liveness_signal:
  what: "betteruptime_heartbeat.inngest_server_probe pages when no beat arrives within period+grace (5400 s); the feeder beats only when it confirms a fresh host_role=dedicated SOLEUR_INNGEST_SERVER_PROBE row (age <= 4500 s) in the Better Stack Logs warehouse. Pre-arm, the feeder's own liveness is the Sentry cron monitor scheduled-inngest-probe-heartbeat plus the per-run verdict line"
  cadence: "every 15 min, dispatched by the web server watchdog clock (ADR-248) with a */15 schedule fallback; Sentry margin 60 min"
  alert_target: "Better Stack email (ops@ via team_name 'Your team'; betteruptime_policy.uptime when var.betterstack_paid_tier) once armed; Sentry issue on the monitor (unrouted until the Stage 3 routing PR; emails after it)"
  configured_in: ".github/workflows/scheduled-inngest-probe-heartbeat.yml, scripts/inngest-probe-heartbeat-feeder.sh, apps/web-platform/server/watchdog-dispatch-table.ts, apps/web-platform/infra/sentry/cron-monitors.tf, apps/web-platform/infra/uptime-alerts.tf (heartbeat), plugins/soleur/lib/heartbeat-manifest.ts"
error_reporting:
  destination: "Sentry cron monitor scheduled-inngest-probe-heartbeat (check-in ok iff verifier exit 0) and the workflow run log (::error:: / ::notice:: annotations, one 'inngest-probe-feeder: verdict=' marker per run)"
  fail_loud: "exit 0 is exactly {beat, fresh_heartbeat_paused}; every withheld or failed outcome exits non-zero and posts a Sentry error check-in; a dead feeder is a missed Sentry check-in and, once armed, an absent beat"
failure_modes:
  - mode: "probe emitter dead, Vector journald-allowlist regression, or sink outage (no fresh dedicated row)"
    detection: "verifier withholds the beat (verdict=no_rows or producer_silent) -> workflow run log ::error:: (layer 6) and Sentry monitor error check-in (Sentry monitor); once armed the Better Stack heartbeat pages 90 min after the last beat"
    alert_route: "Better Stack heartbeat email (vendor absence alarm, the inngest-heartbeat class) + Sentry issue"
  - mode: "warehouse unreadable (credential, helper, malformed response)"
    detection: "verdict=query_failed reason=<…> in the workflow run log (layer 6); Sentry monitor error check-in"
    alert_route: "Sentry issue; heartbeat page if it persists past 90 min once armed"
  - mode: "beat cannot be delivered (heartbeat missing/ambiguous, URL refused, non-2xx)"
    detection: "verdict=beat_failed reason=<…> with ::error:: in the workflow run log (layer 6); Sentry monitor error check-in"
    alert_route: "Sentry issue; heartbeat page once armed"
  - mode: "feeder dispatch dark (clock down on both hosts, workflow disabled, GitHub outage)"
    detection: "Sentry monitor missed check-in within interval + margin = 75 min (Sentry monitor); the watchdog clock's own SOLEUR_WATCHDOG_DISPATCH markers (Better Stack Logs)"
    alert_route: "Sentry issue; heartbeat page once armed (a true 'feeder dark' finding)"
  - mode: "spurious beat (feeder beats while the probe is dead)"
    detection: "prevented by construction and pinned by harness fixtures (stale/other-host/other-role/quoting/future-dated rows each withhold); the nightly heartbeat-live-reconcile classifies the row against the manifest"
    alert_route: "CI red on the harness; reconcile issue/marker"
  - mode: "heartbeat unpaused while unfed (arming gone wrong)"
    detection: "the Arming Procedure's compound command polls on a wall-clock deadline of 5300 s and rolls back in the same shell; Better Stack pages at 5400 s if even that fails"
    alert_route: "Better Stack heartbeat email"
logs:
  where: "GitHub Actions run log of scheduled-inngest-probe-heartbeat.yml (verdict markers; no URL, token or row payload); Sentry cron check-in history"
  retention: "GHA run retention (repo default); Sentry monitor history per org plan"
discoverability_test:
  command: "bash scripts/inngest-probe-heartbeat-feeder.sh --selftest"
  expected_output: "inngest-probe-feeder selftest: ok"
```

The selftest (no network, no credentials, under a second) loads the shared predicate and runs its own selftest. The LIVE signal, which does need credentials, is read without SSH by the commands in `## Arming Procedure` (P2 for the verdict line, P3 for the heartbeat state). No `credentials_required` is declared on purpose: declaring it would move the repo-global `BASELINE_DECLARED_PROBES` ratchet, a file every sibling plan also edits.

Observability layers cited (hr-observability-layer-citation): layer 6 (workflow-run log, `::error::` annotations) for every verifier verdict; the Sentry cron monitor and the Better Stack heartbeat are the asynchronous no-SSH sinks. No Inngest function, pino logger or host-side code is added, so layers 1–5 and 7 do not apply. The feeder runs on a GitHub-hosted runner, a surface the operator cannot inspect interactively; the verdict marker carries every discriminating field (`age_s`, `limit_s`, `reason`, `http`) in one line, so each competing cause (probe silent, warehouse unreadable, beat undeliverable) is distinguishable from the log alone.

## Encryption Posture

```yaml
at_rest:
  mechanism: "no new persistent store: a workflow, a script, a dispatch-table row and a Sentry monitor declaration. The only retained artifacts are GitHub Actions run logs and Sentry check-in history, which carry verdict markers and ages, never row payloads, tokens or the heartbeat URL"
  evidence: "scripts/inngest-probe-heartbeat-feeder.sh prints only marker lines; the harness asserts the URL and bearer never appear in stdout/stderr"
  defends_against: "no storage is introduced, so nothing sensitive is persisted by this change"
  does_not_defend: "the heartbeat URL still lands in terraform.tfstate and Doppler soleur/prd via the existing resources (unchanged); a runner compromise during a run can read the in-memory URL and token"
  disclosed_as: "existing heartbeat-URL disclosure class (same as doppler_secret.inngest_heartbeat_url_prd); BETTERSTACK_API_TOKEN breadth is the sweeper's existing disclosure"
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

**Assembly.** The property quantifies over: the warehouse selection (host, host_name, emitter, anchored marker, first `host_role=` token, newest-by-`dt` with `T`/space normalised), the freshness and future-slack constants, the heartbeat resolution (exact name, cardinality 1, `paused`, URL shape), and the ONE beat call site. Structural chokepoint: the beat `curl` appears exactly once in the script and every path to it passes the verdict function; the harness asserts that by counting beat-shaped invocations in the stub's call log across every fixture and by a static count of the call site in the script. Uptime-API access is quantified separately: the `curl` stub fails any non-GET on the API path.

**Mutation matrix.**

| # | Edit under test | Must drive the guard |
|---|-----------------|----------------------|
| M1 | raise the bound by one second (age 4501 s must withhold, 4500 s must beat) | RED — boundary pair of fixtures |
| M2 | drop the `host`/`host_name` filter | RED — fixture: fresh row from another host, stale dedicated row |
| M3 | replace the shared predicate with a substring match on the marker | RED — fixture: fresh `doppler`-emitter row quoting the marker, stale probe row |
| M4 | drop the `host_role=dedicated` filter | RED — fixture: fresh `host_role=web` probe row newer than a stale dedicated one |
| M5 | select the first row instead of newest-by-`dt` | RED — fixtures: a stale dedicated row ordered before a fresh one, and a fresh row first with a future-dated newest row after it |
| M6 | call the beat before the freshness verdict (reorder, not delete) | RED — every withheld-path fixture asserts zero beat calls in the stub log (observed during the run, not after it) |
| M7 | ignore `paused == true` | RED — fixture: fresh row, paused heartbeat, assert no beat and `verdict=fresh_heartbeat_paused` |
| M8 | accept zero or two heartbeats with the name | RED — fixtures: name absent; two entries (second member after a compliant first) |
| M9 | loosen the URL shape check | RED — fixtures: a `url` on another host; a `url` carrying a quote or newline |
| M10 | print the resolved URL or bearer, or put either on argv | RED — secret-sentinel fixtures grep stdout, stderr and the call log's argv |

Every non-beat verdict fixture asserts both the exit status AND the exact `verdict=` token, which is the harness's own-dispatch floor (a branch that returns 0 for a withheld verdict reds there).

**Harness rows.** (a) Harness mutation: a stub `curl` that returns success for anything, and a harness whose total is `fail == 0`, would pass a script that beats unconditionally — so the suite asserts an exact case count (`EXPECTED_CASES`, a literal that must move with any added or deleted block) and a floor of beat-call assertions, and the final line must read `N passed, 0 failed` with N equal to that literal. (b) Must-PASS non-canonical inputs: a row whose `dt` uses `T` instead of a space; a row whose message carries a second `host_role=` token after the first (first-wins); extra unknown fields; a probe row followed by a doppler-quoting row of newer `dt` (the quoting row is set aside, the probe row decides).

**Anchor.** The 4500 s bound and the 15-minute slot are cross-checked against values this diff does not own: the suite parses `period`/`grace` from `apps/web-platform/infra/uptime-alerts.tf` and the slot from the `watchdog-dispatch-table.ts` row selected BY `workflowFile` (never by position) and asserts `2 × slot + (12 + 41 + 2) min < (period + grace)/60`, so weakening the cadence or shrinking the heartbeat budget alone turns it RED; `inngest-server-probe-heartbeat.test.sh` independently pins `period = 3600` / `grace = 1800`, so a diff that edits both files must also edit that second suite.

### Guard 2 — feeder-evidence binding: `heartbeat-reprovision-parity.test.ts` (relaxed arm) + the harness's wiring assertions

**Property.** The manifest's claim that `inngest_server_probe` is fed refers to a workflow that is clock-dispatched, runs the verifier on a `run:` line, and whose verifier resolves exactly this heartbeat by its `.tf` name.

**Assembly.** The manifest row (`evidence.file`, `evidence.pattern`); the workflow file's parsed `run:` steps; the verifier's literal heartbeat name; `betteruptime_heartbeat.inngest_server_probe`'s `name` in `uptime-alerts.tf`; the `WATCHDOG_DISPATCH_TABLE` row; the Sentry monitor slug in `cron-monitors.tf` and the workflow's `sentry-heartbeat` step. Members are enumerated through the parsed YAML and the parsed `.tf` blocks, not through prose; the existing sentry parity suite already owns the trigger, concurrency and slug checks, so this guard does not restate them.

**Mutation matrix.**

| # | Edit under test | Must drive the guard |
|---|-----------------|----------------------|
| G1 | change the verifier's heartbeat-name literal | RED — name equals the `.tf` `name` |
| G2 | turn the workflow's `bash scripts/inngest-probe-heartbeat-feeder.sh` into an `echo` of that text (pattern present, not on a `run:` command) | RED — the harness asserts the pattern sits on a parsed `run:` line |
| G3 | relaxed regex admits a non-workflow, non-infra path (`scripts/x.yml`) or a free-form pattern | RED — the new regex arm is shape-bound on both file and pattern |

**Harness rows.** Suite mutation: `checkFeeders` is exercised with a synthetic manifest row whose evidence is a workflow and whose pattern is absent (must report the "survives only in a comment / absent" violation) — a regex relaxed to match everything would not. Must-PASS non-canonical: a synthetic row using a *different* workflow filename and script name of the allowed shapes passes, proving the arm is a shape and not the single literal.

**Anchor.** The heartbeat's `.tf` name and the monitor slug live outside the files this change authors (`uptime-alerts.tf`, `cron-monitors.tf` are pinned by their own suites); renaming the heartbeat in a diff that also edits the verifier still reds `inngest-server-probe-heartbeat.test.sh` and the live reconcile's `absent-live` class.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Extend `inngest-luks-property-8296.sh` to push | Rejected | The issue's instruction; it never exits 0/1 by design and dies with its tracker |
| Daily follow-through sweeper + widen `period` (e.g. 86400/7200) | Rejected | Sweeper schedule delivers one run per 2–7 h; exit 0 closes a tracker; widening turns "one skipped emission" into a day of blindness and writes to Better Stack at merge |
| Host-side push inside `inngest-server-probe.sh` | Rejected | Cannot see Vector-allowlist or sink failures; needs an OCI re-bake and `inngest-host-replace` (#6780) |
| Inngest cron function | Rejected | Circular (the watched host is the scheduler's host) and would put warehouse-read credentials into the web app runtime |
| `schedule:`-only workflow, or 60-minute dispatch slots | Rejected | `schedule:` delivers one run per 2–7 h (ADR-248); 60-minute slots give a ~115 min worst gap against 90 |
| URL as a repo secret set at arm time (no uptime API in the feeder) | Rejected | Arming becomes two writes in two systems with an ordering hazard (beating a paused heartbeat, the undocumented response), the pre-arm run can no longer prove the URL resolves, and the URL lives in a second store that drifts if the heartbeat is recreated; the cost accepted instead is the sweeper-shared repo token, used GET-only |
| URL via `DOPPLER_TOKEN_PRD`, or a new Terraform `github_actions_secret` | Rejected | Broad production-config credential for one URL; or a new resource plus a `-target` line in a workflow 482 KB against ADR-231's 490 KB cap and a merge-time apply |
| Add `inngest_server_probe` to `arm-heartbeats.sh`'s chain | Rejected | It would auto-arm on the first push-apply after merge, bypassing the per-command authorization; its helpers are the model for the compound arming command |
| Beat while paused (to "measure" pre-arm) | Rejected | The response is undocumented and `updated_at` does not move; no measurement results |

## Files to Edit

- `plugins/soleur/lib/heartbeat-manifest.ts` — row flip (Phase 4)
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` — evidence-shape arm
- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — section (h)
- `apps/web-platform/server/watchdog-dispatch-table.ts` — third row
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` — expected slug set
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — `NON_INNGEST_MONITORS`
- `apps/web-platform/infra/sentry/cron-monitors.tf` — new monitor
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — unrouted entry
- `scripts/lib/inngest-probe-row.test.sh` — `MUST_FIND`
- `scripts/test-all.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/test-affected-kb-consumers.baseline.txt` — registration
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — watcher entry and the durable arming procedure
- `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md` — amendment
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ regenerated `model.likec4.json`) — the forced clauses and counts

## Files to Create

- `scripts/inngest-probe-heartbeat-feeder.sh`
- `scripts/inngest-probe-heartbeat-feeder.test.sh`
- `.github/workflows/scheduled-inngest-probe-heartbeat.yml`

Not edited, deliberately: `apps/web-platform/infra/uptime-alerts.tf`, `apps/web-platform/infra/betterstack-logs-alerts.tf`, `.github/workflows/apply-web-platform-infra.yml`, `apps/web-platform/infra/arm-heartbeats.sh`, `scripts/followthroughs/inngest-luks-property-8296.sh` (until Stage 3).

## Open Code-Review Overlap

- #8659 (`scripts/test-all.sh`, EXIT-trap sandbox leak in suites that source `test-helpers.sh`): **Acknowledge** — different concern; the new harness sources no helper and installs its own cleanup trap.
- #7942 (`scripts/test-all.sh`, `*.mutation.sh` batteries run in no gate): **Acknowledge** — the new suite is a plain `*.test.sh` registered with `run_suite`; no `.mutation.sh` file is added.
- #8595 (`sentry-monitor-iac-parity.test.ts`, `NON_INNGEST_MONITORS` staleness + cadence parity): **Acknowledge** — this plan adds one entry to each list and the new row is covered by the existing per-row cadence assertions; the reverse-direction staleness guard stays its own cycle.

## Acceptance Criteria

### Pre-merge (PR, Stage 1)

- [ ] `bash scripts/inngest-probe-heartbeat-feeder.test.sh` passes with the literal expected case count; mutation runs RED against a mutated copy of the script are recorded in the PR body for the spurious-beat gates only (M1, M4, M6, M7); the remaining rows are proven by their fixtures.
- [ ] `bash scripts/lib/inngest-probe-row.test.sh` passes (the census classifies the new verifier; `MUST_FIND` includes it).
- [ ] `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` passes (row is `kind: "cron"`, `arming_pending` kept).
- [ ] `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts plugins/soleur/test/heartbeat-live-reconcile.test.ts` passes; G1–G3 demonstrated RED.
- [ ] `cd apps/web-platform && npx vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts test/server/inngest/function-registry-count.test.ts test/server/inngest/sentry-cron-monitor-routing-parity.test.ts test/server/watchdog-dispatch-clock.test.ts test/server/inngest/execution-placement.test.ts` passes.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash plugins/soleur/test/c4-model-freshness.test.sh` pass after `bash scripts/regenerate-c4-model.sh`.
- [ ] `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py --changed` pass; `terraform fmt -check` and `terraform validate` pass in `apps/web-platform/infra/sentry` (CI is the authority for the full battery).
- [ ] The diff contains no edit to `uptime-alerts.tf`, `betterstack-logs-alerts.tf` or `apply-web-platform-infra.yml`: `git diff origin/main --name-only -- apps/web-platform/infra .github/workflows/apply-web-platform-infra.yml | grep -v '^apps/web-platform/infra/sentry/'` prints only `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh`. (The pathspec is exact because `*` in a git pathspec crosses `/` and would also match the sentry root.)
- [ ] The PR's CI infra plan shows no change to `betteruptime_heartbeat.inngest_server_probe` or `doppler_secret.inngest_server_probe_heartbeat_url` (read it from the plan-only run; stop and surface any diff).
- [ ] The PR body's FIRST line answers "does merging this alone mutate production?": "Merging creates one Sentry cron monitor via apply-sentry-infra.yml, fires apply-web-platform-infra.yml with no Better Stack change in its plan, and starts clock-dispatched runs of the new workflow that beat nothing while the heartbeat is paused. It writes nothing to Better Stack."
- [ ] `bash scripts/inngest-probe-heartbeat-feeder.sh --selftest` prints `inngest-probe-feeder selftest: ok` and finishes inside the 15 s Check 10 cap with no credentials set.
- [ ] The beat call site appears exactly once in the script, after the verdict logic; the stub fails any non-GET API call; neither the URL nor the bearer is ever printed or placed on argv (harness-asserted).
- [ ] PR body: `Ref #9703` only (no closing keyword), `## Changelog`, a "Production writes" paragraph, the arming procedure linked, and ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; commits carry the `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` trailer.

### Post-merge (read-only, run by the agent; no go-ahead needed)

- [ ] `apply-sentry-infra.yml` run for the merge SHA is green and the monitor exists (`gh run list --workflow=apply-sentry-infra.yml --limit 3`).
- [ ] `apply-web-platform-infra.yml` run for the merge SHA is green and its plan shows no Better Stack change.
- [ ] Once the web release carrying the table row has deployed, the workflow shows runs with `event=workflow_dispatch` at about 15-minute spacing, each log containing `verdict=fresh_heartbeat_paused` (no manual dispatches: they consume a slot's tolerance).
- [ ] The heartbeat is still `paused=true` (P3 read-back) — Stage 1 must not have changed it.

### Stage 2 and Stage 3 (separate, tracked on #9703)

- [ ] Arming per `## Arming Procedure`, authorized as one unit; read-back shows `up / paused=false`.
- [ ] Stage 3 PR per Phase 7; #9703 closed explicitly with the read-back evidence.

## Test Scenarios

Harness fixtures (stubbed `scripts/betterstack-query.sh` and `curl` in a fake tree; the verifier resolves its repo from its own location, as 8296's harness does):

1. Fresh dedicated row (age 60 s), heartbeat unpaused → `verdict=beat http=200`, exit 0, exactly one beat call, none of URL/bearer in output or argv.
2. Age 4500 s → beat; age 4501 s → `producer_silent`, exit 3, zero beat calls.
3. No rows; only other-host rows; only `host_role=web` rows; only doppler-emitter rows quoting the marker → withheld, correct reason tokens.
4. Newest-by-`dt` with a future-dated (more than 300 s) newest row → `row_unusable field=dt_future`; unparseable `dt` → `field=dt`.
5. Warehouse failures: secret unset, helper missing, helper non-zero, malformed body, selector lib missing/selftest fail → `query_failed reason=<each>`, exit 3.
6. Heartbeat paused → `fresh_heartbeat_paused`, exit 0, zero beat calls.
7. Heartbeat absent, duplicated, URL on another host or carrying a quote/newline, API unreadable → `beat_failed`, exit 4, zero beat calls.
8. Beat returns 500, 302, or curl fails → `beat_failed reason=http_status`, exit 4.
9. xtrace with a credential set → exit 78; malformed `INNGEST_FEEDER_NOW` → exit 3; any argument other than `--selftest` → exit 64; `--selftest` with no credentials → `inngest-probe-feeder selftest: ok`, exit 0, zero network calls, and with `INNGEST_PROBE_ROW_LIB=/dev/null` → exit 3 (a lib that defines nothing fails the selftest); an injected unexpected status → exit 3 `trap_remapped`.
10. Static: the workflow's `run:` line carries the manifest evidence pattern; the heartbeat-name literal equals the `.tf` name; the budget inequality (Guard 1 Anchor).
11. Boundary pair and the "second member after a compliant first" cases from the Guard 1 matrix.

## Risks and Sharp Edges

- **Beat-to-paused semantics are unknown.** The verifier never beats while paused, so the first beat Better Stack ever sees from this feeder is the one the arming command forces; its `status=up` is the measurement.
- **Ordering at merge.** The Sentry monitor is created by the push-apply; the clock dispatches only after the web release deploys the table row. A missed check-in in the gap opens one unrouted Sentry issue (no email). Expected, not a defect.
- **Unrouted monitor.** Until Stage 3 routes it, a withheld verdict reaches Sentry only as an issue, not an email. Pre-arm that is acceptable (the heartbeat is paused); post-arm the heartbeat's own page covers a dark pipeline. Routing is in Phase 7 and is on the #9703 checklist, not a silent deferral.
- **A paused heartbeat after arming is silent in the feeder** (exit 0, `fresh_heartbeat_paused`). The net is the nightly `heartbeat-live-reconcile` `fed-but-paused` class, re-armed when Stage 3 drops `arming_pending`.
- **Credential sharing.** `BETTERSTACK_API_TOKEN` is read/write for the uptime API; the workflow uses GET only (stub-enforced), holds `contents: read`, and runs only from `main`. Confirm at arming time that the repo secret and the Doppler `prd_terraform` token are the same value (P3), or a feeder GET can fail while the arming GET succeeds.
- **Inngest-host failure domains.** A fully dark Inngest host also stops the probe, so this heartbeat pages (correct) while `inngest_prd` and `inngest_consumer` heartbeats page too; the verdict marker distinguishes "probe dark" from "feeder dark".
- **C4 counts are gated, not guessed.** Run `c4-count-parity.test.sh` and copy its numbers; a hand-derived count is the #7826 class.
- **A plan whose `## User-Brand Impact` section is empty, holds only filler text, or omits the threshold fails `deepen-plan` Phase 4.6;** this plan declares `none` with a scope-out bullet because the diff touches `apps/web-platform/server/` and `apps/web-platform/infra/`.
- **Do not pin or edit** the Inngest volume attachment, never touch web-1's LUKS volume 106443278, never reboot or replace a host from this work; none is in scope and none is needed.
- **Read back any file a probing loop edited** before committing; do not rebase after an attestation names commit ids.
- **Arming prose must not claim "armed".** Docs, the ADR amendment and the manifest comment say "fed; arming pending on #9703" until the Stage 2 read-back exists.
