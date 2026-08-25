---
feature: feat-one-shot-7462-arm-idempotent-g3
plan: knowledge-base/project/plans/archive/20260820-174219-2026-08-20-fix-inngest-arm-idempotent-g3-plan.md
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

## Phase 4 — Skip the redundant write — **REVERTED at review; recorded, not deleted**

- [x] 4.1 ~~Guard the G4 write of `INNGEST_POSTGRES_URI` on the Phase 3 flag. (AC6)~~
      **Implemented, then REMOVED before merge, and AC6 is retired with it.** The guard bought
      nothing — writing a secret to the value it already holds is a no-op — and it introduced a
      branch whose inversion is catastrophic and which no behavioural test covered: flipping its
      polarity skipped the write on the FIRST-arm transition, booting the host onto the dark
      backend while the cutover reported success, with the whole suite green. All three prod
      writes are now unconditional, which is strictly stronger: the arm ESTABLISHES the invariant
      rather than observing it. Idempotence comes from G3 no longer refusing, never from skipping
      a write. Do not reintroduce the branch.
- [x] 4.2 Assert the `INNGEST_HEARTBEAT_URL` write and the G5 `INNGEST_CUTOVER_FLIP=armed` write remain reachable on the skip path — skipping them would silently turn a successful arm into a no-op. (AC7)
      Superseded in form by 4.1's reversal: with every write unconditional there is no skip path
      to keep reachable. The assertion is retained as a regression guard against re-introducing one.

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

## Phase 8 — Review dispositions (added 2026-08-20; the CONCUR gate DISSENTED on both proposed scope-outs, so all four land inline)

- [x] 8.1 Add a pre-G4 flush-latch gate (**G3.7**) to `op=arm`, reusing `_flip_transition_dt`'s
      existing no-SSH Better Stack reader — refuse when a prior `flip-complete` /
      `refuse-rearm-after-done` row exists, **before `armed` is written**. Closes the
      PR-introduced armed-window double-fire at its source and implements the G2 precondition
      `op=resume`'s header has documented since #7228.
      Shipped as a pure `flush_latch_decide()` + a stub-driven `_flush_latch_count()` + a single
      positive-allowlist abort gate. **Not** the alternative of driving the flag to a
      non-allowlisted terminal on G6 failure: `aborted` is already outside the allowlist, so that
      covers only the G6-timeout half and adds a branch for nothing.
- [x] 8.2 41 new assertions across four axes (decision, reader **with argv fidelity**, cross-file
      emitter parity, assembly + ordering). Suite 449/0; anti-deletion floor 408 → 449.
- [x] 8.3 Mutation battery: **16 rows, 16 caught, 0 survived, 0 void**, unmutated control green
      before and after, every mutation asserted to have landed against a pristine backup.
      Axes edited: abort gate (delete / invert / relocate past the prod write), decision (each of
      the three arms), reader (each `--grep`, the `--since` bound, the fail-closed sentinel, the
      purity contract, admitting the `noop-*` firehose), window constant, workflow env mapping,
      cross-file emitter parity (both reasons).
      **Axes deliberately NOT edited, stated plainly:** the assertion helper itself and the
      scenario-dispatch harness (both already carry self-tests that `exit 2` — `assert`'s
      two-direction self-test and the `fl_case` canary), and the suite-wide anti-deletion floor.
- [x] 8.4 Map `FLUSH_LATCH_SINCE` into the workflow step env. Without it the G3.7 refusal would
      name a lever the operator cannot pull — the #6617 dead-remediation defect, which that same
      workflow file already carries a comment about.
- [x] 8.5 Document **G3.6 and G3.7** in the runbook's `op=arm` gate list. G3.6 was this PR's own
      gap: it shipped a gate the runbook never named.
- [x] 8.6 Correct four stale "dark backend" prose surfaces, by content anchor:
      `inngest.tf` (the `~0 prod-pooler load` sentence), `inngest-host.tf` (the "distinct non-prod
      Postgres backend" qualifier in its opening paragraph), `knowledge-base/operations/expenses.md`
      (the `Hetzner CPX22 (inngest)` row's "until the cutover flips it" framing), and
      **`ADR-030-inngest-as-durable-trigger-layer.md`** — the one of the two `ADR-030-*` files that
      owns I8 — at its "Transient by design" clause. The two dated records (the ledger row and the
      ADR-030 changelog entry) are corrected by APPENDING a dated note that cites the old text,
      never by editing it. Table-cell pipe parity re-verified after the ledger edit.
- [x] 8.7 `cloud-init-inngest.yml`: staleness recorded **in ADR-100**, file NOT edited. Verified
      mechanically first — `inngest-host.tf` renders it via `templatefile()` into
      `user_data = base64gzip(...)` on `hcloud_server.inngest`, which carries **no**
      `ignore_changes = [user_data]`, so Terraform diffs the rendered bytes and a comment-only edit
      arms a force-replace of the fleet's sole scheduler. Not a merge-time hazard (none of that
      file's resources are in the per-PR `-target=` set) but a real one on the next
      `apply_target=inngest-host` dispatch, the drift detector, or any untargeted apply. The four
      deferral criteria have no slot for "correct, cheap, unsafe to deliver until an unrelated
      window opens", which is the signal it belongs in the record rather than the backlog.
      Recorded that AC-DARK's **conclusion** survives by a different mechanism (the flip guard
      refuses every prod-URI start outside `{armed,flipping,flushed,done}`) while its stated
      **premise** does not.
- [x] 8.8 ADR-105's `default_pool_size = 30` arithmetic is **NOT a separate finding** — checked,
      not assumed. ADR-105 names the durable resolution as "collapses to **one** prod-pool writer
      permanently", not to zero, and its budget is one writer at `P × 5 ≤ 20 < 30`; the dedicated
      host honours that cap (`--postgres-max-open-conns` is in its durable-backend ExecStart and is
      independently pinned as the durability sentinel). The falsified claim is `inngest.tf`'s "~0"
      alone, which contradicted the ADR it anchors even before the DSN write made it stale.
      Correcting it reconciles the two documents; no budget re-derivation follows. Recorded as a
      negative result in ADR-100 so it is not re-opened.
- [x] 8.9 Net issue flow for this PR: **0**. Nothing filed, nothing re-litigated.
