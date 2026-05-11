---
name: Manual workflow_dispatch substitutes for first-scheduled-tick verification
date: 2026-05-11
category: best-practices
tags: [github-actions, follow-through, workflow-dispatch, verification, bundling]
related_issues: [3604, 3605]
related_prs: [3559, 3606]
---

# Learning: Manual workflow_dispatch substitutes for first-scheduled-tick verification when the external blocker resolves mid-cycle

## Problem

A follow-through issue (#3604) tracked the **first weekly cron tick** of a
newly-merged `scheduled-compound-promote.yml` workflow as its acceptance
gate. The actual first scheduled tick the day after merge (#3559) failed not
because the workflow was broken, but because an unrelated external
dependency (Anthropic API credit balance) had run dry. That failure was
also the catalyst for a sibling bug filing (#3605: preflight hard-fails on
HTTP 400 "credit balance is too low" instead of soft-skipping).

When the operator topped up credits during a fresh brainstorm session, the
naive default was to **wait ~7 days for the next scheduled tick** to
re-validate. That defers signal a full week and risks losing context.

The naive alternative was to **bundle dispatch + fix into the same PR** —
which couples two operationally-independent risks (validation-on-real-data
vs. preflight-classification-correctness) and gates the validation signal
on review-cycle time.

## Solution

Treat the two concerns as **independent tracks**:

- **Track A (validation):** Manual `gh workflow run <workflow.yml> --ref main`
  on the unblocked state. The dispatch exercises the same workflow file,
  same gates, and same code path as the scheduled tick — the only
  unexercised surface is the cron trigger itself (which is GitHub Actions
  infrastructure, not project code, and effectively zero-risk).
- **Track B (fix):** The preflight classification bug ships on a feature
  branch as a normal PR — completely independent of Track A.

Closing condition for the follow-through issue: a green dispatch run
where either (a) a draft PR opens with all synthetic check-runs posted, or
(b) the no-op path runs cleanly with `promotion-log.md` unchanged. **Both
outcomes count as validated.** The original issue text ("first weekly cron
tick") is a literal description, not a load-bearing constraint —
substitute manual dispatch when the underlying intent ("the loop runs on
real data") is preserved.

## Key Insight

A follow-through issue's literal trigger condition ("first scheduled cron
run") is the cheapest description of the verification, **not the
verification itself**. When the actual gate is "the workflow successfully
executes on real data," any invocation method that exercises the same code
path qualifies — and `workflow_dispatch` does. The cron trigger is only
load-bearing if you're explicitly validating the cron expression, which is
rarely the actual concern.

Corollary: when bundling a follow-through verification with an adjacent bug
fix from the same parent PR, **never couple them into one PR**. They
present as related because they share a parent, but the failure modes,
review cycles, and rollback semantics are orthogonal. Independent tracks
keep both fast.

## Prevention

When opening a follow-through issue whose validation runs on a schedule
(weekly cron, monthly job, deploy probe), include an explicit
`Alternative validation:` line in the issue body naming the
`workflow_dispatch` equivalent. Future operators (or agents)
encountering the same blocker won't need to re-derive that the literal
trigger is substitutable.

Template for `scheduled-*.yml` follow-through issues:

```markdown
## Verification

```yaml
type: manual
sla_business_days: 14
alternative: gh workflow run <name>.yml --ref main  # equivalent to scheduled tick
```
```

## Session Errors

- **Bash CWD drift across `cd && bash ...` compound commands.**
  Recovery: ran `pwd` to diagnose, switched to relative paths from the new CWD.
  Prevention: covered by `2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`
  session errors — Bash tool persistent CWD is a known footgun. No new rule needed.

## Tags

- category: best-practices
- module: github-actions
