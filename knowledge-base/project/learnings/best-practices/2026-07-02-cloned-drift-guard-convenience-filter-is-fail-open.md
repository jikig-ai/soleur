---
title: A cloned drift-guard block's convenience type/scope filter is fail-OPEN — mirror the precedent's breadth or fail closed
date: 2026-07-02
category: best-practices
module: plugins/soleur/test
tags: [drift-guard, parity-test, fail-closed, precedent-clone, terraform-target, code-review]
issue: 5884
pr: 5910
---

# Learning: a cloned drift-guard's convenience filter is fail-open

## Problem

#5884 extended the terraform `-target` parity guard
(`plugins/soleur/test/terraform-target-parity.test.ts`) to cover the Sentry apply
pipeline (`apply-sentry-infra.yml`) — a verbatim structural clone of the existing
#5566 non-SSH block (`extractAllResources ∪ extractAllTargets + a frozen exclusion
Set`). The clone added one "for-relevance" convenience over the precedent:

```ts
sentryResources = listSentryTfFiles()
  .flatMap((f) => extractAllResources(stripComments(readFileSync(f, "utf8"))))
  .filter((a) => a.startsWith("sentry_"));   // <-- not in the #5566 precedent
```

The filter reads as harmless (the sentry root contains only `sentry_*` resources
today, so it is a no-op). But it is **fail-OPEN by construction**: the guard's entire
purpose is to flag a *new managed resource that was forgotten in the `-target` list*.
A future non-`sentry_` resource added under `infra/sentry/*.tf` (a `random_password`,
`doppler_secret`, `null_resource`) would be silently `.filter`ed out of the parity
check and could ship un-applied — precisely the #5566 silent-un-applied class the
guard exists to prevent.

A second, related divergence: the new block passed the workflow text to
`extractAllTargets` **raw**, so a commented-out `# -target=sentry_issue_alert.foo`
line would be counted as "covered" — masking a real un-applied resource (the same
inert-alert class).

## Solution

- **Drop the convenience filter.** The precedent checks *every* discovered resource
  against `targets ∪ exclusions` with no type filter — mirror that breadth. Removing
  the `.startsWith("sentry_")` filter is a no-op today (all managed resources are
  `sentry_`) yet makes a future off-type resource **fail closed** (flagged uncovered)
  instead of vanishing from the check.
- **Comment-strip the workflow text before extracting targets** (fold `stripComments`
  into `extractAllTargets` so both the #5566 and #5884 blocks are comment-safe with no
  asymmetry). Verified no-op against the current workflows.

Both were caught by `pattern-recognition-specialist` (fail-open filter, P3) and
`test-design-reviewer` (comment-strip asymmetry, MEDIUM) at post-implementation
multi-agent review — not by the RED→GREEN cycle, which was green with the filter in
place because the divergence is invisible on today's corpus.

## Key Insight

When you clone a drift/parity guard, any filter, narrowing, or "only look at the
relevant subset" convenience the clone adds over its precedent is a **fail-open
suspect**: it can pass green today while silently shrinking the set the guard
protects. The precedent's *breadth* is load-bearing, not incidental. Two mechanical
checks before merging a cloned guard:

1. **Diff the discovery/coverage predicate against the precedent line-by-line.** Any
   `.filter(...)` / narrower regex / extra guard the clone adds but the precedent
   lacks must be justified as fail-*closed*, or dropped.
2. **Both sides of a parity check must be normalized identically.** If the
   resource side is comment-stripped, the target/workflow side must be too — a
   one-sided strip lets a disabled entry on the un-stripped side read as "covered."

A cloned guard that is green on today's corpus is necessary but not sufficient; its
fail-closed-ness is only visible by comparing its breadth to the precedent's.

## Session Errors

1. **Plan-phase `Write` blocked by the IaC-routing PreToolUse hook** (flagged the word
   "operator" in the post-merge framing). — Recovery: added the documented
   `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out after confirming the
   change routes entirely through the existing `apply-sentry-infra.yml` terraform path
   (no SSH/manual provisioning). — Prevention: none needed — the ack comment is the
   designed escape hatch for a genuinely-in-terraform-path change; used correctly.
   One-off.
2. **`grep -c <pattern>` returned `0` (exit 1) and broke an `&&`-chained verification
   command**, silently skipping the insertion-anchor grep that followed it. — Recovery:
   re-ran the anchor grep as its own command. — Prevention: for count-then-continue
   verification, either append `|| true` to the `grep -c`, or split independent
   verification greps into separate commands rather than `&&`-chaining them. One-off
   bash gotcha.

## Tags
category: best-practices
module: plugins/soleur/test
