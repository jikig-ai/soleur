---
date: 2026-05-12
issue: 2721
parent_issue: 2718
parent_brainstorm: knowledge-base/project/brainstorms/2026-04-21-claude-skills-audit-brainstorm.md
parent_spec: knowledge-base/project/specs/feat-claude-skills-audit/spec.md
worktree: .worktrees/feat-orchestration-lanes
branch: feat-orchestration-lanes
draft_pr: 3625
attribution_source: https://github.com/alirezarezvani/claude-skills (MIT, Copyright 2025 Alireza Rezvani)
brand_survival_threshold: none
---

# Brainstorm — Named Orchestration Lanes in `brainstorm` + `work`

## What We're Building

A single `lane:` field that captures **Phase 0.5 domain-leader breadth** for any `brainstorm` (or downstream `work`) session, with three honest values:

- **`single-domain`** — Phase 0.5 spawns one domain leader. The leader either self-assesses or delegates to its own specialists per the existing 3-phase contract.
- **`cross-domain`** — Phase 0.5 spawns two or more domain leaders in parallel. The default when keyword auto-detection is ambiguous (fail-closed).
- **`procedural`** — Phase 0.5 spawns zero leaders. Reserved for deterministic skill-chain work (scaffolds, lockfile bumps, format-only edits) where leader judgement adds no signal.

Auto-detection runs at a new **Phase 0.4** (between the existing `USER_BRAND_CRITICAL` tag at 0.1 and the roadmap freshness check at 0.25): keyword scan on the feature description proposes a default, AskUserQuestion surfaces it pre-filled, operator can override. The selected lane writes to the brainstorm doc's YAML frontmatter, is carried into `spec.md`, and is read (informational only) by `plan` and `work`.

**Work skill Tier 0/A/B/C is untouched.** Lanes describe brainstorm breadth, not work parallelism.

## Why This Approach

**Single-axis under operator-confusion constraint.** The upstream `alirezarezvani/claude-skills/orchestration/ORCHESTRATION.md` defines four named patterns (Solo Sprint, Domain Deep-Dive, Multi-Agent Handoff, Skill Chain) that span two orthogonal axes — domain-leader breadth and execution parallelism. A 2026-03-03 learning explicitly warns: collapsing those two axes into a single label is "the original sin operators hit" — operators conflate phase-level parallelism (Tier 0) with task-level parallelism (Tier A/B/C) with domain-leader breadth (Phase 0.5). Locking lanes to the breadth axis only preserves the existing `work` Tier system, matches the existing `USER_BRAND_CRITICAL` override precedent in `brainstorm-domain-config.md`, and gives operators one new concept to learn instead of three.

**Three lanes, not four.** Under single-axis, "Solo Sprint" and "Domain Deep-Dive" produce identical Phase 0.5 fan-out (both = 1 leader). The upstream distinction lives in execution depth, which is the work-tier axis we excluded. Carrying a 4th label that has no observable Phase 0.5 effect would be vocabulary inflation that the `/soleur:help` discoverability cost outweighs.

**Fail-closed default = `cross-domain`.** The user-impact gate (`hr-weigh-every-decision-against-target-user-impact`) and the regulated-data gate (`hr-gdpr-gate-on-regulated-data-surfaces`) are non-negotiable; they only fire when the relevant domain leaders are present at Phase 0.5. A cheapest-default lane (`procedural` or `single-domain`) would silently skip those gates for ambiguous-keyword cases — exactly the operator-facing risk #1 the founder flagged. The asymmetry is decisive: cost of false-positive fan-out is extra tokens (recoverable); cost of false-negative is a shipped feature that bypassed the brand-survival check.

**Lane is informational downstream, not binding.** `plan` and `work` read the carried lane to inform suggestions, never as a hard constraint. This avoids coupling drift between brainstorm decisions made hours-or-days earlier and the realities the implementer sees. The single source of truth for work parallelism remains the Tier 0/A/B/C pre-check at `work` Phase 2.

**Soleur idiom, not upstream names.** Upstream labels (Solo Sprint, Multi-Agent Handoff) frame work as "shape of execution"; Soleur operators reason in "who touches it." Renaming to `single-domain` / `cross-domain` / `procedural` matches the `pdr-*` passive-domain-routing vocabulary already in AGENTS.md and side-steps the MIT-per-file attribution requirement CMO flagged for verbatim lifts. Per the parent audit, attribution still belongs in skill file headers when verbatim text is lifted, but a rename to native idiom removes that obligation.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Single-axis: lanes describe Phase 0.5 domain-leader breadth only; `work` Tier 0/A/B/C is untouched | 2026-03-03 learning: collapsing axes is the historical operator-confusion failure mode. Single-axis keeps the two orthogonal concepts visible separately. |
| 2 | Three lanes: `single-domain`, `cross-domain`, `procedural` | Honest mapping under single-axis. Upstream's 4th (Domain Deep-Dive) collapses into `single-domain` because both produce one-leader Phase 0.5 fan-out. |
| 3 | Auto-detect lane at a new Phase 0.4, between `USER_BRAND_CRITICAL` (0.1) and roadmap freshness (0.25) | Sits before Phase 0.5 spawns; mirrors the `USER_BRAND_CRITICAL` tag-then-override pattern; surfaces selection via AskUserQuestion so the operator acknowledges it once. |
| 4 | Fail-closed default = `cross-domain` when keyword inference is ambiguous | Per `hr-weigh-every-decision-against-target-user-impact`: cost of an unfired user-impact gate dominates cost of an extra leader spawn. CPO + CTO converged on this. |
| 5 | Soleur-idiom labels, not verbatim upstream names | CMO: verbatim lifts require per-file MIT attribution under MIT §1; rename to native idiom drops the obligation. Also matches `pdr-*` vocabulary already in AGENTS.md. |
| 6 | Lane is carried via YAML frontmatter (`lane:`) through brainstorm → spec → plan → work | Single source of truth; `plan` and `work` treat it as informational, not binding. Matches the existing `brand_survival_threshold:` carry-forward pattern. |
| 7 | If `USER_BRAND_CRITICAL=true` from Phase 0.1, force lane to `cross-domain` regardless of keyword inference | Already-decided gate must win; lane is a refinement, not a downgrade path. |
| 8 | Amend parent audit spec FR4 to `3 lanes (single-axis)` with rationale link to this brainstorm | FR4 currently lists 4 lanes; amendment is part of implementation in the plan/work phase, not this brainstorm. |
| 9 | Keyword inference rules live in `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` next to the existing 8-domain table | Single source of truth; matches the table-driven routing pattern from learning `2026-02-22-domain-prerequisites-refactor-table-driven-routing`. |
| 10 | Operator override surfaced as a free-text "Other" path on the AskUserQuestion | Auto-Other is appended by the runtime per Phase 0.1 precedent; lets the operator pin an unusual lane without inventing a new flag. |

