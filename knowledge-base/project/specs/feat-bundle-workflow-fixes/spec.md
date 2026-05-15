---
lane: cross-domain
brand_survival_threshold: single-user incident
issues: ["#2732", "#2733", "#2741"]
branch: feat-bundle-workflow-fixes
pr: "#3808"
brainstorm: "knowledge-base/project/brainstorms/2026-05-15-bundle-workflow-fixes-brainstorm.md"
---

# Spec: Bundle Workflow Fixes (#2732 + #2733 + #2741)

**Issues:** [#2732](https://github.com/jikig-ai/soleur/issues/2732), [#2733](https://github.com/jikig-ai/soleur/issues/2733), [#2741](https://github.com/jikig-ai/soleur/issues/2741)
**Branch:** feat-bundle-workflow-fixes
**Date:** 2026-05-15
**Brainstorm:** [2026-05-15-bundle-workflow-fixes-brainstorm.md](../../brainstorms/2026-05-15-bundle-workflow-fixes-brainstorm.md)
**Draft PR:** #3808

## Problem Statement

Three workflow-improvement issues from the 2026-04-21 peer-plugin-audit session remain open. Each is small, well-scoped, and overlaps with the others (#2733 and #2741 both edit `plugins/soleur/skills/brainstorm/SKILL.md`). Shipping them in three separate PRs would burn three CI cycles and three review rounds for ~400 LOC total.

- **#2732** — `plugins/soleur/hooks/security_reminder_hook.py` blocks legitimate doc authoring when specs / learning files describe scanner patterns (false positive on literal token names).
- **#2733** — Two workflow patterns observed during the 2026-04-21 brainstorm (premise validation before research; productize checkpoint for recurring work) are unencoded in the brainstorm skill, so future brainstorms re-discover them session-by-session.
- **#2741** — SKILL.md `description:` fields have a cumulative word-budget cap; the plan and brainstorm skills don't measure headroom before approving edits, so descriptions can be silently truncated.

## User-Brand Impact

- **Artifact:** `plugins/soleur/hooks/security_reminder_hook.py` literal-token guard.
- **Vector:** Operator pastes a real credential into a fenced ```` ```text ```` block (mistaking it for a sample); the post-fix hook skips the block; the credential lands on `main`.
- **Threshold:** `single-user incident` — one leaked credential is one operator's brand-survival event.
- **Carry-forward to plan:** plan Phase 2.6 must reproduce this `User-Brand Impact` block verbatim. The PR review phase MUST invoke the `user-impact-reviewer` agent.

## Goals

- G1 (#2732): Allow doc authors to describe scanner patterns inside fenced ```` ```text ````, ```` ```prose ````, or ```` ```diff ```` blocks without tripping the security-reminder hook.
- G2 (#2733): Encode the premise-validation pattern as brainstorm Phase 1.0.5 and the productize-checkpoint pattern as brainstorm Phase 2.5.
- G3 (#2741): Enforce SKILL.md description word-budget headroom at plan time (Phase 1) and brainstorm time (Phase 2 checkpoint), backed by a hard rule in `AGENTS.rest.md`.
- G4: Ship all three as a single PR with a single review round.

## Non-Goals

- N1: Backfill of existing SKILL.md descriptions (the new budget rule fires on future PRs only).
- N2: Broader docs-allowance approaches for the security hook (path whitelist; allow-marker comment). Option 1 is sole accepted approach.
- N3: Retirement of any existing AGENTS.md rule. #2741's "rule retirement required" premise is dissolved by AGENTS.md sidecar refactor (75 rules across 4 files, 32,470 bytes total — well under any prior cap).
- N4: Cross-session pattern analysis or scheduled scans against the rule corpus.

## Functional Requirements

- FR1 (#2732): `security_reminder_hook.py` skips literal-token detection inside markdown fenced-code blocks whose info-string is `text`, `prose`, or `diff`.
- FR2 (#2732): The fence-skip is implemented as a token-stream filter (track fence open/close), NOT a regex over the entire file body — to avoid pathological backtracking on long docs.
- FR3 (#2732 — defense-in-depth): Inside a fence-skipped block, the hook STILL flags any line matching a high-entropy credential pattern (e.g., `sk_(test|live)_[A-Za-z0-9]{20,}`, `xox[bp]-`, `ghp_[A-Za-z0-9]{36}`). The fence allowance is for literal token NAMES, not for credential bodies.
- FR4 (#2733): `plugins/soleur/skills/brainstorm/SKILL.md` gains a `### Phase 1.0.5 — Premise Validation` subsection between current Phase 1.0 and Phase 1.1, with text matching #2733's issue body.
- FR5 (#2733): Same file gains a `### Phase 2.5 — Productize Checkpoint` subsection between current Phase 2 and Phase 3, with text matching #2733's issue body.
- FR6 (#2741): `plugins/soleur/skills/plan/SKILL.md` Phase 1 gains a step measuring cumulative SKILL.md `description:` word headroom (cap: 1800) when the plan edits any `description:` in `plugins/soleur/skills/*/SKILL.md`; if headroom < 10 words, the plan must prescribe exact sibling-description trims with before/after text.
- FR7 (#2741): `plugins/soleur/skills/brainstorm/SKILL.md` Phase 2 gains a budget-measurement checkpoint when the brainstorm proposes adding or restructuring skills.
- FR8 (#2741): `AGENTS.rest.md` gains `[id: cq-skill-description-budget-headroom]` with body: "When a PR edits any `description:` in `plugins/soleur/skills/*/SKILL.md`, the plan MUST measure current cumulative word headroom (cap: 1800). If headroom < 10 words, the plan MUST prescribe exact sibling-description trims with before/after text."
- FR9 (#2741): `AGENTS.md` index gains `- [id: cq-skill-description-budget-headroom] → rest` under `## Code Quality`.

## Technical Requirements

- TR1: All edits land in `feat-bundle-workflow-fixes` worktree (already created, draft PR #3808 already open).
- TR2: Test coverage for FR1-FR3 is in `plugins/soleur/hooks/tests/` (or wherever `security_reminder_hook.py` tests live — discover in plan phase). Three required cases: (a) `text` fence skips literal token names; (b) `python` fence still detects literal token names; (c) `text` fence containing a `sk_test_*` literal still trips FR3's high-entropy check.
- TR3: FR6-FR7 use a one-line `awk` or `wc -w` measurement script. Reuse the exact one-liner from the source learning at `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`.
- TR4: PR description must use `Closes #2732, Closes #2733, Closes #2741` in the body (NOT the title) per `wg-use-closes-n-in-pr-body-not-title-to`.

## Implementation Order

1. `security_reminder_hook.py` + tests (#2732) — isolated change, no cross-coupling.
2. `plugins/soleur/skills/brainstorm/SKILL.md` — apply #2733 first (structural phase inserts), then #2741's Phase 2 checkpoint (inline addition anchored to the now-stable Phase 2).
3. `plugins/soleur/skills/plan/SKILL.md` — #2741 Phase 1 step.
4. `AGENTS.rest.md` + `AGENTS.md` index — #2741 rule landing.

## Domain Review (carry-forward)

Phase 0.5 leader triad skipped per brainstorm Key Decision #6 (USER_BRAND_CRITICAL=true was tagged on hook docs-allowance vector, but Option 1 was already decided and triad would be ceremonial). `user-impact-reviewer` agent at PR review time is the load-bearing gate.

## Acceptance Criteria

- AC1: Hook tests for #2732 cover (a) fence-skip works, (b) non-allowed fences still scan, (c) high-entropy literals inside allowed fences still trip.
- AC2: Brainstorm SKILL.md diff shows Phase 1.0.5 and Phase 2.5 inserted at correct positions with body text matching issue #2733.
- AC3: Plan SKILL.md Phase 1 contains the budget-measurement step.
- AC4: Brainstorm SKILL.md Phase 2 contains the budget-measurement checkpoint.
- AC5: `AGENTS.rest.md` contains the new rule; `AGENTS.md` index contains the pointer.
- AC6: All three issues close on PR merge via `Closes` in PR body.
