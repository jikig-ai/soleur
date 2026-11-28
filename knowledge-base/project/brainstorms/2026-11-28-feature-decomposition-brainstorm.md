---
title: "Design-level feature decomposition with dependency-aware pipeline fan-out"
date: 2026-11-28
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [engineering, orchestration, one-shot, fan-out, autonomy, clean-room]
related_issues: [12528]
related_prs: [13105]
---

# Feature decomposition and dependency-aware fan-out — brainstorm (issue #12528)

## What We're Building

Build an internal-first orchestration capability that takes one approved design document, proposes a small dependency-aware feature graph, and dispatches each feature through the existing `soleur:one-shot` pipeline. Each child feature gets its own issue, branch, worktree, PR, review, merge, and postmerge verification; independent features may run in parallel while dependent features wait for prerequisite merges.

This is not a new implementation pipeline and not a server-side orchestration service. It is a composition layer over the existing one-shot lifecycle, with deterministic graph validation, explicit operator approval before spend, aggregate cost/concurrency controls, durable per-feature state, and failure-aware sequencing.

## Why This Approach

Three approaches were considered:

1. **New prose orchestrator skill plus deterministic helper** — chosen. A portable skill composes `soleur:one-shot`; a pure helper validates the graph and classifies scheduling outcomes. This reuses existing collision gates, worktrees, review, merge, and postmerge behavior while remaining cross-harness portable.
2. **Workflow-first scheduler** — rejected for v1 as the primary surface. Dynamic workflows are a good later opt-in because they can express exact dependency-aware parallel scheduling, but long-running nested one-shot dispatch through workflow agents is not yet proven across harnesses.
3. **Extend `drain-labeled-backlog`** — rejected. Drain batches same-area cleanup issues into one PR; this feature requires a feature DAG, separate child PRs, dependency unblock, and descendant skipping. The semantics are different enough that combining them would obscure both operator intents.

A server-side Inngest/Postgres orchestrator was also rejected for this issue: it introduces production runtime, tenancy, credential, observability, and GDPR surfaces far beyond the requested internal CLI capability.

## Operator Decisions

| Decision | Ruling | Rationale |
|---|---|---|
| v1 audience | Internal dogfood first | Validate decomposition quality, failure behavior, and cost before exposing the capability to users. |
| Approval model | Approve graph once | Operator reviews and approves the graph, cost envelope, and dispatch plan before fan-out; no per-phase approvals after that. |
| Failure policy | Fail node, skip dependents | `one-shot` already contains implementation/review/fix loops; whole-child automatic retry multiplies cost without clear evidence of benefit. |
| Merge authority | Autonomous merge | For internal dogfood, children run the normal one-shot lifecycle through merge once dependencies clear. Legal risk is accepted for v1 internal use and must be revisited before external release. |
| Fan-out envelope | 2 parallel, 5 features | Default concurrency 2, hard cap 3; default maximum 5 features, hard stop 10. |
| Child issues | Yes, one per feature | Stable collision targets, visible audit trail, clean `Closes #N` mapping, and better recovery evidence. |
| Copyright boundary | Role-separated clean room | Implementation must be performed by a fresh implementation context using only this abstract functional brief and Soleur code, with no upstream retrieval. |

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Create a new orchestrator skill, working name `feature-orchestrator` | Keeps design decomposition semantically distinct from backlog draining and one-shot execution. |
| 2 | Compose `soleur:one-shot`; do not reimplement lifecycle stages | `one-shot` already owns worktree creation, plan/deepen, work, review, QA, compound, ship, merge, and postmerge verification. |
| 3 | Use a machine-readable feature graph artifact | A graph enables deterministic validation, resume, reporting, and independent verification rather than prose-only orchestration. |
| 4 | Validate the graph fail-closed before any child side effects | Duplicate IDs, dangling dependencies, self-dependencies, cycles, excess feature count, and unsafe overlap must stop before issue/branch/PR creation. |
| 5 | File one child issue per approved feature | Child issues provide stable collision targets, PR close references, operator-visible scope, and recovery evidence. GitHub blocking edges may supplement but not replace the local run journal. |
| 6 | Dispatch dependents only after prerequisite merge and postmerge verification | Child one-shots branch from current `origin/main`; waiting for merge avoids orchestrator-managed rebasing and stacked-PR complexity. |
| 7 | Use independent external evidence for child completion | Child prose is not terminal evidence. Completion requires externally observable merged PR/issue state plus absence of budget-capped or failure markers. |
| 8 | Continue independent branches after a child failure | Parallel independent work should not be sacrificed to an unrelated failure. |
| 9 | Recursively skip descendants of a failed node | A dependent feature cannot safely start when required interfaces or behavior never landed. Skipped nodes need explicit resume state, not silent omission. |
| 10 | Enforce an orchestration-level cost/work envelope | Per-branch tallies are insufficient because each child can independently remain under cap while the aggregate run exceeds operator intent. |
| 11 | Serialize overlap and shared-resource risk | File overlap, migrations, deployment surfaces, test locks, and other shared resources can force serialization even when feature logic appears independent. |
| 12 | Persist a parent run journal before dispatch | Spawn acceptance is not completion. The orchestrator must know the expected child set and compare it with terminal per-child outcomes. |
| 13 | Keep v1 plugin-local and internal | No hosted control plane, external-user exposure, cross-repo orchestration, or multi-provider routing in v1. |
| 14 | Keep the dynamic workflow port as follow-up or opt-in | Prose remains the portable default; workflow scheduling can be added after the nested one-shot contract is proven. |
| 15 | Require clean-room provenance controls | AGPL-licensed inspiration may contribute abstract ideas only. No upstream code, prompts, schemas, tests, comments, documentation passages, file layout, or paraphrase may be copied. |
| 16 | Keep the new skill description within the measured 21-word headroom | The current model-visible skill-description total is 2469/2490; the new skill must fit within 21 words or the plan must trim siblings first. |

