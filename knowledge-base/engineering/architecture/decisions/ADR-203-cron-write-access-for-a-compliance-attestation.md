---
title: "ADR-203 — A weekly cron may advance a compliance attestation on the default branch, gated on a comparison it performed in the same run"
status: accepted
date: 2026-09-04
tags: [compliance, vendoring, cron, gdpr, accountability, write-access]
related_adrs: [ADR-026, ADR-033, ADR-077, ADR-094, ADR-121, ADR-186, ADR-189, ADR-196, ADR-197]
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

This is a **deviation from AP-024** ("a verification surface does not actuate … must not
itself perform the write it is judging"), recorded rather than argued away. The write step
is separated (`attest-freshness` is its own `step.run`, allow-listed to one path, its own
PR), but the **credential is not** — one memoized installation token serves both the
comparison and the write — and the **grader is not**: `mayAttestFreshness` runs in-process
over totals the same step produced. AP-024 separates the write, the blast radius, the
credentials and the verdict; this separates two of the four. Admitted because the
alternative that would satisfy it (a second independently-credentialed actor re-deriving
the comparison) buys a guarantee the shipped-artifact constraint already bounds: the write
is one date field on one file, visible in `git log` and refutable by re-running the
comparison. See ADR-189 for the principle's origin.

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
   the **two** rulesets targeting this repository's default branch
   (`ruleset-ci-required.tf`, `ruleset-cla-required.tf`), whose relevant bypass actors are
   both `bypass_mode: "pull_request"`. The stronger containment argument, omitted by an
   earlier revision: the bot is in **no bypass list at all**, so its PR must satisfy the
   required CI contexts, of which it self-signs only the synthetic subset. (That revision
   counted **three**; the third governs `jikig-ai/soleur-marketplace` — a different
   repository — and *does* carry a `pull_request` rule, which is why residual 4 must be
   scoped to this repo to be true at all.)
   `mergeMode: "direct"` opens the PR and squash-merges it, which is what the drift route
   already does, and inherits the allow-list, the deletion guard and the replay idempotency
   that a hand-rolled path would discard.

### Why not the alternatives

**Raise the staleness window.** Rejected. A gate whose failing output is indistinguishable
from its passing output is not a gate, and widening the window makes the two *more* alike,
not less. It also treats a missing writer as a threshold-calibration problem.

**Replace the date-based threshold with a content-identity check.** Rejected, and this is
the option that looks most attractive from outside. An identity check cannot see calendar
rot, and it passes *by construction* on the no-drift arm — which is the arm that was
failing here. The date-based threshold is the right instrument for the question it asks;
it was lying because its writer had been deleted.

> An earlier revision attributed that rejection to ADR-121 and ADR-186, claiming each
> "already places that substitution in a rejected-alternatives table". **That was false** —
> neither mentions identity, hashing or checksums at all, and ADR-186 leans the other way,
> *adopting* an equality assertion in place of a freshness pin. The claim came from this
> change's plan and shipped unverified. The reasoning above is sound and is **this ADR's
> own**; it inherits nothing. Recorded rather than quietly deleted, because a false
> citation propagates further than a missing one — AP-024's own registration note.

**Have an operator advance the field.** Rejected. An operator editing `last-verified` by
hand asserts a comparison that no artifact records, which is the state this ADR exists to
end.

**Have the release commit advance it.** Rejected, and this is the alternative a reader
reaches for first: CI already writes to `main` on merge, so a writer with default-branch
access exists and needs no new grant. It fails on WHERE the evidence must live. The plugin
ships to customers with no `GH_TOKEN`, no access to this repo's Actions history and no
access to Soleur's Sentry, so the gate on a customer's machine can only read freshness out
of the **shipped artifact**. That is also why repairing the `#7255` cron-liveness probe
would not substitute: a signal living in CI is invisible where the gate runs. The field
must be committed, and the thing that commits it must be the thing that performed the
comparison.

## Residuals — named, not resolved

These are recorded as live gaps. None is claimed to be fixed by this decision.

1. **The ADR-026 / ADR-197 D-2 tension.** ADR-026 binds the gdpr-gate hook to an advisory
   `exit 0`, so the hook half cannot fail loud, while the cron half posts a non-OK
   check-in. The two halves of one control therefore have different failure semantics.
   That asymmetry is deliberate for now and is not resolved here.

2. **#7255 leaves the anti-backdating half of the trust binding inert.** `cron-run-stale`
   queries a workflow that no longer exists, so it returns 999 on every call and
   `MIN(notice, 999) == notice`. `last-verified` is operator-writable, so a backdated value
   is currently unchecked.

   **This change makes that materially worse.** `gdpr-gate.sh` argues the direction is
   fail-SAFE — true only while the field was static. Now that it is bot-advanced on a
   cadence, a fresh `last-verified` actively suppresses both banners with no independent
   liveness signal behind it: the gate's remaining freshness evidence becomes a value the
   bot writes. The restored writer is the natural liveness source but is **not wired as
   one** here. #7255 stays open and is noted there.

3. **`pushed_at` age is not checked.** An upstream abandoned but **not archived** returns
   SAME forever, so the attestation keeps advancing over a corpus nobody maintains — this
   ADR's own failure class one level up. Not addressed.

   Narrower than an earlier revision implied: the **archived** and **renamed** cases, and
   the case where the repo-meta probe cannot answer at all, ARE handled —
   `upstreamRepoState` is a conjunct of the write predicate. Before it existed the cron
   would open a `compliance/critical` "upstream archived" issue and advance `last-verified`
   in the same pass, because every file still compared SAME against the pinned SHAs. What
   remains uncovered is only the *silent* abandonment an unarchived repo cannot signal.

4. **The write bypasses CODEOWNERS routing on the NOTICE, by design.** The NOTICE carries a
   CODEOWNERS entry requiring review. A self-merging bot PR does not obtain that review.
   Note the containment argument that is NOT available here: **no ruleset targeting THIS
   repository's default branch** carries a `pull_request` rule, so there is no
   required-review gate and CODEOWNERS only auto-requests a reviewer. The mitigation is the
   scope of the write plus the required CI contexts the bot cannot bypass, not a review
   gate.

5. **The allow-list is a path PREFIX, not an exact path.** `safeCommitAndPr` filters with
   `startsWith`, so `.../gdpr-gate/NOTICE` would also admit a hypothetical `NOTICE.md`
   sibling, and nothing constrains the commit to one FIELD within the file — any dirty edit
   to the NOTICE would ride along. Nothing else in this path dirties that file, so the
   practical exposure is nil; but "one file, one field" is what residual 4 leans on, and it
   should be stated as what it is.

## Consequences

- `last-verified` becomes a machine-written field. Its value is now evidence of a specific
  comparison rather than an operator's recollection, which is what makes it usable as
  Art. 5(2) accountability evidence.
- The Sentry check-in for `scheduled-content-vendor-drift` becomes conditional: a
  verified-clean run that fails to LAND the advance posts non-OK. It tracks the MERGE, not
  the PR — `safeCommitAndPr`'s direct path falls back to arming auto-merge and still
  reports `status: "committed"`, so the result carries an explicit `merged` flag and the
  heartbeat keys on that. Keying on the status would have flipped the monitor green the
  moment the PR opened, before anything reached `main`.
- The 30-day banner becomes a genuine early warning instead of a standing condition. If it
  fires after this lands, the writer has stopped — which is a real signal for the first
  time.
- `content-vendoring.md` §6a governs the verification-only refresh path, which §6 (drift
  detected) never covered.
