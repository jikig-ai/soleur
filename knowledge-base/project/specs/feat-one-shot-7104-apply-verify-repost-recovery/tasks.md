# Tasks — feat-one-shot-7104-apply-verify-repost-recovery

Derived from `knowledge-base/project/plans/2026-08-12-fix-apply-verify-repost-recovery-plan.md`
after plan review.

**Read this first.** The plan's `## Implementation Phases`, `## Test Scenarios` and both function
signatures were written before the R13–R15 review revisions and are **superseded** by them
(plan R15.2). Task 1.1 reconciles them. Until it is done, R13/R14/R15 are authoritative.

**The work splits into two PRs** (plan R14.3, CPO condition C1). The order is forced, not
stylistic: PR-B's recovery would fire on the wrong runs without PR-A's discriminator.

---

## Phase 1 — Reconcile the plan (blocks everything else)

- [x] **1.1** Regenerate `## Implementation Phases`, `## Test Scenarios`, and both function
      signatures from R13/R14/R15 so the plan describes **one** machine. Specifically remove the
      R3-reversed teardown relocation from Phase 3, add the `DPF_REPLACED` extraction and the
      saved-plan rework, and correct T1 (a stale frame with `DPF_REPLACED == false` must classify
      non-zero).
- [x] **1.2** Fix the `GATE_MIN_ASSERTIONS` circular reference: Phase 0 records the **pre**-change
      count; the raise happens after the new assertions exist, from a **post**-change measurement.
- [x] **1.3** Restate Guard 1's Property to cover the escape-hatch arm (R15.1) and the
      `DPF_REPLACED == false` arm, and extend the mutation matrix to the post-revision arm set.

## Phase 2 — Preconditions to measure (not assume)

- [x] **2.1** Measure clock skew: compare a recent run's frame `start_ts` against that run's runner
      clock. **This decides whether R2 ships at all** (plan R13.3). Material → implement as a
      single comparator, no fallback arm. ~0 → defer with a re-evaluation trigger.
- [x] **2.2** Probe `FILE_MAP ⊆ TRIGGER_FILES` (plan R15.7). R1's skip arm is only truthful if it
      holds.
- [x] **2.3** Confirm the production call-site pin's three clauses survive an indentation-only wrap
      into `verify_once` (`adjudicate_infra_config /tmp/`, `infra_config_count_invariant /tmp/`, an
      intervening `done`).
- [x] **2.4** Record the pre-change assertion count from `bash apps/web-platform/infra/infra-config-gate.test.sh`.
- [x] **2.5** Re-derive the ADR ordinal across **all** `origin/*` refs (not just `origin/main`).
- [~] **2.6** PR-B SCOPE (gates task 6.4, not PR-A) — Verify `terraform plan -replace=… -target=…` composes and shows exactly one replaced
      resource. Read-only; no apply.

## Phase 3 — PR-A: the sensor (ships first)

- [x] **3.1** Change `Terraform plan` / `Terraform apply` to produce and consume a **saved plan
      file**. This is a dependency of 3.2, not a bonus — `DPF_REPLACED` read from a plan equals
      what was applied only if that plan is what was applied. Independently fixes the confirmed
      TOCTOU (the `host_creates` guard has been adjudicating a discarded plan).
- [x] **3.2** Extract `DPF_REPLACED` from the saved plan's `resource_changes[]`, using the repo's
      `select(.change.actions? | index(...))` convention.
- [x] **3.3** On `DPF_REPLACED == false`: assert the frame is UNCHANGED across the apply
      (equality against a pre-apply reading), plus a runner-side `APPLY_START_EPOCH` assert on
      the degraded sub-arm. **Rewritten at review:** the original text said *skip the freshness
      pin and adjudicate on count + content only* — the design ADR-186 lists under
      *Alternatives considered* as REJECTED, because on this arm a content match is guaranteed
      by construction. Task 1.1 was meant to reconcile superseded plan text into one machine
      and this line escaped it; left as-was, a future reader would conclude the implementation
      drifted from the plan when in fact the plan text was stale. Ends the three false-red merge classes
      (`seccomp-bwrap.json`, `apparmor-soleur-bwrap.profile`, `server.tf`).