## Required v1 Behavior

### Input and preview

- Accept a design document path plus optional parent issue reference.
- Read the design and produce a proposed feature graph with stable feature IDs, titles, scopes, dependencies, file hints, acceptance intent, and shared-resource hints.
- Default to dry-run/preview behavior in interactive use.
- Show feature count, dependency depth, independent frontier, overlap warnings, concurrency cap, expected cost multiplication, and child issue/PR creation plan.
- Require one explicit operator approval before any child issue, branch, worktree, or PR is created.

### Validation

The deterministic validator must reject:

- duplicate or unstable feature IDs;
- dangling dependencies;
- self-dependencies;
- dependency cycles;
- more than the configured feature cap;
- independent nodes with unresolved ownership overlap;
- unsafe text that cannot be encoded into branch names, issue titles, or shell arguments.

Cycles are fatal before side effects. They must not be degraded into a final tier.

### Execution

- Dispatch independent ready nodes up to the concurrency cap.
- Create one child issue per feature after graph approval.
- Do not pre-create all child branches or worktrees.
- Invoke the existing `soleur:one-shot` lifecycle for each dispatched feature.
- Dependents become ready only after every prerequisite child PR has merged and postmerge verification has completed.
- If a child fails, mark it terminal-failed, recursively mark descendants `skipped-blocked`, and continue independent ready work.
- Do not silently retry a failed child. A retry requires explicit operator action or a clearly bounded resume command.

### Observability and accounting

The parent run journal must record at minimum:

- run ID and design hash;
- graph nodes and dependency edges;
- feature state transitions;
- child issue, branch, worktree, PR, and session identifiers where known;
- dispatch, completion, failure, skip, budget-cap, and cancellation timestamps;
- aggregate work counters and per-child attribution where available;
- final counts for merged, failed, skipped, deferred, and unaccounted features.

A run with missing or unknown child outcomes is not complete. A partial graph must render as partial, never as success.

## Non-Goals

- External-user productization, hosted orchestration, marketplace claims, or a polished UI.
- Server-side Inngest/Postgres orchestration.
- Cross-repo or multi-host orchestration.
- Multi-provider model routing or cross-vendor fallback.
- Stacked PRs, integration branches, or orchestrator-managed rebasing.
- Dynamic re-planning of the graph mid-run.
- Retroactive decomposition of an already implemented large diff.
- Copying or paraphrasing AGPL-licensed implementation material.

## Open Questions

- What exact machine-readable result contract should `one-shot` expose for orchestrated children without weakening its existing anti-bypass and completion-floor guarantees?
- How should intentional sibling one-shot PRs be distinguished from accidental duplicate-work collisions in existing collision probes?
- Should overlap force an automatically inserted dependency edge, a hard validation failure, or operator-editable graph approval? This is a technical design fork for the plan-phase CTO ruling.
- What is the minimum parent/child tally rollup that is accurate enough for caps without double-counting branch-local ledgers?
- Should the first workflow port ship in the same implementation PR as an opt-in or after the first successful dogfood?
- Which internal design documents are the first three dogfood candidates?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Proceed only as a small instrumented internal MVP: machine-proposed but operator-approved decomposition, conservative dependency scheduling, strict caps, and evidence-gated productization. Dogfood at least three real internal design documents before considering external exposure.

