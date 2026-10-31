# Tasks — feat-11678-merge-queue-batching

Plan: `knowledge-base/project/plans/2026-10-31-ci-merge-queue-batching-queue-jump-plan.md`
Issue: #11678 · PR: #11681 · Branch: `feat-11678-merge-queue-batching`

## 1. Queue-jump script + runbook (ships independently)

- [ ] 1.1 Write `scripts/merge-queue-jump.sh` — `mergeQueueEntry` probe;
  `enqueuePullRequest(jump: true)` for armed PRs (incl. armed-not-yet-enqueued);
  refuse never-armed with named reason; `expectedHeadOid` pin; `--reason` +
  `--yes` non-TTY contract; re-read head/entry after confirmation before
  mutating; MERGED-vanished entry exits 0; distinct jumped-but-unattributed
  exit code on attribution-post failure.
- [ ] 1.2 Write `plugins/soleur/test/merge-queue-jump.test.sh` — fixture
  battery + assertion floor: not-queued refusal, armed-not-yet-enqueued,
  stale `expectedHeadOid`, GraphQL stub serving both entry shapes.
  (Auto-registered via `SUITE_GLOBS` — no `test-all.sh` line.)
- [ ] 1.3 Write runbook `knowledge-base/engineering/operations/runbooks/merge-queue-jump.md`
  — urgency bar, rebuild-cost caveat, queue→jump→`--admin` tiering,
  attribution model, watcher-fencing before any manual dequeue.
- [ ] 1.4 Add CODEOWNERS explicit row for `scripts/merge-queue-jump.sh`.

## 2. TR1 measurements (gate for 3)

- [ ] 2.1 Measure `MergeQueueEntry.headCommit` ↔ candidate `head_sha`
  correlation; record in ADR-270 addendum (decides primary vs fallback source).
- [ ] 2.2 Measure grouped `merge_group.head_ref` shape AND which member
  `pr-<N>` names (deepest vs leader); whether in-flight members stay in
  `mergeQueue.entries` while building.
- [ ] 2.3 Measure `check_response_timeout` clock origin (enqueue vs dispatch)
  and ALLGREEN bisection-vs-group-atomic ejection; re-derive timeout or record
  keep-75 justification.

## 3. CLA group enumeration (precondition — must precede 4)

- [ ] 3.1 Rework `scripts/merge-queue-cla-verify.sh` — primary membership
  `entries` filtered by `headCommit.oid == HEAD_SHA` (positions≤ fallback);
  invariants fail closed: named PR ∈ member set + maximal; `first:N` +
  `pageInfo.hasNextPage` handled or die; zero members = failure; retry budget
  ≥ `gh_read`. Singleton groups MUST stay green (merge→apply window compat).
- [ ] 3.2 Update `merge-queue-cla-synthetics.yml` comment/contract.
- [ ] 3.3 Update `merge-queue-cla-verify.test.sh` — GOOD_REF battery, F3,
  pass floor, negative row (green head + red member → fail), multi-member
  must-PASS row.
- [ ] 3.4 Update `merge-queue-cla-workflow-wiring.test.sh` + `required-checks-merge-group-coverage.test.sh`/fixture (conditional on posting shape).

## 4. The raise

- [ ] 4.1 `infra/github/ruleset-ci-required.tf` L349 → `max_entries_to_merge = 3` + comment re-derivation.
- [ ] 4.2 `scripts/create-ci-required-ruleset.sh` L117 — same value, params in lockstep.
- [ ] 4.3 `infra/github/README.md` params table L110 + jump-path pointer.
- [ ] 4.4 `tests/scripts/test-audit-ruleset-bypass.sh` — Guard-2 sanctioned set {1,3}; T-mq-1.m9 → unsanctioned-value RED; H2 fixture (~L1153) migrated; `_mq_write_queue_block` comment refresh.
- [ ] 4.5 `pr-<N>-` reader sweep + their test files — shared grouped-ref caveat line (correlate by `headSha`/`createdAt`); stall-check aging-window note.
- [ ] 4.6 `test-trio-baseline-census.sh` grouped-shape fixture row.

## 5. Records + canary

- [ ] 5.1 ADR-270 addendum — measurements (2.x), enumeration design, jump decision.
- [ ] 5.2 CLO addendum on `2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` (conditioned on merge).
- [ ] 5.3 Canary after apply: first grouped merge (squash shape, push-event count, per-member CLA); first group ejection blast radius (record-as-observed); live read-back `maximumEntriesToMerge=3` + anonymous probe prints `3`.

## Deferred (documented in-place, no issues — re-evaluation triggers in runbook/ADR)

- `max_entries_to_build` raise (canary-gated; re-evaluate if burst dwell persists)
- Label-triggered jump workflow (re-evaluate if jump cadence becomes routine)
