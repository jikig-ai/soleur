---
title: Review Workflow Hardening — Fix-Inline Discipline
type: refactor
date: 2026-04-15
branch: review-workflow-hardening
pr: 2375
issue: 2374
brainstorm: knowledge-base/project/brainstorms/2026-04-15-review-workflow-hardening-brainstorm.md
spec: knowledge-base/project/specs/review-workflow-hardening/spec.md
---

# Review Workflow Hardening — Fix-Inline Discipline

## Overview

Shift the default disposition of code-review findings from "file as GitHub issue" to "fix inline on the PR branch." In 3 days, 53 review-origin issues were filed. Root cause: `/review` SKILL.md tells agents to file ALL findings; `/ship` Phase 5.5 doesn't check whether findings are resolved; `compound` route-to-definition files issues in headless mode.

This PR rewrites three SKILL.md surfaces and adds one AGENTS.md rule. Backlog triage (53 existing issues) and regression telemetry are **deferred to follow-up issues** — they are independent of the prevention mechanism and bundling them would triple the PR review surface. Fixing the source is the load-bearing change; detection and cleanup can follow.

## Problem Statement

From #2374:

- **2026-04-13 → 2026-04-15:** 53 open issues with strict review-origin title prefixes (`review:`, `Code review #`, `Refactor:`, `arch:`, `compound:`, `follow-through:`). Corpus verified at plan-freeze: `gh issue list ... | length = 53`.
- **PR #2282** → 5 follow-ups. **PR #2213** → 8 follow-ups. Healthy baseline: 0-1.
- **Compound headless mode** (`plugins/soleur/skills/compound/SKILL.md:265`) files `compound: route-to-definition proposal` issues instead of editing the target skill — 10 such issues in 3 days.
- **Primary driver** (`plugins/soleur/skills/review/SKILL.md:289`): `<critical_requirement> ALL findings MUST be stored as GitHub issues via gh issue create. Create issues immediately after synthesis - do NOT present findings for user approval first.`

The findings themselves are legitimate; the **disposition** is wrong. Work that should complete in the originating PR gets pushed to a backlog that then accumulates.

## Proposed Solution

Three instruction rewrites + one Phase 5.5 gate + one AGENTS.md rule + one label.

