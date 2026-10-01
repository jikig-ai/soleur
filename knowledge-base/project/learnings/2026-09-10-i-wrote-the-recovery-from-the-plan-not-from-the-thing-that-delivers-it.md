---
title: "I wrote the recovery taxonomy from the plan, not from the thing that delivers the recovery"
date: 2026-09-10
issue: 7836
pr: 7984
category: workflow-patterns
tags: [documentation-correction, runbook, unmeasured-claims, art-30-register, terraform, review]
---

# I wrote the recovery taxonomy from the plan, not from the thing that delivers the recovery

## Problem

`infra/github/README.md` §"Phase 5 -- Rollback" told an operator to list prior state versions in R2
and restore one by `versionId`. R2 implements no object-versioning API, so step 1 returned
`NotImplemented` and step 2 had no input. The procedure had never been executable. The claim
originated in ADR-006 — *"R2 as remote backend **with bucket versioning**"* — was false on the day
it was written, and over ~18 months propagated into a runbook and into a GDPR Art. 30 register as
an **Art. 32 technical measure**.

The correction was straightforward. **What the correction got wrong is the learning.**

## The structural cause

Five review seats produced 18 findings. Four of the five P1s were one gap:

> The recovery taxonomy was written from the **resource list and the plan**, not from the
> **workflow and DR script that must actually deliver the recovery.**

Every one reduces to *"the runbook asserts a recovery capability nobody measured against its
implementer"* — which is precisely the defect class the PR existed to remove, reproduced inside the
replacement text.

| What the new text claimed | What the implementer does |
|---|---|
| §5c: auto-apply "restores state without terminal access" | `apply-github-infra.yml` imports **3 of 6** addresses. The 4th then plans a CREATE against a live same-named ruleset, the apply dies, and state is left *partially* restored — the worst of the three outcomes |
| §5b: recreate with the DR script, then `terraform import soleur:14145388` | `create-ci-required-ruleset.sh` does `gh api ... -X POST`, so GitHub issues a **new** id. The documented import 404s, and that id is hardcoded in 12+ sites |
| §5a: the config revert "needs nothing from you but a PR" | Reverting a commit that added a required check is a nested delete, so the destroy guard fails the apply **closed** without `[ack-destroy]`; and a self-locking apply blocks every PR *including the revert* |
| The taxonomy's routing table | Assumed every ruleset is Terraform-managed. Four are live; this root manages three |

**The tell:** I could describe each claim as "what the recovery does" rather than "what
`<file>:<line>` does". A recovery claim is a claim about an implementer. If you cannot name the
file and line that performs it, you have written an intention.

## Corrections to the correction

Five findings were false statements introduced **by** the correction. This is the second learning,
and it is separable: **a correction PR's own corrections are the least-audited surface in it.** The
author is holding the retired claim in mind, and the replacement text feels like bookkeeping.

- The §(g) note asserted the cited **`§Rotation` heading does not exist**. It does —
  `## Phase 4 -- Rotation` — and my own item (2) cites it three sentences later. A false statement
  newly added to a statutory register, in the PR whose subject is false statements in that register.
- The Art. 33/34 precedent pointed at `breach-register.md`'s 2026-08-06 row — which **is a row in
  that register**, recorded as *contested* — cited to support declining a row.
- The Art. 4(12) rationale was *"a control that never existed cannot have failed."* That returns the
  same answer **even if a state loss had occurred**, so it is insensitive to the only fact that
  would matter. The two sound grounds (no triggering event; §(c) records the personal-data
  categories as "None of substance") were one cell away.
- PA12 §(c)/§(e) still defined the data-subject population by possession of a PAT retired in #4384.
  The diff is what made §(g) contradict them *in the same block*.
- I asserted *"no writer is advancing `last-verified`"* on an unrelated row. False — #7841 merged
  the writer three days earlier. A parallel session refuted it with the merged PR.

## A measured claim beats an inherited one

The runbook said `terraform state push` needs `-force` because *"a restored snapshot is always
older than the state a bad apply just wrote."* Measured on v1.10.5 in a scratch root:

```
remote serial 1, push an EQUAL-serial matching-lineage snapshot, no -force  -> rc=0
remote serial 7, push the serial-1 snapshot, no -force                      -> rc=1
   Failed to write state: cannot import state with serial 1 over newer state with serial 7
```

Equal serial is the **common** case — an apply that failed *before* persisting, which is exactly
what the pre-write snapshot exists for. So the old text steered the reader onto the one flag that
disables the wrong-root lineage guard, across a bucket holding six state objects. The corrected
text reaches for `-force` only on the refusal message that warrants it.

## The sweep proved something narrower than its name

A structural-enumeration seat asked whether the sweep's *assembly* equalled its *property*. It did
not: four unmarked live sites remained, **two carrying runnable commands** for a capability that
does not exist — including the plan the runbook section was transcribed from.

The resolution was to apply the PR's own carve-out criterion consistently: **correct live
commitments, append to dated records.** An unmeetable open checkbox is a live commitment and gets
closed out; a dated plan is a record and gets a supersede banner rather than a rewrite.

