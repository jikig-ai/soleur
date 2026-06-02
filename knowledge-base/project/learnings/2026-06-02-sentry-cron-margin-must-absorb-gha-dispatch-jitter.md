# Learning: a GHA-fired Sentry cron monitor's check-in margin must absorb GitHub Actions scheduled-dispatch jitter, not run duration

## Problem

The Sentry cron monitor `scheduled-terraform-drift` (web-platform, production) paged a
recurring "missed check-in → regressed" pair: Sentry opened a missed-check-in issue, then
flipped it to "regressed" the moment the run finally checked in. The terraform-drift GitHub
Actions workflow was **succeeding on every run** — this was not a real-failure detector
firing.

Concrete page: the 2026-06-01 18:00 UTC run landed at 21:34 UTC (214 min late), exceeding the
monitor's `checkin_margin_minutes = 180`; Sentry opened the miss at 21:00, then the
late-but-successful check-in flipped it to "regressed" (`recovery_threshold = 1`).

## Root cause

GitHub Actions does **not** honor `on.schedule` cron times precisely — under runner-pool load,
scheduled dispatch is delayed, often by hours. A `gh run list --workflow=<wf>.yml` survey of 115
scheduled runs over 58 days showed the `0 6,18 * * *` workflow's actual dispatch landing:
- 06:00 slot: median 134 min late, **max 339 min late** (overnight pool degradation is worst).
- 18:00 slot: median 80 min late, max 215 min late.
- ~11% of all deliveries exceeded the 180-min margin → ~11% of fires were eligible to page a
  false alarm.

The 180-min margin was sized for run *duration* + safety (the `README` "observed + 2x"
heuristic), not for *delivery jitter*. Applied to a GHA-fired cron, that under-sizes the margin.

## Solution

Raise `checkin_margin_minutes` to cover the observed worst-case delivery lateness with headroom,
while staying strictly **below the inter-fire interval** so a late run of one slot is never
misread as a missed run of the next:

- Chose **480 min (8h)**: covers the 339-min max with ~42% headroom, and 480 < the 720-min
  06:00→18:00 inter-fire gap, so genuine single-run misses still page within one cycle (real-miss
  sensitivity preserved).
- Sentry-as-IaC (ADR-031): the edit lands in `apps/web-platform/infra/sentry/cron-monitors.tf`
  and auto-applies via `.github/workflows/apply-sentry-infra.yml` on merge (it already
  `-target=`s the resource). No operator step.
- Workflow untouched — it is healthy.

## Key Insight

**The "missed check-in → immediately regressed" pair on a healthy cron is the signature of an
undersized `checkin_margin`, not a failing job.** Diagnose by comparing `gh run list` actual
`createdAt` against the cron schedule; size a GHA-fired monitor's margin to observed worst-case
delivery lateness (bounded by the inter-fire interval), not to run duration.

This is the established treatment for the **GHA-fired cohort** in `cron-monitors.tf`, distinct
from the Inngest-fired cohort (30-min margins — Inngest fires with ≤2-min jitter). Sibling
precedents: `scheduled_gh_pages_cert_state` = 240 (daily), `scheduled_realtime_probe` = 1440
(widened after GitHub *dropped* a whole run, #4189). 480 sits between them: > gh-pages because
this workflow's observed max exceeds gh-pages' tolerance; ≪ realtime-probe because the failure
mode here is *jitter*, not a *whole-run drop* (twice-daily firing recovers a single dropped run
within 12h regardless).

Distinct from the Inngest-desync false-miss class in
[[2026-05-27-sentry-cron-community-monitor-missed-checkin]] and
[[2026-05-30-inngest-cron-desync-regression-needs-runtime-self-heal-not-ci-guard]] — those are a
different substrate's drop, not GHA delivery jitter. See also
[[2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn]].

## Session Errors

1. **Branch fell behind `origin/main` mid-pipeline.** The plan+deepen subagent's
   `git fetch origin main` (collision scope-check) advanced local `origin/main` to include
   sibling PR #4769, which merged after this branch's base. `git diff origin/main` then listed
   the sibling's files as if this branch reverted them — a false scope-breach signal.
   **Recovery:** confirmed the only behind-commit (#4769) had no `cron-monitors.tf` overlap,
   `git rebase origin/main` (clean), force-push. **Prevention:** known behind-main stale-ref
   pattern ([[2026-05-21-bare-clone-working-files-drift-from-origin-main]]); always read the
   three-dot `git diff origin/main...HEAD` and re-check after a subagent that fetches. The clean
   post-rebase diff is the gate.
2. **Classification bash exited 127** (`ZSH_VERSION: unbound variable` from a sourced
   shell-snapshot under `set -u`). Harmless host-environment quirk; the classification data
   printed fine and was used. **Prevention:** none actionable in-repo (host shell-snapshot, not
   project code); don't treat a 127 whose stdout is complete as a hard failure without reading it.

## Tags
category: integration-issues
module: apps/web-platform/infra/sentry
