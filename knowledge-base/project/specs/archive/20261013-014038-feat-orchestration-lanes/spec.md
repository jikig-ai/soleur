---
feature: feat-orchestration-lanes
issue: 2721
parent_issue: 2718
parent_spec: knowledge-base/project/specs/feat-claude-skills-audit/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-12-orchestration-lanes-brainstorm.md
branch: feat-orchestration-lanes
draft_pr: 3625
brand_survival_threshold: none
lane: cross-domain
---

# Spec — Named Orchestration Lanes (Single-Axis, Phase 0.5 Breadth)

## Problem Statement

Soleur's `brainstorm` and `work` skills already orchestrate domain leaders (Phase 0.5) and work parallelism (Tier 0/A/B/C) — but there is no named surface for an operator to declare or auto-detect the **breadth** of leader involvement before Phase 0.5 spawns. Two operator-facing failure modes follow:

1. **Wrong-shape Phase 0.5 fan-out** — a security/data-touching feature can run a Solo-Sprint-shaped session that spawns one leader (or none), silently skipping the user-impact gate (`hr-weigh-every-decision-against-target-user-impact`) and the regulated-data gate (`hr-gdpr-gate-on-regulated-data-surfaces`). Both gates only fire when the relevant domain leaders are at Phase 0.5.
2. **Operator confusion** — operators conflate phase-level parallelism (work Tier 0), task-level parallelism (work Tier A/B/C), and domain-leader breadth (brainstorm Phase 0.5) because none of them have a named surface to refer to before they fire. (See `knowledge-base/project/learnings/2026-03-03-tier-0-lifecycle-parallelism-design.md`.)

