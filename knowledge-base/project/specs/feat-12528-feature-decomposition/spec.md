---
title: design-level feature decomposition with dependency-aware pipeline fan-out
issue: 12528
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: design-level feature decomposition with dependency-aware pipeline fan-out

## Problem Statement

`soleur:one-shot` ships one branch and one PR. A large design must currently be decomposed by the operator into separate issues before each part can run through the autonomous engineering lifecycle. This produces either oversized PRs or manually sequenced one-shot runs.

Issue #12528 requests an orchestration layer that takes one design document, decomposes it into dependency-aware feature units, dispatches each unit through the existing one-shot pipeline, runs independent units in parallel, and skips dependents when a prerequisite fails.

See brainstorm: `knowledge-base/project/brainstorms/2026-11-28-feature-decomposition-brainstorm.md`.

## User-Brand Impact

- **Artifact:** the plugin-local feature orchestration workflow and the child issues, branches, PRs, merges, and run artifacts it creates.
- **Vector:** worst case, incorrect decomposition or uncontrolled fan-out creates multiple bad autonomous PRs, burns model/CI budget, merges partial scope, or misrepresents incomplete work as complete.
- **Threshold:** single-user incident for internal dogfood. External release requires renewed product/legal review.

## Goals

- Convert one approved design document into a validated feature dependency graph.
- Let the operator inspect and approve the graph and cost envelope once before any child side effects.
- Dispatch each approved feature through the existing `soleur:one-shot` lifecycle.
- Run independent features in parallel under a conservative concurrency cap.
- Start dependent features only after prerequisite PRs merge and postmerge verification completes.
- Continue independent branches when one feature fails, while recursively skipping its dependents.
- Persist durable run state sufficient for audit, resume, and final accounting.
- Maintain clean-room provenance from AGPL-licensed inspiration.

## Non-Goals

- External-user exposure, hosted orchestration, or a polished UI.
- Server-side Inngest/Postgres orchestration.
- Cross-repo, multi-host, or multi-provider orchestration.
- Stacked PRs, integration branches, or orchestrator-managed rebasing.
- Dynamic re-planning of the graph mid-run.
- Automatic whole-child retries after terminal failure.
- Retroactive decomposition of an already implemented large diff.
- Copying or paraphrasing upstream AGPL-licensed implementation material.
- Replacing or weakening the existing one-shot lifecycle gates.

## Key Decisions

| Decision | Ruling |
|---|---|
| v1 audience | Internal dogfood first |
| Primary surface | New plugin-local orchestrator skill, working name `feature-orchestrator` |
| Execution unit | Existing `soleur:one-shot` per feature |
| Approval | Operator approves graph once before fan-out |
| Child visibility | One GitHub child issue per feature |
| Merge authority | Autonomous merge through normal one-shot lifecycle for internal dogfood |
| Default envelope | Concurrency 2, hard cap 3; max 5 features by default, hard stop 10 |
| Failure behavior | Failed node becomes terminal-failed; descendants are recursively skipped; independent branches continue |
| Implementation boundary | Role-separated clean room; implementer must not inspect upstream inspiration |
| Execution engine | Prose skill first; dynamic workflow port is opt-in/follow-up |

## Functional Requirements

### FR1: Design intake

The orchestrator accepts a design document path and optional parent issue reference. It reads the design, relevant repository context, and existing issue/PR state needed to propose feature boundaries.

### FR2: Feature graph proposal

The orchestrator produces a machine-readable graph containing, for each feature:

- stable feature ID;
- title;
- scope and explicit exclusions;
- dependency IDs;
- file/path ownership hints;
- acceptance intent;
- shared-resource or collision-risk hints.

The exact schema must be designed independently within Soleur conventions.

### FR3: Dry-run preview and one-time approval

Interactive execution defaults to a dry-run preview. Before any child issue, branch, worktree, or PR is created, the operator sees and approves:

- feature count and dependency depth;
- dependency edges and independent frontier;
- file-overlap and shared-resource warnings;
- concurrency and feature-count caps;
- expected cost multiplication;
- child issue/PR creation plan;
- merge authority posture.

