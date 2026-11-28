---
title: "feat(engineering): design-level feature decomposition with dependency-aware pipeline fan-out"
type: feat
date: 2026-11-28
slug: feat-design-level-feature-decomposition
branch: feat-12528-feature-decomposition
issue: 12528
closes: 12528
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(engineering): design-level feature decomposition with dependency-aware pipeline fan-out

## Overview

Implement issue #12528 as a plugin-local internal-dogfood orchestrator, working name `feature-orchestrator`. The orchestrator accepts one approved design document, proposes a small dependency-aware feature graph, presents a dry-run preview, and — after one explicit operator approval — creates one child issue per feature and dispatches each feature through the existing `soleur:one-shot` lifecycle. Independent children run up to concurrency 2 (hard cap 3). Dependents dispatch only after prerequisite PRs merge and postmerge verification completes. Failure of a prerequisite recursively skips descendants while independent branches continue.

This is a composition layer, not a new pipeline and not a server-side service. The implementation must preserve the operator-approved role-separated clean-room boundary: implementation agents receive only this plan/spec and Soleur repository context and must not retrieve or inspect upstream inspiration.

## Research Insights

### Premise Validation

- Issue #12528 is open and not closed by any PR (`gh issue view 12528 --json state,title,closedByPullRequestsReferences`).
- Draft PR #13105 is open and unmerged; it is this branch's own artifact vehicle, not a foreign collision.
- Deferred follow-up #13120 is open and has no open implementation collision.
- `collision-precheck.sh 12528` reports only PR #13105, the current vehicle; `collision-precheck.sh 13120` is clear.
- Required integration files exist on `origin/main`: `plugins/soleur/skills/one-shot/SKILL.md`, `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`, `plugins/soleur/scripts/pipeline-tally.sh`, `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, and `plugins/soleur/lib/workflow-fidelity.ts`.
- No stale premise found. The only collision hit is the expected current draft PR.

### Property List

1. A design can be split into reviewable feature units with explicit dependency relationships.
2. Invalid dependency relationships fail before any GitHub or worktree side effects.
3. Independent feature units can run concurrently without sharing a mutable branch or worktree.
4. Dependent feature units start only after prerequisite code has merged and verified.
5. Failure of a prerequisite prevents dependent spend while allowing unrelated work to finish.
6. The operator can approve the whole graph once and later audit/resume it from durable state.
7. Aggregate fan-out cost/work is bounded across all children, not only per branch.
8. Child completion is established from external evidence, not prose self-report.
9. Intentional sibling feature PRs are distinguishable from accidental duplicate work.
10. The implementation remains independent of AGPL-licensed expressive material.
11. Sibling branches avoid semantic/file collision where the graph can detect it before dispatch.
12. The operator can see and control each feature through a stable GitHub tracking object.

### Mechanism Minimality and Cut List

| Mechanism in the ask/proposal | Property it buys | Already covered on `origin/main`? | Disposition |
|---|---|---|---|
| Decompose design into a machine-readable feature graph | properties 1, 2, 6 | No. Repo research found no executable feature-graph primitive; existing `depends_on` uses are metadata/static annotations. | Keep |
| Dependency-aware scheduler/dispatcher | properties 3, 4, 5, 6 | Partial precedent only: resolve workflows tier local edits; drain delegates clusters to one-shot without dependency edges or failure propagation. | Keep |
| Per-feature worktrees/branches/PRs | isolation part of property 3 | Yes. `one-shot` + `worktree-manager.sh` already own this. | Reuse; do not rebuild |
| Full plan/work/review/ship lifecycle per feature | child correctness and review gates | Yes. `soleur:one-shot` owns it. | Compose; do not rebuild |
| Server-side durable orchestration service | durability/resume | No, but not required for plugin-local v1. | Cut as v1 overreach |
| Workflow-first scheduler | deterministic parallelism | Dynamic workflows are useful later, but long-running nested one-shot dispatch is unproven. | Cut from v1 critical path; tracked as #13120 |
| Extending `drain-labeled-backlog` | dispatch precedent | Drain semantically batches cleanup issues into one PR, not a feature DAG. | Cut as primary surface |

### Local research consolidation

- `one-shot` is the correct child execution unit: it owns worktree creation, draft PR creation, plan/deepen, work, review, QA, compound, ship, merge, and postmerge verification.
- `drain-labeled-backlog` is the closest fan-out precedent: it validates input, builds scoped briefs, delegates to `soleur:one-shot`, and counts dispatches. It lacks dependency ordering, failure propagation, durable feature IDs, and a true concurrency scheduler.
- `resolve-todo-parallel`/`resolve-parallel` contain dependency-tiering concepts, but they edit within one branch and do not dispatch independent pipelines.
- `pipeline-tally.sh` is branch-scoped. It can supply child evidence, but the parent needs its own run journal and aggregate accounting.
- `worktree-manager.sh` already provides leased isolated worktrees and idempotent draft PRs through one-shot.
- `workflow-fidelity.ts` and `commands/go.md` are the integration points if the orchestrator becomes a routable pipeline skill.
- Relevant tests/sentinels include `components.test.ts`, `workflow-fidelity.test.ts`, harness parity tests, dynamic workflow count bridging tests, and drain fixture style tests.

### Institutional learnings applied

- Parallel fan-out must be bounded, consented, scoped, and coordinator-integrated.
- Spawn acceptance is not success; persist the expected child set and collect terminal outcomes fail-closed.
- Collision gates are point-in-time; revalidate issue/PR/file state before expensive transitions.
- Empty or apparently inactive worktrees may be live; adopt or stop rather than duplicate.
- Durable artifacts beat mutable progress cursors; recover from positive content.
- Parallelizing serial work changes the resource bound, not just speed.
- Cost-cap stops must be classified and resumable, never silent or blocking forever.
- File disjointness is insufficient when shared CI, migration, deployment, test-lock, or external-service resources are involved.

### Community/functional overlap

Community research found partial prior art but no exact fit. Examples include dependency-aware parallel task dispatch, planner/executor swarm skills, orchestration platforms with structured run artifacts, feature-factory products, archived branch-per-feature dependency tools, and collision-scoring tools. All were skipped for installation because none compose Soleur's existing `one-shot` lifecycle with plugin-local child issues, typed outcomes, cross-branch rollup, and Soleur collision semantics. Highest-value semantic patterns: independent feature graph JSON, conservative file ownership, dependency waves with a hard fan-out cap, structured child-result artifacts, orchestrator-owned collision policy, and deterministic rollup generation. No community artifact is installed.

### Skill description budget

Measured baseline with the enforcing test helpers: **2469/2490 words, 21 words headroom**. Proposed new skill description draft is 18 words: “This skill should be used when decomposing a design into dependency-aware features and fanning them out through one-shot.” It fits without sibling trims. Re-measure after implementation.

## Problem Statement / Motivation

`soleur:one-shot` ships one branch and one PR. Large design documents require manual pre-slicing into issues, then manual sequencing of separate one-shot runs. That produces either oversized PRs or operator-heavy milestone execution. The missing capability is an orchestration layer that proposes the slice boundaries once, proves them valid, and executes them through the existing lifecycle with bounded parallelism and failure-aware sequencing.

## Proposed Solution

Build `feature-orchestrator` as a new Soleur skill backed by deterministic graph/state helpers. The skill composes `soleur:one-shot`; it does not inline lifecycle phases. A narrow orchestrated-child result contract in `one-shot` provides machine-readable correlation through explicit child arguments and return-contract metadata; environment variables are not used because harnesses do not reliably propagate them into spawned agents. A deterministic controller script is the sole control-plane chokepoint for validation, preview, approval binding, journal mutation, occupancy accounting, readiness decisions, evidence verification, reconciliation, stop-scheduling state, and rollup. It does not invoke `soleur:one-shot` directly: skill invocation is harness-mediated. The orchestrator skill/agent executes controller-emitted dispatch envelopes through the harness and returns outcomes to the controller. A parent run journal is the authoritative orchestration state; GitHub child issues/PRs are externally visible evidence.

### High-level flow

1. Intake design document and optional parent issue.
2. Decompose into a proposed feature graph.
3. Validate graph fail-closed before side effects.
4. Render dry-run preview: nodes, edges, overlap/shared-resource warnings, depth, concurrency, cost multiplication, child artifact plan.
5. Operator approves once.
6. File one child issue per feature and optionally link blocking relationships.
7. Dispatch ready independent features up to cap through `soleur:one-shot`.
8. Wait for externally verified merge/postmerge completion before unblocking dependents.
9. On terminal child failure, mark descendants skipped and continue independent branches.
10. Emit final partial/complete report and resume instructions.

## Scope Check

### Ask mapping

| Ask/property | Plan response |
|---|---|
| Decompose one design into features with dependency edges | FR1-FR4; graph schema and validator |
| Fan each feature through the existing one-shot pipeline | FR5-FR8; compose one-shot, no lifecycle reimplementation |
| Parallel where independent | FR6; ready-node dispatch under cap |
| Sequential where dependent | FR6; prerequisite merge/postmerge readiness |
| Skip dependents of failed features | FR9; recursive skip propagation |
| Per-feature worktrees already exist | Reuse through one-shot; no new worktree manager |
| Clean reimplementation | TR6; implementation prompt boundary and provenance review |

### Item provenance

| Planned item | Provenance |
|---|---|
| New orchestrator skill/helper/tests | Directly mapped to issue mechanism |
| One-shot orchestrated-child receipt | Inferred from verified gap: no machine-readable child result contract; required by external-evidence property |
| Parent run journal/rollup | Inferred from operations/legal/product assessments; required for audit, caps, and resume |
| Child issue filing | Operator decision during brainstorm; maps to properties 6, 9, and 12 as the externally visible control/correlation object for each feature |
| Human approval once before spend | Operator decision during brainstorm |
| Autonomous child merge | Operator decision during brainstorm |

No unmapped ask. No unjustified inferred item.

### Split assessment

The dynamic workflow port is deliberately split to #13120 because it is execution machinery after the prose contract is proven, not required for v1 correctness. External productization is out of scope and must return only after dogfood evidence.

## Technical Considerations

### Architecture impacts

- New plugin surface: `plugins/soleur/skills/feature-orchestrator/`.
- Deterministic pure logic in an importable module for validation, readiness, failure propagation, and result classification.
- Narrow one-shot contract addition for orchestrated-child result receipts.
- No DB, server route, Terraform, Inngest, or hosted runtime in v1.
- No workflow port in v1; #13120 tracks the follow-up.

### Graph schema direction

Design independently in Soleur conventions. Required conceptual fields:

- `id`, `title`, `scope`, `exclusions`, `depends_on`, `file_hints`, `acceptance`, `shared_resources`.
- Parent run metadata: graph hash, caps, approval state, child issue/branch/PR/worktree/receipt state, terminal classification.

The implementation must not copy upstream schema names, file layout, examples, or wording. These field names may be refined by the implementer if tests and docs remain coherent.

### Scheduler semantics

- Graph validation rejects duplicates, dangling refs, self-dependencies, cycles, malformed schema versions, and unsafe IDs. Node-count/concurrency limits are execution-policy checks, not graph-validity checks; approval/scheduling rejects over-cap graphs unless the operator explicitly chooses a supported override within hard caps.
- Readiness is derived from terminal prerequisite evidence, not wall-clock order.
- Concurrency is a scheduler-owned in-flight count. Pipeline tally is cumulative accounting, not occupancy.
- Overlap/shared-resource risk serializes nodes unless the approved graph already encodes ordering.
- Dependents are never pre-branched; they start after blockers merge so one-shot branches from current `origin/main`.
- Resume reconciles journal vs live GitHub/worktree state before any dispatch.

### Deterministic contract decisions

- **Nested-dispatch gate:** parallel dispatch remains disabled until a controlled prototype proves two child `one-shot` invocations can run noninteractively, independently, and resumably in the target harness. The prototype may use trivial/mock child tasks, but it must exercise real process/agent spawning, journal occupancy, cancellation, and result classification. If the harness cannot support this, v1 degrades to explicit sequential mode rather than unsafe fake parallelism.
- **Controller:** `plugins/soleur/skills/feature-orchestrator/scripts/feature-orchestrator.mjs` owns deterministic control-plane operations: `preview`, `approve`, `run`, `status`, and `stop-scheduling`; internal suboperations may exist, but the operator-facing contract is these five. The executable is a thin façade over the pure graph module plus small GitHub/worktree/evidence adapters, not a monolithic implementation of all logic. It emits explicit child dispatch envelopes containing feature metadata and a required return contract. The skill/harness performs the actual nested `soleur:one-shot` invocation; the controller records occupancy before handoff and consumes externally verified results afterward.
- **Operator contract:** document exact invocations, exit codes, stdout schemas, and transcripts for happy path, resume, policy stop, and failure. `status --run <id>` renders a tree of nodes with child issue/PR links, branch/worktree, last verified evidence, blocker, next action, and exact resume command.

- **Schema version:** the graph carries an explicit integer `schema_version`. v1 is `1`; unknown or missing versions fail validation.
- **Unsafe input:** invalid IDs, scope text, paths, or refs are rejected. v1 never normalizes unsafe IDs into safety.
- **Overlap/resources:** overlapping high-risk file hints or shared controlled resource keys are validation errors unless the operator adds an explicit dependency edge. v1 does not silently synthesize serialization edges; the approved graph is the exact graph executed. `shared_resources` is a closed enum (initially `migration`, `deploy`, `ci-capacity`, `test-lock`, `terraform`, `package-publish`, `external-service`), not free-form prose; unknown keys fail validation.
- **Approval binding:** approval is bound to the SHA-256 of canonical graph bytes. Operator edits require a fresh validation, dry-run, hash, and approval. Dispatch refuses any hash mismatch among approved artifact, journal, and graph input.
- **Evidence:** prerequisite completion requires all of (a) child PR merged, (b) a machine-readable postmerge verification artifact present and passing, and (c) terminal child receipt correlated by run/node/branch/PR. v1 must add that artifact/result surface if none exists; prose postmerge output alone is insufficient. Child issue closure is informational only, never sufficient. GitHub API/transport failure, malformed JSON, negative state, and missing artifacts are distinct classes; transport failure is retryable per bounded policy, while malformed/missing evidence is fail-closed.
- **Issue lifecycle:** child issues are filed only after approval. The approved graph and idempotency keys are journaled before the first external write; the journal updates atomically after every issue/dispatch transition so crash windows are reconcilable. Issues receive a blocked/holding state or label until their node becomes dispatch-ready. Terminal skipped/stopped/unaccounted nodes receive an explanatory comment and label transition; skipped or operator-stopped child issues are closed when no further work is intended, while unaccounted issues remain open but visibly blocked pending reconciliation.
- **Stop scheduling:** `stop-scheduling` stops new dispatch, records a classified stop, and reconciles already-running children as external processes. It does not claim real child cancellation. The command output must list active children and residual expected spend; any future real child cancellation requires explicit operator acknowledgment.
- **Run locking:** at most one active orchestration run per target repository plus canonical design hash. Run ID is instance identity, not the dedupe key. A second invocation for the same target/design reconciles/resumes rather than starting duplicate fan-out.
- **Failure states:** terminal `failed` recursively marks descendants `skipped-blocked`. `unaccounted` blocks descendants pending reconciliation; descendants become `skipped-blocked` only when the prerequisite is terminally classified failed or unrecoverable. Multi-prerequisite nodes require every prerequisite complete.
- **Budget model:** v1 uses enforceable units, not vague “full run” estimates: approved node dispatch count, active pipeline slots, retry count, and observed child counters when available. Default dispatch budget equals the approved node count; failed children do not retry automatically. Child one-shot loops retain their existing internal caps. The controller reads child counters through the existing `pipeline-tally.sh show --branch <child>` surface and records snapshots in the parent journal; it must not maintain a second divergent counter system or double-count workflow/prose paths.
- **Resume:** matching keys are run ID, graph hash, feature ID, child issue, branch, worktree, PR, merge SHA where present, and receipt. A modified graph hash refuses resume and requires new approval. Existing foreign artifacts stop the affected node as collision; existing orchestrated artifacts are adopted only when keys match. Skipped nodes are not retried implicitly; an explicit new approved graph/run is required.
- **Child identity:** each child invokes exactly one immutable child issue. The approved issue body carries the run ID, node ID, intended branch name, graph hash, scope, exclusions, receipt path, approved sibling set, and return contract. Child dispatch args repeat those explicit identifiers and require `Closes #<child-issue>` in the child PR; postmerge verification counts only when that close exists. Child dispatch never derives resume identity from regenerated prose or slugified args alone.
- **Supervisor mechanics:** the harness-facing skill owns a supervisor loop with explicit states `reconcile → reserve → emit dispatch envelope → await/wake on child completion → record result → repeat`. Wake/cancel mechanics are harness-specific and therefore isolated behind the skill prompt; the controller owns only deterministic state transitions. If no harness primitive can supervise two concurrent children, v1 runs sequentially.
- **Parent reservation ledger:** the controller maintains a fail-closed parent reservation ledger for active slots, approved dispatch count, and retry count. Ledger unreadable/unknown is `STOP`, unlike child `pipeline-tally` fail-open telemetry. Child caps are allocated explicitly in dispatch envelopes; observed child counters remain telemetry read through `pipeline-tally.sh show --branch`.
- **Cross-instance serialization:** reconcile/reserve/emit must occur under the shared session-state lock/semaphore with stale-owner recovery. Atomic file write alone is insufficient because it does not serialize multi-step decisions across orchestrator instances.
- **Receipt persistence:** child receipts are written to shared session state before worktree cleanup and keyed by run ID, node ID, branch, PR, and merge SHA. Cleanup must not destroy the only machine-readable result.
- **Failure taxonomy:** distinguish `paused-budget-capped`, `unaccounted`, `failed-permanent`, and `skipped-blocked`. Only `failed-permanent` recursively skips descendants. `paused-budget-capped` and `unaccounted` block dependents pending explicit resume/reconciliation; they are never silently terminal success.
- **Stall/liveness policy:** each child has a declared heartbeat/evidence timestamp and a hard wall-clock deadline (default 6 hours unless the approved run overrides it within documented bounds). A child with no verifiable progress past the probe interval becomes `stalled`; after deadline or failed bounded probes it becomes `unaccounted` and the run can still emit a partial final report. The exact intervals are constants in the controller and covered by failure-injection fixtures.
- **Public-write approval:** the approval hash covers canonical graph bytes plus exact child issue titles, bodies, and dispatch briefs. Mutation requires reapproval. Pre-create secret scanning must run over those exact bytes.
- **Diff containment:** before autonomous child merge, the child pipeline/orchestrator verifies the PR diff is contained within approved scope/exclusions or records a scope breach. Orchestration must not widen child scope silently.