## Open Questions

- Keyword vocabulary for `cross-domain` auto-inference: minimum set the brainstorm doc commits to vs. the broader set that lives in `brainstorm-domain-config.md`? Plan-phase decision.
- Should the operator override write a one-line "override reason" to the brainstorm doc (parallel to USER_BRAND_CRITICAL telemetry), or is the lane field alone enough audit trail? Plan-phase decision.
- `work` skill consumes `lane:` from spec.md frontmatter how exactly — at Phase 0 (alongside constitution load) or at Phase 2 (Tier 0/A/B/C selection)? Plan-phase decision.
- Telemetry: does Phase 0.4 emit a rule-application incident when lane is forced by `USER_BRAND_CRITICAL`? Probably yes (mirrors Phase 0.1 emit) but defer to plan-phase telemetry sweep.
- Does `/soleur:go` need a `--lane=X` shortcut to bypass Phase 0.4 entirely in pipeline mode? Plan-phase ergonomics decision.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Lock Soleur-idiom labels (`single-domain` / `cross-domain` / `procedural`); fail-closed to `cross-domain` on ambiguity. Founder outcome: operators stop accidentally shipping security/data-touching work through a Solo-Sprint-shaped session that silently skips the user-impact gate. Explicit `--lane` flag logs operator overrides.

### Engineering (CTO)

**Summary:** Lanes are presets over the existing Phase 0.5 axis, not new primitives. Auto-detect via keyword-prefilled AskUserQuestion at brainstorm start; fail-closed default is the broadest lane (`cross-domain`) to preserve the user-impact gate per `hr-weigh-every-decision-against-target-user-impact`. Work Tier 0/A/B/C remains untouched — lane is read-only informational input there. (Note: CTO's original framing was two-axis preset; this brainstorm locked single-axis after the 2026-03-03 operator-confusion learning surfaced — CTO position carried forward as one-axis-lanes-plus-existing-tier-system.)

### Marketing (CMO)

**Summary:** Verbatim lift of upstream lane names (Solo Sprint, Multi-Agent Handoff, etc.) would require per-file MIT attribution header in `brainstorm`/`work` SKILL.md. Renaming to Soleur idiom (`single-domain` / `cross-domain` / `procedural`) drops the attribution obligation entirely — taxonomies and ideas are not copyrightable, only expression is. The brainstorm doc retains attribution to the upstream source in frontmatter for provenance.

## Capability Gaps

No Soleur capability gaps blocking this work. Evidence:

- Phase 0.5 domain-leader fan-out exists and is table-driven via `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` (repo-research confirmed table headers + 8 domain rows).
- The `USER_BRAND_CRITICAL` precedent already overrides the standard domain-sweep at Phase 0.1; the new lane logic is structurally identical — read tag, expand or contract the relevant-domain set.
- YAML frontmatter carry-forward is already used for `brand_survival_threshold` and date metadata.
- AskUserQuestion is already the primary operator-acknowledgment surface in Phase 0.1 — extending it to Phase 0.4 reuses an existing pattern.
- No new agent, no new skill, no new script needed. All work lands in SKILL.md edits and one reference file update.

## User-Brand Impact

**Tagged:** `USER_BRAND_CRITICAL=false` (no trigger keywords matched in operator's free-text answer).

**Meta-observation:** This feature *governs whether* the user-impact gate fires for downstream brainstorms — a wrong-lane auto-detection on a security-sensitive feature would silently skip the gate at Phase 0.5. That is risk #1 from the operator's framing. The fail-closed default (cross-domain on ambiguity) is the mitigation, and Decision #7 (USER_BRAND_CRITICAL=true forces cross-domain) is the belt-and-suspenders.

## Attribution

Upstream source: `https://github.com/alirezarezvani/claude-skills/orchestration/ORCHESTRATION.md` (MIT, Copyright 2025 Alireza Rezvani). All four pattern names (Solo Sprint, Domain Deep-Dive, Multi-Agent Handoff, Skill Chain) were considered as labels and rejected in favor of Soleur-native idiom per the CMO assessment. No verbatim file content is being lifted.
