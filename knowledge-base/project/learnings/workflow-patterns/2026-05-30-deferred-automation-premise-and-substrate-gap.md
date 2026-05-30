---
title: A `deferred-automation` issue's stated blocker is a hypothesis to re-verify, not a fact — and the real blocker may be a never-wired substrate
date: 2026-05-30
category: engineering
tags: [deferred-automation, sentry, observability, byok-delegations, verify-the-negative, terraform]
classification: workflow-patterns
sources: [PR #4653 (#4364), learning 2026-05-15-sentry-mcp-alert-rule-creation, learning 2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions]
---

# `deferred-automation` premise re-verification + substrate-gap discovery (#4364)

## What happened

Issue #4364 was filed with a `deferred-automation` label and a body asserting two
blockers for creating the BYOK Art. 33 Sentry alert rule:
1. "the Sentry alert-rule API is gated to UI-only for the action-shape configuration"
2. "there is no Sentry MCP server installed today"

Both were **false**. The repo already had `apps/web-platform/infra/sentry/` — a
full terraform IaC root (ADR-031) with 4 `sentry_issue_alert` resources, an R2
backend, and an auto-apply workflow. Sentry issue-alert `conditions`/`filters`/
`actions` are entirely API-settable (the "UI-only" claim conflated metric-alerts
with issue-alerts; see [[2026-05-15-sentry-mcp-alert-rule-creation]]). The work
was a routine extension of existing IaC, not a blocked operator task.

## The deeper trap — the real blocker was a never-wired substrate

The issue's acceptance criteria assumed PR-A (#4290) emitted an `art_33_breach=true`
tag on the cross-tenant path. A `verify-the-negative` grep proved it did NOT:

```
$ git grep -n "art_33_breach\|cross-tenant-violation" -- apps/web-platform
064_byok_delegations.sql:197:  -- TS layer can tag art_33_breach="true" on the Sentry event.
```

The ONLY hit was a SQL **comment** describing intent. The TS emitter never wired
it — the cross-tenant P0001 fell into the `merged-rpc-failure` catch-all,
indistinguishable from a transient DB error. **The alert rule's filter would have
matched zero events forever.** Building only the rule (the issue's literal AC)
would have shipped a dead control. The fix required wiring the missing emission
(`SilentFallbackOptions.art33Breach` → tag; a distinct `op=cross-tenant-violation`
branch in `cost-writer.ts`) FIRST, then the rule.

## How to apply

1. **Treat a `deferred-automation` body's stated blocker as a hypothesis to
   re-verify at re-activation, not a fact.** The deferral was written at a moment
   in time; the substrate (MCP servers, IaC roots, provider capabilities) drifts.
   Cheapest check: grep for the IaC root / provider resource type the task needs
   before accepting "no automation path exists." Hard rules
   `hr-exhaust-all-automated-options-before` + `hr-never-label-any-step-as-manual-without`
   apply at re-activation, not just at first triage.
2. **When an alert/monitor AC names a tag/metric, verify-the-negative that the
   emitter actually produces it** before building the consumer. A SQL comment, an
   ADR, or a plan describing a tag is not proof the tag is emitted. `git grep` the
   tag literal across the emitting layer; zero hits = unsatisfiable filter =
   build the emission first.
3. **Detection controls have a substrate dependency the AC often omits.** "Add an
   alert for X" silently assumes "X is observably emitted." Confirm the producer
   before the consumer, or the control ships dead and green.

## See also
- [[2026-05-15-sentry-mcp-alert-rule-creation]] — Sentry issue-alerts are API/terraform-settable
- [[2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions]] — distinct `frequency` avoids POST-time dedup
