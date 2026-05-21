---
title: "PR-body Post-merge sections accrete operator handoffs that hard rules already forbid; gate them at gh pr ready"
date: 2026-05-21
tags: [workflow, ship, operator-handoff, hr-never-label-any-step-as-manual-without, wg-block-pr-ready-on-undeferred-operator-steps]
related_prs: [4227]
related_issues: [4211]
related_rules:
  - hr-exhaust-all-automated-options-before
  - hr-never-label-any-step-as-manual-without
  - wg-block-pr-ready-on-undeferred-operator-steps
  - hr-when-a-workflow-concludes-with-an
  - hr-no-dashboard-eyeball-pull-data-yourself
---

# Post-merge sections accrete operator handoffs that hard rules already forbid

## Symptom

`/soleur:work` repeatedly produces PR bodies whose `## Post-merge` (or `## Operator follow-ups`) section lists 3-5 items the agent could have done inline. Recurring example (PR #4227, TR9 PR-3 oauth-probe Inngest migration):

1. "Verify Doppler prd has `OAUTH_PROBE_GITHUB_CLIENT_ID` + `SUPABASE_PROJECT_REF` set before merge"
2. "T+90 min: confirm Sentry `?status=ok` check-in"
3. "T+24h: confirm Sentry issue auto-resolves"
4. "Within 48h: file TR9 PR-4 follow-up issue per AC25"

All four are inline-automatable:

- (1) `doppler secrets get … --plain` to probe; `doppler secrets set` to remediate when source values exist elsewhere in Doppler.
- (2)/(3) The Sentry monitor already has `failure_issue_threshold = 1` + `recovery_threshold = 1` — the monitor IS the verification (`hr-no-dashboard-eyeball-pull-data-yourself`); the operator-eyeball bullet was duplicate of an already-automated alert path.
- (4) `gh issue create` with the template the bullet itself described.

The user surfaced this with "why do you keep adding operator follow ups? please modify the workflow so those things are entirely automatically driven by Soleur from now on. It's been happening over and over again this week."

## Root cause

Three hard rules forbid this pattern (`hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`, `wg-block-pr-ready-on-undeferred-operator-steps`) and a gate existed at `/ship` Phase 5.5 — but:

1. **The gate fired at `/ship`, not at `gh pr ready`.** When the agent skipped `/ship` (or invoked `gh pr ready` directly during `/work`'s post-implementation pipeline), the gate never ran.
2. **The detection regex was too narrow.** It matched `operator (run|create|provision|configure|paste|copy)` but missed `Operator:` (with colon, bullet-heading shape), `Operator verify/confirm/check/file/set/...`, `T+<N><units>` verification bullets, `Within <N>h of merge: file/run/verify`, and the legacy `AC<N>:` form (only `AC-PM<N>` was caught).
3. **The agent had no Phase 4 self-audit step.** The work skill's Phase 4 (handoff) had a Playwright-first audit + entry-guard but no symmetric audit on the PR-body itself; the agent's only forcing function was at the gate.

## Fix

1. **New PreToolUse hook**: `.claude/hooks/ship-operator-step-gate.sh`. Intercepts `gh pr ready` / `gh pr merge --auto` (and chained forms via `&&`/`;`/`||`); reads the PR body via `gh pr view`; runs an expanded regex (4 groups: explicit operator/manual declarations with extended verb set, `T+<N><units>` verification bullets, `Within <N>h of merge: <verb>` bullets, legacy `AC-PM<N>`); for each match requires a `(Tracks|Refs) #<N>` companion to an OPEN issue whose body carries the `deferred-automation` / `automation gap` sentinel. Override: `SOLEUR_SKIP_OPERATOR_STEP_GATE=1` (rare attestation case).
2. **Work skill §Post-Merge Section Self-Audit (HARD GATE)**: after drafting the PR body and BEFORE `gh pr ready`, scan every line under `^##\s+(Post-?merge|Operator|Follow-?ups?)` headings; classify each bullet against a 6-row pattern→action table (Doppler verify → `doppler secrets get`; `Within Nh: file <issue>` → `gh issue create` NOW; Sentry/monitor verify → the monitor IS the gate; genuine operator-only → file `type/chore deferred-automation` tracked issue; default → inline-execute).

The hook closes the bypass; the skill text gives the agent the active resolution playbook so the hook rarely needs to deny.

## How to apply

- Touched a PR body's `## Post-merge` / `## Operator` section? Run the self-audit table before `gh pr ready`. Inline-execute the resolvable items; for the residual genuine handoffs, file `type/chore deferred-automation` issues and add `Tracks #N` next to each.
- New gate written? Wire it as a PreToolUse(Bash) hook so it fires regardless of which skill the agent invokes — gating via skill-internal prose alone has reliably bypass-prone failure modes.
- When the agent surfaces a "T+<N> dashboard verify" bullet, ask: does the monitor already alert on the bad path? If yes, the bullet duplicates an automated signal and should be deleted (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Verification

After this PR lands, the next `gh pr ready` invocation on a PR whose body contains an undeferred `Operator:` / `T+<N>h verify` / `Within Nh of merge: file` bullet will be DENIED at the PreToolUse hook, with a structured message listing every match and the three resolution paths (inline, file deferred-automation issue, override).
