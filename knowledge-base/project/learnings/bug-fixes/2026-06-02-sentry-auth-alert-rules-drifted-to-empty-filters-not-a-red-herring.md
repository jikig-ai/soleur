---
title: "\"triggered by auth-callback-no-code-burst\" was NOT a red herring — the 4 auth alert rules had drifted to empty filters and matched every issue"
date: 2026-06-02
category: bug-fixes
tags: [sentry, observability, alert-noise, alert-rule-drift, terraform, ignore_changes, feature-flags, false-assumption]
related_issues: [4781, 4571]
related_learnings:
  - knowledge-base/project/learnings/best-practices/2026-05-27-sentry-warning-level-still-triggers-alert-rules.md
  - knowledge-base/project/learnings/2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods.md
  - knowledge-base/project/learnings/bug-fixes/2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn.md
  - knowledge-base/project/learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md
---

# Learning: the "auth-callback-no-code-burst red herring" lore was wrong — verify the live rule before dismissing it

## Problem

A `/soleur:go` was triggered by a production Sentry **WARNING** on `GET /login`
(event `8563c7e88cc240c1a44d1427d4fdf33e`): `feature=feature-flags`,
`op=flagsmith.getIdentityFlags`, the expected debounced warn-mirror that **#4571
deliberately added**. The email said *"triggered by auth-callback-no-code-burst"*.

Two layers of wrong assumption nearly mis-routed the fix:

1. **The auto-generated plan proposed a code fix that #4571 had explicitly
   rejected** — adding a Flagsmith `defaultFlagHandler`. PR #4571's body says
   verbatim: *"No `defaultFlagHandler` added — it would delete the observability
   signal."* `lib/feature-flags/server.test.ts` even carries an **AC5 regression
   guard**: `expect(ctorArg).not.toHaveProperty("defaultFlagHandler")` with the
   comment *"Guards against re-introducing the rejected approach."* The planning
   subagent (sparse checkout) only read the top mock block and never saw the guard.

2. **The repo's own lore said the "auth-callback-no-code-burst" email line is a
   coincidental red herring** — stated in ≥5 learnings (cron-monitor,
   inngest-desync, uptime-fuse, etc.). That lore was treated as settled.

Both were false for THIS event.

## Root Cause

Pulling the live rule via the Sentry API (`GET /projects/{org}/{proj}/rules/`)
showed the truth: **all 4 auth issue-alert rules had `conditions: []` and
`filters: []`** with `actionMatch=all`/`filterMatch=all`. A Sentry issue alert
with zero filters matches **every** issue in the project — so
`auth-callback-no-code-burst` (intended filter `feature=auth AND
op=callback_no_code`) was emailing on a `feature=feature-flags` event. Not
coincidental — the rule genuinely fired, because it had no filters to exclude it.

The rules were `createdBy: web-platform-ci-…@proxy-user.sentry.io`,
`dateCreated: 2026-05-17` → created by **terraform** with the
`conditions_v2=[]`/`filters_v2=[]` placeholders from
`apps/web-platform/infra/sentry/issue-alerts.tf`, under
`lifecycle.ignore_changes=[conditions_v2, filters_v2, …]`. The intended filters
from `apps/web-platform/scripts/configure-sentry-alerts.sh` were never (re)applied
after the terraform CREATE, and `ignore_changes` then froze them empty. Nothing in
the audit pipeline asserts non-empty filters, so the drift was silent.

## Solution

Restored all 4 auth rules' `conditions`+`filters` to their
`configure-sentry-alerts.sh` definitions via a direct Sentry API PUT (live only;
`ignore_changes` means terraform will not revert it — that is the sanctioned
"filters managed out-of-band" model per ADR-031). Verified via re-GET that all 4
now report non-empty conditions+filters. Recurrence guard tracked in **#4781**.

## How to apply

- **An `auth-callback-no-code-burst` email is NOT automatically a red herring.**
  Before dismissing it (or any "triggered by <rule>" email), pull the live rule:
  `GET /api/0/projects/{org}/{project}/rules/` (token: Doppler prd
  `SENTRY_IAC_AUTH_TOKEN`/`SENTRY_AUTH_TOKEN`) and check the named rule's
  `conditions`+`filters`. **Empty filters = catch-all = it really did fire.**
  Only conclude "coincidental" after confirming the rule's filter cannot match
  the event's tags.
- **A Sentry-paste-driven plan is a hypothesis, not a work order.** When the plan
  prescribes a code change, grep the target file's tests for a guard that forbids
  exactly that change (`expect(...).not.toHaveProperty`, "rejected approach",
  "do not re-introduce") and read the cited prior PR's body BEFORE implementing.
  Here, AC5 + #4571's body together made the prescribed `defaultFlagHandler` a
  deliberate-revert.
- **`ignore_changes` on a resource's substantive attributes means that attribute
  is NOT version-controlled.** If the import/out-of-band step that was supposed to
  populate it is skipped or fails, the resource silently keeps its empty
  placeholder. Any "import-only + ignore_changes" design needs a positive audit
  assertion (non-empty filters) or it can drift to a catch-all without any signal.