### Security and prompt-injection considerations

- Design docs, issue bodies, feature names, and generated scopes are untrusted input.
- IDs/slugs use a strict character set; shell commands never interpolate raw prose.
- Child briefs are least-context: feature slice plus required interfaces, not whole-repo/design replication by default.
- Single-provider v1; no silent cross-vendor routing.
- External writes confined to approved target repository.
- Public issue/PR content must use existing publication/secret safeguards.

### NFR impacts

- Reliability: partial failures must be explicit and resumable.
- Cost/resource use: aggregate cap and conservative concurrency bound spikes.
- Operability: run journal and final report are the observability surface.
- Portability: prose skill remains cross-harness; workflow is deferred.
- Compliance: clean-room provenance and local-only v1 are mandatory.

## User-Brand Impact

- **If this lands broken, the user experiences:** multiple incorrect autonomous branches/PRs or a milestone reported complete when only part of the design landed.
- **If this leaks, the user's [data / workflow / money] is exposed via:** design/repository content replicated into public child issues/PRs or excessive model/CI spend from uncontrolled fan-out.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** v1 is internal dogfood, but one bad run can create public artifacts and real spend; that is a single-operator incident rather than an aggregate user pattern.

CPO sign-off is satisfied for planning by the CPO brainstorm assessment carried forward here; `soleur:engineering:review:user-impact-reviewer` remains required at review time.

