---
title: "TR9 PR-6 — gh CLI absent from Hetzner Dockerfile blocks bash-spawn; apply-sentry-infra.yml -target= list is not a wildcard"
date: 2026-05-25
type: learning
pr: 4416
umbrella: 3948
tags:
  - tr9
  - inngest
  - cron-substrate
  - sentry-monitor
  - terraform
  - dockerfile
  - octokit
  - github-actions
---

# TR9 PR-6 Learning — Two deepen-pass discoveries

Two load-bearing corrections caught by the `/soleur:deepen-plan` pass on
the v1 PR-6 plan. Both shipped as part of the migration; both will recur
on future TR9 children unless internalized.

## (a) `gh` CLI is NOT in `apps/web-platform/Dockerfile` → port to Octokit, do not spawn

### Discovery

V1 plan envisioned `spawn("/bin/bash", ["scripts/strategy-review-check.sh"], …)`
inside an Inngest `step.run` — the simplest possible migration for a
shell-only cron. The plan assumed the script could be re-fired verbatim
from the Hetzner runtime.

Reading `apps/web-platform/Dockerfile:57-59` at deepen-pass time:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git bubblewrap socat qpdf \
    && rm -rf /var/lib/apt/lists/*
```

`gh` (GitHub CLI) is NOT in that apt list. The script calls `gh label
create`, `gh issue list`, and `gh issue create` — every operation is `gh`.
Spawning the script in production would have failed at runtime with
`gh: command not found` for every cron fire.

### Decision

**Port the script's logic to TypeScript using `@octokit/core` + `gray-matter`**
rather than install `gh` in the Dockerfile.

Rationale:

1. **Blast radius**: installing `gh` adds an apt-source (GitHub's keyring),
   a version pin to maintain, and broadens the production runtime surface
   for one-off cron use. The TS port is local to the cron file.
2. **PR-5 precedent**: `cron-bug-fixer.ts` already does all GH operations
   via Octokit (35 invocations, zero `gh` spawns). The pattern is
   established; PR-6 is its first pure-TS application.
3. **Reversibility**: the script (`scripts/strategy-review-check.sh`)
   stays on disk for operator-local hand-testing where `gh` IS installed.
   It is no longer the cron's runtime contract; the TS port is.

### Sharp edges that come with the port

- **`parseISODate` is stricter than `date -d`**: the TS port only accepts
  `YYYY-MM-DD`. Bash `date -d "Mon May 25 2026"` parsed; the TS port
  rejects and counts the doc as `errors++`. This is intentional (rejects
  ambiguous shapes) but is a behavioral divergence.
- **Milestone resolution requires an extra request**: `gh issue create
  --milestone "Post-MVP / Later"` accepts the title; Octokit REST requires
  the integer `number`. The TS port calls
  `GET /repos/{owner}/{repo}/milestones?state=open` first and falls back
  to creating the issue without a milestone on miss (matches script's
  `|| true` fallback).
- **Script-vs-TS drift hazard**: the bash script and TS port now live in
  parallel. Any future edit to the script's cadence map, dedup label, or
  scope directories MUST be mirrored in the TS port. A header comment on
  the script noting the dual-source contract is a recommended follow-up.

### When to install `gh` in the Dockerfile instead

The "port to Octokit" decision is sized to a single cron. If a future
TR9 child also depends on `gh`, the cost equation flips: one apt-source
addition vs. another full TS port. Suggested threshold: **the third TR9
child needing `gh`**, file as a `chore` Dockerfile-update PR.

### Plan-time verification rule

When planning any cron migration whose source is a bash script:

```bash
# 1. Enumerate the script's external CLI dependencies.
grep -nE '^\s*(gh|aws|gcloud|curl|jq|az) ' scripts/<name>.sh

# 2. Confirm each is present in the runtime container.
grep -nE 'gh|aws|gcloud|jq|az' apps/web-platform/Dockerfile

# 3. If any are missing, decide port-to-TS vs. install-in-Dockerfile
#    BEFORE writing the spawn() call.
```

## (b) `apply-sentry-infra.yml` `-target=` list is NOT a wildcard

### Discovery

V1 plan assumed adding a new `sentry_cron_monitor.*` resource to
`apps/web-platform/infra/sentry/cron-monitors.tf` would auto-apply on the
next push to main. The `cron-monitors.tf` file header even implies this
("auto-applies via apply-sentry-infra.yml").

Reading `.github/workflows/apply-sentry-infra.yml:168-179` at deepen-pass
time:

```yaml
terraform plan \
  -target=sentry_cron_monitor.scheduled_terraform_drift \
  -target=sentry_cron_monitor.scheduled_oauth_probe \
  -target=sentry_cron_monitor.scheduled_github_app_drift_guard \
  -target=sentry_cron_monitor.scheduled_daily_triage \
  -target=sentry_cron_monitor.scheduled_realtime_probe \
  -target=sentry_cron_monitor.scheduled_skill_freshness \
  -target=sentry_cron_monitor.scheduled_content_vendor_drift \
  -target=sentry_cron_monitor.scheduled_community_monitor \
  -target=sentry_cron_monitor.scheduled_gh_pages_cert_state \
  -target=sentry_cron_monitor.scheduled_follow_through \
  -no-color -input=false -out=tfplan
```

This is an **explicit allow-list**, NOT a wildcard. Every new resource
must be added by hand. Without the same-commit YAML edit, the new
resource would land in TF state only when a sibling-resource drift
forced a full re-target — operationally invisible until then.

### Decision

Add `-target=sentry_cron_monitor.scheduled_strategy_review` to the
workflow's `-target=` list in the same commit as the TF resource
definition. Promoted to PR-6 AC6b as a hard gate.

### Sibling-PR gap discovered in passing

PR-5's `scheduled_bug_fixer` is also missing from this list — the same
operational silence PR-6 v1 would have had. PR-6 does NOT fix this in
scope (strict single-PR scope per K8); filed as follow-up tracking issue
"Add scheduled_bug_fixer to apply-sentry-infra.yml -target= list (TR9 PR-5
follow-up)" for post-merge triage.

### Plan-time verification rule

When adding a `sentry_cron_monitor.*` resource:

```bash
# Current entries in the allow-list (will become N+1 after this PR).
grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml

# After your edit, the count MUST increment by 1 per new resource.
```

Document this as a binding AC on every TR9 child plan that adds a
Sentry cron monitor. The `-target=` list should not be silently widened
to a wildcard — explicit allow-listing is a feature, not a bug (prevents
unintended apply of work-in-progress resources).

## Cross-cutting takeaway

Both gotchas share a shape: **a v1 plan assumed runtime infrastructure
parity with an assumed-default environment** (gh-in-the-container for
shell scripts; wildcard-target for Terraform). Both were caught by
reading the relevant file directly at deepen-pass time. The lesson is
not "do more verification" — it's "verify the specific file paths the
plan depends on existing/working/being-wildcarded as described".

Generalize: at deepen-plan time, every plan claim of the form "X is
configured to do Y automatically" must be backed by a Phase 0
`grep -nE 'pattern' path/to/file` step that pins the exact line(s)
making the claim true.

## Session Errors

**1. One-shot picked an already-migrated workflow because the umbrella body was stale.**
Initial `/soleur:go` routed `/soleur:one-shot` to `scheduled-bug-fixer`, but PR #4377 had merged that migration ~3h earlier and the umbrella #3948 checkbox list still showed `[ ]`. Planning subagent caught the contradiction at first preflight (target YAML missing on main; `cron-bug-fixer.ts` exists). Recovery: closed empty draft PR #4398, removed worktree + branch (local and remote), updated umbrella body to mark PR-5 done, re-routed to `scheduled-strategy-review`.
**Prevention:** /soleur:one-shot should add a pre-worktree check for TR9-shape migrations: if `apps/web-platform/server/inngest/functions/cron-<workflow-slug>.ts` exists OR `.github/workflows/scheduled-<workflow-slug>.yml` is absent on main, abort with "this workflow is already migrated; pick another from `gh issue view 3948`". Cheap one-grep gate that closes the failure class.

**2. Plan-quoted `-target=` count was stale.** Plan said the allow-list had 11 entries; actual was 10 because PR-5's bug-fixer didn't add itself. Caught at Phase 0 grep, used the corrected 10→11 transition. Confirms the existing "plan-quoted numbers are preconditions to verify" rule fired correctly; no new prevention needed.

**3. `bun test` invocation in plan/tasks; app uses vitest.** `bunfig.toml` has `pathIgnorePatterns = ["**"]` blocking bun test discovery (defense against happy-dom corruption of native APIs; see #1469). Switched to `./node_modules/.bin/vitest run`. **Prevention:** plan/tasks templates that prescribe test commands inside `apps/web-platform` should detect `bunfig.toml` `pathIgnorePatterns = ["**"]` and prescribe vitest, not bun.

**4. P1 gray-matter Date coercion caught only at review (zero TS unit tests had a real `matter(...)` fixture).** See sibling learning `2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap.md` for the full root-cause + prevention pattern.

**5. Bash CWD does not persist across separate Bash tool calls.** Repeated session-wide gotcha; recovered via single chained `cd <abs-path> && cmd`. Already documented as `2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md` session errors; reproduced here as a reminder. No new prevention proposed.
