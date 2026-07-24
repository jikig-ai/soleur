# Learning: a material legal over-claim can be HELD pending an infra teardown that cures it; and "draining" an umbrella issue can mean keeping it OPEN

## Problem

Draining #6897 (the encryption-posture "lower-severity consolidated items" umbrella) surfaced two
workflow forks that the default rules get wrong:

1. **Close-the-umbrella reflex.** The plan's default was to `Closes #6897` and re-home its 8 ledger
   `tracking_issue: #6897` references to 3 new follow-up trackers. But #6897's residual items
   (superseded plaintext backstop volumes pending teardown, zot HTTP by-design, host-posture
   measurement) are **ongoing bounded exceptions, not one-time fixes** — closing the umbrella +
   spawning 3 trackers is **net +2 backlog** (the opposite of "draining"), and orphans the exceptions
   (they'd point at a closed issue).

2. **Fold-inline-or-bust reflex.** A legal-audit (`legal-compliance-auditor`) found a **material
   over-claim** (the #6588 P1 class): published legal docs assert, unqualified, that "workspace git
   data sits on a LUKS-encrypted volume (encryption at rest)" — true of the LIVE store (post-cutover
   `workspaces_luks` mapper) but false of completeness, because two **attached plaintext ext4 backstop
   volumes still hold pre-cutover copies** on seizable Hetzner disks. The plan's rule: "a material
   over-claim MUST be folded inline, never deferred."

## Solution

Both defaults were overridden by informed operator decisions, and both overrides are legitimate:

1. **Draining an umbrella can mean keeping it OPEN (net 0).** When the residual items are ongoing
   bounded exceptions, keep the umbrella issue open to home them, verify the ledger rows are current
   (read-only), and do NOT file new trackers. "Drain" = the actionable work is done + the residuals
   are honestly tracked, not "the issue is closed." Net-issue-flow stays 0.

2. **A material over-claim can be HELD when a SECOND, tracked remediation path will cure it.** The
   auditor gave two paths: (1) infra — tear down the plaintext backstops (DL-2 wipe + detach/destroy)
   → the existing wording becomes unconditionally true, no doc edit; (2) wording — qualify the published
   claim. Path 1 was unavailable *now* (zero-live-infra-mutation; `git_data` is a deliberate rollback
   backstop *pending* DL-2), so the plan would force Path 2. The operator instead **held** the copy fix,
   because Path 1 will cure it and is **already tracked** by the still-open #6897 + the ledger rows'
   `reevaluate_when` triggers (workspaces_luks cutover irreversible → detach+destroy; git_data_luks
   cutover → DL-2 wipe). The legal-recon is thereby **bound to the infra teardown**.

**To hold safely (make it auditable, not a silent omission):** record the finding + the override
explicitly in `decision-challenges.md` (rendered into the PR body), **preserve the auditor's proposed
Path-2 wording** verbatim for teardown-time (so if the teardown slips, qualifying is one edit away),
and keep the umbrella issue open so its `reevaluate_when` re-fires the recon when the infra changes.

## Key Insight

A "material over-claim MUST be folded inline" rule assumes **wording is the only remediation**. When a
tracked **infra** change will independently make the existing wording true, the honest end-state can be
to hold the copy edit and bind its resolution to that infra tracker — provided the hold is explicit,
auditable, and the alternative wording is preserved. Leaving a *pre-existing* over-claim live for a
bounded, tracked window is an operator/CLO risk decision, not a silent defer. Symmetrically, an umbrella
issue whose children are ongoing exceptions is honestly "drained" by staying open, not by closing +
spawning trackers that grow the backlog. **Bind legal/compliance reconciliations to the ledger's
`reevaluate_when` so they re-run when the measured posture actually changes.**

This recurs when the other encryption-posture teardowns land (workspaces detach, git_data DL-2 wipe):
re-run the legal-recon at that point to confirm the LUKS at-rest wording became true, or qualify it then.

## Tags
category: workflow-patterns
module: encryption-posture-ledger, legal-reconciliation, drain
related: [[2026-07-24-formalizing-a-provisional-provider-attestation-honest-close-and-citation-not-probe]]
issues: 6897, 6588, 6893, 6894, 6895
