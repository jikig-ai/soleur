---
title: A drift-guard's canonical mirrors the SSOT, not live — live-probe the audited resource at review time
date: 2026-07-05
category: best-practices
tags: [drift-guard, audit, review, live-probe, infra-drift, ci-ruleset]
issues: [6061]
pr: 6070
---

# A drift-guard's canonical mirrors the SSOT, not live — live-probe the audited resource at review time

## Problem

When you ship an audit/drift-guard whose canonical snapshot mirrors an **imperative
SSOT** (a `create-*.sh` script, a `.tf`, a config file), the canonical and the
LIVE resource it audits can already be diverged before your PR even lands. The
plan's tempting post-merge AC — "the first cron run completes green against the
live resource, no false-positive" — is a *hypothesis that assumes live == SSOT*,
not a fact.

Concretely (#6061, the CLA Required ruleset drift guard): the plan built a canonical
JSON mirroring `scripts/create-cla-required-ruleset.sh` (which requires
`cla-check` + `cla-evidence`), enforced canonical==SSOT with a sync gate, and
asserted a green first run. All the file-vs-file gates were internally consistent
and green. But a review-time `gh api repos/.../rulesets/13304872` probe showed the
**live** ruleset required only `cla-check` — `cla-evidence` (added to the SSOT by
a prior PR #3201) was never reconciled onto live. So the audit's very first run
would (correctly) file a TRUE-POSITIVE "required_status_checks dropped a gate"
critical drift issue, contradicting the "green first run" AC.

## Solution

At **review time**, live-probe the exact resource the audit will compare against —
do not trust the plan's "first run green" assumption or the SSOT's stated values
(`hr-no-dashboard-eyeball-pull-data-yourself`; "plan-quoted numbers are
preconditions to verify"). One `gh api`/`curl` read is cheap:

```bash
gh api repos/jikig-ai/soleur/rulesets/13304872 \
  --jq '{enforcement, bypass_actors:[.bypass_actors[]|{actor_id,actor_type,bypass_mode}],
         required_status_checks:[.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks[]|{context,integration_id}]}'
```

Then reconcile the finding **the honest way**:
- Keep the canonical mirroring the SSOT (that IS the desired state; corrupting it
  to match a drifted live state would defeat the guard and break the sync gate).
- Do NOT silently mutate production (e.g. run the create-script against live) as a
  side effect of a drift-guard PR — that can be a merge-blocking branch-protection
  change and is an operator/CTO call.
- Surface the pre-existing live drift explicitly (a decision-challenge + corrected
  AC + operator action), and let the audit file its true-positive on first run.
  The first-run drift issue is the feature *working*, not noise.

## Key Insight

A drift guard's job is to compare LIVE against a DESIRED snapshot. Whether live
currently matches is exactly the question the guard answers — so a "first run green"
AC pre-supposes the answer. The generalizable rule: **when the deliverable is an
audit/guard over an external resource, verify the external resource's current state
at plan/review time; a divergence you find is a real pre-existing finding to
surface, and the canonical must track the SSOT/desired state, never the drifted
live state.** This is the drift-guard-specific corollary of `hr-no-dashboard-eyeball`
+ "trace the ACTUAL producer, not the plan's assumption."

## Session Errors

1. **echo-after-redirect masked the real exit code** — a compound Bash command
   (`bash test-all.sh > log 2>&1; rc=$?; echo "EXIT=$rc"`) had its newlines
   collapsed by the tool wrapper, so the `echo` ran after the redirect and printed
   to stdout (the task-output file) instead of the log; a grep for `EXIT=` in the
   log found nothing. Recovery: read the exit line from the background task's
   output file. **Prevention:** for a load-bearing exit code, keep `rc=$?; echo
   "EXIT=$rc"` as its OWN Bash step, or read `rc` from a file the redirect can't
   swallow — already the spirit of the existing `test-all tail-masking` learning.
2. **Edit `old_string` dash mismatch** — a plan-file Edit failed
   `String to replace not found` because the quoted text used a different dash
   glyph than the file. Recovery: updated the sibling `tasks.md` instead.
   **Prevention:** for prose files with typographic punctuation, anchor Edit
   `old_string` on ASCII-only spans, or Read the exact bytes first.
3. **Stale Monitor timeout** — a `test-all.sh` completion Monitor timed out after
   the gate was already verified manually. One-off; expected. **Prevention:** none
   needed — the manual verification was authoritative.
4. **Foreground `sleep` blocked** — used `sleep 45` to wait on a background task;
   the harness blocks foreground sleeps. Recovery: peeked at the log without
   sleeping and awaited the completion notification. **Prevention:** wait via the
   task-completion notification or a Monitor `until`-loop, never a foreground sleep.
