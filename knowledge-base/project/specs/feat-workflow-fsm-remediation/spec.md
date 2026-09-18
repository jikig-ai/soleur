---
title: Workflow FSM remediation — instrument, reconcile, ratchet
date: 2026-09-18
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-workflow-fsm-remediation
pr: 8301
brainstorm: knowledge-base/project/brainstorms/2026-09-18-workflow-fsm-remediation-brainstorm.md
status: ready-for-plan
---

# Spec — Workflow FSM Remediation

## Problem Statement

Soleur's workflow state machine is declared in two disagreeing places and read by
nothing that can refuse an action.

- **States** live in `.claude/phase-surface-map.json` (5 phases; 16 of 99 skills
  mapped = 16%). **Transitions** live in `plugins/soleur/lib/workflow-fidelity.ts`
  as a TypeScript `switch` (7 nodes, forward-only, zero back-edges). Nothing
  reconciles the two node sets, and bash cannot read a TS switch.
- **Enforcement is prose.** `workflowFidelityInstructions()` returns a markdown
  string; the contract's mechanism is the word "FORBIDDEN" rendered into a
  prompt — ADR-011 tier 3, the tier that decays as context fills.
- **The interception point exists and abstains.** Of 44 `PreToolUse` hooks,
  exactly one matches `Skill`: `skill-invocation-logger.sh`. It logs and returns
  no verdict. The only state-reading component, `phase-surface-hint.sh`, is
  `PostToolUse` — it fires after dispatch and structurally cannot block
  (deliberate, per ADR-086).
