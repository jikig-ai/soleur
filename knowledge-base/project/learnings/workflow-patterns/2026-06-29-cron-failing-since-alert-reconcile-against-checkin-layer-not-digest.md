# Learning: a cron "failing since DATE" alert reconciles against the CHECK-IN layer, not the downstream artifact — and a docs-remediation can surface a SECOND distinct defect

category: workflow-patterns
module: inngest-cron-substrate / observability
date: 2026-06-29
refs: #5728, #5674, #5680; runbook cloud-scheduled-tasks.md H10; learning integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md

## Problem

A Sentry "Your Cron Monitors Aren't Working — failing since 2026-06-13" alert for
`scheduled-community-monitor` was routed through `/soleur:go → one-shot` as a fix.
The deepened plan reconciled the "June 13" date as imprecise and pinned a single
cause: fleet-wide Anthropic credit exhaustion starting **June 22** (the GitHub
fallback issues #5626→#5666 all carry `Credit balance is too low`). June 13–21 were
treated as "real digests = healthy."

A cheap authoritative live read at /work time falsified that reconciliation. The
**Sentry check-in timeline** (`GET /monitors/scheduled-community-monitor/checkins/`)
showed: last `ok` 2026-06-12; `missed` daily 06-13→06-21; `error` daily
06-22→06-29. So there were **two distinct failure regimes**, and the alert's
"failing since June 13" was *accurate against the check-in layer* (last ok 06-12) —
even though the GitHub digest layer kept producing real digests 06-13→06-21.

## Solution / Key Insight

Two reusable nuggets:

1. **Reconcile a "failing since DATE" cron alert against the SAME observability
   layer the alert is emitted from (the Sentry check-in heartbeat), not a
   downstream success artifact (the GitHub digest issue).** The two layers can
   disagree: a run that completes and files its issue can still post no `?status=ok`
   heartbeat (a check-in delivery/timing defect). Reading only the digest layer
   over-reports health and makes the alert date look "imprecise" when it is exact.
   This is the inverse of the "which green layer is lying" trap in the sibling
   learning — there the run-log lied high; here the digest layer lies high relative
   to the check-in layer.

2. **A docs-remediation that runs live diagnosis can surface a SECOND distinct
   defect the plan framed as one cause.** The credit-exhaustion regime (06-22→29)
   was the plan's whole story; the live read exposed a separate check-in-delivery
   defect (06-13→21). Correct move: keep the remediation scoped (credit + docs),
   and **file the second defect as its own follow-up (#5728)** rather than expanding
   the PR — the plan's own Risk section pre-authorized exactly this ("scope it as a
   follow-up"). Don't let a discovered second defect either bloat the PR or get
   silently absorbed into the first cause's narrative.

The general rule: when a one-shot plan's premise includes a *reconciliation of a
surprising input* (an alert date that doesn't match the codebase evidence), treat
the reconciliation as a hypothesis and run the cheapest authoritative read that
could falsify it BEFORE accepting it (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Session Errors

- **Plan premise (alert-date reconciliation) was partially wrong.** Recovery: ran
  the Sentry check-in-timeline GET; corrected the runbook + learning addendum and
  filed #5728 for the 06-13→21 delivery defect. **Prevention:** for any plan that
  reconciles a surprising alert/log value, run the authoritative live read at
  /work-start before depending on the reconciliation (this learning).
- **Plan's Phase 4 issue close-list was stale** (listed 06-19→21 real digests as
  fallbacks). Recovery: read each issue body, closed only the 8 real fallbacks
  (06-22→29). **Prevention:** the plan already said "re-enumerate at /work time" —
  honor that for any dated-issue list; verify shape (fallback vs digest) by body,
  not by date.
- **Mislabeled `SENTRY_IAC_AUTH_TOKEN` "read-only" in the runbook** while the same
  bullet instructed a PUT with it. Caught by 4 review agents concurring. Recovery:
  corrected to write-capable IaC token (`project:admin`/`alerts:write`).
  **Prevention:** before labeling a credential's scope in a runbook, verify it
  against the token-scope audit docs (`knowledge-base/legal/audits/2026-05-2*-sentry-token-*`),
  not from memory.
- **CWD-persistence foot-gun:** ran `cd apps/web-platform` twice; the second failed
  because the Bash tool persists CWD across calls. Recovery: absolute path.
  **Prevention:** already documented in work/SKILL.md — use absolute paths or a
  single `cd <abs> && <cmd>` per call. (one-off)
- **Cross-agent contamination:** a review agent reported the worktree "switched to
  main." Recovery: verified branch/HEAD intact via `git branch --show-current` +
  `git log`. **Prevention:** already a documented review sharp-edge — verify
  worktree state yourself before trusting an agent's branch-scope alarm. (one-off)

## Tags
category: workflow-patterns
module: inngest-cron-substrate