After approval, the run does not ask for per-phase approval. It may stop only for classified failure, collision, invalid state, budget-cap, or operator cancellation.

### FR4: Deterministic graph validation

Before side effects, a deterministic validator rejects:

- duplicate or unstable feature IDs;
- dangling dependencies;
- self-dependencies;
- cycles;
- graphs exceeding configured feature limits;
- independent nodes with unresolved ownership overlap;
- unsafe text that cannot be encoded into branch names, issue titles, or shell arguments.

Cycles are fatal before side effects and must not be silently reordered.

### FR5: Child issue creation

After graph approval, the orchestrator files one child issue per feature. Child issues link back to the parent design/issue and carry enough scope and acceptance detail for a standalone one-shot run. GitHub-native blocking edges may be used as supplemental visibility, but the local run journal remains authoritative for orchestration state.

### FR6: Dependency-aware dispatch

The scheduler dispatches ready independent features up to the concurrency cap. A feature is ready only when all prerequisite child PRs are merged and postmerge verification is complete. Dependent branches are not created before that point; they branch from current `origin/main` through the normal one-shot worktree flow.

### FR7: Existing one-shot lifecycle composition

Each dispatched feature runs the existing `soleur:one-shot` lifecycle. The orchestrator must not inline plan, work, review, QA, compound, ship, merge, or postmerge behavior.

### FR8: Child outcome verification

The orchestrator does not trust child prose as terminal evidence. It classifies a child complete only from external evidence such as:

- child PR exists and is merged;
- linked child issue is closed;
- child session state does not contain budget-capped or failure markers;
- expected branch/PR identifiers match the run journal.

Missing or unknown child evidence means the child is unaccounted, never successful by default.

### FR9: Failure and skip propagation

When a feature fails terminally:

1. mark that feature failed with a machine-readable failure class;
2. recursively mark descendants `skipped-blocked` with the upstream failure reason;
3. continue scheduling independent ready features;
4. preserve enough state for an explicit later resume or retry command.

A final report containing failed, skipped, or unaccounted features must not claim complete success.

### FR10: Aggregate cost and concurrency controls

The orchestrator enforces an aggregate envelope across the full graph. v1 defaults:

- concurrency default 2;
- concurrency hard cap 3;
- default maximum 5 features;
- absolute maximum 10 features;
- no child dispatch without enough remaining budget/work allocation for a full one-shot;
- classified `budget-capped` stop with a resume artifact rather than a blocking prompt.

The orchestrator also serializes nodes that share high-risk resources such as migrations, deployment surfaces, test locks, or overlapping file ownership.

### FR11: Durable run journal and final report

The orchestrator persists a run journal before dispatch and updates it at every state transition. It records at minimum:

- run ID and design hash;
- feature nodes and dependency edges;
- feature state transitions and timestamps;
- child issue, branch, worktree, PR, and session identifiers where known;
- dispatch/completion/failure/skip/cancellation state;
- aggregate and per-child work counters where available;
- final merged/failed/skipped/deferred/unaccounted counts.

### FR12: Resume behavior

A resume command or documented resume path must reconcile the run journal against live issue/PR/branch state before dispatching more work. It must adopt or stop on existing child artifacts rather than creating duplicates.

### FR13: Operator visibility

The operator can inspect current state as a durable artifact with per-node status and links. Child transcripts alone are not sufficient visibility.

## Technical Requirements

### TR1: Plugin-local implementation

Implement in the Soleur plugin as a new skill plus deterministic helper/test machinery. Do not add production database tables, server routes, Terraform, Inngest functions, or hosted services for v1.

### TR2: Compose existing primitives

Use `soleur:one-shot` for child execution, `worktree-manager.sh` through one-shot for isolation, and `pipeline-tally.sh` or its extension for work accounting. Reuse drain-labeled-backlog and resolve-parallel workflow concepts as precedent, not by copying their semantics blindly.

### TR3: Orchestrated child contract

If existing one-shot output is insufficient for reliable correlation, add the narrowest possible machine-readable orchestrated-child result contract. The contract must not weaken one-shot anti-bypass, completion-floor, review, QA, or ship gates.

### TR4: Collision semantics