## A mechanical enumeration counts exclusions as inclusions

The same seat reported ~92 unmapped (activity, vendor) pairs in the Art. 30 sub-processor mapping.
I spot-checked three and reported all three as verified. **One was a false positive.** PA-10 §(d)
affirmatively determines *"No third-party recipients at v1"* and that those sub-processors *"do not
receive the contents"*; PA-7 §(d) carries `NOT a recipient:` limbs. A grep for "processor named in
§(d)/§(e)/§(g)" counts every negative determination as a positive.

So the figure was never propagated into any artifact, and the register now records that a mention
is not by itself an activity — the rule whose absence would make every future pass re-derive it
differently.

## Prevention

- **For any claim about what happens automatically, cite the implementer by `file:line` and read
  it.** "The workflow imports the resources" is an intention; "the workflow imports these three
  addresses at `apply-github-infra.yml:291-305`" is a claim.
- **On a correction PR, review the new assertions before the new code.** Budget review attention
  for the replacement text, not the deletion.
- **A count derived by grep over prose is a lower bound with an unknown error term** whenever the
  prose can carry negations. Sample it before citing it, and never put an unvalidated figure in a
  statutory-register issue body.
- **Never write a `#N` into a committed artifact before `gh issue create` returns it.** I wrote
  `#7997`; the real number was `#8014`.

## Session Errors

1. **Wrote the recovery taxonomy from the plan rather than the implementing workflow.** — Recovery:
   five review seats; four P1s. — Prevention: the `file:line` rule above.
2. **Asserted `state push` serial semantics inherited from the runbook.** — Recovery: measured in a
   scratch root; the claim was false in the common case. — Prevention: measure any vendor/tool
   semantics a runbook branches on.
3. **Asserted "no writer is advancing `last-verified`" without measuring.** — Recovery: a parallel
   session refuted it with merged PR #7841; corrected here and on #7255. — Prevention: `gh issue
   view` + grep the implementing file before asserting an absence.
4. **Reported Cloudflare/PA-10 as a verified missing pair; it was a false positive** (PA-10
   excludes those sub-processors explicitly). — Recovery: the CONCUR gate caught it. — Prevention:
   when spot-checking a grep-derived enumeration, read the *whole* source cell, not the match.
5. **Fabricated a filename** (`ADR-030-sentry-terraform-managed-alerts.md`) when re-pointing an
   exemplar. — Recovery: verified before committing; used ADR-007, measured at 19 lines/3 sections.
   — Prevention: `ls` any path before citing it.
6. **Wrote `#7997` into the register before the issue existed.** — Recovery: filed, got `#8014`,
   corrected in the same change. — Prevention: file first, then reference.
7. **Shipped a no-op `lint-infra-ignore` region** on ADR-006. — Recovery: mutation-tested it (strip
   the markers, re-run the gate — still green), removed it. — Prevention: a suppression that
   suppresses nothing falsely advertises a waived finding; mutation-test every one.
8. **Read a commit's exit status from a trailing command.** The task reported "exit code 0" while
   `COMMIT_EXIT=1` and the commit had failed on a lint gate. — Recovery: read the rc file. —
   Prevention: capture `rc=$?` on its own line; never infer from a task notification.
9. **Read `gh pr checks` as coverage.** Nine checks returned, mostly passing, while the required
   `test` context was **absent from the set** — CI had last run on a pre-rebase SHA. — Recovery:
   `gh run list --commit <sha>` showed only `pull_request_target` workflows re-fired. — Prevention:
   name the context you expect and confirm it is in the returned set, against the reviewed SHA.
10. **Mangled an unrelated line** with an over-broad regex while fixing a pre-existing lint error in
    a dated plan. — Recovery: restored the line byte-for-byte from `origin/main`, dropped the edit.
    — Prevention: do not fix unrelated pre-existing lint in a file you are touching for one line.
11. **A parallel Claude session committed to the branch during a report-only panel** (different
    session id in the trailer). Its change was correct and was kept after verification. —
    Prevention: the panel-scale rule assumes the only writers are the agents you spawned; verify
    `git rev-parse HEAD` before and after, not just `git status`.
12. **`comm` invoked on unsorted input** several times, silently producing nothing usable. —
    Prevention: `grep -Fxf` for set intersection, or sort both sides explicitly.
13. **Three plan-quoted counts were stale** (credential-form sites, managed resources,
    `errored.tfstate` hits). — Prevention: re-derive plan-quoted numbers at implementation time.
14. **A pre-existing lint violation blocked an unrelated one-line improvement, twice** (the
    telegram-bridge tick; the 2026-05-16 banner). — Recovery: dropped both rather than suppress an
    unrelated finding or rewrite a dated record; recorded the residual. — Prevention: none
    available; this is a real cost of file-scoped fail-closed gates and is worth stating rather
    than hiding.
15. **The plan's AC21 rationale ("the tick is free because the ADR is open anyway") did not
    survive contact.** — Prevention: an opportunistic AC should state what makes it free, so the
    condition can be checked rather than assumed.
