---
lane: cross-domain
issues: ["#2733", "#2741"]
branch: feat-bundle-workflow-fixes
pr: "#3808"
spec: "knowledge-base/project/specs/feat-bundle-workflow-fixes/spec.md"
brainstorm: "knowledge-base/project/brainstorms/2026-05-15-bundle-workflow-fixes-brainstorm.md"
requires_cpo_signoff: false
brand_survival_threshold: none
---

# Plan: Bundle Workflow Fixes — #2733 + #2741

**Issues:** [#2733](https://github.com/jikig-ai/soleur/issues/2733), [#2741](https://github.com/jikig-ai/soleur/issues/2741)
**Branch:** `feat-bundle-workflow-fixes`
**Date:** 2026-05-15
**Spec:** [feat-bundle-workflow-fixes/spec.md](../specs/feat-bundle-workflow-fixes/spec.md)
**Brainstorm:** [2026-05-15-bundle-workflow-fixes-brainstorm.md](../brainstorms/2026-05-15-bundle-workflow-fixes-brainstorm.md)
**Draft PR:** #3808

## Overview

Bundle two small workflow-improvement issues from the 2026-04-21 peer-plugin-audit session into one PR. Originally three issues; **#2732 closed at plan time** (the named hook is external — not in our repo — see Research Reconciliation).

- **#2733** — Add `#### 1.0.5 Premise Validation` and `### Phase 2.5: Productize Checkpoint` to brainstorm SKILL.md, plus a Phase 2 inline budget checkpoint for skill-editing brainstorms.
- **#2741** — Add SKILL.md description word-budget headroom enforcement: new `### 1.8` sub-section in plan SKILL.md Phase 1, and new `[id: cq-skill-description-budget-headroom]` rule in `AGENTS.docs.md` + pointer in `AGENTS.md` index.

> **[Updated 2026-05-15 — post-plan-review]** Architecture-strategist caught a P0 sidecar misfit: SKILL.md edits classify as `.md` → `docs-only` per `.claude/hooks/session-rules-loader.sh` lines 102-126. `AGENTS.rest.md` does NOT load on docs-only sessions, so the rule would have been silent-no-op for its own trigger. Moved rule body to `AGENTS.docs.md` and pointer to `→ docs-only`. Also dropped Phase 5 dogfood verification (the bundle doesn't edit any `description:` field, so the measurement is theater) and three duplicate Sharp Edges. Reordered Phase 2 brainstorm edits to FR1 → FR4 → FR2 to avoid anchor drift.

Approximate diff: ~80 LOC across 4 files.

## Research Reconciliation — Spec vs. Codebase

| Claim source | Claim | Reality | Plan response |
|---|---|---|---|
| Spec / brainstorm (carry-forward from #2732 issue body) | `plugins/soleur/hooks/security_reminder_hook.py` scans markdown for literal Python tokens | TWO hooks share the name. The Soleur-repo hook at `.claude/hooks/security_reminder_hook.py` only scans `.github/workflows/*.yml` (narrowed by PR #2528 on 2026-04-18). The hook that actually blocks docs is the **external `claude-plugins-official/security-guidance` plugin** at `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/security-guidance/hooks/security_reminder_hook.py` — confirmed by tripping it during plan authoring. | Drop #2732 from bundle. Close as out-of-scope (external plugin, not Soleur-owned). Fix path is upstream PR or plugin disable, not in-repo. FR1-FR3 + AC1 removed from spec. |
| Issue #2741 body | `AGENTS.md` at 106/100 rules and 36566/40000 bytes — retire-a-rule required | Sidecar refactor: 75 rules across 4 files, 32,470 bytes total. No per-file cap binding. Always-loaded payload (B_ALWAYS) IS critical (23,196 > 22,000) but the new rule lands in `AGENTS.docs.md` (not always-loaded; see post-plan-review correction banner above for the rest.md→docs.md fix). | Drop rule-retirement work. New rule lands in `AGENTS.docs.md` only. Acknowledge pre-existing B_ALWAYS critical state in Sharp Edges. |
| Source learning (`2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`) line 33 | Canonical measurement one-liner is Node, not awk | Verified — source learning explicitly says "portable; avoids awk edge cases" then provides Node form. The Node form uses `fs.readdirSync`/`fs.readFileSync` only (no shell-invocation primitives). | Reference the one-liner BY POINTER (`source-learning §line 33`) from FR3 and FR4 — do NOT re-quote a modified copy in the plan body. (Lessons-learned during plan authoring: a re-quoted modified form using `child_process` tripped the external `security-guidance` plugin's hook.) |
| Brainstorm SKILL.md insertion points | Phase 1.0 at line 195, Phase 1.1 at line 199, Phase 2 at line 262 | Verified via `grep -n "^### Phase\|^#### 1\."`. | Cite line numbers as anchors; re-grep at /work-time before editing (file may have shifted since plan write). |
| Plan SKILL.md insertion point | Phase 1 has sub-sections 1, 1.4, 1.5, 1.5b, 1.6, 1.6b, 1.7, 1.7.5 then jumps to `### 2.` | Verified via `grep -n "^### "` — confirmed §1.7.5 Code-Review Overlap Check followed by §2 Issue Planning. | Insert new `### 1.8. Skill Description Budget Check (Conditional)` between §1.7.5 and §2. Do NOT renumber existing sub-sections. |

## User-Brand Impact

- **If this lands broken, the user experiences:** A future brainstorm/plan run uses outdated guardrails until next session-start. Worst-case symptom: an over-cap SKILL.md description silently truncated by `plugins/soleur/test/components.test.ts`, weakening one skill's agent discoverability until /work notices.
- **If this leaks, the user's data is exposed via:** N/A — no credentials, auth, data, payments, or user-owned resources touched.
- **Brand-survival threshold:** none. Scope-out justification: workflow-skill self-improvement only, no user-data surface, no agent capability outside the operator's own session.

The brainstorm's original `single-user incident` framing was anchored to the now-dissolved (then re-dissolved-with-corrected-reason) #2732 vector. With #2732 removed, no vector remains. `user-impact-reviewer` agent at PR review is NOT required.

## Files to Edit

1. **`plugins/soleur/skills/brainstorm/SKILL.md`** — three edits:
   - Insert `#### 1.0.5 Premise Validation` block between current `#### 1.0` (line ~195) and `#### 1.1` (line ~199).
   - Insert `### Phase 2.5: Productize Checkpoint` block between current `### Phase 2:` (line ~262) and the existing `### Phase 3:` section.
   - Insert inline Phase 2 budget-checkpoint paragraph at the end of `### Phase 2: Explore Approaches` body (before the new `### Phase 2.5:` heading).
2. **`plugins/soleur/skills/plan/SKILL.md`** — one edit: insert `### 1.8. Skill Description Budget Check (Conditional)` between current `### 1.7.5. Code-Review Overlap Check` (line ~186) and `### 2. Issue Planning & Structure` (line ~227).
3. **`AGENTS.docs.md`** — one edit: insert new `cq-skill-description-budget-headroom` rule body under `## Code Quality` (line 3 heading), at the end of the existing `cq-*` cluster (after the current last entry `cq-eleventy-critical-css-screenshot-gate`).
4. **`AGENTS.md`** (index) — one edit: insert `- [id: cq-skill-description-budget-headroom] → docs-only` under `## Code Quality`, immediately after the existing `- [id: cq-eleventy-critical-css-screenshot-gate] → docs-only` pointer (keeps `→ docs-only` cluster contiguous).

## Files to Create

None.

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200` against the 4 files above. Five open issues mention `AGENTS.md` but only as a rule source citation — none propose edits to `AGENTS.md` itself.

## Implementation Phases

### Phase 1 — Preconditions

- T1.1 Verify branch / worktree: `git branch --show-current` returns `feat-bundle-workflow-fixes`; `pwd` is the worktree root.
- T1.2 Verify insertion-point anchors haven't drifted since plan-write:
  ```bash
  grep -n "^#### 1\.0 External\|^#### 1\.1 Research\|^### Phase 2:\|^### Phase 3:" plugins/soleur/skills/brainstorm/SKILL.md
  grep -n "^### 1\.7\.5\.\|^### 2\. Issue Planning" plugins/soleur/skills/plan/SKILL.md
  grep -n "\[id: cq-eleventy-critical-css-screenshot-gate\]" AGENTS.md AGENTS.docs.md
  ```
  If any expected anchor is missing, halt and re-check the file structure before editing.
- T1.3 Read each target file once (Edit tool requires prior Read) and confirm the current text around each insertion point matches what this plan assumes.

### Phase 2 — Edits to `plugins/soleur/skills/brainstorm/SKILL.md`

**Order: FR1 → FR4 → FR2** (per architecture-strategist P2 — avoids anchor drift). FR1 lands in its own zone (between Phase 1.0 and Phase 1.1). FR4 appends to the **untouched** end of Phase 2 body. FR2 then inserts a new sub-section after Phase 2 (now containing the FR4 paragraph). This sequence means each edit anchors against text the previous edit did not modify.

- T2.1 (FR1): Insert new `#### 1.0.5 Premise Validation` subsection between `#### 1.0 External Platform Verification` and `#### 1.1 Research (Context Gathering)`. Body MUST match #2733 issue body verbatim:
  > Before launching research agents, grep existing truth sources (CI report, roadmap, prior brainstorms) for named external entities or claims in the feature description. If the framing contradicts what the ground truth documents say, surface the contradiction and re-scope with the user before continuing. A framing defect caught here is worth more than a full research sprint built on it.
- T2.2 (FR4): Append a one-paragraph Phase 2 budget-checkpoint at the end of `### Phase 2: Explore Approaches` body, **immediately before the existing `### Phase 3:` heading** (anchor BEFORE FR2's new heading is inserted). Exact text:
  > **Budget checkpoint:** If the brainstorm proposes adding or restructuring skills, run the SKILL.md description word-budget measurement one-liner (Node form, see `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` line 33) before authoring approach proposals. Surface headroom as a first-class constraint if < 10 words remain against the 1800-word cumulative cap.
- T2.3 (FR2): Insert new `### Phase 2.5: Productize Checkpoint` subsection between the now-FR4-tail-ending `### Phase 2:` body and `### Phase 3: Create Worktree (if knowledge-base/ exists)`. Body MUST match #2733 issue body verbatim:
  > When proposing an action plan, ask: is the inciting work pattern likely to recur (scheduled workflow output, weekly review cadence, batch-triggered task, recurring competitive-intel finding)? If yes, propose a skill or sub-mode of an existing skill that captures the workflow. A recurring-work plan that produces issues but no reusable artifact has done half the work.

### Phase 3 — Edit to `plugins/soleur/skills/plan/SKILL.md`

- T3.1 (FR3): Insert new `### 1.8. Skill Description Budget Check (Conditional)` subsection between `### 1.7.5. Code-Review Overlap Check` and `### 2. Issue Planning & Structure`. Body (clarified per spec-flow Flow 4 — addresses Phase 1 vs Phase 2 timing):
  > If the feature description, research findings (1.1), or repo grep (Phase 1.7 consolidation) surfaces a candidate `description:` edit to any `plugins/soleur/skills/*/SKILL.md`, run the budget one-liner now (Node form, see [`knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`](../../../knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md) line 33). Record baseline headroom in Research Insights. Re-run in Step 2 once `## Files to Edit` is finalized to confirm the budget impact of the actual edits. If headroom < 10 words at either check, include exact sibling-trim text (before/after) in `## Files to Edit` before proceeding. Cap: 1800 cumulative words, enforced by `plugins/soleur/test/components.test.ts`. Skip silently if no SKILL.md `description:` edit is candidate or finalized.

### Phase 4 — Edits to AGENTS files (single atomic commit)

Per spec TR4 (`cq-rule-ids-are-immutable` enforcement): FR5 and FR6 MUST commit together so `scripts/lint-rule-ids.py` sees both sides of the ID.

- T4.1 (FR5): Append to `AGENTS.docs.md` under `## Code Quality`, immediately after the existing `cq-eleventy-critical-css-screenshot-gate` line (end of the cluster). Exact rule body (one line, ≤ 600 B per `cq-agents-md-why-single-line` cap):
  > `- When a PR edits any \`description:\` in \`plugins/soleur/skills/*/SKILL.md\`, the plan MUST measure current cumulative word headroom (cap: 1800) [id: cq-skill-description-budget-headroom] [skill-enforced: plan §1.8, brainstorm Phase 2 budget checkpoint]. If headroom < 10 words, the plan MUST prescribe exact sibling-description trims with before/after text. **Why:** #2741 — see \`knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md\`.`
  - Kieran's plan-review measurement: 489 B (under 600 B cap, well under the 580 B margin target). Re-measure after insert with `awk '/cq-skill-description-budget-headroom/ {print length}' AGENTS.docs.md`.
- T4.2 (FR6): Insert into `AGENTS.md` index under `## Code Quality`, immediately after the existing `- [id: cq-eleventy-critical-css-screenshot-gate] → docs-only` line (keeps `→ docs-only` cluster contiguous):
  > `- [id: cq-skill-description-budget-headroom] → docs-only`
- T4.3 Run `python3 scripts/lint-rule-ids.py` (no args). Expect exit 0.
- T4.4 Run `python3 scripts/lint-agents-rule-budget.py` (no args). Expect exit 0 for the bundle-induced delta. The script will likely surface the pre-existing B_ALWAYS warning (23,196 > 22,000) — that's a pre-existing state, not a bundle regression. The new rule lands in `AGENTS.docs.md` (conditionally-loaded), NOT in always-loaded core/index, so B_ALWAYS is unchanged by this bundle except for the ~50-byte index pointer line.

### Phase 5 — Commit + push + PR ready

- T5.1 Stage edits: `git add plugins/soleur/skills/brainstorm/SKILL.md plugins/soleur/skills/plan/SKILL.md AGENTS.docs.md AGENTS.md`.
- T5.2 Run `skill: soleur:compound` before commit per `wg-before-every-commit-run-compound-skill`.
- T5.3 Commit. Suggested message (heredoc; do NOT include `Closes #2732`):
  ```
  feat(workflow): brainstorm Phase 1.0.5/2.5 + SKILL.md description budget rule

  Bundles #2733 + #2741 (originally bundled with #2732, which closed at
  plan-phase as out-of-scope — the named hook is external to our repo;
  see plan §Research Reconciliation).

  - brainstorm SKILL.md: add Phase 1.0.5 (premise validation before research)
    and Phase 2.5 (productize checkpoint after approach selection); add a
    Phase 2 inline budget checkpoint for skill-editing brainstorms.
  - plan SKILL.md: add §1.8 Skill Description Budget Check.
  - AGENTS.docs.md + AGENTS.md index: add cq-skill-description-budget-headroom
    rule with **Why:** pointer to the source learning.

  Closes #2733
  Closes #2741
  ```
- T5.4 Push and mark PR #3808 ready: `git push && gh pr ready 3808`.
- T5.5 Queue auto-merge per `wg-after-marking-a-pr-ready-run-gh-pr-merge`: `gh pr merge 3808 --squash --auto`.

## Test Strategy

Bundle is documentation-class (skill instruction additions + AGENTS.md rule). No unit tests added.

**Verification surface (all run in Phases 1, 4):**
- `grep -n` checks against insertion-point anchors before and after edits.
- `python3 scripts/lint-rule-ids.py` (FR6 pointer parity with FR5 body).
- `python3 scripts/lint-agents-rule-budget.py` (per-rule ≤ 600 B; pre-existing B_ALWAYS state acknowledged as out-of-scope).

## Sharp Edges

- **External `security-guidance` plugin hook will trip on `child_process` / `exec*` / `subprocess.call(..., shell=True)` patterns in any Write or Edit, including markdown.** The plan body learned this the hard way. Reference the source-learning's Node one-liner by pointer (path + line 33), never re-paste an inline-modified copy.
- **`### 1.8` numbering risk in plan SKILL.md.** Current Phase 1 sub-sections are 1, 1.4, 1.5, 1.5b, 1.6, 1.6b, 1.7, 1.7.5. Inserting 1.8 follows the existing numbering pattern. Do NOT renumber existing sub-sections — that would invalidate every existing cross-reference (this skill itself has cross-references between sub-sections).
- **#2733's value already demonstrated THREE times in this brainstorm/plan/plan-review cycle.** (1) Brainstorm Phase 1.1 caught the #2741 AGENTS.md byte-cap premise dissolution. (2) Plan Phase 1 caught the #2732 hook-scope premise dissolution + re-dissolved with corrected upstream-plugin attribution. (3) Plan-review architecture-strategist caught the rule-placement loader-class misfit — exactly the kind of premise-validation defect #2733 is designed to surface earlier. The rule pays for itself three times before it ships. Worth mentioning in PR description for review-time context.
- **Phase 2.5 of brainstorm SKILL.md (#2733's productize checkpoint) is text-only — no enforcement gate.** This is per the issue body's intent. If recurrence of "produced issues but no reusable artifact" continues, that's a follow-up workflow-gates rule, not in scope here. Spec-flow-analyzer also flagged that several FR1/FR2/FR4 body texts have ambiguous exit branches — those gaps are present in #2733's own issue body which the FR text is verbatim with; tightening them is a follow-up issue against #2733's prose, not in this bundle.
- **PR title vs body for `Closes #N`.** Per `wg-use-closes-n-in-pr-body-not-title-to`, closure directives MUST be in the PR body. PR title should be terse: `feat(workflow): brainstorm phases + SKILL.md description budget` (or similar). Do NOT include `Closes #2732`.
- **AGENTS.md insertion ordering inside `## Code Quality`.** The pointer line MUST land at the same relative position as the body line in `AGENTS.docs.md` (both at the end of the `cq-*` cluster, after the existing `cq-eleventy-critical-css-screenshot-gate` sibling). Mis-ordering won't fail lint, but `git diff` reviewability suffers.

## Out of Scope / Deferrals

- **B_ALWAYS shrink** (pre-existing critical). File as separate `chore` issue post-merge.
- **Longest-rule shrink** (pre-existing 1150-byte rule). File as separate `chore` issue post-merge.
- **Investigation of what actually blocked the 2026-04-21 audit-session writes** (now that #2732 is closed). Deferred unless recurrence; file fresh if observed.
- **Upstream PR to `claude-plugins-official/security-guidance`** to add fence-aware skipping. Out of bundle scope; file as separate issue (suggestion: title `chore: upstream PR to claude-plugins-official for fenced-code skip in security_reminder_hook`).
- **Backfill of cumulative SKILL.md description headroom** to maximize agent discoverability across all skills. Out of bundle scope; the new rule only fires on future edits.

## Plan Review Plan

Run `/plan_review knowledge-base/project/plans/2026-05-15-feat-bundle-workflow-fixes-plan.md` after writing this plan. Reviewers should focus on:

- (DHH) Is bundling these two issues into one PR overengineered when the bundle is only ~80 LOC? Would two parallel single-issue PRs be simpler? Counter: both issues edit the same file (`plugins/soleur/skills/brainstorm/SKILL.md`), so two parallel PRs would create a merge conflict — bundling is the cheaper path.
- (Kieran) Are FR1/FR2 body texts truly verbatim with #2733's issue body? Verify by re-reading #2733. Also: is the `[skill-enforced: ...]` annotation in T4.1 worth its bytes given B_ALWAYS is already critical? Counter: this lands in `AGENTS.docs.md`, not core; the annotation is informative for grep-discovery of the enforcing surface.
- (Code-simplicity) Could the Phase 2 inline budget-checkpoint paragraph (FR4) be dropped — does the AGENTS.md rule + plan Phase 1.8 already cover the same surface? Counter: brainstorm runs BEFORE plan; without the brainstorm-time checkpoint, the constraint surfaces only after research has burned ~10 minutes of agent time. The checkpoint pays for itself.

## Domain Review

**Domains relevant:** Engineering only.

Internal tooling change. No cross-domain implications.

### Engineering

**Status:** carried forward from brainstorm (assessment unchanged after scope reduction)
**Assessment:** Bundle is a four-file, ~80 LOC workflow improvement to brainstorm + plan skills and a new `cq-*` rule. Single-atomic-merge via standard `/soleur:review` → `/soleur:ship` flow. No CPO/CLO/CTO sign-off required (USER_BRAND_CRITICAL dropped to false at plan time).