## GDPR / Compliance Gate

- v1 is plugin-local and internal-only; no new Jikigai-controlled processing activity, hosted datastore, or processor relationship is introduced.
- Child issues/PRs are public repository artifacts and must not include secrets, personal data, confidential client content, or copied third-party text.
- Article 22 expectation: negative; the system acts on code tasks, not decisions about people.
- Cross-provider routing is forbidden in v1.
- Any future hosted, operator-assisted, Jikigai-keyed, alpha-tester, or customer-repository use requires fresh legal review and Article 30/DPIA/LIA screening before enablement.

## Observability

```yaml
liveness_signal:
  what: "feature-orchestrator run journal with per-node state transitions and final aggregate verdict"
  cadence: "on every dispatch, completion, failure, skip, cap, cancellation, and final report"
  alert_target: "operator terminal plus parent spec/run artifact"
  configured_in: "plugins/soleur/skills/feature-orchestrator/"

error_reporting:
  destination: "parent run journal and orchestrator terminal output"
  fail_loud: "nonzero validation exit, explicit failed/skipped/unaccounted node states, or budget-capped classified stop"

failure_modes:
  - mode: "dependency cycle or dangling dependency"
    detection: "deterministic validator rejects before side effects"
    alert_route: "operator terminal and run journal"
  - mode: "child one-shot fails or is budget-capped"
    detection: "child receipt plus external PR/issue/session-state verification"
    alert_route: "run journal marks node failed and descendants skipped"
  - mode: "child outcome missing or unaccounted"
    detection: "expected-child set lacks terminal receipt/evidence"
    alert_route: "final report is partial/failed, never success"
  - mode: "aggregate cap reached"
    detection: "orchestrator rollup gate before next dispatch"
    alert_route: "classified budget-capped stop with resume artifact"

logs:
  where: "knowledge-base/project/specs/<orchestration-parent>/ plus child spec session-state artifacts"
  retention: "repository lifetime for committed artifacts; local branch lifetime for scratch state"

discoverability_test:
  command: "bash plugins/soleur/test/feature-orchestrator-graph.test.sh"
  expected_output: "feature-orchestrator-graph: ok"
```

