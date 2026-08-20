---
category: best-practices
module: sentry-iac
problem_type: logic_error
symptom: "A script reads as superseded legacy; deleting it would remove the only definition of a live control"
issues: [7590, 4781, 7634]
date: 2026-08-19
---

# I proposed deleting a control because Terraform appeared to own it

## Problem

While migrating three sibling scripts off a deprecated Sentry endpoint, I
classified `configure-sentry-alerts.sh` as safely deletable:

> the LEGACY pre-Terraform configurator that ADR-031 superseded with
> `issue-alerts.tf`, retained only as a documented escape hatch (ADR-031:700)

Every clause was checkable and the conclusion was wrong. ADR-031:700 is the
**revert trigger for a migration phase**, retired once the import succeeded —
not what keeps the script alive.

What keeps it alive is four lines of `issue-alerts.tf`:

```hcl
  conditions_v2 = []
  filters_v2    = []

  lifecycle {
    ignore_changes = [conditions_v2, filters_v2, actions_v2, environment, frequency]
  }
```

Terraform declares those attributes **empty** and then declares that it does not
manage them. So Terraform does not own the alert filters and an apply **cannot**
restore them. `configure-sentry-alerts.sh` is their only executable definition.

The four rules that block is on are `auth-exchange-code-burst`,
`auth-callback-no-code-burst`, `auth-per-user-loop` and `auth-signout-burst`.
Name them, because there is a *different* set of four in the same file and
confusing the two is the failure mode below.

This is not hypothetical. On 2026-06-02 all four auth alert rules drifted to
empty filters, matched every issue in the project, and were repaired by a manual
re-PUT of that script's definitions. The recurrence guard, **#4781**, is still
open. Deleting the script would have deleted the remediation source for an open
P2.

## Root cause

`ignore_changes` inverts the usual reading of a Terraform resource. A resource
block normally means "this is the desired state". With an attribute in
`ignore_changes` **and** declared empty, the block means the opposite: *something
outside Terraform owns this, and Terraform will not fight it.* A reader
skimming for "is this in Terraform?" sees the resource and concludes ownership.

## The correction that was itself wrong

I then found what looked like the same false premise sitting in a comment in a
*third* script, `assert-byok-rules-exist.sh`, and rewrote it:

> The rule's `conditions_v2`/`filters_v2`/`actions_v2` are Terraform-owned (only
> `environment` is in `lifecycle.ignore_changes`), and this assertion runs
> POST-apply … so tag-drift is self-healing on the next apply.

**That comment was correct and I falsified it.** It is about a different four
rules. `issue-alerts.tf` holds two disjoint sets, and only a per-resource read
tells them apart:

| Set | Rules | `ignore_changes` | v2 attributes | Who owns the filters |
|---|---|---|---|---|
| `EXPECTED_RULES` in `assert-byok-rules-exist.sh` | `byok-art-33-breach`, `byok-cap-exceeded`, `chat-message-save-failure`, `workspace-sync-health` | `[environment]` **only** | fully populated | **Terraform.** Drift *is* self-healing on the next apply. |
| the `auth-*` set | `auth-exchange-code-burst`, `auth-callback-no-code-burst`, `auth-per-user-loop`, `auth-signout-burst` | `[conditions_v2, filters_v2, actions_v2, environment, frequency]` | declared `[]` | **Not Terraform.** `configure-sentry-alerts.sh` is their only executable definition — this is what #4781 and the 2026-06-02 incident are about. |

The 2026-06-02 incident refutes the self-healing claim for the `auth-*` set and
for that set only. Applied to the BYOK/chat/workspace-sync four it refutes
nothing, because no apply was ever prevented from restoring them.

**A file-level grep for `ignore_changes` cannot tell these sets apart.** Both
blocks live in one file; grep returns the file. I ran that grep, saw the wide
`ignore_changes`, and concluded it governed the rules the script asserts on. It
governs four other resources forty lines away.

Had the rewrite shipped, an operator whose BYOK Art. 33 breach alert had drifted
would have been told an apply cannot help, and pointed at a script that does not
define that rule at all — the exact inversion of the error this file was opened
to record, committed while recording it. Reverted in `a279d511`; the original
paragraph is restored verbatim with the trap noted beside it, because the
mistake is one file-level grep away from being made again.

## Solution

Before deleting or deprecating anything that looks like superseded tooling, ask
**what consumes its output**, not what replaced it:

1. For a Terraform-adjacent script, read the `lifecycle` block **of the specific
   resource blocks that script names** — not the file's. An attribute in
   `ignore_changes` is *not* owned by Terraform, whatever the resource
   declaration looks like; but a sibling resource's `ignore_changes` says
   nothing about yours. Resolve the attribute per RESOURCE BLOCK. One `.tf`
   file routinely holds both postures, and `grep -l` collapses them.
2. Grep for open issues naming the script or the state it maintains
   (`gh issue list --search "<script>"`). An open recurrence guard is a live
   dependency.