The parent audit (#2718, FR4 of `feat-claude-skills-audit/spec.md`) endorsed extracting the upstream `alirezarezvani/claude-skills` orchestration vocabulary as the mitigation. This spec refines FR4 under the single-axis lock decided in the 2026-05-12 brainstorm.

## Goals

- Add a single `lane:` field that captures Phase 0.5 domain-leader breadth at brainstorm time and is carried through spec → plan → work as informational metadata.
- Define three lane values that map honestly to observable Phase 0.5 fan-out cardinality.
- Auto-detect lane via keyword heuristic, surface to operator via AskUserQuestion at a new Phase 0.4, fail-closed to the broadest lane on ambiguity.
- Force lane to `cross-domain` when `USER_BRAND_CRITICAL=true` from Phase 0.1.
- Amend parent audit spec FR4 from "four lanes" to "three lanes (single-axis)" with a link back to this spec and brainstorm.

## Non-Goals

- Changing the work skill's Tier 0/A/B/C selection logic. Lane is read-only informational input to work, never a hard binding.
- Adding a new domain leader or agent. All work lands in existing `brainstorm` SKILL.md, `work` SKILL.md, and the `brainstorm-domain-config.md` reference file.
- Verbatim adoption of upstream lane names (Solo Sprint, Domain Deep-Dive, Multi-Agent Handoff, Skill Chain). Per CMO, that would require per-file MIT attribution; renaming drops the obligation.
- A `--lane=X` shortcut for `/soleur:go` to bypass Phase 0.4 (deferred to plan-phase ergonomics).
- A separate "override reason" capture field beyond the YAML `lane:` (deferred — frontmatter alone is sufficient audit trail for now).

## Functional Requirements

### FR1: Three-value lane taxonomy

The `lane:` field accepts exactly one of:

- `single-domain` — Phase 0.5 spawns one domain leader.
- `cross-domain` — Phase 0.5 spawns two or more domain leaders in parallel.
- `procedural` — Phase 0.5 spawns zero domain leaders (deterministic skill-chain work).

Any other value is invalid; emit a warning and fall back to `cross-domain`.

### FR2: New `brainstorm` Phase 0.4 — Lane Auto-Detect and Selection

Insert a new phase between Phase 0.1 (`User-Impact Framing`) and Phase 0.25 (`Roadmap Freshness Check`):

1. **Skip** if `USER_BRAND_CRITICAL=true` from Phase 0.1 — set `LANE=cross-domain` and continue (Decision 7 in brainstorm).
2. **Keyword scan** on the feature description against the inference table (FR5).
3. **AskUserQuestion** with the inferred lane pre-selected (Recommended) and the other two as alternatives. Operator can pick "Other" for free-text override.
4. **Fail-closed on ambiguity** — if the keyword scan returns no matches AND the operator picks no preset (only free-text "Other" that does not resolve to a lane label), default to `cross-domain`.
5. **Write** the selected lane to a session variable `LANE=<value>`.

### FR3: Carry-forward via YAML frontmatter

The selected lane is written to the brainstorm document's frontmatter as `lane: <value>` and to the spec.md frontmatter as `lane: <value>`. Downstream `plan` skill writes `lane: <value>` to the plan doc's frontmatter. `work` reads the lane from the spec or plan it consumes.

### FR4: Phase 0.5 lane-driven domain-set expansion

The Phase 0.5 Processing Instructions (currently 6 steps in SKILL.md) gain a step 0 that reads `LANE`:

- If `LANE=procedural` — skip Phase 0.5 entirely, proceed to Phase 1.
- If `LANE=single-domain` — assess relevance against the 8 domains and spawn the single most relevant leader; if tied, ask the operator to pick.
- If `LANE=cross-domain` — assess relevance and spawn every domain leader that matches; if fewer than 2 match, expand to 2 by including the next closest (fail-closed).

The existing `USER_BRAND_CRITICAL=true` override at step 2 of the table continues to apply on top of FR4.

### FR5: Keyword inference table in `brainstorm-domain-config.md`

A new section `## Lane Inference` defines:

- Keywords mapping to `cross-domain` (e.g., audit, review, security, compliance, migration, data, infra, regulated, payment, auth, cross-tenant, billing).
- Keywords mapping to `procedural` (e.g., scaffold, lockfile, format, rename, dep-bump, version-bump).
- Default = `single-domain` when feature description matches no keyword.

The minimum-viable set ships in the initial PR; expansion is a follow-on plan decision.

### FR6: Operator-override telemetry parity with Phase 0.1

When the operator's lane selection differs from the keyword-inferred default, emit a one-line `lane_override` note to the brainstorm doc body (under "User-Brand Impact" or a new "Lane" section). No new incident type — parallel to the existing Phase 0.1 telemetry emit.

### FR7: Parent audit spec FR4 amendment

Update `knowledge-base/project/specs/feat-claude-skills-audit/spec.md` FR4 to:

- Drop "four named lanes" wording.
- Replace with "three named lanes under single-axis (Phase 0.5 breadth only)".
- Add a link to this spec and the 2026-05-12 brainstorm for rationale.

Update TR7 (backwards-compatibility guarantee) in the same parent spec to specify that auto-detection fails closed to `cross-domain`, not silently to a cheaper lane.

### FR8: `work` skill reads lane as informational input

`work` Phase 0 (Load Knowledge Base Context) gains a step that reads `lane:` from the spec.md frontmatter when present and surfaces it in the announced status: "Loaded constitution, tasks, and lane=<value> for feat-<name>." Lane is read-only at `work` — no binding to Tier 0/A/B/C selection. Plan-phase decides whether `work` uses lane as a Tier hint (deferred).

## Technical Requirements

### TR1: Single-axis isolation

`work` Phase 2 Tier 0/A/B/C selection logic remains unchanged. The Phase 2 step 0 / step 1 logic in `plugins/soleur/skills/work/SKILL.md` reads only the task list and pipeline-mode flag, never the lane. (The lane may be exposed as a Phase 0 announce-only string per FR8.)

### TR2: Fail-closed default semantics

When keyword inference returns no signal AND operator selects no preset, AND `USER_BRAND_CRITICAL=false`, the lane defaults to `cross-domain`. This is asymmetric with Phase 0.1 (which defaults to USER_BRAND_CRITICAL=false on no match) and is intentional — the cost of a missed user-impact gate dominates the cost of an extra leader spawn.

### TR3: Carry-forward fidelity

The lane value MUST match across brainstorm doc frontmatter, spec.md frontmatter, plan.md frontmatter, and any work-time announce string. Any plan-phase implementer modifying the lane MUST update all four locations in the same edit cycle (Worktree-or-PR atomic). Mismatches are a hard plan-phase review finding.

### TR4: Soleur-idiom labels — no verbatim upstream lifts

Lane labels (`single-domain`, `cross-domain`, `procedural`) are Soleur-native and do not require MIT attribution. The upstream attribution in this brainstorm's frontmatter and `## Attribution` section is for provenance only; SKILL.md files do not carry a per-file MIT header for the lane vocabulary.

### TR5: Telemetry stays single-purpose

The lane logic emits at most one rule-application incident per brainstorm session: when `USER_BRAND_CRITICAL=true` forces lane (already emitted at Phase 0.1) or when the operator overrides the keyword inference (FR6). No new incident type added.

### TR6: Validation gate at PR review

PR review must include a check that the spec.md (or plan.md) lane field matches the brainstorm doc's lane field for the same feature. Add this as a code-quality rule reference, not a new agent.

### TR7: Token budget

The Phase 0.4 prose addition to `brainstorm` SKILL.md MUST stay under 600 words (the per-phase budget pattern). The `## Lane Inference` table in `brainstorm-domain-config.md` MUST stay under 400 words. Combined addition to the file does not bust the per-skill 1800-word description-budget rule per `plugins/soleur/AGENTS.md`.

## Acceptance Criteria

- `brainstorm` SKILL.md exposes a new Phase 0.4 that auto-detects, prompts, and writes `lane:` to the brainstorm doc frontmatter.
- `brainstorm-domain-config.md` has a `## Lane Inference` section with the minimum-viable keyword set.
- Phase 0.5 Processing Instructions read `LANE` and adjust the relevant-domain set per FR4.
- `work` SKILL.md Phase 0 announces the loaded lane when a spec.md is present (FR8).
- Parent audit spec FR4 and TR7 are amended per FR7.
- An end-to-end dry run on a `cross-domain`, a `single-domain`, and a `procedural` feature description produces matching lane fields across brainstorm doc + spec + plan + work-announce string.
- The `USER_BRAND_CRITICAL=true` override path forces `cross-domain` and bypasses Phase 0.4 selection.

## Out of Scope (Deferred)

- A `--lane=X` shortcut on `/soleur:go` or `/soleur:brainstorm`.
- Operator-override reason capture beyond the YAML frontmatter alone.
- Using `lane:` as a binding input to `work` Tier 0/A/B/C selection.
- Expanding the keyword-inference vocabulary beyond the minimum-viable set.
- Cross-skill lane validation as a CI hook (only PR-review gate at TR6).