## Encryption Posture

Not applicable: v1 introduces no persistent hosted datastore and no new cross-component network connection. Run artifacts are local repository files; GitHub API traffic uses existing authenticated `gh` transport and credential posture.

## Guard Contract

### Guard 1 — feature graph validator

**Property.** No dependency-invalid, unsafe, duplicate, over-cap, or unsafe-overlap graph can produce child side effects.

**Assembly.** All orchestrator entry paths that accept or load a graph: initial decomposition, operator-edited graph approval, and resume reconciliation. The chokepoint is a single pure validation function invoked before issue creation, dispatch, or resume.

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Add a dependency cycle after validation-order sorting | guard RED / validation rejects before side effects |
| Add a dangling dependency ID | guard RED |
| Duplicate a feature ID | guard RED |
| Add a sixth feature under default cap 5 | guard RED |
| Make two independent nodes own the same high-risk file path without an explicit dependency | guard RED / validation rejects |
| Harness row: validator test invokes the wrong `schema_version` or empty fixture | guard RED |
| Must-pass row: valid DAG with width 2 and depth 2 | guard PASS |

**Anchor.** The guard is anchored by independent unit fixtures and by the orchestrator's dry-run rendering of the same graph hash that is later approved.

### Guard 2 — dependency-aware scheduler/result classifier

