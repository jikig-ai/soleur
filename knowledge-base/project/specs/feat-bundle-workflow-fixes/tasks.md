---
lane: cross-domain
issues: ["#2733", "#2741"]
branch: feat-bundle-workflow-fixes
pr: "#3808"
spec: "knowledge-base/project/specs/feat-bundle-workflow-fixes/spec.md"
plan: "knowledge-base/project/plans/2026-05-15-feat-bundle-workflow-fixes-plan.md"
---

# Tasks: Bundle Workflow Fixes (#2733 + #2741)

Derived from the plan. Hierarchical numbering follows plan Phase 1-6.

## Phase 1 — Preconditions

- [ ] 1.1 Verify branch is `feat-bundle-workflow-fixes` and CWD is the worktree root
- [ ] 1.2 Run anchor-drift greps (plan §T1.2)
  - [ ] 1.2.1 `grep -n "^#### 1\.0 External\|^#### 1\.1 Research\|^### Phase 2:\|^### Phase 3:" plugins/soleur/skills/brainstorm/SKILL.md`
  - [ ] 1.2.2 `grep -n "^### 1\.7\.5\.\|^### 2\. Issue Planning" plugins/soleur/skills/plan/SKILL.md`
  - [ ] 1.2.3 `grep -n "\[id: cq-regex-unicode-separators-escape-only\]" AGENTS.md AGENTS.rest.md`
  - [ ] 1.2.4 Halt + re-check if any expected anchor is missing
- [ ] 1.3 Read each of the four target files once before editing (Edit tool requires prior Read)

## Phase 2 — Edits to `plugins/soleur/skills/brainstorm/SKILL.md`

- [ ] 2.1 (FR1) Insert `#### 1.0.5 Premise Validation` subsection between current `#### 1.0 External Platform Verification` and `#### 1.1 Research (Context Gathering)`. Body text MUST match #2733 issue body verbatim.
- [ ] 2.2 (FR2) Insert `### Phase 2.5: Productize Checkpoint` subsection between current `### Phase 2:` and `### Phase 3:`. Body text MUST match #2733 issue body verbatim.
- [ ] 2.3 (FR4) Append Phase 2 inline budget-checkpoint paragraph at the end of `### Phase 2: Explore Approaches` body, before the new Phase 2.5 heading from 2.2.

## Phase 3 — Edit to `plugins/soleur/skills/plan/SKILL.md`

- [ ] 3.1 (FR3) Insert `### 1.8. Skill Description Budget Check (Conditional)` subsection between current `### 1.7.5. Code-Review Overlap Check` and `### 2. Issue Planning & Structure`. Body references the source-learning Node one-liner by pointer (path + line 33).

## Phase 4 — Edits to AGENTS files (single atomic commit)

- [ ] 4.1 (FR5) Insert `cq-skill-description-budget-headroom` rule body into `AGENTS.rest.md` under `## Code Quality`, immediately before the existing `cq-regex-unicode-separators-escape-only` line. End with `**Why:** #2741 — see <learning path>.`
- [ ] 4.2 (FR6) Insert `- [id: cq-skill-description-budget-headroom] → rest` into `AGENTS.md` index under `## Code Quality`, immediately before the existing `cq-regex-unicode-separators-escape-only` pointer.
- [ ] 4.3 Measure new rule body length with `awk '/cq-skill-description-budget-headroom/ {print length}' AGENTS.rest.md`; verify ≤ 600.
- [ ] 4.4 Run `python3 scripts/lint-rule-ids.py`; expect exit 0.
- [ ] 4.5 Run `python3 scripts/lint-agents-rule-budget.py`; expect exit 0 for the bundle-induced delta. Pre-existing B_ALWAYS warning is out-of-scope.

## Phase 5 — Dogfood verification (TR6)

- [ ] 5.1 Run the source-learning's Node one-liner verbatim (from line 33-57 of the learning file) via bash from worktree root. Do NOT inline-modify with `child_process` / `execSync` (will trip the external `security-guidance` plugin hook).
- [ ] 5.2 Verify cumulative headroom ≥ 0; paste output into PR body `## Budget check` section.
- [ ] 5.3 If headroom < 0: HALT, investigate, trim siblings per the new rule's procedure.

## Phase 6 — Commit + push + PR ready

- [ ] 6.1 Stage the four edited files with explicit paths (NOT `git add -A`).
- [ ] 6.2 Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`.
- [ ] 6.3 Commit with the heredoc message in plan §T6.3 (`Closes #2733`, `Closes #2741` in body — NOT `Closes #2732`).
- [ ] 6.4 `git push && gh pr ready 3808`.
- [ ] 6.5 `gh pr merge 3808 --squash --auto`; poll `gh pr view 3808 --json state` until MERGED; run `cleanup-merged`.

## Out-of-bundle follow-ups (file after merge)

- [ ] OB1 File issue: B_ALWAYS shrink (pre-existing critical state, 23,196 > 22,000).
- [ ] OB2 File issue: Longest-rule shrink (pre-existing 1150-byte rule).
- [ ] OB3 File issue (optional): Upstream PR to `claude-plugins-official/security-guidance` to add fenced-code skip for `text`/`prose`/`diff` info-strings.
