---
title: "Reverting a fallback that an alert keys on must preserve the emit; op-scoped alerts need a reverse-guard"
date: 2026-06-04
category: best-practices
module: observability
tags: [revert, sentry, reportSilentFallback, alert-contract, op-contract-test, tenant-isolation]
pr: 4929
related:
  - knowledge-base/project/learnings/best-practices/2026-05-30-routing-through-shared-tag-filtered-alert-primitive-needs-all-filter-tags.md
  - knowledge-base/project/learnings/2026-06-03-drift-guard-assertion-false-passes-on-comment-prose.md
---

# Reverting a fallback that an alert keys on must preserve the emit; op-scoped alerts need a reverse-guard

## Problem

PR #4929 reverted the #4913/#4919 service-role tenant-mint fallback in
`kb-route-helpers.ts` (dead code — PIR #4913 proved the mint failure was a
misdiagnosis). The fallback and its `reportSilentFallback(...)` emit were added
in the SAME diff, but a separate alert (#4920, `kb_tenant_mint_silent_fallback`,
`filter_match="all"`) keys on the emit's `op` slug. A naive `git revert -m` of
#4913 would have deleted the emit too, silently darkening the alert — recreating
the "latent for weeks" failure mode the alert exists to prevent.

The same PR added a new op-scoped alert (`kb_db_error`, `op IS_IN
"create,list,revoke,preview,preview-invariant"`). The first op-contract test
only guarded the FORWARD direction (each listed slug exists in both emit + tf
block). A new db-error op added to `kb-share.ts` would silently fall outside the
`IS_IN` value and never page, while the test stayed green.

## Solution

1. **Hand-revert, preserving the emit.** Separate the *recovery mechanism* (the
   `createServiceClient()` fallback — dead, remove it) from the *signal* (the
   `reportSilentFallback` emit — keep it, it is the alert's input). Return the
   pre-fallback error (503/403) but emit BEFORE the branch so every cause still
   fires the signal. Verified by a test asserting `reportSilentFallback` is still
   called with the exact `op` slug the alert filters on.

2. **Op-scoped alert needs a fail-closed reverse-guard.** Beyond the forward
   "each IS_IN slug exists in the emit file" assertion, add: every distinct
   `op: "X"` emitted in the (single-feature) emit file must be in the IS_IN value
   OR in an explicit `EXCLUDED_FROM_ALERT` list. This forces a conscious in/out
   decision when a new op is added. Also pin the structural predicates the alert
   semantics depend on (`filter_match = "all"`, op `match = "IS_IN"`,
   feature `match = "EQUAL"`) — a flip leaves slug-presence assertions green
   while breaking the alert.

## Key Insight

An alert's emit is a SEPARATE artifact from whatever recovery logic happened to
introduce it. When deleting recovery logic, grep every alert that filters on the
emit's tags (`filter_match="all"` rules AND on every tag) and confirm the emit
survives. Cross-artifact op-contract tests must guard BOTH directions — forward
(filter slug → emit exists) catches renames; reverse (emit op → filter covers it
or explicitly excludes it) catches the silent-drop of a newly-added op, which is
the higher-severity "alert never fires" class.

## Session Errors

- **Ran `vitest` from the bare-root `apps/web-platform` on the first RED check**
  → false "43 passed" against the stale synced copy; re-ran from the worktree-
  absolute path → correct "5 failed". Recovery: always `cd <worktree-abs> &&
  ./node_modules/.bin/vitest`. **Prevention:** already covered by the work
  skill's CWD-drift warning + learning `2026-04-19-admin-ip-drift-misdiagnosed-
  as-fail2ban.md`; no new rule needed.
- **The new frequency-uniqueness op-contract test false-FAILED on its own block
  comment** (`frequency=13` in prose matched the loose `frequency\s*=\s*13`
  regex → count 2). Recovery: line-anchored the regex to `^\s*frequency\s*=`
  (multiline) so only real HCL attribute lines count. **Prevention:** sibling of
  `2026-06-03-drift-guard-assertion-false-passes-on-comment-prose.md` (that one
  is false-PASS; this is the false-FAIL twin) — a drift-guard regex over a config
  file must anchor to the attribute-line shape, never a bare `key=value`
  substring that comment prose can satisfy. Already fixed inline.

## Tags
category: best-practices
module: observability
