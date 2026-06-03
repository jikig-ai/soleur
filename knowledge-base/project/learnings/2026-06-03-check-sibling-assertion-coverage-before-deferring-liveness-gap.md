# Learning: before deferring a "no liveness assertion exists" gap as known-debt, grep the assertion's EXPECTED list — a sibling may have already generalized it

## Problem

The plan for the `workspace-sync-health` Sentry alert (#4882) declared, in its
Sharp Edges, a deferred "known debt": *"the apply workflow has a post-apply
`assert-byok-rules-exist.sh` liveness check for the BYOK rules, but no
equivalent for the new rule … the `chat_message_save_failure` rule shipped with
the same gap, so this is consistent precedent."* Both halves were false.

## Investigation

`user-impact-reviewer` (fired by the single-user-incident threshold) flagged the
future-drop regression (a later edit dropping the `-target` line silently
un-applies the rule; the contract test reads only the `.tf`, not live Sentry).
Reading `assert-byok-rules-exist.sh` to size the fix revealed:

- The script header says *"Issue-alert detector liveness assertion (#4656 item
  5; **extended #4849**)"* — it is NOT BYOK-specific.
- `EXPECTED_RULES` already contained `chat-message-save-failure` (added by
  #4849). So chat was NOT "shipping with the same gap" — it was covered.
- `EXPECTED_RULES` is the canonical join-list: every apply-created
  `sentry_issue_alert` is expected to be added to it.

So the "gap" was a one-line omission in the implementation, not deferrable
debt. Fix: add `workspace-sync-health` to `EXPECTED_RULES` + the test (T8
isolation case), and generalize the "both rules"/Art.33-only runtime messages
that #4849 had left stale. A dropped `-target` now fails the apply loudly.

## Key Insight

A plan's framing of "no mechanism exists for X, defer it" is a claim about the
codebase that must be verified the same way as any other premise. The cheapest
check for an assertion/guard/liveness gap: **grep the guard's EXPECTED /
allow-list / registered set for a sibling of the same class.** If a sibling is
already listed, the mechanism exists and is generalized — the "gap" is just a
missing list entry (a `pr-introduced`, fix-inline omission), not architectural
debt to defer.

Corollary for the brainstorm/plan phases: when an assertion script's *name* is
narrow (`assert-byok-rules-exist.sh`) but its *header* says "extended #N", trust
the header + the EXPECTED list over the name. Names lag scope; #4849 generalized
the script's contents but not its filename or its user-facing messages.

This is the assertion-coverage analogue of the existing brainstorm rule
[[2026-06-03-brainstorm-grep-observability-layer-before-greenfield-detection-framing]]
— both say: verify the mechanism's *actual current coverage* against code before
framing work as greenfield-build or deferred-debt.

## Session Errors

1. **Plan declared a false "known debt" deferral.** The Sharp Edge claimed no
   liveness assertion existed for non-BYOK rules and that chat shared the gap;
   `EXPECTED_RULES` already covered chat (#4849). **Recovery:** review caught it;
   added the rule to the assertion inline + corrected the plan. **Prevention:**
   the Key Insight above — grep the guard's EXPECTED list for a sibling before
   deferring an assertion-coverage gap. The brainstorm/plan premise probes
   should extend to "does the named assertion script already cover this class?"

## Tags
category: observability
module: web-platform/infra/sentry