**Property.** A node dispatches only when all prerequisites are externally complete; failure skips descendants without stopping independent branches; missing evidence is never success.

**Assembly.** Every state transition in the parent run journal and every child receipt classification path. The chokepoint is a pure scheduler/classifier module consumed by the prose skill and tests.

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Mark prerequisite merged in prose but leave PR unmerged externally | child remains not-ready / guard RED if dispatched |
| Fail prerequisite `A` and attempt dependent `B` | `B` becomes `skipped-blocked`; independent `C` may continue |
| Remove a child terminal receipt after spawn acceptance | node becomes unaccounted/failed-closed, never complete |
| Reorder completion callbacks so a dependent finishes before a blocker | aggregate classification remains deterministic and does not depend on callback order |
| Harness row: fixture omits one expected child from the graph | guard RED |
| Must-pass row: two independent children under cap 2 both complete | guard PASS |

**Anchor.** External GitHub/issue/session evidence is the anchor; child prose and orchestrator memory are not authoritative.

## Implementation Phases

### Phase 1 — Clean-room boundary, architecture record, and dispatch prototype

1. Create the architecture decision record for “feature-decomposition orchestrator composes one-shot pipelines.”
2. Add a provenance note to the implementation prompt/plan artifacts: implementation agents must not retrieve upstream inspiration.
3. Prototype nested noninteractive child dispatch first, including two concurrent trivial/mock children, cancellation, resume, and journal occupancy. Gate parallel mode on this evidence; sequential mode is the fallback. The controller may only emit envelopes; the harness must perform child invocation.
4. Prototype explicit-argument orchestrated-child metadata/return contract plus machine-readable postmerge evidence on a mocked/minimal path.
5. Validate that a child can emit feature ID, parent run ID, branch, PR, terminal state, failure class, budget-cap state, machine-readable postmerge evidence, and artifact paths without weakening completion floors.

