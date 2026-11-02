# `approval-queue` flag: creation hand-over (not done by the PR)

The PR registers the flag in code only (`lib/feature-flags/server.ts` RUNTIME_FLAGS, `.env.example` `FLAG_APPROVAL_QUEUE=0`, `flip.sh` map). Nothing is created in Flagsmith or Doppler and nothing is flipped. Absent means OFF, so the merge does not depend on it.

## Operator steps (typed-yes, each a production write; run only after the legal commit and the post-merge checks below are green)

1. Create the feature with `soleur:flag-create` (name `approval-queue`, default OFF, mirror `FLAG_APPROVAL_QUEUE=0` in Doppler dev and prd).
2. Do NOT flip it as part of the create. Enabling is a separate decision per workspace cohort via a per-workspace segment override (`soleur:flag-set-role`), evaluated per workspace identity.

## Enabling gates: ADR-309 flip checklist (copied verbatim; the ADR is the source, edit both together)

Authoritative: `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`, section "Flag-flip checklist (before the flag is turned on for anyone)". "Below" and "above" in the copied text refer to the ADR sections of that name (Accepted deviation, Rollback and post-deploy verification). Nothing in this PR flips or creates the flag.

1. **Cohort rule: no workspace with more than one member gets the flag until the Owner card names the requester and `reattach` stops sending full action text to non-Owners.** Until both hold, the flag is limited to
   single-member workspaces (also: the decide path out of the agent process, or the sentinel gap re-accepted). Check the `workspace_members` count for the workspace before any per-workspace override, and **re-check it on
   every member invite**: inviting a second member to an enabled workspace takes it out of the cohort, so its override is removed first or in the same change.
2. **`SENTRY_USERID_PEPPER` is non-empty in the running container** (not only set in Doppler `prd`; invariant 1 fails closed without it, and `approval-key-unavailable` pages). Verify read-only after the deploy that
   the container has it and that the `approval-key-unavailable` alert has no events. **Never rotate the pepper while any approval is live**: a rotation invalidates every pending and approved row (and changes ADR-029 pseudonyms).
3. **Route the cron monitor** (accepted deviation, below): `scheduled_approval_expiry` is declared-unrouted under the two-PR rule and has no independent cover (the unanswered alert is emitted by the sweep itself, and no Better Stack
   missing-`SOLEUR_APPROVAL_SWEEP` monitor exists). After its first measured check-in, route it into `cron_monitor_failure` (add its id to the sorted `monitor_ids`, delete the unrouted entry) in a follow-up PR before the flip.
4. **Real-SDK probe and post-deploy verification**: re-run the probe (`dev-probe-approval-gate.ts`, ADR-305 checklist) and confirm the post-deploy verification below is green.
5. **Erasure and fingerprint conformance** (compliance-posture row, item (i)): after a real-database erasure of a personal workspace, `select count(*) from approval_request where workspace_id = :erased_user_id` is 0 and the
   fingerprint is keyed (pepper set, known-answer vector green); both recorded in `knowledge-base/legal/audits/`. The integration test `approval-request.tenant-isolation.test.ts` is the falsifier; `verify/180` deliberately has no row-level check (invariant 3).
6. **CLO attestation and sign-offs** (compliance-posture row, items (b), (h), (i)): (b) the full CLO attestation is discharged in `knowledge-base/legal/audits/` (a Jikigai-owned canary needs only its (b-canary) verification step);
   (h) the autonomous-mode card copy is non-provisional with both the CPO and CLO reviewer fields filled; (i) as item 5. Evidence gates #9776 and #10111 are closed.
7. **First-call flag-error posture**: decide whether to harden a flag read error on the first gated call of a turn to deny before enabling beyond the Jikigai canary (today it takes the flag-off path, a legacy card; see "Fail closed, sticky for the rest of the turn").

## Other preconditions

- Migration 180 applied in prd (release workflow `verify-migrations` green) and the cron monitor `scheduled-approval-expiry` checking in (Sentry).
- ADR-309 adopted; the legal records in this PR merged.
