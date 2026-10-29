# Cron monitors for the 8 currently-scheduled GitHub Actions workflows that
# touch secrets. Closes #3236 (vendor-hosted dead-man's-switch). The plan
# enumerated 9 workflows; `scheduled-cf-token-expiry-check` is deferred
# this cycle (its `schedule:` block is commented out — see the
# breadcrumb-only resource gap at lines 50-56). Re-introduce a 9th
# resource when that workflow's schedule lands.
#
# Sentry derives the monitor slug
# from `name` (slugified); we use the workflow filename without `.yml` so
# the slug matches the MONITOR_SLUG env var in each workflow's check-in
# steps (Phase 4).
#
# AUTO-CREATED on push to main via .github/workflows/apply-sentry-infra.yml
# (Phase 5.5) — this closes the window between Phase 4 check-in steps
# shipping and the monitors existing in Sentry.
#
# Per-workflow grace periods (checkin_margin_minutes / max_runtime_minutes)
# come from observed run history. TBD entries fall back to 60/15 defaults
# until the operator captures real medians via `gh run list`.
#
# All monitors use UTC timezone — workflow cron expressions are UTC by GHA
# convention.
#
# `failure_issue_threshold` default is 1 (single missed check-in opens an
# issue). All hourly Inngest-fired monitors use 1; daily/weekly monitors
# use 1 because a single miss on a daily monitor is itself noteworthy.
#
# `checkin_margin_minutes` is sized per-substrate. Hourly Inngest-fired
# monitors (`scheduled_oauth_probe`, `scheduled_github_app_drift_guard`) use a
# 30-min margin — Inngest fires deterministically with ≤2-min jitter, so 30 is
# honest. #8450 returned two GHA-fired monitors
# (`scheduled_prod_version_drift` — since destroyed by the #6590 PR-B prune;
# `zot_restart_loop_alarm`) to hourly cadence
# with larger margins (360/120) sized for GHA schedule-delivery jitter, not
# Inngest's. Since #8495 `zot_restart_loop_alarm` and `scheduled_inngest_health`
# are dispatched by the web server's watchdog clock (ADR-248), so their margins
# are budgeted for the clock plus the MEASURED runner queue instead (inngest 15 -> 50, zot
# 120 -> 60; see each resource).
# Daily/weekly monitors use 30-1440 min as their observed jitter dictates; the 1440
# outlier is scheduled_realtime_probe, sized to survive one wholly dropped daily run.
# The TR9 substrate-migration sequence completed the move off GHA hourly cron
# for the Inngest-fired cohort: PR-1 #3985 (daily-triage), PR-2 #4062
# (follow-through), PR-3 #4227 closing issue #4211 (oauth-probe), PR-4
# closing issue #4235 (github-app-drift-guard).
#
# CLAUDE-EVAL COHORT — 60-min margin (NOT 30). The 12 `max_runtime_minutes = 55`
# monitors (scheduled_bug_fixer, scheduled_community_monitor, scheduled_roadmap_review,
# scheduled_legal_audit, scheduled_agent_native_audit, scheduled_competitive_analysis,
# scheduled_content_generator, scheduled_ux_audit, scheduled_campaign_calendar,
# scheduled_growth_audit, scheduled_growth_execution, scheduled_seo_aeo_audit) post a
# SINGLE end-of-run Sentry heartbeat (`_cron-claude-eval-substrate.ts` → handler step 4
# `sentry-heartbeat`) AFTER a `claude --print` run whose budget is 50 min
# (`MAX_TURN_DURATION_MS = 50 * 60 * 1000`) plus token-mint + depth-1 clone + workspace
# teardown overhead (~5-10 min). So a fully SUCCESSFUL run lands its check-in up to ~60 min
# after the scheduled fire — a 30-min margin false-pages "missed check-in" on success. This
# is exactly the false positive that paged for scheduled-agent-native-audit on 2026-06-15
# (the run filed issue #5318 at 09:09 UTC; only the end-of-run heartbeat was late). 60 =
# 50-min budget + setup/teardown slack; it stays far under every cohort monitor's inter-fire
# gap (the tightest cohort cadences are twice-weekly / weekly / monthly — all ≥ 1 day), so a
# maximally-late run is never misread as a missed NEXT run, and a genuinely dead cron still
# pages within ~1h. `cron-inngest-cron-watchdog` (`scheduled_inngest_cron_watchdog` liveness
# beacon + the parity-guarded `EXPECTED_CRON_FUNCTIONS` manifest) remains the not-firing
# backstop. NOTE: the small-cron / pure-TS Inngest crons keep the 30-min margin — only the
# single-end-of-run-heartbeat-after-a-50-min-budget shape warrants 60.
#
# `max_runtime_minutes` only matters for two-step (in_progress -> ok/error)
# check-ins where Sentry can detect a job exceeding its declared budget.
# All monitors currently defined here use a single end-of-job heartbeat
# (oauth-probe + 7 sister workflows post-rollout), so this field is
# decorative — only missed-run detection is in play. Retain the value
# for schema/sibling consistency and as a future-compat default if any
# monitor migrates back to the two-step pattern. If a new monitor lands
# in two-step shape (e.g. scheduled-cf-token-expiry-check per the gap at
# lines 71-77), update this prose AND verify the field becomes load-
# bearing for the new resource.
#
# ALERT ROUTING (#8630). Every monitor here must be routed in cron-monitor-alerts.tf
# or listed in its unrouted map (Guard 1); adding or removing one follows the
# two-PR rule in this root's README. Keep this file pure sentry_cron_monitor.

