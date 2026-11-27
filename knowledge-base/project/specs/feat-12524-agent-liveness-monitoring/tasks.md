# Tasks: Spawned-Agent Liveness Monitoring (`#12524`)

## Phase 1: Capability Matrix, Metadata Schema & ADR

- [x] 1.1 RED(unit): Write failing unit tests in `plugins/soleur/test/agent-liveness.test.ts` for `getLivenessCapabilities()`, `classifySeatSilence()`, `decideSeatRecovery()`, and metadata-only seat state schema
- [x] 1.2 GREEN: Implement `LivenessCapabilities` and `getLivenessCapabilities()` in `plugins/soleur/lib/harness.ts` and create `plugins/soleur/lib/agent-liveness.ts` (blockedBy: 1.1)
- [x] 1.3 Author `knowledge-base/engineering/architecture/decisions/ADR-332-cross-harness-agent-liveness.md` documenting the cross-harness liveness and bounded-recovery contract

## Phase 2: Ephemeral Seat State CLI & `run-health-emit.sh` Integration

- [ ] 2.1 RED(integration): Write failing integration tests in `plugins/soleur/test/seat-liveness.test.sh` with live, slow-progress, rate-limited, truncated, dead/zombie, and 24h TTL cleanup controls
- [ ] 2.2 GREEN: Create `plugins/soleur/scripts/seat-liveness.sh` (`init`, `heartbeat`, `sweep`, `decide`, `cleanup`, `--self-test`) and extend `plugins/soleur/scripts/run-health-emit.sh` with seat-liveness summary counts (blockedBy: 2.1)

## Phase 3: Fan-Out Workflow Integration

- [ ] 3.1 Wire seat liveness registration, sweep, dirty-diff verification, and bounded recovery into `plugins/soleur/skills/one-shot/SKILL.md` and `plugins/soleur/skills/review/{SKILL.md,workflows/review.workflow.js}` (blockedBy: 1.2, 2.2)
- [ ] 3.2 Wire seat liveness registration, sweep, dirty-diff verification, and bounded recovery into `plugins/soleur/skills/{resolve-parallel,resolve-pr-parallel,resolve-todo-parallel,drain-labeled-backlog}/{SKILL.md,workflows/*.workflow.js}` (blockedBy: 1.2, 2.2)

## Phase 4: Verification & Quality Gates

- [ ] 4.1 Run the touched-file suites (`agent-liveness.test.ts`, `seat-liveness.test.sh`, `harness.test.ts`), affected gate, and lint checks (blockedBy: 1.2, 1.3, 2.2, 3.1, 3.2)
