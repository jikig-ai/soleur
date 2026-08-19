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

The same false premise had been sitting in a comment in a *third* script for
months:

> The rule's `conditions_v2`/`filters_v2`/`actions_v2` are Terraform-owned (only
> `environment` is in `lifecycle.ignore_changes`), and this assertion runs
> POST-apply … so tag-drift is self-healing on the next apply.

Both halves false, and the 2026-06-02 incident is the empirical refutation — the
drift was not self-healed by an apply.

## Solution

Before deleting or deprecating anything that looks like superseded tooling, ask
**what consumes its output**, not what replaced it:

1. For a Terraform-adjacent script, read the resource's `lifecycle` block. An
   attribute in `ignore_changes` is *not* owned by Terraform, whatever the
   resource declaration looks like.
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
