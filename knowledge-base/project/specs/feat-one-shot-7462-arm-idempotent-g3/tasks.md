---
feature: feat-one-shot-7462-arm-idempotent-g3
plan: knowledge-base/project/plans/2026-08-20-fix-inngest-arm-idempotent-g3-plan.md
issue: 7462
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — make `op=arm` idempotent (G3)

Phase order is load-bearing: the decision function's contract lands before any consumer or test
depends on it, and the tests land before the consumer is rewired.

## Phase 1 — Extract the decision (contract first)

- [x] 1.1 Read `scripts/cutover-inngest.sh` lines 1004–1090 in full before editing.
- [x] 1.2 Add `g3_decide` above the `arm)` case. Signature: takes the prod value and the current dark value; echoes exactly one of `refuse-empty-dark`, `refuse-txn-pooler`, `refuse-not-session-pooler`, `refuse-not-prod-project`, `skip-already-current`, `write`.
- [x] 1.3 Preserve predicate order from the current block: empty-dark → `:6543` → `:5432` → prod project-ref → equality.
- [x] 1.4 Equality arm returns `skip-already-current` (the only behavioural change).
- [x] 1.5 Function performs no I/O, reads no globals, echoes no input value.
- [x] 1.6 Rewrite the empty-dark arm's comment to the retained rationale (anomalous read despite a G1-proven-readable config). Do **not** restate the obsolete rationale about a silent equality pass. (AC15)
- [x] 1.7 Do not add a prod-value-empty arm — G2 already excludes it upstream.

## Phase 2 — Drive it red (tests before the consumer is rewired)

- [x] 2.1 Add a `g3_decide` unit block to `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, sourcing the script so only the function is defined.
- [x] 2.2 Implement test scenarios 1–7 from the plan, asserting the exact outcome token per row.
- [x] 2.3 Add an evaluation floor asserting a non-zero count of `g3_decide` evaluations ran, so a suite that evaluates nothing cannot report success. (Guard Contract harness row H1)
- [x] 2.4 Verify each mutation-matrix row drives the suite RED by applying it and observing failure; revert each after. (AC4)
      Outcome: rows 1, 2, 3, 4, 6 and the added 5b (population growth) RED. **Row 5 SURVIVED and is
      labelled EQUIVALENT, not caught** — one call site per process, inside a command substitution, so
      no state crosses calls. Control run green first; each mutation asserted to have landed.
- [x] 2.5 Verify harness row H1 drives RED and H2 passes with outcome `write`. (AC5)

## Phase 3 — Rewire the consumer

- [x] 3.1 Replace the inline G3 block in `arm)` with a single `g3_decide` call plus a `case` over its outcome. (AC2)
- [x] 3.2 Confirm no G3 predicate is evaluated inline in the `arm)` case outside the function. (AC3)
- [x] 3.3 Keep each refusal arm's existing message text, except the equality arm.
- [x] 3.4 `skip-already-current` arm emits a `::notice::` and sets the flag Phase 4 reads.
- [x] 3.5 Retain `::add-mask::` on the dark value; assert the arm case still echoes no input value. (AC8)

## Phase 4 — Skip the redundant write

- [x] 4.1 Guard the G4 write of `INNGEST_POSTGRES_URI` on the Phase 3 flag. (AC6)
- [x] 4.2 Assert the `INNGEST_HEARTBEAT_URL` write and the G5 `INNGEST_CUTOVER_FLIP=armed` write remain reachable on the skip path — skipping them would silently turn a successful arm into a no-op. (AC7)

## Phase 5 — Correct the false message

- [x] 5.1 Replace the equality-arm text; it must no longer claim the arm "would flip onto the DARK backend". (AC11)
- [x] 5.2 New text states the target value is already in place and the write is being skipped.

## Phase 6 — Amend ADR-100

- [x] 6.1 Amend `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`: the arm is idempotent; re-arm after rollback is supported; prod-DSN-in-dark-slot is the documented post-first-arm steady state, not drift. (AC12)
- [x] 6.2 Record why the forward/reverse asymmetry for this value is safe — the flush hazard is held by the monotonic latch (#7228 P0-5), not by G3.
- [x] 6.3 Record the falsified #7462 runbook premise (diagnostic boot holds the prod DSN, not a non-prod one).
- [x] 6.4 Claim no new ADR ordinal.

## Phase 7 — Verification

- [x] 7.1 Diff the G1 and G3.5 regions against `origin/main` and confirm byte-unchanged. (AC9)
- [x] 7.2 Confirm the G3.5-precedes-G4 ordering assertion still passes. (AC10)
- [x] 7.3 `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` — passes with a non-zero assertion count. (AC13)
- [x] 7.4 `bash scripts/lint-workflows.sh` — passes. (AC14)
- [x] 7.5 Walk all 16 acceptance criteria and record pass/fail per item.

## Out of scope — do not do

- Dispatch any cutover operation (`op=arm`, `op=execute`, `op=quiesce-web`, `op=rollback`, `op=verify`).
- Restore the soleur-dev DSN to `soleur-inngest/prd`.
- Add a DSN-restoring inverse to `op=rollback`.
- Retire the soleur-dev co-tenancy defences.