The design must distinguish intentional sibling feature branches/PRs from accidental duplicate work. It must not disable existing collision protection globally.

### TR5: Scheduler correctness

Graph validation, readiness calculation, failure propagation, skip propagation, and outcome classification must be implemented as pure deterministic logic with unit tests. Workflow-specific duplication, if any, must be pinned by a logic-parity test.

### TR6: Clean-room provenance

The implementation context must not retrieve, read, quote, summarize, or inspect `hmuhlestein/HephaestusNG` or forks of it. The implementer may use issue #12528, this spec, the brainstorm, and Soleur repository primitives only.

The implementation must independently invent its schema, prompts, validation behavior, tests, file layout, names, and documentation within Soleur conventions. The final PR must include a factual provenance statement and receive final-diff similarity review.

### TR7: Context and credential minimization

Child briefs contain the feature slice and required shared interfaces, not automatically the entire parent design plus unrelated repository context. The v1 orchestrator is single-provider and uses the invoking session's existing credential posture; it must not broaden credential scope or silently route work to another vendor.

### TR8: Prompt-injection and shell safety

Design text, issue text, and feature names are untrusted input. IDs, branch slugs, shell arguments, issue titles, and commit/PR text must be validated or encoded before use. External effects are confined to the approved target repository.

### TR9: Observability and testing

The implementation must include machine-readable run markers or artifacts sufficient to audit graph shape, dispatch, results, skips, caps, and final status. Tests must cover valid DAGs, cycles, dangling dependencies, duplicate IDs, cap enforcement, failure propagation, independent continuation, overlap serialization, resume reconciliation, and mocked one-shot result classification.

### TR10: Skill budget and harness integration

The new skill description must fit within the measured 21-word model-visible headroom (2469/2490 at brainstorm time) unless a separate sibling trim lands first. Harness parity, workflow-fidelity, autonomous-loop disclosure, pipeline-tally, and component-count sentinels must be updated as applicable.

## Operational Acceptance Criteria

- Dry-run preview exists and accurately shows graph shape, cost multiplication, caps, overlap risk, and planned child artifacts.
- No child side effects occur before graph approval.
- No dependent child starts before prerequisite merge and postmerge verification.
- A failed child causes descendants to be skipped while independent work continues.
- Missing child evidence is unaccounted/failed-closed, never success.
- Aggregate cap stop is classified and resumable.
- Orphaned child branches/worktrees/PRs are detectable from the run journal.
- A run with partial completion is reported as partial.

## Dogfood Success Metrics

Use at least three real internal design documents before considering external exposure:

- zero dependents launched before prerequisites complete;
- zero descendants launched after dependency failure;
- zero duplicate branches/PRs on resume;
- at least 70% of proposed feature nodes accepted without material re-slicing;
- at least 80% of dispatched nodes reach correct terminal state without manual cleanup;
- at least 25% wall-clock improvement on graphs with width 2 or more, without more than 10% orchestration overhead in agent/CI work units;
- median no more than one post-approval operator intervention per run.

## Legal and Compliance Constraints

- v1 is plugin-local and internal-only.
- External, hosted, operator-assisted, Jikigai-keyed, alpha-tester, or customer-repository use requires a fresh legal review before enablement.
- The role-separated clean-room boundary is mandatory.
- Do not paste upstream material into implementation prompts or allow implementation agents to fetch upstream material.
- Do not silently route different child features to different AI providers.
- Before any public PR body/comment push, generated content must pass the repository's existing secret/personal-data/publication safeguards.
- Record the Article 22 determination in planning if implementation details create any person-affecting automated decision surface; current expectation is negative because the system acts on code tasks, not people.

## Open Technical Questions for Planning

- Exact shape and location of the run journal and machine-readable child result contract.
- Whether intentional sibling awareness belongs in the orchestrator, one-shot, or both.
- Exact treatment of file overlap: automatic dependency edge, validation failure, or operator-editable warning.
- Minimum accurate parent/child tally rollup without double-counting branch-local ledgers.
- Whether the first dynamic workflow port ships in the same PR as opt-in or after initial dogfood. Deferred-port tracker: #13120.