- **The instrument is mute at three independent layers:** 79 of 98 rules have no
  emit call site; 32% of emitted rows (11,346 of 35,228, counting rotated
  `.gz` archives) sit in 34 sibling worktree roots the aggregator does not read; and the aggregator has no
  schedule (`workflow_dispatch` only since #6042).
- **The waste compounds.** Measured against the 2026-08-13 audit: `review`
  322→430 KB, `work` 257→326 KB, `ship` 187→248 KB in 36 days (~30%), while the
  rule corpus governing it *shrank* from 103 to 98.

## Goals

- G1 — Make rule-fire measurement admissible: repair root resolution so emitted
  rows are collected, and restore an aggregation cadence.
- G2 — Collapse the two node sets into one declarative source of truth that both
  TypeScript and bash can read, with a drift test.
- G3 — Bend the prompt-weight curve with a mechanism that cannot be quietly
  relaxed.
- G4 — Ship a workflow transition gate in **record-mode** with a pinned decision
  date for the block/no-block call.
- G5 — Make the declared graph honest: add the three operator-approved
  back-edges.

## Non-Goals

- **NG1 — No rule pruning, on any signal.** See the correction block; the
  instrument is not yet admissible. (`2026-07-22-rule-metrics-denominator-investigation`, #6794.)
- **NG2 — No block-mode gate this cycle.** ADR-070 permits deny-by-default only
  on re-fetching layers; `Skill` does not re-fetch.
- **NG3 — No sub-phase grammar normalization.** Deferred to its own track:
  4+ incompatible heading grammars, `plan` has zero `Phase` headings across
  258 KB. Migration, not lint.
- **NG4 — No state-conditional loading of rule CONTENT.** ADR-151. Only
  transitions are gated.
- **NG5 — Do not raise phase coverage to all 99 skills.** Map only the
  lifecycle chain.
- **NG6 — No instrumentation that emits on a customer machine.** ADR-179
  decision 4; would convert `command_snippet` into third-party personal data.
- **NG7 — No dashboard, no new ADR-131 adoption decision.**

## Functional Requirements

- **FR1** — Incident-log root resolution resolves to the git **common dir**, so
  a run from any worktree collects the same set. Read-widen only; no new write
  site. Verify against live figures: 23,882 currently readable vs 11,346
  stranded (35,228 total). **Count rotated `.rule-incidents-*.jsonl.gz`
  archives, not just live `.jsonl`** — they hold the majority of history and
  omitting them understates the readable set and overstates the residual.
- ~~**FR2** — Aggregation cadence restored.~~ **SUPERSEDED at plan time
  (Cut C1).** Already bought by the ADR-091 local-producer model; the weekly
  `schedule:` was removed deliberately under #6042 because fresh CI checkouts
  committed all-zero snapshots that clobbered the real local aggregate.
  Implementing this would regress. The `SOLEUR_RULE_METRICS_NO_INCIDENTS`
  null-reading marker is already present and is preserved.
- ~~**FR3** — Investigate why the April skill-emit arm stalled.~~
  **SUPERSEDED at plan time (Cut C5).** One grep answers it:
  `grep -rn 'emit_incident' plugins/soleur/skills/*/SKILL.md` returns **zero**
  call sites across 98 skills — prose instructing an agent to source a bash
  library never became a call site in five months. The finding stands; it needed
  no phase, and it also refutes raising coverage the same way.
- **FR4** — Edge set moves into a declarative source (`transitions` key in
  `phase-surface-map.json` or a sibling file); `workflow-fidelity.ts` reads it
  rather than hard-coding the `switch`.
- **FR5** — Drift test asserts the declarative source and the TS view cannot
  diverge, mirroring the existing `phase-surface-map-parity.test.ts` pattern.
- **FR6** — Declare back-edges `review→work`, `ship→work`, `work→plan`.
  `postmerge→work` is explicitly NOT declared.
- ~~**FR7** — Transition gate as a second `Skill` `PreToolUse` entry.~~
  **SUPERSEDED at plan time (Cut C3, operator-confirmed).** A record-mode
  event reaches no consumer: it carries no corpus rule-id prefix, so the
  aggregator files it under `summary.non_corpus_counts` (nothing reads that
  field), and compound's Deviation Analyst filters to
  `event_type ∈ {deny, bypass}` or `kind == "hook_self_fault"` — none of which
  record-mode can emit. The transition sequence it would record **already
  exists** in `.claude/.skill-invocations.jsonl`.
- ~~**FR8** — The gate's own record path emits.~~ **SUPERSEDED with FR7.**
- **FR7′ (replaces FR7/FR8)** — An **offline** classifier reads the existing
  `.claude/.skill-invocations.jsonl`, groups by `session_id`, and reports
  transitions absent from the declared edge set. No hook, no `settings.json`
  entry, no `PreToolUse` surface.
- **FR9** — Body extraction into `references/`, loaded on demand, **narrowed at
  plan time (Cut C4, operator-confirmed) to `plan`'s `## Sharp Edges` only.**
  `work`'s `## Execution Workflow` (lines 122–1281 of 1392) and `review`'s
  `## Code Review Complete` are core-path: extracting them behind a load
  directive buys two reads for identical bytes plus a new drift surface. The
  proven `references/` pattern operates at ~5% extraction, not 80%. The
  directive for `plan` must be **conditional**, matching the 7 gated directives
  in the repo rather than the 5 unconditional ones.
- **FR10** — Per-file SKILL.md byte ceiling, **monotonically non-increasing**,
  enforced in CI.

## Technical Requirements

- **TR1** — Gate is record-only. No `permissionDecision: deny` on the `Skill`
  matcher. (ADR-070 two-tier rule.)
- **TR2** — Every hook path exits 0. A non-zero exit in this layer silently
  drops output, making the deny invisible.
- **TR3** — Rule **content** remains unconditionally injected (ADR-151). The
  gate scopes what the agent may *do*, never what it may *know*.
- **TR4** — `phase-surface-hint.sh` stays `PostToolUse`. ADR-086 line 23:
  "Never move this to PreToolUse; never add a blocking or unbounded path."
- **TR5** — Incident log retains gitignore + mode `0600`, and no egress. The
  committed aggregate must NOT gain a `command_snippet` field (CLO condition).
- **TR6** — The byte ceiling must be demonstrated **failing red** in CI on a
  deliberately oversized SKILL.md before merge. A ceiling that cannot be shown
  red is exactly ADR-131's "gate that could not fail". Precedent:
  `SKILL_DESCRIPTION_WORD_BUDGET` has been bumped 14 times.
- **TR7** — Edits to `workflow-fidelity.ts` trip
  `plugins/soleur/test/workflow-fidelity.test.ts` via `grok-fidelity-gate.sh`
  (mandatory pre-push). Edits to `go.md`'s routing block trip the eval-harness
  `go-routing` gate.
- **TR8** — Consider an ADR for the single source of truth (CTO recommendation).

## Acceptance Criteria

- [ ] An aggregator run from any worktree reports the same row count as a run
      from the shared checkout.
- [ ] `rule-metrics.json` regenerates on a cadence without manual dispatch.
- [ ] One declarative artifact holds both nodes and edges; a test fails if the
      TS view drifts from it.
- [ ] `review→work`, `ship→work`, `work→plan` are declared and covered by tests.
- [ ] The transition gate records a violation for an undeclared transition and
      blocks nothing; its record path emits a rule-fire.
- [ ] CI fails on a SKILL.md exceeding its pinned ceiling, demonstrated red.
- [ ] A pinned calendar date for the block/no-block decision is recorded.
- [ ] No rule was pruned.

## Deferred

| Item | Why | Re-evaluation trigger |
|---|---|---|
| Sub-phase grammar normalization + loader | 4+ grammars; `plan` has zero `Phase` headings. Week+ migration, orthogonal to the FSM | After Track A/B land |
| Block-mode gate | ADR-070 two-tier rule; 16/99 coverage would false-deny `/go` | At the pinned decision date |
| `postmerge→work` back-edge | Redundant with `ship→work` | If a real case appears |
| Phase-surface coverage beyond the lifecycle chain | YAGNI | — |
| Linear preflight regex false-positives on `ADR-NNN` | `[A-Z]{2,}-[0-9]+` matches every ADR citation | Own issue |
| 634→716 inline learning citations | Prompt weight, but body extraction (FR9) may absorb it | After FR9 measurement |