1. **Rewrite `/review` SKILL.md Section 5.** Default action per finding is fix-inline on the PR branch. Issue filing is allowed only when one of four scope-out criteria (inlined in the SKILL.md, not a separate reference file) is met and the agent writes a `## Scope-Out Justification` section naming the criterion. The filed issue gets a `deferred-scope-out` label.
2. **Rewrite `compound` SKILL.md "Route Learning to Definition."** Both interactive and headless modes default to a direct bullet-append edit on the target skill/agent/AGENTS.md file. Issue filing is retained only for cross-skill / contested / AGENTS.md-semantic changes.
3. **Add `/ship` Phase 5.5 Review-Findings Exit Gate.** Detects open review-origin issues that cross-reference the current PR via `(Ref|Closes|Fixes) #<N>\b` in body text (regex, NOT `gh search`'s loose substring matcher — see Correctness section). Filters out `deferred-scope-out` and `synthetic-test` labels. Single abort path (no interactive menu).
4. **Add one AGENTS.md rule** covering all three surfaces.
5. **Create the `deferred-scope-out` GitHub label** (one-time).

**Deferred to follow-up issues (explicitly OUT OF SCOPE for this PR):**

- **Follow-up A — Backlog triage.** Classify the 53 existing review-origin issues (2026-04-13 → 2026-04-15) as fix-now / valid-defer / invalid. Close invalid, label valid-defer, group fix-now into batched PRs. Tracked as a separate issue against milestone `Post-MVP / Later`.
- **Follow-up B — Regression telemetry.** Per-PR `review_issues_per_merged_pr` metric + email alert. Only build this if the prevention mechanism proves insufficient — the gate is a hard merge-block, so the ratio should stay at 0 by construction. Tracked as a separate issue against `Post-MVP / Later` with re-evaluation criteria "build if a second spike occurs after 2 weeks of fix-inline shipping."

## Technical Approach

### Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│  /review (skill)                                                 │
│    Section 5 Findings Synthesis:                                 │
│      default → fix inline on PR branch (commit + push)           │
│      exception → gh issue create + deferred-scope-out label      │
│                  + body must contain ## Scope-Out Justification  │
└────────────────────────────────┬─────────────────────────────────┘
                                 │ emits zero or N open issues
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│  /ship Phase 5.5                                                 │
│    (a) Code Review Completion Gate      — existing               │
│    (b) Review-Findings Exit Gate        — NEW                    │
│        queries open issues for review-origin title prefix AND    │
│        body contains (Ref|Closes|Fixes) #<PR>\b AND              │
│        no deferred-scope-out, synthetic-test labels.             │
│        If ≥1: hard block with actionable error.                  │
│    (c) Domain Review gates              — existing               │
│    (d) Retroactive Gate Application     — existing               │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  compound                                                        │
│    Route Learning to Definition (interactive + headless):        │
│      default → direct bullet-append edit, commit on current br.  │
│      exception → gh issue create + deferred-scope-out label      │
└──────────────────────────────────────────────────────────────────┘
```

### Implementation Phases

#### Phase 1: Foundation (Label + AGENTS.md Rule)

**Purpose:** stand up the two primitives Phase 2 references.

**1.1 Create `deferred-scope-out` GitHub label.** One-time command:

```bash
gh label create deferred-scope-out \
  --description "Review-origin issue that meets a scope-out criterion — does not block ship Phase 5.5" \
  --color ededed || true
```

Idempotent with `|| true` so re-runs don't fail. Execute once during implementation; not committed to the repo (live GitHub state).

**1.2 Append one AGENTS.md rule** under `## Review & Feedback`:

```markdown
- Review findings default to fix-inline on the PR branch for all severities (P1/P2/P3) [id: rf-review-finding-default-fix-inline] [skill-enforced: ship Phase 5.5 Review-Findings Exit Gate]. Filing a GitHub issue is allowed only when one of four criteria applies — cross-cutting-refactor, contested-design, architectural-pivot, pre-existing-unrelated (defined inline in `plugins/soleur/skills/review/SKILL.md` Section 5 and `plugins/soleur/skills/compound/SKILL.md` Route Learning to Definition). Scope-out issues MUST carry the `deferred-scope-out` label AND a `## Scope-Out Justification` section in the body. `/ship` Phase 5.5 blocks merge on any open review-origin issue cross-referencing the PR without `deferred-scope-out`. Compound's route-to-definition follows the same default (direct edit) + exception (scope-out) pattern in both interactive and headless modes. **Why:** In #2374, 53 review-origin issues were filed in 3 days because the three skills (review, compound, ship) each defaulted to "file as issue" rather than "fix inline." Findings were legitimate; disposition was wrong.
```

**Success criteria:**

1. `gh label list --json name --jq '.[] | select(.name == "deferred-scope-out") | .name'` returns `deferred-scope-out`.
2. `grep -c '\[id: rf-review-finding-default-fix-inline\]' AGENTS.md` returns 1.
3. `python3 scripts/lint-rule-ids.py` exits 0.

#### Phase 2: Behavior Edits (Three SKILL.md Surfaces)

**2.1 `/review` SKILL.md edit** — `plugins/soleur/skills/review/SKILL.md:287-314`.

**Replace the `<critical_requirement>` block at line 289** with:

```text
<critical_requirement>
Each finding's default action is to FIX IT INLINE on the PR branch: make the edit,
commit with a message `review: <summary> (P<N>)`, and push. Apply to P1, P2, P3
equally.

Filing a GitHub issue instead of fixing is allowed ONLY when the finding meets
one of these four scope-out criteria:

  1. **cross-cutting-refactor** — fix requires touching files materially
     unrelated to the PR's core change.
  2. **contested-design** — multiple valid fix approaches; choice requires design
     input that doesn't belong in this PR's scope.
  3. **architectural-pivot** — fix would change a pattern used across the
     codebase and deserves its own planning cycle.
  4. **pre-existing-unrelated** — finding existed on `main` before this PR and
     is not exacerbated by the PR's changes. (Does NOT block merge.)

When filing:

  - The issue body MUST contain a `## Scope-Out Justification` section naming the
    specific criterion and a 1-3 sentence rationale.
  - The issue MUST be created with `--label deferred-scope-out` and `--milestone`
    (per guardrails:require-milestone).
  - The issue title MUST use a review-origin prefix (`review:`, `Code review #`,
    `Refactor:`, `arch:`, `compound:`, `follow-through:`).

Everything else (magic numbers, duplicated helpers, small refactors, missing
tests for PR-introduced code, polish, naming, a11y on PR-introduced surfaces,
performance issues introduced by the PR) MUST be fixed inline.

Filing without scope-out justification will be caught by /ship Phase 5.5 Review-
Findings Exit Gate and BLOCK merge. See rule rf-review-finding-default-fix-inline.
</critical_requirement>
```

**Update line 312** (`<critical_instruction>`): change from "Create GitHub issues for ALL findings immediately" to "Fix inline or, where a scope-out criterion applies, create a `deferred-scope-out` issue. Do NOT present findings for per-item user approval."

**Update Step 3 Summary Report headings (lines 332-347):** split `### Created GitHub Issues` into two sub-sections — `**Fixed Inline:**` (commit SHAs per finding) and `**Filed as Deferred Scope-Out:**` (issue numbers + criterion + rationale).

**Update coupling note at line 308:** append: "Phase 5.5 Review-Findings Exit Gate (new in #2374) additionally detects open review-origin issues cross-referencing the PR by body regex `(Ref|Closes|Fixes) #<N>\b` without `deferred-scope-out` label; filing without scope-out justification will block merge."

**2.2 `/compound` SKILL.md edit** — `plugins/soleur/skills/compound/SKILL.md:255-268`.

**Replace step 3 (line 265)** with:

```text
3. **Default action (interactive and headless):** Apply the edit directly to the
   target skill/agent/AGENTS.md file. Commit with `skill: route <basename>
   <summary>`. The edit surface is BOUNDED: a single bullet-point append, a
   single Sharp Edges entry, or a ≤3-line instruction clarification. Edits that
   change existing bullet semantics, span multiple files, or modify AGENTS.md
   rule wording are OUT OF SCOPE for direct edit — file an issue instead.

4. **File-issue exception:** File a GitHub issue when the edit meets one of:
   cross-skill (touches 2+ skill/agent files), contested-design (competing
   valid approaches), agents-md-semantic-change (modifies existing rule text).
   Title: `compound: route-to-definition proposal for <target-basename>`.
   Body: proposed edit text + target path + source learning path + `## Scope-Out
   Justification` naming the criterion. Flags: `--label deferred-scope-out
   --milestone "Post-MVP / Later"`.

5. **Interactive confirmation for direct edits:** If HEADLESS_MODE is unset,
   show the proposed diff and ask Accept/Skip/Edit-then-Accept before committing.
   In headless mode, apply directly without prompting — the bounded surface
   (single bullet append) is safe without per-edit approval.
```

**Keep the "Graceful degradation" line (270) unchanged.**

**2.3 `/ship` SKILL.md edit** — `plugins/soleur/skills/ship/SKILL.md:268-351`. Insert a new subsection between the existing `### Code Review Completion Gate (mandatory)` (line 270-282) and `### Pre-Ship Domain Review (conditional)` (line 284):

````markdown
### Review-Findings Exit Gate (mandatory)

Blocks merge when review findings from Phase 1.5 / Phase 5.5 Completion Gate
remain unresolved — neither fixed inline nor formally scoped out with a
`deferred-scope-out` label.

**Trigger:** Always runs after the Code Review Completion Gate passes.

**Detection:** Resolve the current PR number, then query for open, unresolved
review-origin issues that cross-reference this PR via body regex
`(Ref|Closes|Fixes) #<N>\b` — NOT `gh search`'s loose substring matcher
(which would match any body containing "<N>" as a substring, including
unrelated SHAs, timestamps, and inline numbers).

```bash
PR_NUMBER=$(gh pr view --json number --jq .number)
UNRESOLVED=$(gh issue list \
  --state open \
  --search "-label:deferred-scope-out -label:synthetic-test" \
  --json number,title,body \
  --jq '[.[]
           | select(.title | test("^(review:|Code review #|Refactor:|arch:|compound:|follow-through:)"; "i"))
           | select((.body // "") | test("(^|\\s)(Ref|Closes|Fixes) #'"$PR_NUMBER"'(\\s|$|[^0-9])"))
           | {number, title}]')
COUNT=$(echo "$UNRESOLVED" | jq 'length')
```

Notes:

- The regex anchors on keyword `Ref|Closes|Fixes` followed by `#<N>` followed
  by a non-digit or end-of-string — prevents `#23750` matching when
  `PR_NUMBER=2375`.
- `synthetic-test` label excluded so Phase 3 validation test issues
  self-exclude.
- Perf contract: under 5s on a repo with <1000 open issues. If the GitHub
  API returns 5xx, retry once with 2s backoff; on second failure, abort the
  gate with the API error surfaced — do NOT silent-pass.

**If COUNT == 0:** Pass silently.

**If COUNT > 0:** Abort with a structured error listing each unresolved issue
number + title. Same abort path in both headless and interactive modes (no
`--force` flag, no interactive remediation menu). Message:

```text
Error: N unresolved review-origin issues reference this PR.
Resolve each by:
  (a) Fixing inline on the branch and closing the issue, OR
  (b) Adding a ## Scope-Out Justification section to the issue body AND
      applying the deferred-scope-out label.

Issues:
  - #A: <title>
  - #B: <title>
```

**Why:** In #2374, 53 review-origin issues accumulated in 3 days because
findings were filed but never resolved before ship. This gate enforces the
fix-inline default at the merge boundary. See rule
`rf-review-finding-default-fix-inline`.
````

**Success criteria (Phase 2):**

1. `grep -c 'default action is to FIX IT INLINE' plugins/soleur/skills/review/SKILL.md` returns 1.
2. `grep -c 'Default action (interactive and headless): Apply the edit directly' plugins/soleur/skills/compound/SKILL.md` returns 1.
3. `grep -c '### Review-Findings Exit Gate (mandatory)' plugins/soleur/skills/ship/SKILL.md` returns 1.
4. `npx markdownlint-cli2 --fix` passes on all three files, re-read after fix (per `cq-always-run-npx-markdownlint-cli2-fix-on`).

#### Phase 3: Validation

**3.1 Gate detection test (on live repo with synthetic-test label).**

```bash
# Create a throwaway issue with the synthetic-test label so it self-excludes
gh issue create \
  --title "review: synthetic test for #2374 Phase 5.5 gate" \
  --body "Ref #2375" \
  --label synthetic-test \
  --milestone "Post-MVP / Later"
# Note the returned number as $SYN_ISSUE.

# Run the detection query WITHOUT the synthetic-test filter (should find it):
gh issue list --state open --search "-label:deferred-scope-out" \
  --json number,title,body \
  --jq '[.[]
           | select(.title | test("^(review:|Code review #|Refactor:|arch:|compound:|follow-through:)"; "i"))
           | select((.body // "") | test("(^|\\s)(Ref|Closes|Fixes) #2375(\\s|$|[^0-9])"))
           | {number, title}]' \
  | jq 'length'
# Expect: ≥1 (the synthetic issue is matched).

# Run the gate's actual query (with synthetic-test exclusion) — should NOT match:
gh issue list --state open --search "-label:deferred-scope-out -label:synthetic-test" \
  --json number,title,body \
  --jq '[.[]
           | select(.title | test("^(review:|Code review #|Refactor:|arch:|compound:|follow-through:)"; "i"))
           | select((.body // "") | test("(^|\\s)(Ref|Closes|Fixes) #2375(\\s|$|[^0-9])"))
           | {number, title}]' \
  | jq 'length'
# Expect: 0 (synthetic-test excluded).

# Now remove the synthetic-test label to prove the main detection fires:
gh issue edit $SYN_ISSUE --remove-label synthetic-test
# Re-run the gate query — Expect: 1.
# Now add the deferred-scope-out label:
gh issue edit $SYN_ISSUE --add-label deferred-scope-out
# Re-run the gate query — Expect: 0 (deferred-scope-out excluded).
# Close the synthetic issue:
gh issue close $SYN_ISSUE --comment "Closed after Phase 5.5 gate validation for #2374."
```

Capture the four expected-vs-actual counts in the PR description.

**3.2 Regex boundary test.** Confirm the regex `#${PR_NUMBER}(\s|$|[^0-9])` does not match `#${PR_NUMBER}X` where X is a digit. Create a second synthetic issue with body `Ref #23750` and run the detection for PR 2375 — expect 0 matches. Close after verification.

**3.3 Markdown + rule-ID lint.** `npx markdownlint-cli2 --fix` on all edited `.md` files (re-read after fix). `python3 scripts/lint-rule-ids.py` exits 0.

**3.4 Self-dogfood.** Run `/review` on this PR itself. The review skill should produce findings that either (a) get fixed inline on this branch or (b) are filed with `deferred-scope-out` + `## Scope-Out Justification`. Phase 5.5 gate must then pass before ship.

**Deliverables:** test evidence in PR description (command output of four gate-query runs + regex boundary test). Self-dogfood review evidence.

**Success criteria:** all four sub-steps pass before ship.

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|--------------|
| Cap issues filed per review (max 3/PR) | Treats symptom. Findings 4+ are still unresolved. |
| Human-triage gate: agents file, human approves fix vs file | Violates `hr-exhaust-all-automated-options-before` — shifts work to human. |
| Move review earlier (into `/work` Phase 3) | Excluded per brainstorm NG1. Revisit if Phase 5.5 proves too late. |
| Remove `<critical_requirement>` entirely | Default persists via training. Must actively rewrite. |
| New `review-fix-inline` skill | Violates NG3. |
| Bundle backlog triage into THIS PR | **Rejected post plan-review.** Prevention and cleanup are independent. Bundling triples PR review surface (53-row table + bulk closures + batched fix-now PRs). Deferred to follow-up issue per `wg-when-deferring-a-capability-create-a`. |
| Bundle regression telemetry into THIS PR | **Rejected post plan-review.** Premature — the gate is a hard block, so the ratio stays at 0 by construction. Build alarm only if gate fails. Deferred with re-evaluation criteria. |
| Three AGENTS.md rules instead of one | **Rejected post plan-review.** Same principle, three enforcement points. One rule cross-referenced from each skill. |
| Separate `review-scope-out-criteria.md` reference file | **Rejected post plan-review.** Four criteria + body template = ~15 lines. Inline in the SKILL.md. |
| Interactive 3-option menu in Phase 5.5 gate | **Rejected post plan-review.** Single abort message states remediation; menu adds branches + failure modes. |
| Use `gh search "in:title,body #${PR}"` for Phase 5.5 detection | **Rejected.** `#${PR}` tokenizes as substring — matches SHAs, timestamps, unrelated numbers. Post-hoc `jq` regex filter is correct. |

## Acceptance Criteria

### Functional Requirements

- [ ] **AC1 (spec FR1, FR2, FR5).** `/review` SKILL.md Section 5 rewritten: default fix-inline; four scope-out criteria inlined in the SKILL.md (not a separate reference file); filing requires `deferred-scope-out` label and `## Scope-Out Justification` section.
- [ ] **AC2 (spec FR3, FR5, TR6).** `/ship` SKILL.md Phase 5.5 has a new `### Review-Findings Exit Gate (mandatory)` subsection; detection uses body regex `(Ref|Closes|Fixes) #<N>\b` (NOT `gh search` substring match); excludes `deferred-scope-out` + `synthetic-test` labels; single abort path; perf <5s on <1000-issue repo.
- [ ] **AC3 (spec FR4).** `/compound` SKILL.md "Route Learning to Definition" default action in BOTH interactive and headless modes is direct bullet-append edit on the target file. Issue filing retained only for cross-skill / contested / AGENTS.md-semantic changes with same label and justification requirements.
- [ ] **AC4.** One new AGENTS.md rule `[id: rf-review-finding-default-fix-inline]` in `## Review & Feedback` section covers all three surfaces. `python3 scripts/lint-rule-ids.py` exits 0.
- [ ] **AC5.** `deferred-scope-out` GitHub label created in live repo.
- [ ] **AC6 (deferral tracking per `wg-when-deferring-a-capability-create-a`).** Two follow-up GitHub issues created, each milestoned to `Post-MVP / Later`:
  - **Follow-up A:** "Backlog triage: classify 53 review-origin issues (2026-04-13→2026-04-15) against `rf-review-finding-default-fix-inline`." Re-evaluation criteria: once this PR ships, run the triage within 7 days.
  - **Follow-up B:** "Regression telemetry: per-PR `review_issues_per_merged_pr` metric + email alert." Re-evaluation criteria: build only if a second spike (>3 review-origin issues on any single PR) occurs in the 2 weeks after this PR merges.

### Non-Functional Requirements

- [ ] **NFR1 (TR6).** Phase 5.5 gate query returns in <5s. Verified in Phase 3.1.
- [ ] **NFR2 (TR4).** Rule ID immutable, format + section prefix valid. `scripts/lint-rule-ids.py` passes.
- [ ] **NFR3 (TR5).** `npx markdownlint-cli2 --fix` passes on all edited `.md` files.

### Quality Gates

- Phase 3 validation evidence captured in PR description.
- Self-dogfood `/review` run on this PR exercises the new rule.
- `/soleur:qa` not required (no UI, infra only).

## Test Scenarios

### Acceptance Tests

- **TS1 (AC2, detection on):** Given a synthetic issue with title `review: synthetic test (#2375)` and body `Ref #2375` and no exclusion labels, when the Phase 5.5 query runs with `PR_NUMBER=2375`, then COUNT == 1.
- **TS2 (AC2, deferred-scope-out excludes):** After adding `deferred-scope-out` to the synthetic issue, COUNT == 0.
- **TS3 (AC2, synthetic-test excludes):** Re-add `synthetic-test` label (remove `deferred-scope-out`), COUNT == 0.
- **TS4 (AC2, regex boundary):** Given a second synthetic issue with body `Ref #23750`, when the query runs for PR 2375, then that issue is NOT matched (regex requires non-digit or boundary after `<N>`).
- **TS5 (AC2, non-cross-reference body):** Given a synthetic issue with body "this discusses PR 2375 but doesn't reference it via Ref/Closes/Fixes," the issue is NOT matched (regex requires one of the three keywords).
- **TS6 (AC1):** Given `/review` SKILL.md Section 5, the default-action text "FIX IT INLINE" appears before any `gh issue create` instruction.
- **TS7 (AC3):** Given compound in headless mode detects a bullet-append proposal, the run commits the edit directly to the current branch. `git log` shows a commit with message `skill: route ...`. No `gh issue create` invocation.
- **TS8 (AC4):** `grep '\[id: rf-review-finding-default-fix-inline\]' AGENTS.md` returns exactly one match.
- **TS9 (AC6):** Two follow-up issues exist, both milestoned `Post-MVP / Later`, each with re-evaluation criteria in the body.

### Regression Tests

- **RT1:** Existing Phase 1.5 / Phase 5.5 Code Review Completion Gate still works. Verify: run `/ship` on a branch with no review evidence — it still aborts with "no review evidence found."
- **RT2:** Existing `code-review` label detection on Phase 1.5 still works. Verify: create a `code-review`-labeled issue with body `PR #2375`, run Phase 1.5 — it detects evidence.
- **RT3:** Existing compound-capture behavior (separate from route-to-definition) unchanged.

### Edge Cases

- **EC1:** Zero open issues reference the PR → gate passes (COUNT == 0).
- **EC2:** Issue body mentions `#2375` without `Ref|Closes|Fixes` keyword → regex does not match (TS5).
- **EC3:** `#23750` body text when `PR_NUMBER=2375` → boundary regex does not match (TS4).
- **EC4:** GitHub API 5xx on the `gh issue list` call → retry once with 2s backoff; second failure aborts with error (no silent pass).
- **EC5:** Issue title `review(ci):` (parenthesized variant) → NOT caught by regex `^(review:|...)`. Known limitation; accepted because false negatives (missed detection) are safer than false positives (blocking unrelated work). If observed in practice, extend regex in a follow-up.

## Success Metrics

Per spec SC1-SC6 (measured post-merge):

- **SC1:** Weekly review-origin issue count ≤8 within 2 weeks (down from ~25/week).
- **SC2:** Average review-origin issues per merged PR ≤1.
- **SC3:** Phase 5.5 Review-Findings Exit Gate catches ≥1 ship attempt with unresolved findings in first 2 weeks.
- **SC6:** Merged-PRs-per-week doesn't drop by more than 20% in the week following rollout.

SC4 (telemetry) out of scope — tracked in Follow-up B. SC5 (backlog triage outcome) out of scope — tracked in Follow-up A.

Measurement: manual `gh issue list` counts at week +1 and week +2 post-merge, compared against the pre-merge baseline of 53.

## Dependencies & Risks

### Dependencies

- `gh` CLI — already required across the repo.
- `jq` — already required.
- No new GitHub secrets. No new workflow permissions.

### Risks

- **R1 — Review agents may not have commit-and-push capability from subagent context.** The `/review` skill spawns reviewer agents via the Task tool. Subagents can invoke Bash, but working directory and branch context must match the PR. **Mitigation:** validated during Phase 2.1 implementation — if a subagent cannot push, the orchestrating skill fetches findings and applies fixes serially in the primary thread, documented as the canonical path. If serial fix is the only workable mode, update Section 5 to reflect it explicitly; the *default* ("fix inline") is what matters, not *who* does the fixing.
- **R2 — Phase 5.5 gate regex misses parenthesized title variants like `review(ci):`.** EC5 documents this. Extend regex only if observed.
- **R3 — False positives: unrelated issue with body `Ref #2375` for a different reason.** Very low probability — `Ref #<N>` is a specific cross-reference convention. If it happens, the author adds `deferred-scope-out` to exclude.
- **R4 — Synthetic test pollution on live repo.** Mitigated by the `synthetic-test` label + `gate excludes synthetic-test`. Phase 3.1 closes the test issue after validation.
- **R5 — Compound bounded-edit surface is prose, not enforced.** A compound run could still write multi-line edits to multiple files. **Mitigation:** bounded-surface claim is descriptive (matches existing compound-capture behavior), not prescriptive enforcement. Plan review + commit diff inspection catch violations. Skip a runtime linter for now (YAGNI).
- **R6 — Coupling with existing Phase 1.5 / 5.5 / pre-merge hook `code-review` label detection.** The new gate is a DIFFERENT concern (resolution status, not run status). Both coexist. The coupling note at `review/SKILL.md:308` is updated to describe both. Explicit ordering in `ship/SKILL.md`: Completion Gate (existing) → Review-Findings Exit Gate (new).
- **R7 — Deferring backlog triage leaves 53 open issues.** The new gate looks at issues referencing the CURRENT PR, not the reverse — so backlog issues referencing OLD PRs don't block NEW PRs. The triage follow-up (Follow-up A) is still sequenced within 7 days post-merge to keep the backlog from growing.

## References & Research

### Internal References

- `plugins/soleur/skills/review/SKILL.md:287-358` — current Section 5 Findings Synthesis.
- `plugins/soleur/skills/ship/SKILL.md:268-351` — current Phase 5.5 (Trigger/Detection/If triggered/Why pattern).
- `plugins/soleur/skills/compound/SKILL.md:255-270` — current Route Learning to Definition.
- `AGENTS.md` `## Review & Feedback` section — new rule appended.
- `scripts/lint-rule-ids.py` — immutable-ID + prefix lint.

### Institutional Learnings Applied

- `knowledge-base/project/learnings/2026-04-02-ship-review-evidence-coupling.md` — multi-signal detection lesson; regex + label filter instead of single hardcoded path.
- `knowledge-base/project/learnings/2026-03-29-workflow-gate-multi-signal-detection.md` — detection kept flat (regex + label filter).
- `knowledge-base/project/learnings/2026-03-27-skill-defense-in-depth-gate-pattern.md` — Phase N.5 gate pattern followed (always runs, detect, branch headless/interactive, `**Why:**` block).
- `knowledge-base/project/learnings/2026-03-30-compound-headless-issue-filing-over-auto-accept.md` — this plan reverses that earlier decision; justified by bounded-edit surface (single bullet append).
- `knowledge-base/project/learnings/2026-04-15-ux-audit-scope-cutting-and-review-hardening.md` — corpus claim verified at plan-freeze.

### Related Work

- PR #2375 (this PR). Issue #2374. Brainstorm + spec at paths in frontmatter.

## Domain Review

**Domains relevant:** none

Internal engineering-workflow hardening: three SKILL.md instruction edits, one AGENTS.md rule, one label. No user-facing surface (no new pages, no new components, no customer-affecting behavior). Per the Product/UX Gate contract: "A plan that *discusses* UI concepts but *implements* orchestration changes (e.g., adding a UX gate to a skill) is NONE." CPO/CMO assessment questions (end-user experience, content/distribution opportunities) do not fire. CTO-equivalent concerns (architecture, CI/workflow correctness) are addressed in Phase 3 validation and the Risks section. The brainstorm document contained no `## Domain Assessments` section, confirming the engineering scope.