### Phase 2 — Graph schema and deterministic validator

1. Create `plugins/soleur/skills/feature-orchestrator/lib/feature-graph.mjs` with pure validation, topological readiness, failure propagation, and aggregate classification helpers.
3. Create `plugins/soleur/skills/feature-orchestrator/references/graph-schema.md` documenting the independently designed schema, including `schema_version`, rejection-only unsafe-input behavior, overlap rejection, caps, evidence classes, and transition table.
4. Add unit/fixture tests covering valid DAGs, duplicate IDs, dangling refs, self-deps, cycles, cap overflow, unsafe IDs, overlap serialization, failure propagation, independent continuation, missing evidence, and deterministic ordering.

### Phase 3 — Orchestrator skill intake, preview, approval, and child issues

1. Create `plugins/soleur/skills/feature-orchestrator/SKILL.md` with an 18-word model-visible description within budget.
2. Implement design intake, decomposition prompt, graph artifact writing, dry-run rendering, and explicit approval-once flow.
3. Implement immutable child issue creation and parent/child linkage after approval, embedding run/node/branch/graph correlation and exact approved public-write bytes.
4. Ensure no child issue/branch/worktree/PR is created before approval.
5. Add API-budget disclosure and pipeline-tally/autonomous-loop sentinel integration.

### Phase 4 — Scheduler, run journal, caps, dispatch, and resume

1. Create `plugins/soleur/skills/feature-orchestrator/scripts/feature-orchestrator.mjs` as the sole control-plane controller.
2. Implement parent run journal schema, shared cross-instance run locking, atomic local updates, fail-closed reservation ledger, approval-hash binding over graph plus exact public write bytes, and per-issue crash reconciliation.
3. Implement concurrency-limited ready-node scheduling with default concurrency 2, hard cap 3, max features 5 default, hard stop 10.
4. Implement dispatch-envelope emission and harness-mediated child invocation through `soleur:one-shot`; the controller never shells out to or directly invokes a skill.
5. Implement external child outcome verification with distinct transport, negative-state, malformed-evidence, missing-evidence, and timeout classes.
6. Implement permanent-failure propagation, independent continuation, paused/unaccounted blocking semantics, cancellation reconciliation, classified budget-capped stop, and resume reconciliation.
7. Implement aggregate rollup from child tally/session evidence where available; never double-count workflow/prose paths.

### Phase 5 — Collision semantics and harness/plugin integration

1. Add intentional-sibling correlation so orchestrated child PRs are not misclassified as accidental duplicates, without disabling collision protection globally.
2. Keep `feature-orchestrator` deliberately unrouted/internal for the internal-dogfood v1: do not add `/go` routing or workflow-fidelity pipeline registration in this PR. Add tests/assertions documenting that exclusion where component contracts require it; routing is a post-dogfood decision.
3. Update autonomous-loop/tally sentinels in `components.test.ts` and related tests.
4. Verify skill description budget and component contracts.

