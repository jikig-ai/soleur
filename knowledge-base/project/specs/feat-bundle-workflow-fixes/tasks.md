---
lane: cross-domain
issues: ["#2733", "#2741"]
branch: feat-bundle-workflow-fixes
pr: "#3808"
spec: "knowledge-base/project/specs/feat-bundle-workflow-fixes/spec.md"
plan: "knowledge-base/project/plans/2026-05-15-feat-bundle-workflow-fixes-plan.md"
---

# Tasks: Bundle Workflow Fixes (#2733 + #2741)

Derived from the plan. Hierarchical numbering follows plan Phases 1-5 (Phase 5 dogfood dropped at plan-review per code-simplicity; bundle does not edit any `description:` field so headroom is by-construction unchanged from main).

## Phase 1 — Preconditions

- [ ] 1.1 Verify branch is `feat-bundle-workflow-fixes` and CWD is the worktree root
- [ ] 1.2 Run anchor-drift greps (plan §T1.2)
  - [ ] 1.2.1 `grep -n "^#### 1\.0 External\|^#### 1\.1 Research\|^### Phase 2:\|^### Phase 3:" plugins/soleur/skills/brainstorm/SKILL.md`
  - [ ] 1.2.2 `grep -n "^### 1\.7\.5\.\|^### 2\. Issue Planning" plugins/soleur/skills/plan/SKILL.md`
  - [ ] 1.2.3 `grep -n "\[id: cq-eleventy-critical-css-screenshot-gate\]" AGENTS.md AGENTS.docs.md`
  - [ ] 1.2.4 Halt + re-check if any expected anchor is missing
- [ ] 1.3 Read each of the four target files once before editing (Edit tool requires prior Read)

## Phase 2 — Edits to `plugins/soleur/skills/brainstorm/SKILL.md`

**Order: FR1 → FR4 → FR2** (each edit anchors against unmodified text).

- [ ] 2.1 (FR1) Insert `#### 1.0.5 Premise Validation` subsection between current `#### 1.0 External Platform Verification` and `#### 1.1 Research (Context Gathering)`. Body text MUST match #2733 issue body verbatim.
- [ ] 2.2 (FR4) Append Phase 2 inline budget-checkpoint paragraph at the end of `### Phase 2: Explore Approaches` body, immediately before the existing `### Phase 3:` heading. (Anchor is the **original** Phase 2/3 boundary, before FR2 changes it.)
- [ ] 2.3 (FR2) Insert `### Phase 2.5: Productize Checkpoint` subsection between current `### Phase 2:` body (now FR4-tail-ending) and `### Phase 3:`. Body text MUST match #2733 issue body verbatim.

## Phase 3 — Edit to `plugins/soleur/skills/plan/SKILL.md`

- [ ] 3.1 (FR3) Insert `### 1.8. Skill Description Budget Check (Conditional)` subsection between current `### 1.7.5. Code-Review Overlap Check` and `### 2. Issue Planning & Structure`. Body references source-learning Node one-liner by pointer (path + line 33). Trigger wording: "if Phase 1 surfaces a candidate `description:` edit; re-run in Step 2 once `## Files to Edit` is finalized."

## Phase 4 — Edits to AGENTS files (single atomic commit)

- [ ] 4.1 (FR5) Append `cq-skill-description-budget-headroom` rule body to `AGENTS.docs.md` under `## Code Quality`, after the existing `cq-eleventy-critical-css-screenshot-gate` line. End with `**Why:** #2741 — see <learning path>.` Measured length: 489 B (under 600 B cap).
- [ ] 4.2 (FR6) Insert `- [id: cq-skill-description-budget-headroom] → docs-only` into `AGENTS.md` index under `## Code Quality`, immediately after the existing `cq-eleventy-critical-css-screenshot-gate` pointer.
- [ ] 4.3 Measure new rule body length with `awk '/cq-skill-description-budget-headroom/ {print length}' AGENTS.docs.md`; verify ≤ 600.
- [ ] 4.4 Run `python3 scripts/lint-rule-ids.py`; expect exit 0.
- [ ] 4.5 Run `python3 scripts/lint-agents-rule-budget.py`; expect exit 0 for the bundle-induced delta. Pre-existing B_ALWAYS warning is out-of-scope.

## Phase 5 — Commit + push + PR ready

- [ ] 5.1 Stage the four edited files with explicit paths (NOT `git add -A`).
- [ ] 5.2 Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`.
- [ ] 5.3 Commit with the heredoc message in plan §T5.3 (`Closes #2733`, `Closes #2741` in body — NOT `Closes #2732`).
- [ ] 5.4 `git push && gh pr ready 3808`.
- [ ] 5.5 `gh pr merge 3808 --squash --auto`; poll `gh pr view 3808 --json state` until MERGED; run `cleanup-merged`.

## Out-of-bundle follow-ups (file after merge)

- [ ] OB1 File issue: B_ALWAYS shrink (pre-existing critical state, 23,196 > 22,000).
- [ ] OB2 File issue: Longest-rule shrink (pre-existing 1150-byte rule).
- [ ] OB3 File issue (optional): Upstream PR to `claude-plugins-official/security-guidance` to add fenced-code skip for `text`/`prose`/`diff` info-strings.
- [ ] OB4 File issue (optional): Tighten #2733's prose for FR1/FR2/FR4 exit branches (spec-flow-analyzer flagged ambiguity at plan-review). Out-of-scope here because FR text is verbatim with #2733's issue body.