# scheduled-terraform-drift is now Inngest-DISPATCHED, not GHA-`schedule:`-fired.
# An Inngest cron (apps/web-platform/server/inngest/functions/cron-terraform-drift.ts,
# `0 6,18 * * *`, ≤2-min jitter) triggers the scheduled-terraform-drift GHA
# workflow via workflow_dispatch; the GHA run still executes terraform and emits
# this monitor's end-of-job heartbeat (the Inngest fn does NOT check in here).
# Because Inngest replaces GHA's jittery `schedule:` trigger, the margin tightens
# 480 -> 60: Inngest fire (≤2 min) + dispatch (seconds) + runner queue + terraform
# (~2-3 min) lands the check-in ~5-10 min after schedule, so 60 min is comfortable
# headroom while staying far under the 720-min inter-fire gap (06:00 -> 18:00) —
# a maximally-late run of one slot is never misread as a missed run of the next,
# and a genuinely dropped run still pages within 60 min instead of up to 8h.
# This supersedes the GHA-schedule-jitter rationale that justified 480 in PR #4772
# (which widened 180 -> 480 to absorb the jitter this PR removes at its source).
# The dispatcher's OWN liveness is covered by cron-inngest-cron-watchdog (the
# parity-guarded EXPECTED_CRON_FUNCTIONS manifest), not a second monitor.

