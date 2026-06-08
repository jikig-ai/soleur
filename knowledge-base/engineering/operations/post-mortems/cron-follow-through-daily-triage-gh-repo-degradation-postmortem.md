---
title: "scheduled-follow-through (+daily-triage) crons failed every run for ~2 weeks — gh missing GH_REPO in /app"
date: 2026-06-08
incident_pr: 5011
incident_window: "2026-05-27 → 2026-06-08 (~12 days; follow-through ~9 weekday failures, daily-triage silently degraded)"
recovery_at: "2026-06-08 (on merge of PR #5011 + container restart)"
suspected_change: "TR9 PR-2 migration of the crons from a checked-out GitHub Actions workflow to the Inngest /app container — gh lost git-remote repo resolution and buildSpawnEnv never set GH_REPO."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - silent ops degradation of scheduled automation (no uptime/error-rate signal beyond the cron monitor)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The Inngest cron `cron-follow-through-monitor` (`0 9 * * 1-5`) posted a Sentry
**error check-in every weekday run** from 2026-05-27 onward. The follow-through
monitor's job — checking open `follow-through` issues for SLA/escalation/auto-close
— did not run; the eval's `gh issue list` (and every agent `gh issue view/edit/close`)
failed:

```
Command failed: gh issue list --label follow-through --state open --json number,title,body --limit 100
failed to run git: fatal: not a git repository (or any of the parent directories): .git
```

`gh` was authenticated (the cron mints a GitHub App installation token into
`GH_TOKEN`) but could not resolve the **target repo**. The cron runs `gh` from
the prod Next.js container CWD `/app`, which is not a git checkout — and unlike
the audit/bug-fixer crons it never clones a repo (it only touches issues).
`gh`'s repo precedence is `--repo` > `GH_REPO` env > git-remote of CWD; with no
`--repo`, no `GH_REPO`, and no `.git`, it fell through to git-remote detection
and failed.

The sibling cron `cron-daily-triage` (`0 4 * * *`) carried the **identical latent
defect** but degraded more quietly — its agent's `gh` calls failed individually
inside the eval rather than producing a single hard `execFileSync` error, so its
monitor red signal was weaker. Both shared the same root cause and fix.

## Status

resolved — PR #5011 added `GH_REPO` to both crons' `buildSpawnEnv`; the merge
restarts the container and the next scheduled run posts an OK check-in. A CI
source-shape test asserts `GH_REPO` is present so the gap cannot silently re-open.

## Symptom

`scheduled-follow-through` Sentry cron monitor red (error check-in) every weekday;
follow-through issues silently un-tracked; daily-triage labels silently un-applied.

## Incident Timeline

