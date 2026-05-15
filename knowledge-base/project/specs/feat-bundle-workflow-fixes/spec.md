---
lane: cross-domain
brand_survival_threshold: none
issues: ["#2733", "#2741"]
branch: feat-bundle-workflow-fixes
pr: "#3808"
brainstorm: "knowledge-base/project/brainstorms/2026-05-15-bundle-workflow-fixes-brainstorm.md"
---

# Spec: Bundle Workflow Fixes (#2733 + #2741)

**Issues:** [#2733](https://github.com/jikig-ai/soleur/issues/2733), [#2741](https://github.com/jikig-ai/soleur/issues/2741)
**Branch:** feat-bundle-workflow-fixes
**Date:** 2026-05-15
**Brainstorm:** [2026-05-15-bundle-workflow-fixes-brainstorm.md](../../brainstorms/2026-05-15-bundle-workflow-fixes-brainstorm.md)
**Draft PR:** #3808

> **[Updated 2026-05-15 — scope reduction]** Originally scoped to bundle #2732 + #2733 + #2741. Plan-phase Phase 1 verification dissolved #2732's premise (the named hook lives at `.claude/hooks/`, not `plugins/soleur/hooks/`, AND only scans `.github/workflows/*.yml` for injection sinks — it never scanned markdown for literal Python tokens; PR #2528 narrowed it on 2026-04-18, three days before #2732 was filed). #2732 closed as fixed-by-#2528. FR1-FR3 + AC1 removed. Bundle reduced to #2733 + #2741.

## Problem Statement

Two workflow-improvement issues from the 2026-04-21 peer-plugin-audit session remain open. Both edit `plugins/soleur/skills/brainstorm/SKILL.md`, so bundling them avoids two CI cycles and two review rounds for ~80 LOC total.

- **#2733** — Two workflow patterns observed during the 2026-04-21 brainstorm (premise validation before research; productize checkpoint for recurring work) are unencoded in the brainstorm skill, so future brainstorms re-discover them session-by-session.
- **#2741** — SKILL.md `description:` fields have a cumulative word-budget cap; the plan and brainstorm skills don't measure headroom before approving edits, so descriptions can be silently truncated.

## User-Brand Impact

- **If this lands broken, the user experiences:** A future brainstorm/plan run uses outdated guardrails until next session-start. Worst case: a SKILL.md description over-cap gets silently truncated by the test harness, weakening agent discoverability for one skill until the next /work pass notices.
- **If this leaks, the user's data is exposed via:** N/A — neither edit touches credentials, auth, data, payments, or user-owned resources.
- **Brand-survival threshold:** none — workflow-skill self-improvement, no user-data surface, no agent capability outside the operator's own session.

The brainstorm's original `single-user incident` framing was anchored to the (now-dissolved) #2732 hook docs-allowance vector. With #2732 removed, no vector remains.

## Goals

- G1 (#2733): Encode the premise-validation pattern as brainstorm Phase 1.0.5 and the productize-checkpoint pattern as brainstorm Phase 2.5.
- G2 (#2741): Enforce SKILL.md description word-budget headroom at plan time (Phase 1) and brainstorm time (Phase 2 checkpoint), backed by a hard rule in `AGENTS.docs.md`.
- G3: Ship as a single PR with a single review round.

## Non-Goals

- N1: Backfill of existing SKILL.md descriptions (the new budget rule fires on future PRs only).
- N2: Retirement of any existing AGENTS.md rule. #2741's "rule retirement required" premise is dissolved by the AGENTS.md sidecar refactor (75 rules across 4 files, 32,470 bytes total — well under any prior cap).
- N3: Cross-session pattern analysis or scheduled scans against the rule corpus.
- N4: Re-investigation of what actually blocked the 2026-04-21 audit-session writes (scope-out of #2732 closure; if recurrence happens, file fresh).
- N5: Adding `cq-*` rules to `AGENTS.core.md` — the new rule must land in `AGENTS.docs.md` (docs-only trigger surface — SKILL.md edits classify as `.md` per `.claude/hooks/session-rules-loader.sh` lines 102-126). Demoting any other rule is out of scope. (Note: earlier draft said `AGENTS.rest.md` / code-class — corrected at plan-review per architecture-strategist P0; `AGENTS.rest.md` does not load on docs-only diffs, which would have made the rule silent-no-op for its own trigger.)

## Research Reconciliation — Spec vs. Codebase

| Claim source | Claim | Reality | Plan response |
|---|---|---|---|
| Issue #2741 body | `AGENTS.md` is at 106/100 rules, 36566/40000 bytes — "rule retirement required" | `AGENTS.md` sharded into sidecars: 75 rules across 4 files, 32,470 bytes total. No per-file cap binding. | Drop rule-retirement work entirely; new rule lands in `AGENTS.docs.md` only. |
| Issue #2741 body | New rule applies to "plugins/soleur/skills/*/SKILL.md" descriptions | Confirmed — `plugins/soleur/test/components.test.ts` enforces the 1800-word cumulative cap. | Adopt path glob verbatim. |
| Issue #2733 body | Two new phases (1.0.5, 2.5) in brainstorm SKILL.md | Confirmed insertion points: Phase 1.0 at line 195, Phase 1.1 at line 199 (insert 1.0.5 between); Phase 2 at line 262, Phase 3 elsewhere (insert 2.5 between). | Adopt insertion points; cite line numbers in plan but verify at /work time since the file is live. |
| Source learning (`2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`) | Provides the canonical measurement one-liner | Confirmed at line 33: Node one-liner is preferred over `awk` (avoids edge cases on quoted strings). | Reuse Node one-liner verbatim in both Phase 1 (plan) and Phase 2 (brainstorm) checkpoint text. |

## Functional Requirements

- FR1 (#2733): `plugins/soleur/skills/brainstorm/SKILL.md` gains a `#### 1.0.5 Premise Validation` subsection between current `#### 1.0 External Platform Verification` and `#### 1.1 Research (Context Gathering)`. Body text encodes: "Before launching research agents, grep existing truth sources (CI report, roadmap, prior brainstorms) for named external entities or claims in the feature description. If the framing contradicts what the ground truth documents say, surface the contradiction and re-scope with the user before continuing. A framing defect caught here is worth more than a full research sprint built on it." (Match #2733 issue body verbatim.)
- FR2 (#2733): Same file gains a `### Phase 2.5: Productize Checkpoint` subsection between current `### Phase 2: Explore Approaches` and `### Phase 3: Create Worktree (if knowledge-base/ exists)`. Body text encodes: "When proposing an action plan, ask: is the inciting work pattern likely to recur (scheduled workflow output, weekly review cadence, batch-triggered task, recurring competitive-intel finding)? If yes, propose a skill or sub-mode of an existing skill that captures the workflow. A recurring-work plan that produces issues but no reusable artifact has done half the work." (Match #2733 issue body verbatim.)
- FR3 (#2741): `plugins/soleur/skills/plan/SKILL.md` Phase 1 (Local Research) gains a new sub-step `### 1.8. Skill Description Budget Check (Conditional)` after `### 1.7.5. Code-Review Overlap Check`. Body: "If the plan edits any `description:` in `plugins/soleur/skills/*/SKILL.md`, run the budget one-liner (Node form below), record baseline headroom in Research Insights, and if headroom < 10 words, include exact sibling-trim text in the plan's Files-to-Edit before proceeding to Step 2." Include the Node one-liner verbatim from the source learning.
- FR4 (#2741): `plugins/soleur/skills/brainstorm/SKILL.md` Phase 2 (Explore Approaches) gains a Phase 2 checkpoint paragraph (NOT a new sub-section — inline addition): "If the brainstorm proposes adding or restructuring skills, run the SKILL.md description word-budget measurement one-liner before authoring approach proposals. Surface headroom as a first-class constraint if < 10 words remain (cap: 1800 cumulative words)."
- FR5 (#2741): `AGENTS.docs.md` gains `[id: cq-skill-description-budget-headroom]` rule body under the existing `## Code Quality` heading, appended at the end of the existing `cq-*` cluster (after `cq-eleventy-critical-css-screenshot-gate`). Body: "When a PR edits any `description:` in `plugins/soleur/skills/*/SKILL.md`, the plan MUST measure current cumulative word headroom (cap: 1800). If headroom < 10 words, the plan MUST prescribe exact sibling-description trims with before/after text. **Why:** #2741 — see `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`."
- FR6 (#2741): `AGENTS.md` index gains `- [id: cq-skill-description-budget-headroom] → docs-only` under `## Code Quality`, immediately after the existing `- [id: cq-eleventy-critical-css-screenshot-gate] → docs-only` pointer (keeps `→ docs-only` cluster contiguous).

## Technical Requirements

- TR1: All edits land in `feat-bundle-workflow-fixes` worktree (already created, draft PR #3808 already open).
- TR2: Reuse the Node measurement one-liner from `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` line 33 verbatim. Do NOT invent a new awk form (the source learning specifically chose Node because awk has edge-case bugs on quoted values).
- TR3: New AGENTS.docs.md rule body MUST end with `**Why:** #2741 — see <learning path>.` per `cq-agents-md-why-single-line` convention.
- TR4: The new rule's `[id: ...]` slug `cq-skill-description-budget-headroom` is **immutable** per `cq-rule-ids-are-immutable` once committed. Verify slug presence in `AGENTS.md` index AND `AGENTS.docs.md` body in same commit; `scripts/lint-rule-ids.py` will reject a missing-side state.
- TR5: PR description must use `Closes #2733, Closes #2741` in the body (NOT the title) per `wg-use-closes-n-in-pr-body-not-title-to`. #2732 already closed; do NOT include `Closes #2732`.
- TR6: After edits to `plugins/soleur/skills/{brainstorm,plan}/SKILL.md`, FR3's budget one-liner MUST run against the **modified** files to verify the bundle does not itself violate the cap it introduces. This is the "eat your own dogfood" check. Run inline in /work, record output, paste into PR body.
- TR7: After AGENTS.md edit, `scripts/lint-agents-rule-budget.py` MUST exit 0 against the bundle. The script is the authoritative commit-gate (warns at B_ALWAYS ≥ 20000, rejects at > 22000, rejects any rule body > 600 B). The bundle adds to `AGENTS.docs.md` not core, so B_ALWAYS does not increase, but the new rule body must stay ≤ 600 B.

## Implementation Order

1. **`plugins/soleur/skills/brainstorm/SKILL.md`** — apply FR1 (Phase 1.0.5 insert), FR2 (Phase 2.5 insert), FR4 (Phase 2 inline checkpoint). Three edits to one file; do FR1 + FR2 (structural inserts) first, then FR4 (inline checkpoint anchored to Phase 2 which is now untouched-by-FR2-since-2.5-comes-after).
2. **`plugins/soleur/skills/plan/SKILL.md`** — apply FR3 (new `### 1.8` sub-step inserted after `### 1.7.5`).
3. **`AGENTS.docs.md`** — apply FR5 (new rule body under `## Code Quality`).
4. **`AGENTS.md`** (index) — apply FR6 (pointer line under `## Code Quality`). Must land in same commit as FR5 to keep `cq-rule-ids-are-immutable` happy.
5. **Dogfood verification** — run TR6 one-liner against the modified `brainstorm/SKILL.md` and `plan/SKILL.md`; run TR7 `lint-agents-rule-budget.py` against the bundle. Paste both outputs into PR body.

## Domain Review (carry-forward + reduction)

Phase 0.5 leader triad skipped per brainstorm Key Decision #6. With the scope reduction (USER_BRAND_CRITICAL → false), the original sole basis for spawning CPO/CLO/CTO is also gone. **Domain assessment: Engineering only — internal tooling, no cross-domain implications.**

`user-impact-reviewer` agent at PR review time is NOT required for the reduced scope (no user-data surface). Standard `/soleur:review` flow applies.

## Acceptance Criteria

### Pre-merge (PR)

- AC1: `plugins/soleur/skills/brainstorm/SKILL.md` diff shows the three additions per FR1/FR2/FR4 at the correct positions; body text matches #2733 issue body verbatim (FR1, FR2) and FR4 body matches the spec text.
- AC2: `plugins/soleur/skills/plan/SKILL.md` diff shows the new `### 1.8` sub-section per FR3 with the Node one-liner from the source learning included verbatim.
- AC3: `AGENTS.docs.md` contains the new rule per FR5; `AGENTS.md` index contains the pointer per FR6; both in the same commit.
- AC4: `scripts/lint-agents-rule-budget.py` and `scripts/lint-rule-ids.py` both exit 0 against the bundle.
- AC5: Dogfood check (TR6): the budget one-liner run against the modified `brainstorm/SKILL.md` and `plan/SKILL.md` reports headroom ≥ 0 (cumulative description word count ≤ 1800). Outputs pasted into PR body.
- AC6: PR body contains `Closes #2733` and `Closes #2741`. PR title does NOT.

### Post-merge (operator)

- AC7: None — the bundle has no operator-driven post-merge steps. Auto-merge handles the standard release/deploy workflows per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