resource "sentry_cron_monitor" "scheduled_terraform_drift" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-terraform-drift"
  schedule                = { crontab = "0 6,18 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-3 (closes #4211): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts`. The GHA
# scheduled-oauth-probe workflow was deleted in the same commit per TR9 I-13
# hygiene. Resource id, `name`, and Sentry monitor slug UNCHANGED —
# historical check-in continuity preserved.
resource "sentry_cron_monitor" "scheduled_oauth_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-oauth-probe"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #5674: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts`.
# NEW hourly 1-token canary on the operator ANTHROPIC_API_KEY — pages when the
# claude-eval fleet's credit is exhausted or the key is revoked (the page itself is
# sentry_alert.anthropic_credit_exhausted; this monitor is muted, #8704) (the 2026-06-29
# silent-fleet-down incident). It is a SMALL / pure-TS Inngest cron (no claude-eval
# spawn, no 50-min budget), so it takes the 30-min margin of the hourly small-cron
# cohort (scheduled_oauth_probe / scheduled_github_app_drift_guard / cron_kb_template
# _health), NOT the 60-min CLAUDE-EVAL COHORT. Fires at :47 (off-peak minute).
resource "sentry_cron_monitor" "scheduled_anthropic_credit_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-anthropic-credit-probe"
  schedule                = { crontab = "47 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# scheduled-cf-token-expiry-check: NOT wired this cycle. The workflow's
# `schedule:` block is currently commented out (manual-dispatch only —
# waiting on end-to-end validation per its own header). A cron monitor
# with no firing workflow would surface a permanent "missed check-in"
# false-positive page every Monday. Re-introduce this resource when the
# workflow's schedule line lands in `.github/workflows/scheduled-cf-token-
# expiry-check.yml` lines 13-15.

# TR9 PR-4 (closes #4235): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`.
# The GHA scheduled-github-app-drift-guard workflow was deleted in the same
# commit per TR9 I-13 hygiene. Resource id, `name`, and Sentry monitor slug
# UNCHANGED — historical check-in continuity preserved.
resource "sentry_cron_monitor" "scheduled_github_app_drift_guard" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-github-app-drift-guard"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #3413: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-kb-template-health.ts`.
# NEW hourly probe — no GHA-era predecessor (the issue body named a
# GitHub Actions workflow but the work landed as an Inngest cron per the
# 45-cron-vs-4-workflow precedent + ADR-030; the structural sibling is
# scheduled_github_app_drift_guard above). The slug `cron-kb-template-health`
# matches SENTRY_MONITOR_SLUG in the handler; hourly cadence + 30-min margin
# + 10-min runtime mirror the drift-guard sibling (same API-probe shape).
resource "sentry_cron_monitor" "cron_kb_template_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-kb-template-health"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# scheduled-realtime-probe is GHA-fired (.github/workflows/scheduled-realtime-probe.yml,
# on.schedule "0 7 * * *"), so it is subject to GitHub Actions scheduler
# reliability gaps. On 2026-05-26 GitHub dropped the scheduled run ENTIRELY
# (not jitter — a whole missing run), which paged a "missed check-in" on
# 2026-05-28 even though the last actual run (05-27) passed 5/5. The 180-min
# margin tolerated jitter but not a dropped 24h run; widen to 1440 (24h) so a
# single dropped scheduled run does not page. A genuine realtime regression is
# still caught loudly within any run that DOES fire (the probe's own 5x
# SUBSCRIBED check files ci/realtime-broken); the margin only governs the
# missed-RUN path, which is the false-alarm source. See issue #4189.
resource "sentry_cron_monitor" "scheduled_realtime_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-realtime-probe"
  schedule                = { crontab = "0 7 * * *" }
  checkin_margin_minutes  = 1440
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Issue #4650: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts`.
# LIVENESS BEACON (#4682 retired the self-heal). The watchdog originally queried
# the server's /v1/functions registry to classify + self-restore dropped (H9a) /
# de-planned (H9b) cron triggers, but that introspection API is loopback-gated
# and unreachable from the app container (health=200, /v1/functions=404), and the
# self-heal is redundant with --poll-interval 60 (#4652) + the per-function cron
# monitors. The function now just posts ok=true every 4h: its own check-in proves
# the inngest cron scheduler is alive enough to fire it. So THIS monitor pages
# only on a MISSED check-in (scheduler dead / function dropped), never on ok=false.
# 4-hourly (0 */4 * * *) — 120-min margin per the Inngest ≤2-min jitter.
resource "sentry_cron_monitor" "scheduled_inngest_cron_watchdog" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-inngest-cron-watchdog"
  schedule                = { crontab = "0 */4 * * *" }
  checkin_margin_minutes  = 120
  max_runtime_minutes     = 5
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6374: GHA-fired via .github/workflows/scheduled-inngest-health.yml (on.schedule
# '*/15 * * * *'). The EXTERNAL inngest health watchdog (#5542 crash-loop incident).
# This monitor was MISSING — the workflow's error heartbeat (its final step, POSTing
# ?status=error to the `scheduled-inngest-health` slug) had NO sentry_cron_monitor
# resource, so Sentry silently dropped the check-ins and the P1 [ci/inngest-down] alarm
# ran ~14h unseen (the operator was never paged). This resource closes that delivery
# gap: with failure_issue_threshold=1, a SINGLE ?status=error OR a missed check-in opens
# a Sentry monitor-failure issue → pages the operator within one cadence (~15-30 min).
#
# NOT Inngest-fired — a self-hosted inngest cron cannot detect inngest being down;
# that blind spot is the exact #5542 failure this watchdog closes; see the workflow's
# gate-override header. PRIMARY trigger since #8495: the web server's watchdog dispatch
# clock (apps/web-platform/server/watchdog-dispatch-clock.ts, ADR-248) fires
# workflow_dispatch every 15-min slot from both web hosts; the workflow's own
# `schedule:` cron is only the FALLBACK (GHA measured one scheduled run per 2-7 h).
# checkin_margin_minutes = 50 is budgeted for that clock (#8495 review): the clock's
# WORST case is its in-slot retry path — jitter (<= 2 min, JITTER_MAX_MS) + 3 attempts
# (MAX_ATTEMPTS_PER_SLOT), each reached on the next poll (<= 0.5 min) and bounded by the
# tick deadline (<= 1.5 min), separated by 2 backoffs (RETRY_BACKOFF_MS, 2 min) = 12 min —
# + RUNNER QUEUE (30 min allowance) + job runtime (max_runtime_minutes = 8, the probe job's
# `timeout-minutes: 8`; the single final heartbeat is in that job) = <= 50 min. The queue is
# the dominant term and is MEASURED on this workflow's own jobs (job started_at - created_at,
# last 40 runs, 2026-09-24): median 32 s, p75 635 s, p90 1274 s, max 2272 s — the org runner
# budget (#8450) delays dispatched and scheduled runs alike, so a 15-min margin would miss
# ~40% of slots. Re-measure before changing it:
#   for id in $(gh run list --workflow scheduled-inngest-health.yml --limit 40 --json databaseId --jq '.[].databaseId'); do
#     gh api repos/jikig-ai/soleur/actions/runs/$id/jobs --jq '[.jobs[] | select(.started_at != null) | ((.started_at|fromdate) - (.created_at|fromdate))] | max'; done | sort -n
# The margin bounds only DEAD-TRIGGER detection (clock dark on both hosts AND no GHA tick):
# interval + margin = 65 min. A real inngest outage pages as soon as a run executes — the run
# posts ?status=error — i.e. slot + ~4 min + queue + runtime (median ~10 min, p90 ~30 min),
# independent of this margin. sentry-monitor-iac-parity.test.ts enforces the budget. Slug MUST match the `monitor-slug` in the
# workflow's sentry-heartbeat step (parity-asserted by
# apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts). That test no
# longer asserts membership of an apply-sentry-infra.yml `-target=` allowlist: since
# #6589 the workflow plans the full root, so declaring the resource here IS applying it.
# The slug-parity half of that test remains load-bearing — a slug that drifts from the
# workflow's `monitor-slug` still yields a monitor nothing checks into.
resource "sentry_cron_monitor" "scheduled_inngest_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-inngest-health"
  schedule                = { crontab = "*/15 * * * *" }
  checkin_margin_minutes  = 50
  max_runtime_minutes     = 8
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #5046 PR-2 — host-side egress-allowlist re-resolve timer
# (cron-egress-resolve.timer, every 1 min). A DEAD timer freezes the
# nftables allowlist set → progressive then total container egress loss as
# SaaS IPs rotate, so missed-check-in detection is the load-bearing alarm
# (the unit's OnFailure= only fires when the service RUNS and fails — a
# hang or a never-firing timer pages ONLY here). The systemd timer is
# monotonic (OnUnitActiveSec), not wall-aligned, so check-ins drift across
# crontab windows: margin 5 + threshold 5 pages after ~10 min of true
# silence while absorbing reboot windows and per-tick jitter. Slug MUST
# match SENTRY_SLUG in cron-egress-resolve.sh and cron-egress-alarm.sh
# (parity-asserted by cron-egress-firewall.test.sh).
# feat-operator-inbox-delegation Phase 6: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts`.
# Daily email-ingress liveness probe: sends a tokenized marker email via
# Resend outbound (notifications@ → ops@), step.sleeps 15 min INSIDE the run,
# then asserts its own mail_class='probe' row landed (same-run assertion).
# Probe row found → ?status=ok; absent → ?status=error + throw (the function
# pins retries: 0 so a late-landing probe can never retry-to-green).
# checkin_margin 60 DEVIATES from the 30-min Inngest-fired precedent
# (scheduled_daily_triage cohort): the check-in lands ~16-17 min AFTER the
# scheduled fire (15-min in-run sleep + send/assert overhead), so a 30-min
# margin would leave <14 min of real headroom for redeploy windows and
# queue backpressure; 60 keeps an honest alarm within the hour while never
# paging on the structural in-run delay.
# max_runtime_minutes 25, NOT the small-cron 10: the 15-min sleep is INSIDE
# the run, so a 10-min budget would mark every single run errored.
resource "sentry_cron_monitor" "cron_email_ingress_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-email-ingress-probe"
  schedule                = { crontab = "0 6 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 25
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "cron_egress_resolve" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-egress-resolve"
  schedule                = { crontab = "* * * * *" }
  checkin_margin_minutes  = 5
  max_runtime_minutes     = 5
  failure_issue_threshold = 5
  recovery_threshold      = 1
  timezone                = "UTC"
}

# ---------------------------------------------------------------------------
# 2026-06-11 IaC-gap backfill (surfaced by PR #5133's AC12 verification):
# 13 Inngest crons (+ a 14th, nag-4216-readiness, surfaced by the parity
# test itself) posted heartbeats to monitor slugs that had NO
# sentry_cron_monitor resource — Sentry's check-in API silently accepts or
# drops check-ins for unknown slugs, so a dead cron in this set paged nowhere.
# One resource per code slug below; the parity test
# (apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts)
# asserts every SENTRY_MONITOR_SLUG in server/inngest/functions/ has a
# matching `name` here, so a new cron cannot ship without its monitor.
#
# Margins/runtimes follow the file's established cohorts: pure-TS/script
# Inngest crons (≤2-min jitter) get a 30-min margin + 10-15 min runtime;
# the claude-eval cohort gets a 60-min margin (single end-of-run heartbeat
# after a 50-min MAX_TURN_DURATION_MS budget + slack; see header) AND the
# 55-min runtime (mirroring scheduled_bug_fixer). The four
# Tier-2-dormant claude-spawn crons (campaign-calendar, growth-audit,
# growth-execution, seo-aeo-audit) post their deferral heartbeat on
# schedule today, so missed-check-in detection is live for them now and
# stays correctly sized for Tier-2 restoration.
# ---------------------------------------------------------------------------

# Daily 06:23 UTC — KB workspace sync-health probe (pure TS).
resource "sentry_cron_monitor" "cron_workspace_sync_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-workspace-sync-health"
  schedule                = { crontab = "23 6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Hourly :17 — membership-health invariant probe (pure TS, read-only RPC).
resource "sentry_cron_monitor" "scheduled_membership_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-membership-health"
  schedule                = { crontab = "17 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6291: GHA-fired via .github/workflows/scheduled-zot-restart-loop.yml (on.schedule
# '0 * * * *' — hourly since #8450, relaxed from */30 for the org concurrency budget).
# Self-liveness for the standing zot restart-loop recurrence alarm — a MISSED
# check-in means the alarm went dark (workflow disabled / GHA outage), a ?status=error heartbeat
# means the run's checker returned TRANSIENT (a persistent Better Stack probe fault). GREEN/FIRE/
# PRODUCER-SILENT all check in ok:true (they are successful evaluations — a FIRE's surface is the
# [ci/zot-restart-loop] issue, not this monitor). GHA-fired (NOT Inngest — see the workflow's
# gate-override header: the alarm is a bash pipeline in I7's uncontained class, and the registry is
# a separate host so an Inngest cron on the watched fleet would be a dark-alarm risk).
#
# PRIMARY trigger since #8495: the web server's watchdog dispatch clock
# (apps/web-platform/server/watchdog-dispatch-clock.ts, ADR-248) fires workflow_dispatch every
# hourly slot from both web hosts; the workflow's `schedule:` cron is only the FALLBACK. The old
# margin of 120 (2× the interval) existed to absorb GHA `schedule:` jitter (measured gaps up to
# 243 min on the old */30 cadence); a dispatched run is created within seconds, so it is
# re-derived: checkin_margin_minutes = 60 >= the clock's worst case (12 min: jitter + 3
# retried ticks + 2 backoffs, see scheduled_inngest_health) + RUNNER QUEUE (30 min allowance; measured on this workflow's jobs 2026-09-24:
# median 17 s, p90 1169 s, max 2438 s — see scheduled_inngest_health for the command) +
# runtime (max_runtime_minutes = 10; the job's `timeout-minutes: 8`) = <= 52 min.
# A dead trigger (clock dark on both hosts AND no GHA tick) pages within interval + margin =
# 120 min (was ~3 h). This monitor posts a SINGLE end-of-run heartbeat within ~1-2 min of the checker
# finishing (a small bash probe, not a claude-eval spawn); detection of a loop itself stays
# window-bound (the alarm's own 3h look-back). max_runtime_minutes = 10 mirrors the GHA-fired
# small-cron cohort (scheduled_realtime_probe). Slug MUST match MONITOR_SLUG in the workflow's
# sentry-heartbeat step (scheduled-zot-restart-loop).
resource "sentry_cron_monitor" "zot_restart_loop_alarm" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-zot-restart-loop"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #9703: GHA-fired via .github/workflows/scheduled-inngest-probe-heartbeat.yml (on.schedule
# '*/15 * * * *' is the FALLBACK; the PRIMARY trigger is the web server's watchdog dispatch clock,
# ADR-248, one workflow_dispatch per 15-minute UTC slot — see WATCHDOG_DISPATCH_TABLE). The workflow
# is the repo-side verifier that feeds the Better Stack dead-probe heartbeat
# `betteruptime_heartbeat.inngest_server_probe`: it beats only while a fresh host_role=dedicated
# inngest-server-probe row is in the warehouse. A MISSED check-in here means the feeder went dark
# (clock + fallback both dead, workflow disabled); a `status=error` check-in means the run WITHHELD
# or FAILED a beat (stale or absent probe row, API/credential fault) — it says nothing about the
# store itself, and the heartbeat (armed, #9703) is the paging surface. GHA-fired by the web watchdog clock, NOT
# Inngest: the heartbeat is the sole paging surface, so an Inngest-fired feeder would turn an Inngest
# or web-1 outage into a false "probe dark" page (ADR-248 amendment 2026-10-11).
#
# checkin_margin_minutes = 60 is the parity ceiling (MAX_MARGIN_MINUTES in
# sentry-monitor-iac-parity.test.ts) and covers the measured tail, so a slow runner queue does not
# file a missed check-in while the heartbeat is still safe: 12 min clock worst case + 40.6 min
# measured runner-queue max (2438 s over 40 runs of the zot watchdog, 2026-09-24 — the parity
# test's QUEUE_ALLOWANCE_MINUTES of 30 is the asserted floor, this uses the observed max) + 6 min
# runtime (max_runtime_minutes = 6; the job's `timeout-minutes: 6`) = 58.6 min <= 60. A dead trigger
# opens a Sentry issue within interval + margin = 15 + 60 = 75 min and, routed (#9703 Stage 3b), emails
# through sentry_alert.cron_monitor_failure. Re-measure the queue tail on this workflow once
# it has history, before changing the margin (same command as scheduled_inngest_health):
#   for id in $(gh run list --workflow scheduled-inngest-probe-heartbeat.yml --limit 40 --json databaseId --jq '.[].databaseId'); do
#     gh api repos/jikig-ai/soleur/actions/runs/$id/jobs --jq '[.jobs[] | select(.started_at != null) | ((.started_at|fromdate) - (.created_at|fromdate))] | max'; done | sort -n
# Slug MUST match MONITOR_SLUG in the workflow's sentry-heartbeat step
# (scheduled-inngest-probe-heartbeat). Routed (#9703 Stage 3b): cron-monitor-alerts.tf.
resource "sentry_cron_monitor" "scheduled_inngest_probe_heartbeat" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-inngest-probe-heartbeat"
  schedule                = { crontab = "*/15 * * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 6
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Liveness for the Better Stack incident mirror (#10390 WS1):
# .github/workflows/scheduled-betterstack-incident-mirror.yml. The mirror is GHA-executed and
# watchdog-dispatched (WATCHDOG_DISPATCH_TABLE, 15-min slots); its `schedule:` trigger is only the
# fallback. It CANNOT be Inngest-scheduled — it observes the Better Stack paging substrate the
# Inngest fleet's own outages report through (the 2026-10-22 email-only incident delivery), so an
# Inngest-scheduled mirror goes dark exactly when the incidents it mirrors are firing
# (ADR-033 anti-circularity; the workflow carries the ADR-248 gate-override header). The check-in
# is the workflow's terminal sentry-heartbeat step, `ok` only on a deciding exit 0
# (verdict mirrored|no_incidents); every read/filing failure posts `error`, and a dead dispatch
# clock is a missed check-in. A dead mirror opens a Sentry issue within interval + margin.
# Margin = 12-min clock skew + measured worst queue + runtime (max_runtime_minutes = 6; the job's
# `timeout-minutes: 6`) — capped at 60 to match the parity ceiling; re-measure the queue tail once
# this workflow has history before narrowing it (same command as scheduled_inngest_health).
# Slug MUST match `monitor-slug` in the workflow's sentry-heartbeat step
# (scheduled-betterstack-incident-mirror). Routing: declared UNROUTED under the two-PR rule —
# cron-monitor-alerts.tf `local.cron_monitor_alert_unrouted`; a follow-up PR moves it into
# monitor_ids after the first measured apply.
resource "sentry_cron_monitor" "scheduled_betterstack_incident_mirror" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-betterstack-incident-mirror"
  schedule                = { crontab = "*/15 * * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 6
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Liveness for the runtime-image vulnerability scan (W3, epic #9601):
# .github/workflows/image-cve-scan.yml. The check-in is posted by the sentry-heartbeat step at the
# end of that workflow, `error` on any non-zero scan exit (exit 3 = unmeasured), so this monitor
# covers BOTH "the workflow never ran" (missed check-in) and "the scan ran blind" (error). A blind
# scan must never read as clean.
#
# `name` MUST stay slug-shaped: Sentry derives the slug by slugifying `name`, and the workflow's
# `monitor-slug` input must equal it (sentry-monitor-iac-parity.test.ts asserts the two agree).
# 05:17 UTC mirrors the workflow's `schedule:`; checkin_margin_minutes = 360 follows the measured GHA
# schedule-delivery jitter that scheduled_prod_version_drift's stanza documented (that monitor was
# destroyed by the #6590 PR-B prune — the measurement rationale stays, only the stanza is gone),
# NOT the nominal interval.
resource "sentry_cron_monitor" "image_cve_scan" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "image-cve-scan"
  schedule                = { crontab = "17 5 * * *" }
  checkin_margin_minutes  = 360
  max_runtime_minutes     = 30
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6549 item 2 — liveness for the source-vs-live Better Stack heartbeat reconcile job
# (scheduled-terraform-drift.yml → heartbeat-live-reconcile). Since #7884 (ADR-222) the
# same job also reconciles live monitors and reports unmanaged objects; the slug keeps
# its original name. A GHA-workflow-fired
# heartbeat (no Inngest counterpart); slug mirrors the workflow's `sentry-heartbeat`
# check-in, so sentry-monitor-iac-parity.test.ts's code→IaC GHA-slug guard is satisfied.
# checkin_margin_minutes=60 tracks the Inngest-dispatch cadence (≤2-3 min jitter), NOT
# raw GHA `schedule:` drift — mirrors scheduled_terraform_drift, the same dispatch.
resource "sentry_cron_monitor" "scheduled_heartbeat_reconcile" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-heartbeat-reconcile"
  schedule                = { crontab = "0 6,18 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6031 (ADR-088) — the scheduled-ghcr-token-minter monitor was REMOVED when the minter was
# disabled (App installation tokens cannot pull the private repo-linked GHCR packages). The
# minter itself was deleted by #8714 (ADR-096 task 5.4); there is nothing to restore.

# Liveness for the production version-drift alerter (#7091):
# .github/workflows/scheduled-prod-version-drift.yml. This is the watch-the-watcher layer —
# the workflow's own email + GitHub issue carry the drift verdict, so this monitor answers
# only "did the checker run at all". Without it, a disabled workflow or a dropped schedule
# would be indistinguishable from a permanently CLEAN production.
#
# checkin_margin_minutes = 360, sized to MEASURED delivery rather than to the nominal
# interval. An earlier revision used margin == interval (30) on the strength of the
# `margin == interval` rationale stated elsewhere in this file. That rationale is refuted by
# this repo's own dispatch history, so it is deliberately NOT followed here:
#
#   $ gh run list --workflow=scheduled-zot-restart-loop.yml --event=schedule --limit 60
#     n=59 consecutive scheduled runs of the */30 sibling
#     min=61  median=114  max=243  (minutes between runs)
#     gaps within the 60-minute (tick + 30 margin) window: 0 of 59
#
# GitHub drops scheduled ticks on this repo heavily enough that a */30 cron delivers ~11
# runs/day, and the */15 sibling delivers the SAME ~11. A 30-minute margin would therefore
# put this monitor in a missed-check-in state on essentially every tick: the founder's ONE
# page (Sentry routes cron failures via New/ExistingHighPriorityIssueCondition, so repeats
# are silent — #7142) would be spent on jitter within the first hours, after which a
# genuinely disabled workflow or dropped schedule is indistinguishable from the standing
# noise. That is verbatim the failure this monitor exists to prevent, caused by its own
# margin. The two sibling monitors cited by the old rationale carry the same defect; it is
# pre-existing and out of scope here, but their constants are not evidence. (#8495 later
# moved those two siblings onto the web-server watchdog dispatch clock, ADR-248; this
# monitor's workflow is not a watcher of the scheduling substrate, so it stays GHA-fired.)
#
# 360 exceeds the measured max gap (243) with headroom, and matches the jitter the checker's
# own header cites (median 80-134 late, max 339). A truly dark alarm still pages within ~6h.
# AMENDED by #8450: the workflow no longer keeps */30 — it relaxed to hourly for the org
# concurrency budget, and this monitor's crontab moved with it. The margin rationale above is
# unchanged: 360 still exceeds the worst delivered gap the tighter cadence ever produced.
# (#7471) Liveness for the DAILY published-marketplace-manifest drift check
# (.github/workflows/scheduled-marketplace-drift.yml, on.schedule "37 6 * * *").
#
# WHY IT EXISTS. `jikig-ai/soleur-marketplace` is the plugin's sole distribution channel.
# AMENDED by #7493: this note previously said the repo "has no CI, no required review and no
# CODEOWNERS" and that the workflow was "the only control on it". Both held when written; the
# repo now carries a PR-required ruleset and Terraform owns the manifest's contents. What is
# unchanged is why this MONITOR exists — the workflow is still the only check on the bytes
# actually served, so the control needs a control: without this monitor,
# a workflow that stops being scheduled (GitHub disables schedules on repo inactivity and drops
# ticks under load) is indistinguishable from a manifest that has stayed clean. There is no red
# run to notice, because there is no run.
#
# The workflow's own issue carries the drift verdict; this answers only "did the checker run".
# The heartbeat status carries a `delivered` conjunct, so a drift that was DETECTED and whose
# issue failed to file reports `error` here rather than `ok` — a detected-but-undelivered alarm
# is a monitor failure, not a successful evaluation.
#
# checkin_margin_minutes = 360 follows the measured-delivery rationale established for
# scheduled-prod-version-drift above, NOT margin == interval: this repo's scheduled ticks are
# delivered late often enough that a tight margin would page on essentially every tick, and the
# founder has one page. A genuinely dark checker still surfaces within ~6 h against a 24 h
# check interval.
resource "sentry_cron_monitor" "scheduled_marketplace_drift" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-marketplace-drift"
  schedule                = { crontab = "37 6 * * *" }
  checkin_margin_minutes  = 360
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# (#6808) Liveness for the DAILY /workspaces LUKS at-rest verification
# (.github/workflows/workspaces-luks-verify.yml, on.schedule "41 4 * * *"). The check-in is posted
# by that workflow's final `sentry-heartbeat` step and ONLY on a `schedule` event, so an operator
# dispatch — including the alarm_selftest rehearsal — cannot forge liveness while the cron is dead.
#
# WHY THIS MONITOR EXISTS AT ALL. The workflow's own in-run alarm files an issue for every failure
# it can observe, but it is structurally blind to three modes that produce SILENCE rather than a red
# run: (1) the schedule stops firing (GitHub disables `schedule:` after 60 days of repository
# inactivity, and on 2026-05-26 it dropped a scheduled run ENTIRELY — see scheduled_realtime_probe
# above, #4189); (2) a pending run cancelled by concurrency supersession executes no steps, so no
# `always()` construction inside the run can report it; (3) a run cancelled or torn down before its
# `always()` steps complete — note the ORDINARY `timeout-minutes: 15` teardown is NOT in this set:
# `always()` steps DO run on a timeout cancellation, which is exactly why the workflow chose
# `always()` over `!cancelled()`, so a hung SSH normally files "nothing was proven" by itself.
# What this monitor covers is the residual: a cancellation grace window too short for the alarm's
# `gh` calls to land. A missed check-in is the only layer that sees any of them — and while #6808
# keeps the host-side heartbeat unwired, this workflow is the ONLY automatic verification that
# web-1's /mnt/data is still on the LUKS mapper, with a published present-tense Article 32 claim and
# a 30-day claim_decay_trigger resting on it.
#
# BOTH constants below depart from the file's convention, and they are a PAIR — reverting either one
# in isolation breaks something:
#
#   failure_issue_threshold = 2 (convention: 1). GitHub drops individual scheduled runs on this
#   repo; #4189 records a whole daily run vanishing and paging a false "missed check-in" while the
#   previous run had passed 5/5. At threshold 1 this monitor would page on that jitter, and a
#   founder-grade alarm spent on jitter is an alarm nobody reads.
#
#   checkin_margin_minutes = 420 (convention for a daily cron: 1440, per scheduled_realtime_probe).
#   1440 was that monitor's way of buying single-dropped-run tolerance THROUGH the margin, because
#   its threshold stayed at 1. Here the threshold buys that tolerance instead, so the margin can go
#   back to sizing GHA start-delay jitter (7h is generous against observed delays). Keeping BOTH the
#   1440 margin and the threshold of 2 would push detection of a genuinely dark schedule past 2.5
#   days; keeping the 420 margin with a threshold of 1 reintroduces the #4189 false page.
#
# Net: one dropped run is silent, and a schedule that is genuinely dark pages at ~31 h after the
# first MISSED TICK (24 h to the next expected tick + the 7 h margin) — i.e. ~55 h since the last
# PROVEN verification, which is the number that matters against the decay window. Comfortably
# inside 30 days either way.
#
# WHAT THE THRESHOLD ALSO BUYS, stated because it is easy to miss: Sentry counts an explicit
# `status=error` check-in as a failed check-in exactly like a missed one, so threshold 2 ALSO
# means a single night of asserted failure opens no Sentry issue. That is acceptable only because
# the in-run alarm files a GitHub issue on the FIRST occurrence — Sentry is the backstop for
# silence, never the primary channel for an observed failure. If the alarm's filing path is ever
# made best-effort, this threshold has to be revisited with it.
#
# max_runtime_minutes = 20 is DECORATIVE here, like every other value of it in this file: the
# header above records that it only applies to two-step (in_progress -> ok/error) check-ins, and
# the sentry-heartbeat composite posts a single terminal check-in. It is set to track the
# workflow's own `timeout-minutes: 15` with headroom so the pair stays coherent if Sentry ever
# gains single-check-in runtime detection — NOT because it currently flags a slow SSH run.
#
# #3958 residual, recorded rather than rediscovered: a monitor removed from this file is DEACTIVATED
# in Sentry rather than deleted, so re-adding one with the same name adopts the existing object.
resource "sentry_cron_monitor" "workspaces_luks_verify" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "workspaces-luks-verify"
  schedule                = { crontab = "41 4 * * *" }
  checkin_margin_minutes  = 420
  max_runtime_minutes     = 20
  failure_issue_threshold = 2
  recovery_threshold      = 1
  timezone                = "UTC"
}

# (#6931) Liveness for the web-2 soak-marker job (.github/workflows/workspaces-luks-verify.yml, job
# `web2_marker`, the SAME on.schedule "41 4 * * *" as the web-1 leg above). That job is the single writer and
# deleter of WORKSPACES_LUKS_CUTOVER_AT, so a silently dead schedule leaves a stale marker in place with no
# re-verification; a missed check-in is the only layer that sees it. The check-in is posted by the job's last
# `sentry-heartbeat` step and ONLY on a `schedule` event (a dispatch must not forge liveness).
#
# Every constant mirrors `workspaces_luks_verify` ABOVE and for the same reasons (threshold 2 absorbs the
# dropped scheduled runs recorded in #4189, and the margin then only has to size start-delay jitter; the
# in-run GitHub issue is the primary channel for an observed failure, Sentry the backstop for silence).
# max_runtime_minutes is decorative (the heartbeat posts one terminal check-in) and tracks this job's
# `timeout-minutes: 10` with headroom. The crontab is asserted EQUAL to the workflow's by
# workspaces-luks-verify-workflow.test.sh, as for the web-1 monitor.
resource "sentry_cron_monitor" "workspaces_luks_verify_web2" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "workspaces-luks-verify-web2"
  schedule                = { crontab = "41 4 * * *" }
  checkin_margin_minutes  = 420
  max_runtime_minutes     = 20
  failure_issue_threshold = 2
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Executor liveness for the main-branch health monitor (#7307).
#
# NOT a novel argument — the on-point precedent is `scheduled_domain_model_drift`
# above, which took an own monitor "because weekly-cadence absence-based liveness
# is too weak — a broken executor that files nothing would be invisible for up to
# 7 days" (#5872). #7307 is the same argument at a 6h cadence, and it is the
# empirical counterexample to the posture `cron-main-health-monitor.ts` recorded
# as "Design A — no own Sentry monitor", which rested end-to-end liveness on "a
# broken main goes un-issued" being a readable signal. It was not readable: a job
# timeout is recorded `cancelled` (never `failure`) and `| tee` under the default
# `bash -e {0}` shell discarded the suite's exit code, so the executor filed
# nothing for four months. Design A's SCHEDULER arm is untouched and still correct
# (`cron-inngest-cron-watchdog` + `EXPECTED_CRON_FUNCTIONS`); what this adds is the
# EXECUTOR arm, which nothing covered.
#
# crontab mirrors the Inngest cron in cron-main-health-monitor.ts
# (`{ cron: "0 */6 * * *" }`) — read from that file, not from memory.
#
# checkin_margin_minutes = 210, DERIVED, not copied from the cohort. The cohort's
# 60 belongs to jobs with `timeout-minutes` of 8-15, i.e. 45+ minutes of slack;
# this executor's job ceiling is 185, so a copied 60 would page BEFORE the job's own
# ceiling and a legitimately slow green run would open a P1 on a healthy main.
# The method the header's CLAUDE-EVAL passage actually documents is
# margin = run budget + setup/teardown slack, so: 185 (job ceiling) + 25 (Inngest
# jitter, dispatch, runner queue) = 210, still under the 360-minute inter-fire
# gap, so a genuinely dropped run pages within 210 minutes. If the workflow's
# `timeout-minutes` moves, this moves with it; the static guard in
# plugins/soleur/test/main-health-monitor-workflow.test.sh (G2) fails when it does not.
# The 185 is derived from an uncensored measurement (workflow run 36950488321), see the
# TIMEOUT BUDGET block in the workflow. The +25 slack is checked against the monitor's own
# population, measured over the 62 runs since 2026-09-17: dispatch lag after the 6-hour slot
# (p90 111 s, max 211 s from the slot to the run's created_at) and job queue delay (a few
# seconds typically; the worst two samples were 1509 s and 2176 s). A healthy run takes about
# 110 minutes against the 185-minute job ceiling, so the margin absorbs those worst samples
# with room; a run that ALSO ran to its full ceiling would not. A dry run now has its own
# concurrency group, so a manual measurement cannot queue the scheduled run behind it.
#
# max_runtime_minutes tracks the workflow's own job-level `timeout-minutes` (185), per the
# `workspaces_luks_verify` convention immediately above. It is DECORATIVE under a
# single terminal heartbeat (this file's header, lines on two-step check-ins) —
# but it must not be FALSE.
resource "sentry_cron_monitor" "main_health_monitor" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "main-health-monitor"
  schedule     = { crontab = "0 */6 * * *" }
  # #9410 — the monitor is sharded: the envelope is the run's bounded wall
  # clock, i.e. the SLOWEST leg's job ceiling plus the report job's, not a
  # single job's. Currently max(85, 80, 35, 30, 30) + 15 = 100, margin = +25.
  # The G2 row of plugins/soleur/test/main-health-monitor-workflow.test.sh
  # keeps these two literals coupled to the workflow.
  checkin_margin_minutes  = 125
  max_runtime_minutes     = 100
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# The §2.9 drift detector for the 27 adopted `sentry_alert` rules (#7834).
#
# WHAT THIS BUYS THAT NOTHING ELSE DOES. `scheduled-sentry-alert-drift.yml` was
# the only scheduled workflow with no heartbeat, and its own header named the
# uncovered case: "the dispatch was accepted and the runner never ran." Inngest
# reports success, no GHA run happens, and no step of that workflow executes — so
# nothing there can file anything. The 27 rules are then unwatched and the repo
# looks healthy. `cron-inngest-cron-watchdog` covers the SCHEDULER going quiet;
# only a missed check-in covers the RUNNER never starting.
#
# It could not land with the adoption itself: adding any resource to this root
# would have planned `1 to add`, and that PR's whole safety argument was a plan of
# 27 imports and nothing else.
#
# DISPATCH-HYBRID CLASS, so the margin is deliberately generous. The check-in
# arrives after Inngest dispatch latency + GitHub Actions queue time + up to the
# workflow's `timeout-minutes: 10` — none of which is bounded by the crontab. 60
# matches `scheduled_supabase_advisor_scan`, the closest analogue (daily,
# Inngest-dispatched, GHA-executed, same job ceiling). A margin copied from a
# `schedule:`-driven monitor would page the founder on queue jitter.
#
# max_runtime_minutes tracks the workflow's `timeout-minutes: 10`, per the
# `main_health_monitor` convention above. It is DECORATIVE under a single terminal
# heartbeat — there is no `in_progress` check-in, so runtime is not actually
# monitored — but it must not be FALSE.
resource "sentry_cron_monitor" "scheduled_sentry_alert_drift" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-sentry-alert-drift"
  schedule                = { crontab = "15 7 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Liveness for cron-merge-queue-stall-dispatch (#9482 follow-up (a)) — the
# every-10-minutes Inngest dispatcher that triggers the merge-queue stall probe
# (.github/workflows/merge-queue-stall-check.yml). DISPATCHER-fed: the check-in
# is posted by the Inngest function itself, NOT by the executed workflow (which
# carries no Sentry secrets), so a green check-in means "dispatched", not
# "probe executed". Do not move the heartbeat into the workflow without
# revisiting its secrets posture. Margin follows the Inngest-fired cohort
# convention (30 min over the 10-min interval); no runner-queue allowance is
# needed because the heartbeat posts from the dispatcher, not a runner. A dead
# dispatcher opens a Sentry issue inside ~40 min and emails via
# sentry_alert.cron_monitor_failure (the two-PR rule's second PR, tracked in
# #9493). The workflow's own schedule: is the fallback trigger; its
# detection-latency story lives in the function header.
resource "sentry_cron_monitor" "scheduled_merge_queue_stall_dispatch" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-merge-queue-stall-dispatch"
  schedule                = { crontab = "*/10 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 5
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Executor liveness for the bounded Supabase Postgres-hang auto-restart
# watchdog (.github/workflows/scheduled-supabase-watchdog.yml, #9168, ADR-260).
# Inngest-DISPATCHED every 5 min via
# apps/web-platform/server/inngest/functions/cron-supabase-watchdog-dispatch.ts
# (a regular Inngest cron — NOT the watchdog-dispatch-clock: the dispatch path
# is independent of the WATCHED project — App creds are env-held and run-state
# lives on the dedicated host's Redis, whose backing Postgres is a separate
# Supabase project — so the dispatch fires while soleur-web-platform hangs).
# The workflow's own `*/5` `schedule:` is the documented fallback; the monitor
# crontab must equal it (the #8450 cadence-parity guard).
#
# 30-min margin = the Inngest-fired cohort convention sized here for the
# measured runner queue (p90 ~20 min on the clock-dispatched cohort, 2026-09-24
# measurement) + the ~4-5 min runtime (3 health reads spaced 60 s + issue
# writes) + dispatch jitter. A dead dispatcher or a probe that never lands
# still pages inside the hour; a live-but-failing probe posts status=error.
resource "sentry_cron_monitor" "scheduled_supabase_watchdog" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-supabase-watchdog"
  schedule                = { crontab = "*/5 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
