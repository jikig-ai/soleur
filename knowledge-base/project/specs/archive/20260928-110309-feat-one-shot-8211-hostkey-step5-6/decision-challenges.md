# Decision challenges: feat-one-shot-8211-hostkey-step5-6

Source: plan-review, 2026-09-28, on
`knowledge-base/project/plans/2026-09-28-feat-git-data-delete-unpinned-fallback-arm-5914-plan.md`.
Headless run: these were not auto-applied. The stated direction stays the default until the operator
rules.

## User-Challenge 1: shrink Part A to a link to runbook step 5

- **Operator direction:** the plan must state exactly what step 5 (a)–(d) requires, the data
  sources and read-only queries, and which parts need authorization.
- **Challenge (DHH reviewer):** Part A restates the runbook and will drift from it; replace it with a
  link plus gate G1.
- **Default kept:** Part A stays, because the brief asked for it explicitly.
- **Trade-off:** less drift risk versus the brief's explicit requirement.

## User-Challenge 2: make G1 a sequencing note, G2 the only hard gate

- **Operator direction:** the step-6 PR is gated on the step-5 discharge record being posted first.
- **Challenge (DHH reviewer):** G1 lets a `NOT DISCHARGED` record through, so it only proves a
  comment exists.
- **Default kept:** G1 stays a merge gate. It now also requires a member-authored newest record, and
  zero erasure events since that record.

## Taste 1: reason word `pin_absent` versus a non-prefix word (`pin_missing`)

- **Challenge (DHH reviewer):** `pin_absent` is a prefix of the old `pin_absent_store_enabled`, so
  every match needs the colon.
- **Kept:** `pin_absent` (CTO ruling; it matches the `git_data_pin=absent` startup vocabulary). The
  plan requires matching with the colon.

## Taste 2: runbook ticks for host-key steps 2 and 3

- **Challenge (DHH and simplicity reviewers):** these ticks are catch-up work outside step 6.
- **Kept:** the brief offered them as optional record-only catch-up if the evidence holds, and the
  evidence is on #5914. Each is one line.

## Taste 3: the four register markers and the CLO re-attestation record

- **Challenge (DHH and simplicity reviewers):** file the activation marker and the re-attestation
  separately.
- **Kept:** the CLO ruled that closing residual (b) without the activation marker leaves the cell
  contradicting itself. Register wording is CLO-only, and the CLO asked to write the re-attestation
  at ship Phase 5.5.

## Taste 4: the `pin_absent_at_startup` boot event

- **Challenge (DHH reviewer):** it pages no one until #8572 lands, so either page in this PR or cut it.
- **Kept:** the CPO's sign-off condition C2 asks for a signal before the first user is affected. Paging
  is #8572's scope (another session owns `issue-alerts.tf`). The User-Brand Impact section states the
  gap until then.