3. Check whether a past incident's remediation recipe invokes it. If the repair
   procedure for a known failure mode runs this script, it is a control.
4. Confirm the ADR passage you are citing says what you think. The one cited
   here was a retired revert trigger, not a retention rationale.

## Corollary: prose is a caller

My inventory of "what still hits the deprecated endpoint" was `.sh`-only. Two
markdown files instruct a human or an agent to run it on the next incident:

- a runbook's reconcile recipe, and
- a learning file's "How to apply", naming the dead endpoint as the *first
  diagnostic* on the next paging incident.

That is the same defect as code calling a dead endpoint, and far cheaper to fix.
The two corrections differ by document class: the runbook is **operational**, so
it was edited in place; the learning is a **dated record**, so the original text
stands and a superseding note sits beside it with the live field mapping.

## Key insight

**"Superseded" is a claim about what replaced something; "deletable" is a claim
about what still depends on it, and the second does not follow from the first.**
`ignore_changes` is where those two come apart, because it makes a resource
block read as ownership while declaring the opposite.

## Session Errors

- **I was about to propose deleting a live control.** Caught by
  `code-simplicity-reviewer` at CONCUR. **Prevention:** the checks above —
  `lifecycle`/`ignore_changes`, open issues naming the script, past incident
  remediation recipes — before any "this is legacy, delete it" recommendation.

- **My deferral verdict was right and my reason was wrong.** I justified
  deferring the two remaining scripts with "no automated caller, so a brownout
  only makes a manual run fail loudly". A brownout does **not** fail loudly; it
  fails intermittently, which is the exact misreading the PR existed to correct.
  I had re-applied the rejected reading to two more scripts while writing the
  correction. The reason that survives is measurable: the replacement payload
  has no `conditions`/`filters`/`actions` keys, so both scripts' write bodies are
  structurally dead against it. **Prevention:** state a deferral's reason as
  something falsifiable and then falsify it — "no automated caller" was checkable
  and true; "fails loudly" was checkable and false, and nothing made me check it
  because it was not the load-bearing clause.

- **I "corrected" a true comment into a false one, and two review agents
  agreed with me.** I resolved a CONCUR finding with a file-level `grep
  ignore_changes` instead of reading the resource block the script actually
  names, and inverted an accurate ownership claim. Two agents reviewing the
  result made the identical error and concurred — which is what
  N-artifacts-agreeing looks like when they inherit one premise, not
  independent confirmation. **Prevention:** when a finding turns on an
  attribute of *a specific resource*, the verifying command must be
  resource-scoped (`awk '/^resource "type" "name"/,/^}$/'`), and agreement
  between reviewers who read the same wrong grep is not evidence. Cost: one
  commit to make, one to revert.

- **I superseded a claim in the artifacts I remembered writing, not in the
  artifacts that assert it.** Retracting the "410 was transient" reading, I
  marked `versions.tf` and ADR-031 — the two I had edited — and moved on. A
  predicate sweep (`git grep -ln transient` ∩ `410|issue-alert|rules/`, then
  read each hit) found **four** more carrying the retracted reading with zero
  supersession markers: the post-mortem, the #6636 plan, the Phase 0 evidence
  file, and — worst — a learning whose *title* is
  `transient-provider-410-reproduce-before-choosing-a-fix`, which states the
  retracted stopping rule as a **general rule for any vendor-API break** and is
  therefore what `learnings-researcher` retrieves next time. An unmarked peer
  reads as still-live, and the most-retrieved artifact was the last one anyone
  would think to check, precisely because it is not about this incident.
  **Prevention:** a supersession is not done when the artifacts you *authored*
  are marked. Derive the set from the retracted claim itself — grep the claim's
  own words across the KB, read every hit, mark or clear each — and check the
  generalised restatements first, because a dated incident record ages out of
  circulation while a "Key Insight" does not.

- **An ADR claim that a grep settles in seconds shipped unverified.** ADR-031's
  new Recurrence paragraph promised an `::error::` annotation on "every caller".
  `grep -c '::error::'` on the script returns **0** — it emits `::warning::` —
  and the tripwire only reaches callers routing through that one script's
  `curl_retry`. Both clauses were written in the same PR that built the
  mechanism. **Prevention:** a universal or causal claim added to an ADR needs
  its falsifying command run *before* the sentence is written; the claims
  describing your own new mechanism are the least-checked claims in the PR,
  because you feel you already know them.

## Related

- #4781 — open recurrence guard; its target field moved from `filters` to
  `actionFilters[].conditions[]` with this migration.
- #7634 — the deferred write-shape migration for both remaining scripts.
- [best-practices/2026-07-09-terraform-source-guard-must-key-on-arming-class-not-ignore-changes-value.md](./best-practices/2026-07-09-terraform-source-guard-must-key-on-arming-class-not-ignore-changes-value.md)
  — sibling case where `ignore_changes` misled a guard rather than a human.
