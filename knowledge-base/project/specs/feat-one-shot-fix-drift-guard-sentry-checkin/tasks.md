---
title: "tasks: sister-workflow Sentry heartbeat consolidation (7 workflows + 1 IaC file)"
date: 2026-05-18
lane: single-domain
plan: knowledge-base/project/plans/2026-05-18-fix-drift-guard-sister-workflows-sentry-checkin-plan.md
related_issues: [3968, 3236]
related_pr_reference: 3964
status: pending
---

# Tasks — sister-workflow Sentry heartbeat consolidation

Derived from `knowledge-base/project/plans/2026-05-18-fix-drift-guard-sister-workflows-sentry-checkin-plan.md`.

## Phase 0 — Preflight (no edits)

- [ ] 0.1. Verify 7-workflow inventory via `grep -lE '"\$\{RUNNER_TEMP\}/sentry-checkin-id-' .github/workflows/scheduled-*.yml | sort` returns exactly the 7 files listed in plan frontmatter.
- [ ] 0.2. Capture per-workflow cadence baseline via `gh run list --workflow=<file>.yml --limit 12` for each of the 7 sisters; confirm proposed margins fit observed jitter.
- [ ] 0.3. Capture `actionlint` pre-edit baseline to `/tmp/actionlint-pre.txt` for diff-clean assertion.
- [ ] 0.4. Re-read canonical heartbeat shape at `.github/workflows/scheduled-oauth-probe.yml:528-559` (commit `c04ffd33`).

## Phase 1 — Apply heartbeat shape (one workflow at a time)

For each workflow: delete `in_progress` block + delete `ok`/`error` blocks + insert single `Sentry check-in (final)` heartbeat step per the per-workflow branch table in plan Phase 1.

- [ ] 1.1. `scheduled-community-monitor.yml` — `job.status` branch.
- [ ] 1.2. `scheduled-content-vendor-drift.yml` — `job.status` branch.
- [ ] 1.3. `scheduled-daily-triage.yml` — `job.status` branch.
- [ ] 1.4. `scheduled-github-app-drift-guard.yml` — dual-signal branch (`failure_mode` AND `tripwire.outcome`).
- [ ] 1.5. `scheduled-realtime-probe.yml` — `steps.probe.outputs.failure_mode` branch (mirrors oauth-probe).
- [ ] 1.6. `scheduled-skill-freshness.yml` — `job.status` branch.
- [ ] 1.7. `scheduled-terraform-drift.yml` — `steps.plan.outputs.exit_code` branch (0/2 → ok; 1 → error).

After each file: run `actionlint <file>.yml` and confirm no new findings vs. baseline before moving to next file.

## Phase 2 — Align cron-monitors.tf margins

- [ ] 2.1. Edit `apps/web-platform/infra/sentry/cron-monitors.tf`:
  - `scheduled_terraform_drift`: 30 → 180
  - `scheduled_github_app_drift_guard`: 15 → 180
  - `scheduled_daily_triage`: 60 → 240
  - `scheduled_realtime_probe`: 60 → 180
  - `scheduled_content_vendor_drift`: 60 → 90
  - `scheduled_skill_freshness`: keep 60 (insufficient cadence data)
  - `scheduled_community_monitor`: keep 60 (fits observed jitter)
- [ ] 2.2. Update header comment (lines 31-37) to note all 8 monitors are now heartbeat-shape post-rollout.
- [ ] 2.3. Run `terraform -chdir=apps/web-platform/infra/sentry fmt`.

## Phase 3 — Validation gates

- [ ] 3.1. `actionlint .github/workflows/scheduled-{community-monitor,content-vendor-drift,daily-triage,github-app-drift-guard,realtime-probe,skill-freshness,terraform-drift}.yml` → exit 0, no new findings.
- [ ] 3.2. `( cd apps/web-platform/infra/sentry && terraform init -backend=false -input=false && terraform validate )` → success.
- [ ] 3.3. `grep -lE '"\$\{RUNNER_TEMP\}/sentry-checkin-id-' .github/workflows/scheduled-*.yml` → zero hits (AC1).
- [ ] 3.4. `grep -cE '^      - name: Sentry check-in \(final\)$' .github/workflows/scheduled-*.yml` → 8 (AC6).
- [ ] 3.5. `grep -E '\?status=\$\{status\}.*\|\| true' .github/workflows/scheduled-*.yml` → zero hits (AC7).
- [ ] 3.6. `grep -cE '::warning::Sentry Crons secrets not configured' .github/workflows/scheduled-*.yml` → 8 (AC8).

## Phase 4 — Post-merge (operator)

- [ ] 4.1. After `apply-sentry-infra.yml` runs on merge, wait one cron cycle per monitor and verify each of the 8 monitors shows a fresh successful check-in in the Sentry UI (project `web-platform`, Cron Monitors).
- [ ] 4.2. Issue #3236 is ALREADY CLOSED (verified via `gh issue view 3236` → `closedAt: 2026-05-18T09:24:38Z` via `closedBy: 3964`). Do NOT issue a second close. Confirm it remains closed AND all 8 monitors green. If any monitor stays stale, `gh issue reopen 3236 --comment "Sister-rollout merged but monitor(s) <name-list> still stale — heartbeat plumbing or margin sizing needs follow-up."`
- [ ] 4.3. Verify Sentry alert `WEB-PLATFORM-4` (drift-guard "Last successful check-in: Never") auto-resolves within ~3h (one hourly cycle + 180-min margin); if not, manually mark resolved in Sentry UI AND investigate why heartbeat is not landing.
- [ ] 4.4. After the next monthly cron fire of `scheduled-skill-freshness` (first-of-month 02:00 UTC), capture actual lag via `gh run list --workflow=scheduled-skill-freshness.yml --limit 3` and re-check whether the 60-min margin fits observed cadence. If not, file a follow-up to bump.