- **Start time (detected):** 2026-06-08 (operator noticed the Sentry "Cron failure: scheduled-follow-through" email)
- **End time (recovered):** 2026-06-08 (PR #5011 merge + container restart)
- **Duration (MTTR from detection):** same-day. Latent failure window: ~12 days (firstSeen 2026-05-27).

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-05-27 | First failed run after the TR9 PR-2 Inngest migration (Sentry WEB-PLATFORM-W firstSeen). |
| human | 2026-06-08 | Operator forwards the Sentry cron-failure email and asks to verify the fix state. |
| agent | 2026-06-08 | Pulled the WEB-PLATFORM-W event stderr → root cause (`fatal: not a git repository`); filed #5010. |
| agent | 2026-06-08 | PR #5011 adds GH_REPO to both crons + behavioral tests; merges. |

## Participants and Systems Involved

- Inngest crons `cron-follow-through-monitor` + `cron-daily-triage` (no-clone, `/app` CWD).
- Sentry cron monitors `scheduled-follow-through` (`3f5e80d3-…`) + `scheduled-daily-triage`.
- `gh` CLI repo resolution; GitHub App installation token.

## Detection (+ MTTD)

- **How detected:** external/manual — the operator noticed the Sentry cron-failure
  notification email and asked to verify. The monitor had been red for ~12 days;
  the alert was not acted upon until the operator surfaced it.
- **MTTD:** ~12 days from first failure to operator action. The monitor *did* page
  (red check-in) from day one — the gap was **alert action**, not alert absence,
  for follow-through; for daily-triage the signal itself was weaker (no hard error).

## Triggered by

system — a latent gap (`GH_REPO` never set) introduced when the cron moved from a
checked-out CI runner to the no-checkout Inngest container.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `buildSpawnEnv` lacks `GH_REPO`; no clone → `gh` can't resolve repo in `/app` | Sentry stderr `fatal: not a git repository`; `grep -c GH_REPO` = 0 in the file; `GH_REPO=cli/cli gh repo view` resolves from an unrelated CWD (live-verified) | none | confirmed |

## Resolution

Added `GH_REPO: \`${REPO_OWNER}/${REPO_NAME}\`` (→ `jikig-ai/soleur`) to
`buildSpawnEnv` in both crons (imported from `./_cron-shared`). One env field
fixes the `execFileSync` prefetch and every agent-spawned `gh` call. Behavioral
tests assert `GH_REPO` on every spawn env + an ambient-override positive control.

## Recovery verification

- `tsc --noEmit` clean; `test/server/inngest/` 1528 green; `scripts/test-all.sh` 100/100.
- Post-merge (self-verifying): the `scheduled-follow-through` / `scheduled-daily-triage`
  Sentry monitors flip from error to OK on the next weekday/daily run after the
  container restart; a still-red check-in re-pages (no operator dashboard-watching,
  per `hr-no-dashboard-eyeball-pull-data-yourself`).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did follow-through/triage stop working?** The eval's `gh issue …` commands failed.
2. **Why did `gh` fail?** It could not resolve the target repo.
3. **Why couldn't it resolve the repo?** It ran from `/app` (no `.git`, no clone) with no `GH_REPO` and no `--repo`, so git-remote detection failed.
4. **Why was `GH_REPO` absent?** The cron migrated from a checked-out GitHub Actions workflow (where `gh` derived the repo from the git remote) to the Inngest `/app` container; `buildSpawnEnv` was carried over setting `GH_TOKEN` but not `GH_REPO`.
5. **Why did it run ~12 days before action?** The follow-through monitor red check-in paged but was not acted on (alert fatigue / low-priority operator-dogfood surface); daily-triage's failure produced a weaker signal (per-call gh failures, not one hard error).

## Versions of Components

- **Version(s) that triggered:** all cron versions after the TR9 PR-2 Inngest migration (~2026-05-27).
- **Version(s) that restored:** PR #5011.

## Impact details

### Services Impacted

Two scheduled operator-automation crons: follow-through SLA tracking/escalation/auto-close, and daily issue triage labeling. Both ran but did no useful work.

### Customer Impact (by role)

- Prospect / Authenticated app user / Legal signer / Billing customer / OAuth owner: none — operator-internal automation only.
- Admin via Access: degraded — the founder's follow-through SLA tracking and daily-triage backlog labeling silently stopped for ~12 days.

### Revenue Impact

None.

### Team Impact

Solo operator's issue-hygiene automation was unreliable for ~12 days; the stale backlog had to be re-triaged manually until the fix.

## Lessons Learned

### Where we got lucky

The follow-through monitor produced a hard `execFileSync` error (→ Sentry event with stderr), making the root cause one event-fetch away. Had only the silent daily-triage shape existed, diagnosis would have been much harder.

### What went well

The fix generalized to the sibling cron immediately (pattern-recognition confirmed the two are the only no-clone gh-using crons); a CI source-shape test prevents recurrence.

### What went wrong

(a) `GH_REPO` was dropped silently during the CI→Inngest migration — authentication was migrated, repo-resolution context was not. (b) A red cron monitor paged for ~12 days without action (alert-action gap). (c) daily-triage's failure mode produced a weaker signal than follow-through's.

## Follow-ups

- [x] Add `GH_REPO` to both crons + behavioral tests + CI source-shape guard (PR #5011).
- [ ] Consider strengthening daily-triage's failure signal so per-call `gh` failures surface as a hard error check-in (not just a silently-degraded run) — same detection-gap class as the follow-through heartbeat keying on artifact-creation. (Non-blocking; the GH_REPO fix removes the failure source; this is detection hardening for the next no-clone-gh regression.)

## Action Items

- The flag-absence recurrence is gated by the CI source-shape test in PR #5011 — no separate issue.
- The daily-triage detection-signal hardening is captured in Follow-ups; promote to an issue only if a future no-clone-gh regression recurs with a too-weak signal.
