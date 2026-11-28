# Tasks: design-level feature decomposition with dependency-aware pipeline fan-out

Source plan: `knowledge-base/project/plans/2026-11-28-feat-design-level-feature-decomposition-plan.md`

## 1. Architecture, provenance, and dispatch feasibility

- [ ] 1.1 Create the ADR for “feature-orchestrator composes one-shot pipelines.”
- [ ] 1.2 Add the implementation clean-room provenance instruction to implementation prompts/artifacts.
- [ ] 1.3 Write failing fixtures for nested child dispatch identity, cancellation, resume, and occupancy.
- [ ] 1.4 Prototype harness-mediated nested noninteractive child dispatch using trivial/mock children.
  - [ ] 1.4.1 Prove two concurrent children or record why parallel mode is unavailable.
  - [ ] 1.4.2 Prove controller-emitted envelopes can be executed by the harness without direct skill invocation from Node.
  - [ ] 1.4.3 Gate parallel mode on evidence; implement explicit sequential fallback.
- [ ] 1.5 Prototype explicit-argument child metadata/return contract and machine-readable postmerge evidence.

## 2. Graph schema and pure deterministic core

- [ ] 2.1 Create `plugins/soleur/skills/feature-orchestrator/lib/feature-graph.mjs`.
- [ ] 2.2 Define schema version 1, node fields, controlled resource keys, and canonical serialization.
- [ ] 2.3 Implement validation for duplicates, dangling refs, self-dependencies, cycles, malformed schema versions, unsafe IDs, and unknown resource keys.
- [ ] 2.4 Implement separate policy checks for node count, concurrency, caps, overlap, and approval overrides.
- [ ] 2.5 Implement topological readiness, permanent-failure propagation, independent continuation, unaccounted/paused blocking, and deterministic ordering.
- [ ] 2.6 Implement aggregate classification that treats missing evidence as non-success.
- [ ] 2.7 Create `plugins/soleur/skills/feature-orchestrator/references/graph-schema.md`.

## 3. Controller façade and operator interface

- [ ] 3.1 Create `plugins/soleur/skills/feature-orchestrator/scripts/feature-orchestrator.mjs` as a thin façade over the pure graph module plus small GitHub/worktree/evidence adapters.
- [ ] 3.2 Implement operator verbs `preview`, `approve`, `run`, `status`, and `stop-scheduling`.
- [ ] 3.3 Define exact exit codes, stdout schemas, and happy-path/resume/failure transcripts.
- [ ] 3.4 Implement `status --run <id>` tree output with node state, evidence, blocker, next action, links, and exact resume command.
- [ ] 3.5 Implement shared session-state locking/semaphore with stale-owner recovery across reconcile/reserve/dispatch.
- [ ] 3.6 Implement fail-closed parent reservation ledger for active slots, approved dispatch count, and retry count.

## 4. Orchestrator skill intake, approval, and child artifacts

- [ ] 4.1 Create `plugins/soleur/skills/feature-orchestrator/SKILL.md` with the budgeted 18-word description.
- [ ] 4.2 Implement design intake and decomposition into canonical graph bytes.
- [ ] 4.3 Implement dry-run rendering of graph, exact child issue titles/bodies/briefs, overlap/resource findings, concurrency, depth, and cost multiplication.
- [ ] 4.4 Bind approval to the hash of canonical graph bytes plus exact public-write bytes; require reapproval on mutation.
- [ ] 4.5 Run pre-create secret scanning over exact public-write bytes.
- [ ] 4.6 Initialize the journal and idempotency keys before the first external write.
- [ ] 4.7 Create one immutable child issue per approved feature with run/node/branch/graph correlation and blocked/holding state.
- [ ] 4.8 Update the journal atomically after every issue-write transition.

## 5. Dispatch, evidence, failure, cancellation, and resume

- [ ] 5.1 Implement controller-emitted child dispatch envelopes with explicit run/node/branch/PR/receipt metadata.
- [ ] 5.2 Implement harness-mediated `soleur:one-shot` invocation and require child PRs to close their child issue.
- [ ] 5.3 Add narrow explicit-argument orchestrated-child support to `plugins/soleur/skills/one-shot/SKILL.md` without weakening lifecycle gates.
- [ ] 5.4 Add machine-readable postmerge verification evidence to `plugins/soleur/skills/postmerge/SKILL.md` if absent.
- [ ] 5.5 Implement evidence adapters distinguishing transport failure, negative state, malformed evidence, missing evidence, timeout, and success.
- [ ] 5.6 Implement child receipts in shared session state before worktree cleanup, keyed by run/node/branch/PR/merge SHA.
- [ ] 5.7 Implement stall heartbeat/deadline policy and partial final reports.
- [ ] 5.8 Implement `stop-scheduling` with active-child/residual-spend disclosure; never claim real child cancellation.
- [ ] 5.9 Implement resume reconciliation/adoption/foreign-collision behavior and modified-graph refusal.
- [ ] 5.10 Implement terminal child issue label/comment/close cleanup.

## 6. Collision, tally, and scope containment

- [ ] 6.1 Preserve existing collision protection; pass parent linkage in metadata/journal rather than weakening gates.
- [ ] 6.2 Implement approved sibling-set correlation narrowly enough to avoid false duplicate classification.
- [ ] 6.3 Read child counters through existing `pipeline-tally.sh show --branch` and record parent snapshots without duplicate accounting.
- [ ] 6.4 Propagate allocated child caps in dispatch envelopes.
- [ ] 6.5 Add pre-merge diff-containment verification against approved scope/exclusions.

## 7. Plugin integration and tests

- [ ] 7.1 Keep v1 unrouted/internal; do not add `/go` or workflow-fidelity pipeline registration.
- [ ] 7.2 Update component counts/README only where required by component tests.
- [ ] 7.3 Update autonomous-loop/API-budget/tally sentinel registration in `plugins/soleur/test/components.test.ts`.
- [ ] 7.4 Add `plugins/soleur/test/feature-orchestrator-graph.test.ts` unit coverage.
- [ ] 7.5 Add `plugins/soleur/test/feature-orchestrator-graph.test.sh` and fixtures.
- [ ] 7.6 Cover valid DAG, duplicate IDs, dangling refs, self-deps, cycles, wrong schema version, unsafe IDs, unknown resource keys, overlap policy failure, cap policy failure, deterministic ordering, permanent failure propagation, independent continuation, missing evidence, stalled deadline, approval-hash mismatch, crash reconciliation, foreign collision, stop-scheduling, resume, and scope breach.
- [ ] 7.7 Run skill-description budget measurement and affected plugin test suites.
- [ ] 7.8 Do not execute a real live fan-out in this PR; document post-merge dogfood invocation and metrics.
