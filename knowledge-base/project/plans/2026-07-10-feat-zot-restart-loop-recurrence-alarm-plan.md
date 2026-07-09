---
title: "Durable zot restart-loop recurrence alarm on SOLEUR_ZOT_DISK (Better Stack Logs)"
issue: 6291
branch: feat-one-shot-6291-zot-restart-loop-alarm
date: 2026-07-10
type: observability
lane: cross-domain   # no spec.md present → fail-closed default per plan skill (TR2)
brand_survival_threshold: aggregate pattern
status: draft
---

# 📈 Durable zot restart-loop recurrence alarm (SOLEUR_ZOT_DISK) — Closes #6291

## Overview

The self-hosted zot registry (ADR-096, one dedicated deny-all / no-SSH Hetzner host) can crash-loop
in a way the current alerting is structurally blind to. The disk-absence heartbeat
`soleur-registry-disk-prd` pings **only while `/var/lib/zot < 85%`**, so a *disk-independent* crash
loop (the #6288 failure mode: zot OOM-restart-looping ~4/min during the boot scan of the ~35 GB
store) leaves the heartbeat **GREEN** throughout. The enriched `SOLEUR_ZOT_DISK` self-report
(#6288/#6296) already emits the discriminating fields to Better Stack Logs, but nothing *stands
watch* on them once #6288's one-shot soak follow-through (`zot-restart-plateau-6288.sh`) auto-closes.

This plan provisions the **durable, continuous recurrence alarm** #6291 asks for: it watches the
`SOLEUR_ZOT_DISK` stream and fires when, **scoped to the newest `boot_id`**, ANY of:

1. `exit_code=137` is seen (an OOM exit), OR
2. `zot_restarts` **climbs across ≥ N consecutive events** (the crash-loop signature; default N=3), OR
3. `oom_kills_5m > 0` (journald kernel-OOM backstop).

On fire it opens/updates a deduped, operator-visible `action-required` GitHub issue carrying the
**decoded cause** (host/kernel OOM vs cgroup-cap-contained vs non-OOM → `zot_last_err`); on recovery
it auto-closes. Its own liveness is covered by a Sentry cron monitor so a *dark* alarm also alerts.

**Re-eval trigger is met:** an operator-dispatched inngest cutover verify against current `main` HEAD
just failed on a `registry-probe HTTP 500` — live evidence of registry serving instability — so a
standing recurrence alarm earns its keep now (issue re-eval clause (a)).

## Research Reconciliation — Issue/Spec vs. Codebase

| Claim (issue #6291 / prompt) | Reality (verified in codebase) | Plan response |
|---|---|---|
| Data source is the "isolated `soleur-registry/prd` **source**" | `soleur-registry/prd` is the **Doppler** project/config that holds the *ingest token*. The `SOLEUR_ZOT_DISK` events land in the **SHARED Better Stack Logs source `2457081`** (`soleur_inngest_vector_prd_3`, team `520508`, region `eu-fsn-3`) — reused via the same token + region-bound ingest URL. Confirmed: `inngest.tf:65-73`, `zot-registry.tf:271`, `ADR-096:240`, `model.c4:394`. | The alarm queries source **2457081**, filtered by the `SOLEUR_ZOT_DISK` grep marker — the **same table** `scripts/betterstack-query.sh` already reads (default `BS_TABLE=t520508_soleur_inngest_vector_prd_3_logs`). No new source. |
| "NOT Terraform-expressible … no logs-content alert resource; **dashboard or a thin API wrapper**." | Two facts: (a) the `BetterStackHQ/better-uptime` TF provider indeed has no log-alert resource (confirmed `main.tf:42-44` — only `betteruptime_monitor`/`_heartbeat`/`_policy`). (b) **Better Stack DOES expose a programmatic Telemetry v2 log/SQL-alert create-API** (`POST /api/v2/dashboards/{id}/charts/{cid}/alerts` + `.../explorations/{id}/alerts`, `check_period` = recurring schedule; docs `betterstack.com/docs/logs/api/...`). So "dashboard-only" is FALSE — but the v2 alert is a stateless `{{time}}`-bucketed threshold and is **not** a first-class TF resource. | Mechanism is a **reasoned choice**, not forced (see [Mechanism Decision](#mechanism-decision)). We pick the in-repo GH-Actions cron poller over the native BS v2 alert — and document the v2 API as the considered-and-rejected alternative (honours "exhaust API options first"). |
| `BETTERSTACK_QUERY_*` may need provisioning | Already provisioned as GH Actions repo secrets on 2026-07-03 (`gh secret list`: `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`), consumed today by `scheduled-followthrough-sweeper.yml`. | **No secret provisioning needed** — the alarm workflow reuses them and is **live on merge**. (They are manually-set, not yet TF-managed — pre-existing hygiene gap, see Non-Goals.) |
| Fields "current as of #6296" | `#6296` MERGED 2026-07-09 (dropped `mem_used_mb`, kept `mem_total_mb`). Emit line `cloud-init-registry.yml:221` carries `zot_restarts, ping_rc, mem_total_mb, zot_anon_mb, zot_oom_kills, state_status, oom_killed, exit_code, oom_kills_5m, boot_id, host, zot_last_err`. | Alarm parses these exact keys; `zot_last_err` stays the LAST field (free-text) and is stripped before trusted key=value parsing (mirrors the soak probe). |
| `#6278` fallback-rate is a contrast reference | `#6278` CLOSED — Sentry `zot_mirror_fallback_rate` issue-alert, different data source. | Not a work target; cited only to disambiguate data source (Better Stack Logs, NOT Sentry). |

## User-Brand Impact

**If this lands broken, the user experiences:** a false-negative alarm — the zot registry
crash-loops undetected (heartbeat stays GREEN), CI dual-push + host deploys silently fail to pull
images, and the non-technical operator gets **no** `action-required` issue; OR a false-positive alarm
that opens a noisy issue on a healthy registry, eroding trust in the alert surface. Either way the
concrete artifact is the `[ci/zot-restart-loop]` GitHub issue being wrong (absent when it should
fire, or present when it shouldn't).

**If this leaks, the user's data/workflow is exposed via:** N/A — the alarm reads only
host/container operational telemetry (`df%`, restart counts, OOM counters, a redacted ≤300-byte
`zot_last_err` log tail already stripped at emit). No PII, no secrets, no customer data. The alarm
is a read-only consumer of an existing already-shipped, already-redacted stream.

**Brand-survival threshold:** `aggregate pattern` — this is a safety-net observability alarm over a
systemic infra failure mode; its absence is an aggregate observability gap (missed alerts), not a
per-user data incident. No CPO sign-off required; no sensitive-path write.

## Research Insights

**Canonical files (read):**
- Reporter emit: `apps/web-platform/infra/cloud-init-registry.yml:150-292` (the `SOLEUR_ZOT_DISK`
  producer + `zot-disk-heartbeat.sh` cron). Emit line `:221`.
- Query surface: `scripts/betterstack-query.sh` — ClickHouse HTTP SQL API wrapper. `--grep`,
  `--since Nh`, `--limit`; JSONEachRow `{dt, raw}`; creds via `doppler run -p soleur -c prd_terraform`.
- Runbook: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (three-token
  trap; source 2457081; region `eu-fsn-3`; 3-day retention; a "no-creds/TRANSIENT" error is NOT
  "no access").
- **Existing recurrence detector (the soak sibling to mirror):**
  `scripts/followthroughs/zot-restart-plateau-6288.sh` — newest-`boot_id` scoping, trusted-region
  parse (`sed 's/ zot_last_err=.*//'`), sentinel (`-1` inspect-miss) filtering, exit 0/1/2 contract.
- **Standing-alarm precedent (the workflow shape to mirror):**
  `.github/workflows/scheduled-inngest-health.yml` and `scheduled-realtime-probe.yml` — external
  GH-Actions cron, probe → classify → open/update a deduped `[ci/<class>]` issue → auto-close on
  healthy → Sentry heartbeat final step. `gate-override: new-scheduled-cron-prefer-inngest` header.
- Sweeper (creds precedent): `.github/workflows/scheduled-followthrough-sweeper.yml:60-72` already
  wires `BETTERSTACK_QUERY_*`.
- Sentry self-liveness precedent: `apps/web-platform/infra/sentry/cron-monitors.tf` +
  `.github/actions/sentry-heartbeat` + `.github/workflows/apply-sentry-infra.yml` (auto-apply on push).
- ADR context: `ADR-096` (§Consequences documents the SOLEUR_ZOT_DISK telemetry + the disk
  heartbeat's structural gap — the natural amend site).

**Decode table (from the #6288 reporter, for the issue body):**
- `exit_code=137` AND `oom_kills_5m>0` → **host/kernel OOM** (the box ran out of memory).
- `oom_killed=true` → the cgroup `--memory=7168m` cap **contained** it (container-scoped OOM).
- `exit_code≠137` (non-OOM) → read `zot_last_err` (the ≤300-byte redacted log tail).

**Firing-condition fidelity note:** the native BS v2 alert can faithfully express conditions (1)
`exit_code=137 seen` and (3) `oom_kills_5m>0` as `{{time}}`-bucketed `countIf(...) > 0` thresholds,
but **cannot** faithfully express (2) the *stateful* `zot_restarts climbs across N consecutive
events` scoped to the *newest* `boot_id` (a `max-min>tol` approximation false-fires on a single
legitimate restart, and `{{time}}`-bucketing loses the newest-`boot_id` discriminator that the
immutable hostname-reusing replace requires). This asymmetry is the deciding factor below.

## Mechanism Decision

**Chosen: a standing GitHub-Actions scheduled-cron poller** (`scheduled-zot-restart-loop.yml`) that
queries Better Stack Logs via `betterstack-query.sh`, evaluates the three firing conditions in a
`scripts/` checker, and routes a fire to a deduped `action-required` GitHub issue (+ Sentry
self-liveness heartbeat).

This IS a "Better Stack Logs recurrence alarm" — its **data source is Better Stack Logs** (source
2457081), queried through the Logs **ClickHouse SQL API** (`betterstack-query.sh`). We evaluate the
threshold + notify in our own in-repo poller rather than in a BS-hosted alert. It is fully
automatable and version-controlled (a workflow + script in git), reusing already-provisioned GH
secrets — no dashboard, no Playwright, no vendor-side resource outside git.

**Substrate = GitHub-hosted runners, not Inngest** (deepen-plan Phase 4.4 scheduled-work check):
the primary reason is **ADR-033's own scope carve-out**, not substrate-independence. The alarm is a
bash pipeline (`betterstack-query.sh` + shell decode + `gh issue`); ADR-033 **I7** states the Inngest
cron-containment hook governs the claude-code tool layer only and does **NOT** cover Node-level
`child_process.spawn("bash", …)` — a "spawn-bash cron" is I7's deferred/uncontained class. Folding
this into Inngest would either require a TS rewrite of the shell decode (forking the decode
source-of-truth) or fall into I7's uncontained class; ADR-033's 2026-06-02 scope note explicitly
blesses the GHA path for "a credential-heavy infra cron whose execution must stay in an ephemeral
runner." Substrate-independence (GH runners vs the Hetzner fleet) is a *secondary, low-weight*
corroborator — at steady state a registry crash-loop does NOT stop the Inngest host's crons (the
fleet pulls the registry only at deploy time), so it is weak failure-correlation, not a hard
circular dependency like `scheduled-inngest-health.yml`'s. The gate-override header cites ADR-033 I7
+ the scope note as primary.

**Why not the Better Stack Telemetry v2 SQL-alert API** (the issue's nominal "preferred" option — we
investigated it fully; endpoints confirmed to exist, so this is a rejection *on merits*, not on
absence):
1. **Detection fidelity.** The stateful climb condition (2) + newest-`boot_id` scoping are not
   cleanly expressible as a single `{{time}}`-bucketed threshold; the already-reviewed shell decode
   (newest-boot scoping, sentinel filtering, consecutive-climb) expresses all three at full fidelity
   and keeps **one** source of truth for the decode/parse — enforced by extracting the trusted-region
   parse into a shared sourced helper (`scripts/lib/zot-telemetry-parse.sh`) that BOTH this alarm and
   the #6288 soak probe source (no copy-paste of the spoof-resistance invariant).
2. **Operator-actionable surface.** The operator is non-technical; `operator-digest` harvests
   `action-required` **issues**, not Better Stack alert emails. A native BS alert notifies ops@ email
   / an on-call policy (free tier = email) — a weaker, un-triaged surface. A deduped GitHub issue
   with a decoded cause is the established, digest-visible alarm surface.
3. **IaC / drift.** The v2 alert is **not** a first-class TF resource (provider gap confirmed); it
   would be a REST-provisioned resource whose state lives in Better Stack, needing a bootstrap script
   + drift handling, with the decode SQL divorced from the reporter's decode semantics. The poller is
   plain in-git YAML+shell, testable in CI.

**Why not dashboard config:** manual, not version-controlled, not testable — dominated by both
options above; explicitly rejected per `hr-exhaust-all-automated-options-before`.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)
- Confirm `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` exist as GH Actions secrets (`gh secret list`).
- Confirm live telemetry is flowing: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep SOLEUR_ZOT_DISK --limit 20` returns rows carrying `boot_id=`, `zot_restarts=`, `exit_code=`, `oom_kills_5m=` (falls back to TRANSIENT-safe if the doppler wrap is missing — that is invocation, not a capability gap: `betterstack-log-query.md`).
- Confirm `.github/actions/sentry-heartbeat` exists and the sentry subroot `apply-sentry-infra.yml` auto-applies on push.

### Phase 1 — Shared parse helper + checker script + tests (RED → GREEN, `cq-write-failing-tests-before`)
- **Extract the trusted-parse invariant into one sourced helper** `scripts/lib/zot-telemetry-parse.sh`
  (resolves the review-flagged self-contradiction: duplicating a *security* invariant across two
  scripts is a spoof-resistance maintenance hazard — the "≤3 files, don't build shared infra"
  sharp-edge is about not over-abstracting, NOT about copy-pasting a security guard). The helper
  exposes the shared block used by BOTH the alarm and the soak probe: lexical `sort` → trusted-region
  strip `sed 's/ zot_last_err=.*//'` → newest real `boot_id` scoping (`grep -oE 'boot_id=[0-9a-fA-F-]+' | grep -v unknown | tail -1`)
  → non-`-1` sentinel filtering. Refactor `scripts/followthroughs/zot-restart-plateau-6288.sh` to
  source it (its existing test suite is the safety net); this makes the Mechanism Decision's "one
  source of truth for the decode/parse" claim literally TRUE.
- Create `scripts/zot-restart-loop-alarm.sh` (the continuous checker), sourcing the helper. Distinct
  from the soak probe: **no soak gate** (no `MIN_EVENTS`/`MIN_SPAN`), **continuous**, **never closes
  #6288**. Named constants (NOT env overrides — only the `ZOT_BQ_OVERRIDE` test seam is exposed):
  `WINDOW=3h`, `CLIMB_N=3` (referenced by tests + the cadence sharp-edge). **Exit-code contract:**
  - **GREEN (0):** newest-boot has flat/absent climb, no `137`, `oom_kills_5m==0` → auto-close any open `[ci/zot-restart-loop]` / `[ci/zot-telemetry-silent]`.
  - **FIRE (1):** on the newest boot_id, ANY of — (A) a row has `exit_code=137`; (B) `zot_restarts` (non-`-1` samples) **strictly increases across ≥ `CLIMB_N` consecutive events**; (C) a row has `oom_kills_5m>0`. Emit a machine-readable verdict block + the **decoded cause** (decode table).
  - **TRANSIENT probe-fault (2):** the `betterstack-query.sh` call fails (auth/network) OR a bare control-marker query (`--since 3h --limit 1`, no `SOLEUR_ZOT_DISK` grep) ALSO returns empty/errors → Better Stack itself is unreachable. **No GitHub issue**; the workflow emits an *errored* Sentry check-in so persistent probe-death surfaces as a monitor problem (adopts the simplicity-review cut of the soft issue).
  - **PRODUCER-SILENT (3) — the P1 fix:** the control-marker query returns rows (BS reachable + creds valid) AND `SOLEUR_ZOT_DISK` rows exist in a **24h** lookback (the reporter was recently alive → not a fresh never-installed host) BUT are **absent in the recent 3h** window → the token-gated reporter went dark while the token-free disk heartbeat + Sentry monitor stay GREEN. Escalate to an **`action-required`** `[ci/zot-telemetry-silent]` issue (a real paging surface — this is the "GREEN-while-broken" recurrence the alarm exists to kill, resurfacing one layer up).
  - Fail-safe: never FIRE on zero valid evidence (newest-boot all-`-1` sentinels with no `137`/`oom_kills_5m` → TRANSIENT, not FIRE). **Documented coverage seam** (checker header): a *non-OOM* crash severe enough that `docker inspect` returns only `-1` sentinels — with no `137` and `oom_kills_5m==0` — degrades to TRANSIENT, not FIRE; the #6288 OOM mode is still caught by (A)+(C), and TRANSIENT is loud in Actions logs. This trade buys zero false-positives at the cost of a narrow non-OOM false-negative.
- Create `scripts/zot-restart-loop-alarm.test.sh` with **synthesized** fixtures (`cq-test-fixtures-synthesized-only`) via the `ZOT_BQ_OVERRIDE` stub (mirror the soak test's override seam): climbing→FIRE(B); flat→GREEN; `exit_code=137`→FIRE(A); `oom_kills_5m=2`→FIRE(C); all-`-1`→TRANSIENT; empty+control-empty→TRANSIENT(2); **control-present + 24h-had-rows + 3h-empty → PRODUCER-SILENT(3)**; **fresh host (no rows in 24h) + 3h-empty → TRANSIENT** (not producer-silent); **stale old-boot 137 only, newest-boot clean → GREEN** (newest-boot scoping); **single isolated restart (not `CLIMB_N`-consecutive) → GREEN** (climb, not delta); crafted `zot_last_err=... exit_code=137 ...` on a clean newest-boot → GREEN (spoof-resistance).

### Phase 2 — The standing alarm workflow
- Create `.github/workflows/scheduled-zot-restart-loop.yml`:
  - Header `# <!-- gate-override: new-scheduled-cron-prefer-inngest -->` (the token
    `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` and `scheduled-inngest-health.yml` /
    `apply-inngest-rls.yml` use) + justification, **anchored on ADR-033's own carve-out** (per
    architecture review — substrate-independence is real but low-weight here since the registry is a
    *separate* host from Inngest, so it is NOT the load-bearing reason): (i) **ADR-033 2026-06-02
    scope note + Invariant I7** — the Inngest cron-containment hook governs only the claude-code tool
    layer, NOT Node-level `child_process.spawn("bash", …)`; those "spawn-bash crons" are an explicitly
    *uncontained/deferred* class. This alarm IS fundamentally a bash pipeline (`betterstack-query.sh`
    + shell decode), so folding it into Inngest would either force a TS rewrite of the decode (losing
    the single decode source-of-truth) OR a `spawn("bash")` that lands in I7's uncontained class —
    ADR-033 says GHA is *correct* for a credential-heavy infra cron that must stay in an ephemeral
    runner ("Do not mis-cite this rejection as a blanket ban"). (ii) The signal is read via
    `betterstack-query.sh` (shell + `doppler run`) and fired via `gh issue` — both GH-Actions-native.
    (iii) Secondary/weak: substrate-independence from the Hetzner fleet (failure-correlation only —
    not a true circular dependency like `scheduled-inngest-health.yml`'s). **Structural** precedent
    (probe→classify→dedup-issue→Sentry-heartbeat) = `scheduled-inngest-health.yml` /
    `scheduled-realtime-probe.yml` / `scheduled-followthrough-sweeper.yml`; the `gate-override`
    marker itself exists in 2 files (`scheduled-inngest-health.yml`, `apply-inngest-rls.yml`).
  - `on.schedule: '*/30 * * * *'` (30-min cadence). Detection latency is NOT poll-bound — the checker
    reads a **3h WINDOW** against a **5-min emit** (~36 events/boot ≫ `CLIMB_N=3`), so a loop is caught
    regardless of which tick sees it; 30-min is chosen (over 20) to keep the Sentry self-liveness
    monitor's missed-check-in margin tolerant of GHA `schedule:` jitter (see Phase 3) + `workflow_dispatch`.
  - `concurrency: group: scheduled-zot-restart-loop, cancel-in-progress: false`.
  - `permissions: contents: read, issues: write`.
  - Env: `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` from `secrets.*` (reused; TRANSIENT-safe if unset).
  - Steps: (1) run `scripts/zot-restart-loop-alarm.sh`; **capture verdict + exit into `$GITHUB_OUTPUT`,
    do NOT let the step `exit 1`** (mirror `scheduled-inngest-health.yml` — a non-zero checker exit is
    data, not a job failure; otherwise a FIRE/TRANSIENT self-darks the liveness check-in). Sanitize all
    telemetry (`strip_log_injection`, ported verbatim) before any `::error::`/`$GITHUB_OUTPUT`.
    (2) **FIRE (1):** open-or-comment a deduped `[ci/zot-restart-loop]` issue
    (`gh issue list --search 'in:title "[ci/zot-restart-loop]"'`), label `action-required` +
    `observability` + `domain/engineering`, body = decoded cause + run URL + the exact
    `betterstack-query.sh` reproduce command. (3) **PRODUCER-SILENT (3):** open-or-comment a deduped
    **`action-required`** `[ci/zot-telemetry-silent]` issue (own-title) — the reporter went dark while
    heartbeats stay GREEN. (4) **GREEN (0):** auto-close the stale `[ci/zot-restart-loop]` AND
    `[ci/zot-telemetry-silent]` issues, each with its **own-title** search (never a union search — #5562
    trap). (5) **TRANSIENT (2):** **no GitHub issue** — log loud in Actions; the final heartbeat step
    emits an *errored/absent* Sentry check-in so persistent probe-death surfaces as a monitor problem
    (replaces the cut `[ci/zot-alarm-probe]` soft issue). (6) Final `./.github/actions/sentry-heartbeat`
    step with **`if: always()`** (`MONITOR_SLUG=scheduled-zot-restart-loop`, status = ok on GREEN/FIRE/
    PRODUCER-SILENT, errored on TRANSIENT) so a *missing* run AND a persistent probe fault both alert.

### Phase 3 — Self-liveness monitor (Sentry) + docs/ADR/C4
- Add `sentry_cron_monitor.zot_restart_loop_alarm` to `apps/web-platform/infra/sentry/cron-monitors.tf`
  (slug `scheduled-zot-restart-loop`, schedule `*/30 * * * *`, UTC). **Pin `checkin_margin_minutes`
  explicitly** (do NOT leave "cohort default") to a value proven tolerant of GHA `schedule:` jitter —
  `cron-monitors.tf` documents the 2026-06-15 `scheduled-agent-native-audit` false-page incident from
  a tight margin on a jittery GHA cron; start at `checkin_margin_minutes = 30`, `max_runtime_minutes = 10`
  (single-step check-in), and note at /work to widen if GHA jitter false-pages. Applied via
  `apply-sentry-infra.yml` on push. Add the `-target=` entry if that root's auto-apply is target-scoped
  (verify against `apply-sentry-infra.yml` + any scope-guard test).
- Amend `ADR-096` §Consequences with the restart-loop recurrence-alarm mechanism decision (see
  [Architecture Decision](#architecture-decision-adrc4)).
- C4: enrich the `betterstack` system description + add the `github -> betterstack` Logs-read edge
  (see [Architecture Decision](#architecture-decision-adrc4)).
- Update the `betterstack-log-query.md` runbook with a short "standing alarms over this source" note
  pointing at the new workflow.

## Files to Create
- `scripts/lib/zot-telemetry-parse.sh` — shared trusted-region parse/scoping helper (sourced by both consumers).
- `scripts/zot-restart-loop-alarm.sh` — continuous checker (exit 0/1/2/3).
- `scripts/zot-restart-loop-alarm.test.sh` — synthesized-fixture unit tests.
- `.github/workflows/scheduled-zot-restart-loop.yml` — standing 30-min alarm cron.

## Files to Edit
- `scripts/followthroughs/zot-restart-plateau-6288.sh` — refactor to `source` the new shared parse helper (its existing test suite is the safety net; makes the "single source of truth" claim true).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add the self-liveness monitor (pinned margin).
- `apps/web-platform/infra/sentry/*` scope-guard / `-target=` list — IFF the sentry auto-apply is
  target-scoped (verify at /work: `git grep -ln 'sentry_cron_monitor\|-target=' apps/web-platform/infra/sentry/ .github/workflows/apply-sentry-infra.yml tests/ scripts/`).
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — §Consequences amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `betterstack` description + `github -> betterstack` read edge.
- `knowledge-base/engineering/architecture/diagrams/views.c4` — `include` line for the new edge IFF it does not already render.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarm note.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `bash scripts/zot-restart-loop-alarm.test.sh` passes; ≥1 fixture per condition (A/B/C) + newest-boot-scoping + isolated-restart-not-climb + all-sentinel-TRANSIENT + empty-TRANSIENT + spoof-resistance.
- [ ] `scripts/zot-restart-loop-alarm.sh` exits **2** (TRANSIENT) — never 1 — when the query stub returns empty/all-`-1` AND the control-marker query is also empty (no false page on a probe fault); exits **3** (PRODUCER-SILENT) only when the control marker + a 24h-lookback prove the reporter was alive but the 3h window is empty (fresh-host fixture → 2, not 3).
- [ ] Dry-run against **live** telemetry: `doppler run -p soleur -c prd_terraform -- bash scripts/zot-restart-loop-alarm.sh` returns a verdict consistent with the current registry state (GREEN if healthy; if the live `registry-probe HTTP 500` instability is still active, a FIRE with a decoded cause). Paste the verdict block into the PR.
- [ ] `actionlint .github/workflows/scheduled-zot-restart-loop.yml` clean; embedded `run:` snippets pass `bash -n` on extraction.
- [ ] The checker step captures verdict+exit into `$GITHUB_OUTPUT` and does NOT `exit 1` the step; the final `sentry-heartbeat` step is `if: always()` (status errored on TRANSIENT) — a FIRE/TRANSIENT never self-darks the liveness check-in.
- [ ] FIRE dedups on `in:title "[ci/zot-restart-loop]"`; PRODUCER-SILENT dedups on `in:title "[ci/zot-telemetry-silent]"`; GREEN auto-closes BOTH with their **own-title** searches (no union close-search — #5562 trap). Labels `action-required`,`observability`,`domain/engineering` all verified to exist (`gh label list`).
- [ ] `terraform validate` clean for the sentry subroot after adding `sentry_cron_monitor.zot_restart_loop_alarm`; `MONITOR_SLUG` in the workflow == the slug Sentry derives from the monitor `name`.
- [ ] ADR-096 §Consequences names the mechanism decision + the BS-v2-API-considered-rejected rationale; C4 `github -> betterstack` edge added and renders (C4 validation tests `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass).
- [ ] PR body uses `Closes #6291`.

### Post-merge (operator/CI — automated)
- [ ] `apply-sentry-infra.yml` auto-applies the new `sentry_cron_monitor` on merge (no operator step). Verify the monitor exists via the Sentry IaC apply run log.
- [ ] First scheduled run of `scheduled-zot-restart-loop.yml` completes GREEN (or opens a correctly-decoded issue if the registry is genuinely looping) and emits a Sentry check-in. Verify via the Actions run + the Sentry monitor's first check-in. `Automation: fully automated — a merge to main fires apply-sentry-infra + the workflow schedule; no manual step.`

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in emitted by the alarm workflow's final (if:always) step — status ok on GREEN/FIRE/PRODUCER-SILENT, errored on TRANSIENT; a MISSING run = the alarm went dark
  cadence: every 30 min (workflow schedule == monitor schedule; checkin_margin pinned for GHA jitter)
  alert_target: Sentry (missing OR errored check-in opens a Sentry issue on the soleur-web-platform project)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (sentry_cron_monitor.zot_restart_loop_alarm) + .github/actions/sentry-heartbeat
error_reporting:
  destination: recurrence → deduped [ci/zot-restart-loop] action-required issue; producer-silence → deduped [ci/zot-telemetry-silent] action-required issue; probe fault → NO issue, errored Sentry check-in (dark-probe surfaces as a monitor problem)
  fail_loud: true   # checker NEVER exits 0 on zero valid evidence; the if:always heartbeat means a FIRE/TRANSIENT/missing-run all reach Sentry
failure_modes:
  - mode: registry crash-loop (climbing zot_restarts on newest boot_id)
    detection: scripts/zot-restart-loop-alarm.sh condition (B) — strictly increasing across ≥N consecutive non-sentinel events, newest-boot-scoped
    alert_route: [ci/zot-restart-loop] issue (cause = decode table)
  - mode: host/kernel OOM (exit_code=137 + oom_kills_5m>0)
    detection: conditions (A)+(C)
    alert_route: [ci/zot-restart-loop] issue, cause="host/kernel OOM"
  - mode: cgroup-cap-contained OOM (oom_killed=true)
    detection: decode step surfaces oom_killed on a fired event
    alert_route: [ci/zot-restart-loop] issue, cause="cgroup --memory cap contained"
  - mode: non-OOM crash (exit_code≠137)
    detection: decode step surfaces zot_last_err on a fired event
    alert_route: [ci/zot-restart-loop] issue, cause=zot_last_err tail
  - mode: producer-silence (SOLEUR_ZOT_DISK stops while disk-heartbeat + Sentry monitor stay GREEN — e.g. BETTERSTACK_LOGS_TOKEN rotation / ingest outage; the token-free disk heartbeat cannot backstop this, verified cloud-init-registry.yml:156 vs :226)
    detection: checker exit 3 — control-marker query returns rows (BS reachable) AND 24h lookback had SOLEUR_ZOT_DISK rows BUT recent 3h window is empty (excludes fresh never-installed host)
    alert_route: [ci/zot-telemetry-silent] action-required issue
  - mode: alarm probe fault (Better Stack unreachable / creds unset — control-marker query also empty/errors)
    detection: checker exit 2 (TRANSIENT); NEVER a recurrence page
    alert_route: errored Sentry check-in (no GitHub issue) + loud Actions log
  - mode: alarm itself stops running (workflow disabled / GHA outage)
    detection: Sentry cron monitor missing check-in
    alert_route: Sentry issue
logs:
  where: GitHub Actions run logs (scheduled-zot-restart-loop) + underlying Better Stack source 2457081 (SOLEUR_ZOT_DISK)
  retention: Actions default (~90d); Better Stack source 3-day hot window
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep SOLEUR_ZOT_DISK --limit 50   # then: bash scripts/zot-restart-loop-alarm.sh"
  expected_output: "JSONEachRow SOLEUR_ZOT_DISK rows with boot_id/zot_restarts/exit_code/oom_kills_5m; checker prints a GREEN/FIRE/TRANSIENT verdict block — NO ssh anywhere"
```

**2.9.2 in-surface probe:** the affected surface (the deny-all, no-SSH registry host) already emits
the discriminating in-surface fields (`exit_code`/`zot_restarts`/`oom_kills_5m`/`boot_id`/
`oom_killed`/`zot_last_err`) FROM the host via the `SOLEUR_ZOT_DISK` self-report (#6288/#6296). This
alarm is the consumer; no new in-surface probe is required — a single event discriminates
host-OOM vs cgroup-OOM vs non-OOM per the decode table.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — one new `sentry_cron_monitor` (self-liveness).
  Provider `jianyuan/sentry` (already declared in the sentry subroot). No new secret, no new vendor,
  no new server. `BETTERSTACK_QUERY_*` already exist as GH Actions secrets (no `TF_VAR` added).
### Apply path
- (b) auto-apply on push: `apply-sentry-infra.yml` applies the sentry subroot on merge to main.
  Verify the target-scope (`-target=sentry_cron_monitor.*` per prior sentry-root convention) covers
  the new resource. Zero downtime; blast-radius = one new monitor.
### Distinctness / drift safeguards
- No `dev`/`prd` split (Sentry monitors are prd observability). The workflow YAML is the alarm's IaC
  (in git). No `terraform.tfstate` secret exposure (the monitor carries no secret).
### Vendor-tier reality check
- Sentry cron monitors are within the existing plan tier (the repo already runs ~20 such monitors,
  `cron-monitors.tf`). No free-tier gate needed. Better Stack: read-only ClickHouse SQL over the
  existing source — no tier change; the native v2 alert path (rejected) is what would have added a
  BS-side resource.

## Architecture Decision (ADR/C4)

### ADR
- **Amend `ADR-096` §Consequences** (not a new ordinal — this extends ADR-096's zot-observability
  story). Record: the disk-heartbeat's structural liveness gap is now closed by a durable Better
  Stack Logs recurrence alarm implemented as an in-repo GH-Actions cron poller; the Better Stack
  Telemetry **v2 SQL-alert API exists and was evaluated** but rejected for this signal (stateful
  climb + newest-boot scoping not faithfully expressible as a `{{time}}` threshold; operator surface
  is a GitHub `action-required` issue, not ops@ email; no first-class TF resource / decode
  source-of-truth divergence). Adds the v2 endpoints to §Alternatives so a future engineer sees it
  was considered. **Discoverability (architecture-review P2):** the mechanism — "log-*content*
  recurrence alarms are in-repo GH-cron pollers, not native BS alerts, for fidelity + operator-surface
  + IaC reasons" — is a **reusable precedent** (the C4 note shows the sweeper already recurs the
  pattern). To keep it grep-findable beyond ADR-096, the amendment adds an explicit
  "Pattern: Better Stack log-content alarms" heading in §Consequences and the runbook cross-links it;
  a standalone ordinal was considered but rejected to avoid ordinal-collision churn (ADR-096 is the
  natural owner of the zot-observability story).

### C4 views
- Read all three (`model.c4`, `views.c4`, `spec.c4`). Enumeration for completeness: external human
  actor = the operator (already modeled); external system = **Better Stack** (`model.c4:262`,
  modeled) + **GitHub** (`model.c4:228`, modeled); container/store = source 2457081 (modeled via the
  `zotRegistry -> betterstack` ship edge `:394`); **access relationship changed** = a **new
  `github -> betterstack` Logs-read edge** (CI polls the SOLEUR_ZOT_DISK source via ClickHouse SQL) —
  currently **absent** from the model (the existing sweeper reads it un-modeled). Add:
  `github -> betterstack "Polls the SOLEUR_ZOT_DISK Logs source (ClickHouse SQL via betterstack-query.sh) for the zot restart-loop recurrence alarm + follow-through soak probes" { technology "HTTPS (ClickHouse SQL, eu-fsn-3)" }`
  and enrich the `betterstack` system description to note its Logs-warehouse-polled-from-CI role.
  Add the `include` line to `views.c4` if the edge does not already render; run the C4 validation
  tests. Not "no C4 impact" — a genuine (previously-unmodeled) load-bearing edge is added.
### Sequencing
- The decision is true on merge (the alarm is live once the workflow + monitor land); the ADR amend
  describes the shipped state, no soak-gated status flip.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** reviewed (semantic sweep — headless/pipeline; CTO lens runs at plan-review).
**Assessment:** Pure infra/observability change on an already-provisioned surface. Key engineering
calls: (a) mechanism = in-repo GH-cron poller over BS-v2-alert (fidelity + operator-surface +
in-git IaC); (b) `new-scheduled-cron-prefer-inngest` gate-override justified (external ops probe, not
an agent-loop cron — ADR-033 inapplicable); (c) fail-safe TRANSIENT contract prevents false pages;
(d) self-liveness via Sentry cron monitor closes the dark-alarm zone. No Finance/Legal/Product/
Marketing/Sales/Support/Ops implications (no UI, no pricing, no data processing, no vendor signup).

### Product/UX Gate
NONE — no UI-surface file in Files to Create/Edit (workflow + shell + TF + docs only). Mechanical
UI-surface override did not fire.

## Open Code-Review Overlap
None — `gh issue list --label code-review --state open` yields no open scope-out naming
`scripts/zot-restart-loop-alarm.sh`, `.github/workflows/scheduled-zot-restart-loop.yml`, or
`cron-monitors.tf` (new files; the TF file is touched additively). Verify at /work with the
two-stage `--json` + standalone-`jq` form.

## Test Scenarios
1. Climbing restarts (88→120→180 across 3 consecutive newest-boot events) → **FIRE(B)**, cause per decode.
2. Flat restarts (5,5,5) → **GREEN**.
3. `exit_code=137` present on newest boot → **FIRE(A)**; with `oom_kills_5m=1` → cause "host/kernel OOM".
4. `oom_kills_5m=2` on newest boot → **FIRE(C)**.
5. `oom_killed=true` on a fired event → cause "cgroup --memory cap contained".
6. Stale OLD-boot `exit_code=137`, newest boot clean → **GREEN** (newest-boot scoping).
7. Single isolated restart bump (not N-consecutive-climb) → **GREEN** (climb, not delta).
8. All-`-1` sentinel `zot_restarts` (docker inspect miss) → **TRANSIENT** (no false PASS/FIRE).
9. Empty window / query failure → **TRANSIENT** (never a recurrence page).
10. Crafted `zot_last_err=...exit_code=137...` on a clean newest boot → **GREEN** (trusted-region parse spoof-resistance).

## Precedent Diff (deepen-plan Phase 4.4 — scheduled-work + pattern-bound behaviors)

- **Scheduled-work substrate (Inngest vs GH-cron).** Inngest cron functions DO exist
  (`git ls-files | grep 'server/inngest/functions/cron-'` → non-zero), so the
  `new-scheduled-cron-prefer-inngest` hook WILL flag the new `scheduled-*.yml`. The `gate-override`
  header + the three-reason justification above (substrate-independence, GH-native tooling, non-agent
  cron) is the sanctioned escape, precedented by `scheduled-inngest-health.yml` (which carries the
  same override for the same substrate-independence reason). **Verdict: GH-cron is correct here** —
  an Inngest cron on the watched fleet is a dark-alarm risk.
- **Checker shell pattern.** Precedent = `scripts/followthroughs/zot-restart-plateau-6288.sh`
  (trusted-region parse, sentinel filtering, newest-boot scoping, exit 0/1/2). The alarm **mirrors
  the parse + scoping verbatim** but diverges deliberately on verdict semantics: soak probe =
  soak-gated one-shot plateau (`max-min<=tol`, closes #6288); alarm = continuous **consecutive-climb**
  (`strictly increasing across ≥N events`, opens a standing issue, never closes #6288). Two
  independent files (no shared lib) per the plan-skill "≤3 files → don't build shared infra" rule.
- **Workflow issue-dedup pattern.** Precedent = `scheduled-inngest-health.yml` (own-title
  `[ci/<class>]` search for open-or-comment; own-title auto-close on healthy; `strip_log_injection`
  ported verbatim; final `sentry-heartbeat` step). Adopted verbatim — **no novel pattern**.
- **Sentry self-liveness.** Precedent = `apps/web-platform/infra/sentry/cron-monitors.tf` (~20
  existing `sentry_cron_monitor`) + `.github/actions/sentry-heartbeat`. Additive; slug ==
  `MONITOR_SLUG` env == workflow-file basename (the repo's slug convention).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails
  `deepen-plan` Phase 4.6. This one is filled (`aggregate pattern`).
- The alarm's checker MUST exit **2** (not 1) on any probe fault or zero-valid-evidence state — a
  standing alarm that pages on its own query failure trains the operator to ignore it. Mirror the
  soak probe's fail-safe: sentinel filtering + "no usable boot_id" → TRANSIENT.
- The GREEN→close step closes TWO title classes (`[ci/zot-restart-loop]` recurrence +
  `[ci/zot-telemetry-silent]` producer-silence); each open/close search must be **own-title**, never a
  union search across the two (a union-close would close the wrong issue — #5562 trap). Probe-fault has
  NO issue class (errored Sentry check-in only), which keeps this to two disciplined title searches.
- `zot_last_err` is free-text and emitted LAST; strip it (`sed 's/ zot_last_err=.*//'`) before any
  key=value parse so a crafted log line cannot spoof `boot_id=`/`exit_code=137`.
- Detection is **window-bound, not poll-bound** (architecture-review correction): the checker reads a
  3h WINDOW against the reporter's 5-min emit (~36 events/boot), so `CLIMB_N=3` consecutive samples are
  always present regardless of the 30-min poll cadence. Do NOT shrink the 3h WINDOW below
  `CLIMB_N × emit-interval` (the real coupling); the poll cadence only governs MTTD, and the Sentry
  self-liveness margin is what constrains it upward (GHA `schedule:` jitter — pin `checkin_margin`).

## Alternatives Considered
| Alternative | Verdict | Deferral tracking |
|---|---|---|
| Better Stack Telemetry **v2 SQL-alert API** (`POST /api/v2/dashboards/{id}/charts/{cid}/alerts`) | Rejected on merits (fidelity of stateful climb + newest-boot scoping; operator surface; no TF resource; decode source-of-truth split). Documented in ADR-096 §Alternatives. | No deferral — deliberately not chosen; endpoints recorded for future reuse. |
| Better Stack **dashboard** manual config | Rejected — not version-controlled/testable; `hr-exhaust-all-automated-options-before`. | None. |
| TF-manage `BETTERSTACK_QUERY_*` as `github_actions_secret` | Out of scope — the secrets already exist and work (sweeper depends on them un-managed); adding TF resources is a pre-existing hygiene item, not required by this alarm. | Optional follow-up issue (infra hygiene) — file at /work only if the reviewer wants it; not blocking. |
| Fold the alarm into `scheduled-followthrough-sweeper.yml` | Rejected — the sweeper is soak-followthrough-scoped (one-shot, closes issues); a standing continuous alarm is a distinct concern with its own cadence, dedup, and self-liveness. | None. |