### Engineering

**Summary:** Build a plugin-local orchestrator skill composing `one-shot`, backed by deterministic graph validation and externally verified child outcomes. Do not build a service; do not extend drain; treat a dynamic workflow port as later opt-in execution machinery.

### Operations

**Summary:** Conditional go for design, not operationally shippable without global dispatch caps, durable state, cost attribution, failure/saturation runbooks, and explicit dry-run confirmation. Initial controls should include concurrency 2, hard cap 3, max 5 features, hard stop 10, and classified budget-capped stops.

### Legal

**Summary:** Amber/conditional proceed. The abstract orchestration ideas are viable, but implementation must preserve role-separated clean-room provenance, avoid all AGPL expressive input, constrain autonomous write authority, and revisit legal posture before hosted, external, or Jikigai-keyed use.

## Capability Gaps

| Gap | Evidence |
|---|---|
| No existing feature architect or design-doc-to-feature-graph primitive | `rg -n -i 'feature_architect\|feature architect\|feature graph\|design doc.*decompos\|decompos.*design doc\|dependency-aware' plugins/soleur/skills plugins/soleur/agents plugins/soleur/scripts plugins/soleur/lib` returned no matches in the product/research sweep. Existing `depends_on` hits are metadata/static annotations, not executable graph primitives. |
| No dependency-aware multi-one-shot scheduler | `drain-labeled-backlog` dispatches clusters to one-shot but has no dependency edges or failure propagation (`plugins/soleur/skills/drain-labeled-backlog/SKILL.md`); resolve-parallel workflows tier local edits, not independent one-shot branches/PRs (`plugins/soleur/skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js`). |
| No machine-readable one-shot child-result contract | `one-shot` has prose return contracts and completion-floor behavior but no orchestrated-child schema for feature id, branch, PR, terminal status, and failure class (`plugins/soleur/skills/one-shot/SKILL.md`). |
| No cross-branch parent cost rollup | `pipeline-tally.sh` is branch-keyed and drain explicitly states child one-shots keep their own ledgers with no cross-branch rollup in v1 (`plugins/soleur/scripts/pipeline-tally.sh`, `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`). |
| No orchestration-level collision semantics | Existing one-shot collision/overlap probes are designed for accidental duplicate work, not intentional sibling feature PRs (`plugins/soleur/skills/one-shot/SKILL.md`). |
| No clean-room provenance enforcement artifact | The content-vendoring policy covers intentional lifts but not independent-implementation provenance or final-similarity review (`knowledge-base/engineering/policies/content-vendoring.md`). |

## Clean-Room Provenance Boundary

The implementation must be role-separated:

1. This brainstorm and the resulting spec are the only upstream-informed functional briefs.
2. The implementation context must not retrieve, read, quote, summarize, or inspect `hmuhlestein/HephaestusNG` or forks of it.
3. The implementer may use issue #12528, this brainstorm/spec, and Soleur's own repository primitives only.
4. The implementation must invent its own schema, prompts, validation behavior, file layout, tests, names, and documentation within Soleur conventions.
5. The final PR must include a factual provenance statement and receive a final-diff similarity review.

Research access in this brainstorm was limited to public metadata/documentation/license inspection for risk assessment; no upstream implementation source was inspected. Upstream documentation details are deliberately not carried into the functional design beyond the abstract concepts already named in issue #12528: decomposition, dependency edges, bounded parallel execution, and failure-aware skipping.

## User-Brand Impact

- **Artifact:** the plugin-local engineering orchestration workflow and the child branches/PRs it creates in the target repository.
- **Vector:** worst case, a bad graph or uncontrolled fan-out creates multiple incorrect autonomous PRs, burns operator/model/CI budget, or merges partial milestone scope while appearing complete.
- **Threshold:** `single-user incident` for internal dogfood; external release requires a fresh legal/product review.

## Lane

`cross-domain`: product, engineering, operations, and legal constraints all shape the design.

## Next Steps

→ Use `skill: soleur:plan` for implementation details.