### Phase 6 — Verification hardening and dogfood preparation

1. Add shell/bun tests for the CLI helper and skill contract.
2. Add integration-style mocked fixtures for dispatch planning, resume, collision states, and child result classification.
3. Run required plugin tests and affected test suites.
4. Prepare but do not execute a real dogfood fan-out in this PR; first live dogfood requires explicit operator invocation after merge.
5. Capture review findings and defer only with tracked issues.

## Files to Create

- `plugins/soleur/skills/feature-orchestrator/SKILL.md`
- `plugins/soleur/skills/feature-orchestrator/lib/feature-graph.mjs`
- `plugins/soleur/skills/feature-orchestrator/scripts/feature-orchestrator.mjs`
- `plugins/soleur/skills/feature-orchestrator/references/graph-schema.md`
- `plugins/soleur/test/feature-orchestrator-graph.test.ts` or equivalent Bun test
- `plugins/soleur/test/feature-orchestrator-graph.test.sh` and fixtures
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-feature-orchestrator-composes-one-shot.md`

## Files to Edit

- `plugins/soleur/skills/one-shot/SKILL.md` — narrow explicit-argument orchestrated-child metadata/return contract only
- `plugins/soleur/skills/postmerge/SKILL.md` — machine-readable postmerge verification artifact/result surface if absent
- `plugins/soleur/test/components.test.ts` — autonomous-loop/API-budget/tally sentinel registration
- `plugins/soleur/README.md` or root README component table as required by component-count tests
- `knowledge-base/project/glossary.md` only if a materially ambiguous new term needs a settled sense

## Open Code-Review Overlap

Queried open `code-review` issues for the final file list on 2026-11-28. No matching open issues found, so there is nothing to fold in, acknowledge, or defer. Re-run before implementation if the file list changes.

## Acceptance Criteria

- [ ] A design document can be decomposed into a machine-readable feature graph artifact.
- [ ] Invalid graphs fail validation before any child issue, branch, worktree, or PR is created; cap violations fail policy/approval before side effects without being mislabeled as graph-invalid.
- [ ] Interactive execution presents a dry-run graph/cost/collision preview and requires explicit approval once before side effects.
- [ ] One child issue is filed per approved feature and used as the externally visible tracking/correlation object named in the journal.
- [ ] Independent nodes dispatch through `soleur:one-shot` up to concurrency 2 by default and never above hard cap 3; if the nested-dispatch prototype fails, execution degrades explicitly to sequential mode rather than fabricating parallelism.
- [ ] A dependent node does not dispatch until every prerequisite PR is merged and postmerge verification is externally confirmed.
- [ ] A terminal child failure marks descendants `skipped-blocked` and allows independent ready nodes to continue.
- [ ] Missing child evidence is classified as unaccounted/failed-closed, never success, and blocks dependents until reconciled or terminally classified.
- [ ] Resume reconciliation does not duplicate existing child branches, worktrees, issues, or PRs, adopts exact-key orchestrated artifacts, stops on foreign collisions, and refuses modified-graph hashes.
- [ ] Approved graph hash, journal graph hash, and dispatch graph hash match exactly before every dispatch; operator edits require fresh preview and approval.
- [ ] Child issues are journal-linked as they are created and remain blocked/holding until their node is dispatch-ready.
- [ ] Parent stop-scheduling stops new dispatch without falsely claiming already-running children stopped, and resume reconciles those children.
- [ ] Child receipts survive worktree cleanup in shared session state and are keyed by run, node, branch, PR, and merge SHA.
- [ ] Parent reservation locking serializes reconcile/reserve/dispatch across concurrent orchestrator instances.
- [ ] Only permanent failure recursively skips descendants; budget-capped and unaccounted states pause/block pending reconciliation.
- [ ] Approval covers exact child issue titles, bodies, and dispatch briefs; mutation requires reapproval.
- [ ] Child autonomous merge is refused or escalated when the PR diff breaches approved scope/exclusions.
- [ ] `status --run <id>` renders node state, evidence, blocker, next action, and exact resume command.
- [ ] `stop-scheduling` lists active children/residual spend and never claims real child cancellation.
- [ ] Stalled children become `unaccounted` after the declared deadline/probe policy and still produce a partial final report.
- [ ] Terminal child issues receive deterministic label/comment/close cleanup.
- [ ] v1 remains unrouted/internal; no `/go` route or workflow-fidelity pipeline registration is added.
- [ ] Aggregate orchestration state and work counters are visible in a durable run journal.
- [ ] Budget-cap stops are classified and resumable.
- [ ] The implementation contains no upstream retrieval or copied/paraphrased upstream expressive material, and the final PR carries a factual provenance statement.
- [ ] Plugin component, harness-parity, skill-budget, graph/scheduler, stop-scheduling, resume, approval-hash, collision, and evidence-classification tests pass.

## Domain Review

**Domains relevant:** Product, Engineering, Operations, Legal

### Product

**Status:** reviewed
**Assessment:** Proceed only as a small instrumented internal MVP: operator-approved decomposition, conservative scheduling, strict caps, and evidence-gated productization. Dogfood at least three real internal design documents before external exposure.

### Engineering

**Status:** reviewed
**Assessment:** Build a plugin-local orchestrator skill composing `one-shot`, backed by deterministic graph validation and externally verified outcomes. Do not build a service; do not extend drain; defer the dynamic workflow port.

### Operations

**Status:** reviewed
**Assessment:** Conditional go. Require global dispatch caps, durable state, cost attribution, failure/saturation runbooks, dry-run confirmation, concurrency 2, hard cap 3, max 5 features, hard stop 10, and classified budget-capped stops.

### Legal

**Status:** reviewed
**Assessment:** Amber/conditional proceed. Abstract ideas are viable, but implementation must preserve role-separated clean-room provenance, avoid AGPL expressive input, constrain autonomous write authority, and revisit posture before external/hosted/Jikigai-keyed use.

### Product/UX Gate

**Tier:** none
**Decision:** not applicable — CLI/orchestration feature with no UI surface
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Plan Review Summary

Panel input applied mechanically before finalization: deterministic controller boundary, explicit child args instead of environment variables, fail-closed reservation ledger, approval over exact public-write bytes, immutable child identity, controlled resource keys, stall/liveness policy, stop-scheduling semantics, terminal issue cleanup, status output contract, and deliberate unrouted/internal v1 posture.

Named-panel taste/user-challenge items intentionally not auto-applied because they conflict with prior operator decisions or require post-dogfood evidence: reducing v1 to dry-run-only, adding per-child merge checkpoints for the first three dogfoods, and enabling `/go`/workflow-fidelity routing. These remain operator decisions; the current plan preserves the approved internal-dogfoot scope, autonomous child merge posture, and unrouted v1 surface.

## Test Scenarios

1. Valid DAG with two independent roots and one dependent produces expected readiness order.
2. Cyclic graph exits nonzero before side effects.
3. Dangling dependency exits nonzero before side effects.
4. Duplicate feature ID exits nonzero.
5. Sixth feature under default cap fails the approval/policy check with a distinct policy exit, not a schema-validation error.
6. Feature ID containing shell metacharacters is rejected.
7. Independent nodes with overlapping high-risk file hints reject unless an explicit dependency is added.
8. Prerequisite prose success but unmerged PR leaves dependent not-ready.
9. Failed prerequisite recursively skips descendants and independent node remains eligible.
10. Missing child receipt produces unaccounted/failed-closed aggregate state.
11. Resume with existing child issue/PR adopts or stops without duplicate creation.
12. Budget-cap exhaustion writes classified stop and resume state.
13. Skill description budget remains within cap after adding the new skill.
14. Orchestrated child receipt does not bypass any one-shot lifecycle gate.
15. Approval-hash mismatch refuses dispatch.
16. Crash after one child issue but before later issue writes reconciles without orphan duplication.
17. GitHub transport failure, unmerged state, malformed evidence, and missing evidence classify distinctly in fixtures.
18. Concurrent orchestrator invocation with the same run lock resumes/reconciles rather than duplicating fan-out.
19. Cancellation leaves a resumable state and does not fabricate child termination.

## Sharp Edges

- Do not execute a live fan-out as part of implementation verification; use mocks/fixtures until after merge and explicit operator invocation.
- Do not let child prose count as terminal completion evidence.
- Do not pre-create dependent branches/worktrees.
- Do not treat topN-style breadth selection as a concurrency cap.
- Do not paste design prose into shell argv, branch names, or commit messages unsanitized.
- Prefer existing child-issue collision gates over adding a broad sibling-correlation exemption; pass parent linkage in metadata/journal rather than weakening duplicate-work detection.
- Do not copy upstream implementation/schema/prompt/documentation expression.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Skill descriptions are at 21 words of headroom; re-measure before commit.
- Commit hook caveat in this environment: use literal unquoted `git -C <worktree>` for commits because the Devin hook envelope omits reliable cwd.

## Alternative Approaches Considered

| Approach | Disposition |
|---|---|
| Prose skill + deterministic helper | Chosen |
| Workflow-first scheduler | Deferred to #13120 |
| Extend drain-labeled-backlog | Rejected; wrong semantic model |
| Server-side Inngest/Postgres orchestrator | Rejected for v1 blast radius |
| Human merge gate | Rejected for internal dogfood by operator, but required reconsideration before external release |