- [~] **3.4** DEFERRED — task 2.1 measured skew at ~0 (within a ~±2 s floor), so R13.3's own branch says do not implement. Tracked in #7527. Original text: Implement R2 **only if** task 2.1 justified it, as a single comparator
      (`FRAME_START_TS` exists and differs from `PRE_APPLY_FRAME_START_TS`, absent-pre as sentinel).
- [x] **3.5** Extend `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` to pin
      `FILE_MAP ⊆ TRIGGER_FILES` (task 2.2's invariant).
- [x] **3.6** Tests for 3.2/3.3 in `apps/web-platform/infra/infra-config-gate.test.sh`.
- [x] **3.8** Write ADR-186 (the PR-A decision record). Added at review — Phase 3 had no row
      for it, and task 9.2 is a DIFFERENT ADR belonging to PR-B.
- [x] **3.7** Re-derive PR-A's own brand-survival threshold — it removes production writes and adds
      none, so it is plausibly `none` rather than inherited.

## Phase 4 — PR-B RED: the contract's tests, before the contract

**Design pivot (plan R16.2).** There is **no** higher-order `infra_config_bounded_verify`. The
decision logic is a **pure predicate** matching the six existing siblings in
`infra-config-gate.sh`; the four-line `if`/`else` that consumes it stays in the YAML. This is what
keeps `set -e` in force (R16.1) and what makes the tests exercise the real decision rather than
stubs.

```
infra_config_should_repush <response-file> <pre-frame-start-ts> <apply-start-epoch> <dpf-replaced>
```

- [ ] **4.1** Predicate cases — one per row of the discriminator table, including the
      `start_ts == baseline` boundary (equality is fresh, matching the existing `-lt`). Three
      clauses only: parses, numeric `start_ts`, not newer than the baseline (plan R13.8 — the
      `files_failed` / `fatal_line` clauses are unreachable).
- [ ] **4.2** `dpf-replaced == false` must return non-zero regardless of frame shape (R1(A)).
- [ ] **4.3** Guard 1 matrix re-derived against the predicate: each row is "input X → wrong
      verdict", which is **stronger** than a stub-driven row because it exercises the real decision.
- [ ] **4.4** The escape-hatch case (R15.1): an `ALLOW_MISSING_STATUS` 404 fall-through must never
      be readable as "verified". Under the predicate design this is structural rather than a
      return-code convention — assert it anyway.
- [ ] **4.5** `ALLOW_MISSING_STATUS=true` fall-through fidelity (R4c).
- [ ] **4.6** One integration-shaped test that drives the **real** YAML decision block twice against
      fixture responses and proves pass 2 was reached (plan R13.7).
- [ ] **4.7** Assert each pass's verdict **independently** — no case may collapse to "the last
      attempt passed".

## Phase 5 — PR-B GREEN: the contract

- [ ] **5.1** Add `infra_config_should_repush` to `apps/web-platform/infra/infra-config-gate.sh`,
      following the file's pure-adjudicator convention. Allow-list semantics: every unclassifiable
      input returns non-zero.
- [ ] **5.2** No higher-order dispatcher. No function takes a function name.
- [ ] **5.3** No existing function's behaviour changes.

## Phase 6 — PR-B: the consumer (workflow wiring)

- [ ] **6.1** Keep the poll loop + terminal adjudication + freshness pin **in the step body, not in
      a function** (R16.1 — a function called from a condition context silently disables `set -e`
      for its whole body). The second pass re-runs the block; accept the duplication, which is what
      preserves both `set -e` and the call-site pin.
- [ ] **6.2** Widen the **existing** poll loop's attempt count rather than adding a second loop
      (plan R13.4 — a second `done` would make Guard 2's "strictly between" clause ambiguous). The
      widened loop's own break condition *is* the re-verify R15.3 requires.
- [ ] **6.3** Retain the last **HTTP 200** response separately from the last response overall, and
      feed the classifier that artifact (R15.4).
- [ ] **6.4** Add `repush_once`: re-record the baseline as a **plain shell assignment**, never
      `$GITHUB_ENV` (R4a); rebaseline pass 2 to the stale frame's own `start_ts` (R15.5); run the
      scoped `-replace` plan; apply R3's **exact-cardinality** assert; guard `[[ -s "$CI_SSH_PUB" ]]`;
      wrap the apply in `doppler run --name-transformer tf-var`. No `|| true`, no `2>/dev/null` on
      the apply.
- [ ] **6.5** Add the `declare -F infra_config_bounded_verify` anti-vacuity check, mirroring the
      existing `infra_config_red_alert` pattern.
- [ ] **6.6** Make the step's final statement the orchestrator call. **No `continue-on-error`.**
- [ ] **6.7** Do **not** relocate the bridge teardown (R3 reversed this).

## Phase 7 — PR-B: observability

- [ ] **7.1** Emit one Sentry `warning` event, `op=infra-config-repush-attempted`, carrying attempt
      number and outcome. It is a breadcrumb, **not** the counter — Sentry is write-only here.
- [ ] **7.2** Create the ledger issue **closed**, outside the `ci/` namespace, titled as a running
      tally; widen its dedupe query to `--state all`. Write it with plain `gh issue` calls —
      **do not touch `scripts/infra-config-red-alert.sh`** (five hardcoded sites; widening the
      fail-open P1 helper is the exposure this avoids).
- [ ] **7.3** Create the ledger label as an explicit task; guard the emission so a failure can
      never red a run that actually recovered.
- [ ] **7.4** Exclude dispatch-triggered runs from the counter (R15.8).
- [ ] **7.5** Add the ≥3-in-30-days escalation through the existing P1 channel — the only
      operator-facing artifact.
- [ ] **7.6** One `$GITHUB_STEP_SUMMARY` line naming both attempts.
- [ ] **7.7** Verify the repo watch setting; if it is *All Activity*, the ledger notifies on every
      comment regardless of state, which raises the importance of 7.2's re-titling.

## Phase 8 — PR-B: Guard 2 and the floor

- [ ] **8.1** Extend the production call-site pin: the workflow calls `infra_config_bounded_verify`,
      and `verify_once` is **invoked** at most twice (count invocations, not textual occurrences).
      Keep the three original clauses byte-identical.
- [ ] **8.2** Add Guard 2 mutation rows 1–3. **Row 4 is cut** (it restates the global floor).
- [ ] **8.3** Raise `GATE_MIN_ASSERTIONS` to the post-change measured count.

## Phase 9 — Documentation

- [ ] **9.1** Edit the 000/502/503 recovery prose and the alert step's operator guidance so each
      remedy is attached to the failure shape it belongs to. Never print a bare
      `terraform apply -replace=` fragment without its full resource address; keep the
      `hcloud_server.web` prohibition in every body.
- [ ] **9.2** Write the ADR — **one decision** (the gate may now write production, bounded to one
      shape-gated re-push; the terminal verdict never leaves the step that fails closed), plus the
      **ADR-072 distinction** — NOT "different hook, different lock" (ADR-186 measured that and
      it does not describe ADR-072, which governs `await-ci` waiting on a CI check-run); state it
      as ADR-186 does: ADR-072 waited on a signal that WAS going to arrive, so adaptive waiting
      was the fix, whereas here the newer frame is never coming and R15.6's cancellation/timeout
      consequence. Cite `decision-challenges.md` for the `continue-on-error` rejection rather than
      restating it. Implementation rationale goes in code comments beside the orchestrator.
- [ ] **9.3** File the follow-up issues: the `server.tf`-in-paths-filter contradiction (R9.1); the
      missing `infra-config-channel-red.md` runbook (R9.4); and R2 if task 2.1 deferred it.
- [ ] **9.4** Move #7104 to the **Phase 4** milestone (CPO condition C2).

## Phase 10 — Exit gate

- [ ] **10.1** `bash scripts/test-all.sh` green; `run-registered-suites.sh` reports no new orphan.
- [ ] **10.2** `actionlint` clean on the workflow; extracted `run:` snippets checked with `bash -c`
      (never `bash -n` on the `.yml`).
- [ ] **10.3** Re-derive the ADR ordinal against freshly-fetched `origin/main` immediately before
      merge, and sweep the plan, this file and every AC if it changes.
- [ ] **10.4** Post-merge: dispatch the workflow and confirm the `DPF_REPLACED == false` path —
      explicit `::notice::`, no re-push, adjudication on count + content, green job.
