---
title: "ADR-203 — A weekly cron may advance a compliance attestation on the default branch, gated on a comparison it performed in the same run"
status: accepted
date: 2026-09-04
tags: [compliance, vendoring, cron, gdpr, accountability, write-access]
related_adrs: [ADR-026, ADR-033, ADR-121, ADR-186, ADR-094, ADR-196, ADR-197]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md
---

# ADR-203 — A weekly cron may advance a compliance attestation on the default branch

## Status

Accepted 2026-09-04 (#7710).

## Context

`plugins/soleur/skills/gdpr-gate/NOTICE` carries `last-verified`: the date on which the
gate's vendored detection corpus was last compared against upstream. The gdpr-gate hook
reads it on every invocation and prints a staleness banner past 30 days and a
`POSTURE_FAIL:` line past 90.

The field had no writer. The `sed` that advanced it lived in a GitHub Actions workflow
deleted by #4483, and the Inngest replacement never reimplemented it while continuing to
ship a pull-request-body sentence claiming it did. `git log -S 'last-verified'` over the
NOTICE returns exactly one commit — the one that introduced the field.

The consequence was not a stale corpus. It was a stale *record* of a corpus that was in
fact verified clean every week: re-measured on 2026-09-04, 8 of 8 registered files were
SAME against upstream `main` at `0594a9ef`. The control operated and produced no evidence
that it operated, which is an Art. 5(2) demonstrability failure and weakly Art. 32(1)(d).

## The decision

**A weekly cron acquires write access to the default branch for a compliance attestation,
through a self-merging bot pull request, gated on a comparison it performed in the same
run.**

That sentence is the architecturally novel part, and it is narrower than the reasoning
that produced it. Everything else here is a restoration or a citation of decisions
ADR-121, ADR-186, ADR-094 and ADR-196 already made.

Three properties make the grant acceptable:

1. **The gate is the comparison's own totals, not a verdict.** The detect step has two
   returns that yield `drift: "none"`, and only one of them means "I compared everything
   and it matched"; the other is reached *after* drift was detected, when the classifier
   declines to categorise it. The write predicate therefore quantifies over
   `{registryCount, filesExamined, filesDrifted, filesError}` and requires a non-empty
   registry, complete examination, zero drift and zero errors. Keying on the verdict would
   let the cron advance a compliance attestation over a corpus the same run had just found
   drift in.

2. **The write is scoped to one file and one field.** `allowedPaths` is the NOTICE alone,
   so an attestation is structurally incapable of carrying a content change on the same
   commit.

3. **The route is a pull request, not a push.** `safeCommitAndPr` has no direct-to-branch
   mode — every path opens a PR against `main` — and a raw push is independently blocked by
   three rulesets whose relevant bypass actors are all `bypass_mode: "pull_request"`.
   `mergeMode: "direct"` opens the PR and squash-merges it, which is what the drift route
   already does, and inherits the allow-list, the deletion guard and the replay idempotency
   that a hand-rolled path would discard.

### Why not the alternatives

**Raise the staleness window.** Rejected. A gate whose failing output is indistinguishable
from its passing output is not a gate, and widening the window makes the two *more* alike,
not less. It also treats a missing writer as a threshold-calibration problem.

**Replace the date-based threshold with a content-identity check.** Rejected, and this is
the option that looks most attractive from outside. ADR-121 and ADR-186 each already place
that substitution in a rejected-alternatives table: an identity check cannot see calendar
rot, and it passes *by construction* on the no-drift arm — which is the arm that was
failing here. The date-based threshold is the right instrument for the question it asks;
it was lying because its writer had been deleted.

**Have an operator advance the field.** Rejected. An operator editing `last-verified` by
hand asserts a comparison that no artifact records, which is the state this ADR exists to
end.

## Residuals — named, not resolved

These are recorded as live gaps. None is claimed to be fixed by this decision.

1. **The ADR-026 / ADR-197 D-2 tension.** ADR-026 binds the gdpr-gate hook to an advisory
   `exit 0`, so the hook half cannot fail loud, while the cron half posts a non-OK
   check-in. The two halves of one control therefore have different failure semantics.
   That asymmetry is deliberate for now and is not resolved here.

2. **#7255 leaves the anti-backdating half of the trust binding inert.** `cron-run-stale`
   queries a workflow that no longer exists, so it returns 999 on every call and
   `MIN(notice, 999) == notice`. `last-verified` is operator-writable, so a backdated value
   is currently unchecked. The restored writer is a *candidate* to become that liveness
   signal — a bot-authored advance is exactly the untamperable timestamp the binding
   wanted — but it is **not wired as one** by this change, and #7255 stays open. Nothing
   here should be read as resolving it.

3. **`pushed_at` age is not checked.** An upstream that is abandoned but not archived
   returns SAME forever, so the attestation would keep advancing over a corpus nobody
   maintains. This is this ADR's own failure class one level up: a signal that cannot
   distinguish "verified current" from "verified against something dead". Not addressed.

4. **The write bypasses CODEOWNERS routing on the NOTICE, by design.** The NOTICE carries a
   CODEOWNERS entry requiring review. A self-merging bot PR does not obtain that review.
   Note the containment argument that is NOT available here: no ruleset carries a
   `pull_request` rule, so there is no required-review gate on the default branch and
   CODEOWNERS only auto-requests a reviewer. The mitigation is the scope of the write —
   one file, one field, one line — not a review gate.

## Consequences

- `last-verified` becomes a machine-written field. Its value is now evidence of a specific
  comparison rather than an operator's recollection, which is what makes it usable as
  Art. 5(2) accountability evidence.
- The Sentry check-in for `scheduled-content-vendor-drift` becomes conditional: a
  verified-clean run that fails to commit the advance posts non-OK. The monitor now tracks
  the artifact rather than the run.
- The 30-day banner becomes a genuine early warning instead of a standing condition. If it
  fires after this lands, the writer has stopped — which is a real signal for the first
  time.
- `content-vendoring.md` §6a governs the verification-only refresh path, which §6 (drift
  detected) never covered.
