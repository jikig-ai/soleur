---
title: The artifact that proves a refusal happened could not be written
date: 2026-08-17
issue: 7555
category: workflow-patterns
tags: [github-actions, permissions, observability, guards, timeouts]
---

# The artifact that proves a refusal happened could not be written

#7552 shipped a delivery dispatcher for a production registry-host replace. On its first real
run, two of three stages did exactly what they were built to do — the delta gate detected
host-visible byte changes, and the preflight refused because the release co-fired on the same
merge. The third stage, whose entire purpose was *"a refusal must never be only a red run nobody
owns"*, emitted:

```
GraphQL: Resource not accessible by integration (addComment)
```

The workflow granted `actions: write` + `contents: read` and no `issues: write`. The call ended
in `|| true`. **The step reported SUCCESS while posting nothing.**

That is the same failure the parent PR spent nine commits removing — a green mechanism doing
nothing — committed inside the fix for it, and it survived a ten-seat review, a strong-model
completeness consult, and a full local suite. None of them could have caught it: the scope is
declared in one file section and consumed in another, and the failure only exists at the moment
the workflow tries to report.

## Three lessons, in descending order of how much they generalize

### 1. `|| true` on an artifact step inverts its meaning

A best-effort suffix is normal on a notification. It is *incoherent* on the step that exists to
guarantee a record. Those two look identical in a diff:

```bash
gh issue comment "$N" --body "$BODY" || true     # fine on a nice-to-have ping
gh issue comment "$N" --body "$BODY" || true     # a lie on the durable-artifact step
```

The rule that separates them: **if a step's justification contains the word "must", it may not
swallow its own failure.** The artifact step now emits `::error::` and exits 1, so the run's own
failure becomes the record of last resort.

### 2. A job timeout shorter than an internal wait *disarms* the failure handler

The preflight waits up to N seconds for in-flight writers to drain. The job carried
`timeout-minutes: 15` while the wait was 480s and the poll allowed a further 1500s.

The obvious harm is the wait getting cut short. The real harm is subtler: a job killed by
`timeout-minutes` is **cancelled**, and `if: failure()` is **false for cancelled**. So every
failure-conditioned step — including the artifact step — silently does not run. Fixing the
permission alone would have left this in place.

**Whenever a step has an internal deadline, assert that the job's `timeout-minutes` exceeds the
sum of every internal deadline on its path**, and remember that the failure mode of getting it
wrong is *silence*, not truncation.

### 3. A permissions lint that over-reports gets "fixed" by widening token scope

This is why the lint added here is conservative to the point of being fussy. A naive scan of the
same class claimed **5** offenders; **1** was real.

- 2 already held the scope (in a *job-level* `permissions:` block — a per-job grant is as valid
  as a top-level one, and demanding the top-level form would push authors to widen scope).
- 2 make no tracker write at all (matched on `gh api` prose).
- The first corrected draft then flagged `pr-auto-close-scanner.yml`, which is **correct**:
  GitHub serves pull-request comments from the `/repos/{o}/{r}/issues/{n}/comments` REST path but
  governs them with `pull-requests: write`, not `issues: write`.

Acting on that last one would have widened a production workflow's token to fix a defect that did
not exist. **For a security-adjacent lint, a false positive is not a nuisance — it is a
recommendation to reduce security.** Both false-positive classes are now pinned by tests, because
the arms that keep a lint honest are the ones that assert it stays quiet.

## The meta-observation

Every defect in this sequence was found by **running the thing**, never by reading it:

| Round | Found by | What it caught |
|---|---|---|
| 1 | a 5-seat review panel | 9 inert mechanisms |
| 2 | design-validity + simplification seats | 9 more, in the round-1 fixes |
| 3 | the repo's own `alarm-issue-filing-guard` | a step that could not run after an earlier failure |
| 4 | CI's `guard-vacuity-floor` | two floors scored uncovered, not passing |
| 5 | **the first production execution** | the artifact step could not write |

Rounds 3–5 were all mechanical, and round 5 required real credentials against a real API. The
generalizable form: **a mechanism that touches an external system has a class of defect that only
its first real invocation can expose**, so the first invocation deserves to be watched as
carefully as a deploy — not treated as the victory lap after the merge.

## Session Errors

- **Shipped an artifact step without the scope it needs, behind `|| true`.** Recovery: added
  `issues: write`, removed the swallow, added `scripts/lint-workflow-issue-write-scope.py`.
  **Prevention:** grep a new workflow's write calls against its `permissions:` block before
  merge — now mechanical.
- **Sized P3's wait at 480s on an assumed ~8-minute release; it is ~31.** Recovery: 2100s, and
  the job timeout 15 → 45 so the wait cannot be cancelled. **Prevention:** derive a wait budget
  from the measured duration of the thing being waited on, not from an estimate of it.
- **Nearly "fixed" a correct workflow.** The first lint draft flagged `pr-auto-close-scanner`,
  and the remedy would have been to widen its token. Recovery: taught the lint that PR comments
  ride the issues path under `pull-requests: write`. **Prevention:** before acting on a lint's
  first output, verify one flagged instance by hand — the fix for a false positive in a
  permissions lint is a security regression.
- **Mis-triaged the ADR-193 collision at rebase time.** Ran `lint-guard-contract.py`, saw it
  pass, and concluded the new floor contract did not bind these suites; the binding guard was
  `scripts/guard-vacuity-floor`. **Prevention:** when a ratchet lands and a suite goes red, find
  the guard from the FAILING OUTPUT's own name, never from a plausibly-related lint.

## Related

- `2026-08-16-every-mechanism-i-shipped-to-prove-the-fix-was-itself-unproven.md`
- `2026-08-16-i-pinned-the-arm-that-already-failed-loudly.md`
