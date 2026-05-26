---
title: "fix: preflight `.git` write + work TDD-gate exit clause (#3532, #3533)"
date: 2026-05-11
type: bug
issues: [3532, 3533]
related_pr: 3512
related_learning: knowledge-base/project/learnings/2026-05-10-review-skill-git-tmp-paths-fail-in-worktrees.md
branch: feat-one-shot-fix-preflight-work-skills-3532-3533
worktree: .worktrees/feat-one-shot-fix-preflight-work-skills-3532-3533
requires_cpo_signoff: false
semver_label: semver:patch
---

# Plan: Fix preflight `.git` write + work TDD-gate exit clause (#3532, #3533)

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Research Reconciliation (verified counts), Acceptance Criteria (added strict-mode guard for grep AC), Implementation Phases (added placement evidence for #3533), Sharp Edges (added step-renumber audit guidance).
**Verifications run:**

- `grep -c '\.git/preflight-diff-files\.txt' plugins/soleur/skills/preflight/SKILL.md` → **12** (4 in code-shaped lines, 8 in prose-shaped lines — issue body's "8+4" was directionally right but inverted on which class is larger; the substitution is class-based, so the count drift does not affect remediation).
- `grep -nE '^### Phase [0-9]+' plugins/soleur/skills/work/SKILL.md` → Phase 2 ends at line 386 (Phase 2.5). Current step 8 (GDPR gate) at line 378. New step 9 placement confirmed unambiguous.
- `grep 'REVIEW_TMP="$(git rev-parse --git-dir)"' plugins/soleur/skills/review/SKILL.md` → confirms PR #3512 fix pattern is in-tree at line 70 (precedent verbatim).
- `gh pr view 3512 --json state` → MERGED.
- `gh issue view 3532/3533 --json state` → both OPEN.
- AGENTS.md rule-ID citation audit: all 6 cited IDs (`hr-when-a-command-exits-non-zero-or-prints`, `wg-use-closes-n-in-pr-body-not-title-to`, `wg-when-deferring-a-capability-create-a`, `hr-when-in-a-worktree-never-read-from-bare`, `cq-write-failing-tests-before`, `rf-review-finding-default-fix-inline`) ACTIVE in AGENTS.md, none on the retired registry (`scripts/retired-rule-ids.txt`).
- `gh label list` for all 5 prescribed labels (`bug`, `type/bug`, `domain/engineering`, `priority/p2-medium`, `semver:patch`) → all exist verbatim.
- `head -5 scripts/test-all.sh` → uses `set -euo pipefail`; deepen-plan AC #2 (strict-mode operator behavior) does not apply here since the new clause only invokes the script, doesn't parse its output.

### Key Improvements

1. **Refined #3532 substitution count**: 12 references (not 12 = 8+4 as issue body implied; actual split is 4 code-shaped + 8 prose-shaped). Plan body already uses class-based AC; no remediation count change needed.
2. **Locked #3533 placement**: new step 9 at line 386 (between current step 8 GDPR gate at line 378 and Phase 2.5 at line 386). Plan body now cites exact line numbers as anchors.
3. **Added rule-ID-citation audit evidence**: every cited AGENTS.md ID verified ACTIVE, none retired — closes the deepen-plan AC for fabricated/retired rule IDs.
4. **Added label-verify evidence**: every prescribed label exists; AC matches the AGENTS.md `cq-gh-issue-label-verify-name` retirement note's intent.
5. **Reaffirmed scope discipline**: deepen-plan does NOT widen scope to "audit all skills for `.git/<file>` literals" (the issue body suggested it; plan defers to a follow-up issue). This keeps the bundled PR mechanical and reviewable.

### New Considerations Discovered

- The issue body for #3532 claims "8 code-block + 4 prose"; grep shows 4 code-shaped + 8 prose-shaped. This is a directional miscount in the issue body, not the plan. Implementer must NOT gate on a specific count — the class-based AC (`zero matches for old literal`) is the load-bearing assertion. Plan body's Risks section already notes this.
- Step-9 placement creates a new step number adjacent to step 8. Future audit: `rg 'step [0-9]+' plugins/soleur/skills/work/SKILL.md` shows zero downstream references to step numbers by index, so renumbering risk is minimal. Plan body's Sharp Edges already calls this out.
- The `scripts/test-all.sh` runner uses `set -euo pipefail` and is described in its own header as "Sequential test runner that isolates test suites to avoid Bun's FPE crash when running all tests via recursive directory discovery." The new step 9 should NOT prescribe parallel discovery — point to the existing script verbatim, which already handles the isolation concern.
- No `## Open Code-Review Overlap` matches were found at plan time (run-time check deferred to work phase per plan body); current open code-review issues do not name either edited file.

## Overview

Two bounded SKILL.md-only edits in the same plugin tree, same defect class:
a skill's internal procedure works in the common case and silently breaks under
a less-common context (worktrees / orphan test files). Single bundled PR — both
changes are mechanical, well-scoped, and share root cause class with PR #3512
(which already fixed the sibling pattern in the review skill).

- **#3532** — `plugins/soleur/skills/preflight/SKILL.md` writes its diff cache
  to `.git/preflight-diff-files.txt`. In a worktree, `.git` is a **file**
  (gitdir pointer), not a directory. Every redirect fails with
  `Not a directory (os error 20)`; path-gated checks silently fall back to
  inline `git diff` and the "single diff scan, reuse everywhere" design intent
  is lost. Mirror the PR #3512 fix verbatim: use
  `PREFLIGHT_TMP="$(git rev-parse --git-dir)"` and replace every literal
  `.git/preflight-diff-files.txt` with `"$PREFLIGHT_TMP/preflight-diff-files.txt"`.

- **#3533** — `plugins/soleur/skills/work/SKILL.md` Phase 2 TDD Gate accepts
  "tests pass" based on touched-file tests only. `scripts/test-all.sh`
  discovers orphan test suites (e.g., `tests/scripts/test-rule-metrics-aggregate.sh`
  alongside `scripts/rule-metrics-aggregate.test.sh`) that the touched-file set
  never sees. Result: PR #3512 shipped a tightened `valid_stream` predicate
  with an orphan suite's fixture still emitting pre-schema lines, surfaced
  only post-merge-queue when CI ran the full suite. Add a single Phase 2 exit
  clause requiring `bash scripts/test-all.sh` before Phase 3 — symmetric to
  the ship Phase 5.5 Review-Findings Exit Gate.

Both fixes are direct edits to operator-facing SKILL.md files. No behavior
change to any production code path, no migrations, no schema, no API surface.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| #3532: "8 code-block + 4 prose references" | Verified at deepen-time: `grep -c '\.git/preflight-diff-files\.txt'` returns **12**; refined split via `grep -nE '^[[:space:]]*(git diff\|grep\|cat) .* \.git/preflight-diff-files\.txt'` returns **4 code-shaped lines** (32, 76, 396, 524 — line 133 is a `cat` in a fenced block too, total ≥4) and **8 prose-shaped lines** (35 twice, 39, 73, 280, 507, 601, etc.). Total still 12 references — the issue body inverted which class is larger but the total is right. | Use `replace_all` semantics on the substring `.git/preflight-diff-files.txt` → `"$PREFLIGHT_TMP/preflight-diff-files.txt"`. The exact count is not load-bearing — the substitution is class-based. AC verifies post-edit grep returns zero matches for the old literal. |
| #3533: "tests/scripts/test-rule-metrics-aggregate.sh" exists as orphan | Verified: `scripts/test-all.sh` does exist (3150 bytes, executable). Per #3512 commit `c99ca728`, the orphan failure pattern is real. | Add a single exit-gate clause to Phase 2 step 8 (end-of-Phase-2 boundary already used by GDPR gate) OR to the per-task TDD Gate body. Plan body specifies placement below. |
| PR #3512 fix pattern in review SKILL.md | Verified: review SKILL.md lines 67-76 use `REVIEW_TMP="$(git rev-parse --git-dir)"` and `"$REVIEW_TMP/review-*.txt"`. Includes inline prose explaining why. | Mirror verbatim with `PREFLIGHT_TMP` naming. Add a one-sentence explanatory prose insertion near the first use, similar to review SKILL.md's lines 67-69. |

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing impact. Both
edits are internal skill procedure changes; the worst case is the agent
continues to misbehave the way it does today (preflight cache silently
disabled in worktrees, work-phase tests passing while CI fails post-merge).
Neither failure mode is amplified by this change.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A —
no credentials, no PII surfaces, no auth flow, no payment surface, no data
schema. Operator-facing skill prose only.

**Brand-survival threshold:** none.

**Sensitive-path scope-out (preflight Check 6 compliance):**
threshold: none, reason: SKILL.md operator-facing documentation only; no
production code path, no credentials, no auth/data/payment/user-resource
surface touched.

## Open Code-Review Overlap

Run-time check at work phase:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "plugins/soleur/skills/preflight/SKILL.md" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
jq -r --arg path "plugins/soleur/skills/work/SKILL.md" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

Expected: zero matches on either file (both bugs are framed as fresh fixes;
neither was logged as a code-review scope-out). If any match surfaces at
work time, fold in or scope-out per `plugins/soleur/skills/review/SKILL.md` §5.

## Files to Edit

- `plugins/soleur/skills/preflight/SKILL.md` — substitute all 12 references
  to `.git/preflight-diff-files.txt`; add a 2-3 line prose insertion near
  the first use explaining the resolver. Style: mirror review/SKILL.md
  lines 67-69.

- `plugins/soleur/skills/work/SKILL.md` — add a single Phase 2 exit-gate
  clause. Placement: as step 8.5 between the GDPR gate (step 8, line 378)
  and Phase 2.5 (line 386), OR as a new bullet inside step 8 ("GDPR /
  Compliance Gate" renamed to "Phase 2 Exit Gates" with two sub-bullets).
  Implementer's choice — both placements are symmetric to the ship Phase
  5.5 Review-Findings Exit Gate and either is correct.

## Files to Create

None.

## Implementation Phases

### Phase 1: Mechanical substitution in preflight SKILL.md (#3532)

1. RED: write a sanity test that `grep -c '\.git/preflight-diff-files\.txt'
   plugins/soleur/skills/preflight/SKILL.md` returns 0 after edit (assert via
   a shell test under `plugins/soleur/skills/preflight/test/` if a convention
   exists; otherwise inline `bash` check in Acceptance Criteria). Verify RED
   by running grep on the unedited file and confirming it returns ≥10 matches.
2. GREEN: edit `plugins/soleur/skills/preflight/SKILL.md`:
   - Insert resolver block near the first use (line 32 area):

     ```bash
     PREFLIGHT_TMP="$(git rev-parse --git-dir)"
     git diff --name-only origin/main...HEAD > "$PREFLIGHT_TMP/preflight-diff-files.txt"
     ```

     with a 1-sentence prose preamble: "Use `git rev-parse --git-dir` to
     resolve a writable tmp path that works in both regular checkouts and
     worktrees: in a worktree `.git` is a file (gitdir pointer), not a
     directory, so `> .git/preflight-diff-files.txt` fails with
     `Not a directory (os error 20)`."
   - Substitute every other occurrence of the literal substring
     `.git/preflight-diff-files.txt` with `"$PREFLIGHT_TMP/preflight-diff-files.txt"`
     (use `Edit` tool with `replace_all: true` for safety; verify via grep
     count goes from 12 → 0 post-edit, but **0 → 0 of the OLD literal**:
     remaining matches will use the new path under `$PREFLIGHT_TMP/`).
3. REFACTOR: re-run the sanity grep, confirm zero hits on
   `\.git/preflight-diff-files\.txt`. Also confirm
   `grep -c '\$PREFLIGHT_TMP/preflight-diff-files\.txt'` returns ≥12
   (substitution complete).

### Phase 2: Add Phase 2 exit-gate clause to work SKILL.md (#3533)

1. RED: write a sanity test that `grep -F 'bash scripts/test-all.sh'
   plugins/soleur/skills/work/SKILL.md` returns ≥1 match in Phase 2 context.
   Verify RED by running the grep on the unedited file — currently 0 matches
   for `test-all.sh` in Phase 2 (it appears only in Phase 3 / ship references).
2. GREEN: edit `plugins/soleur/skills/work/SKILL.md` Phase 2. Recommended
   placement — insert a new step 9 immediately after step 8 (GDPR /
   Compliance Gate) and before Phase 2.5:

   ```markdown
   9. **Full-Suite Exit Gate (single pass, end of Phase 2)**

      [skill-enforced: work Phase 2 exit]

      Before entering Phase 3, run `bash scripts/test-all.sh` once.
      Touched-file tests are the inner loop; `test-all.sh` is the exit
      gate — it discovers orphan test suites (sibling files covering the
      same script, e.g., `tests/scripts/test-rule-metrics-aggregate.sh`
      alongside `scripts/rule-metrics-aggregate.test.sh`) that the
      touched-file set never sees. Symmetric to the ship Phase 5.5
      Review-Findings Exit Gate; catches the gap that PR #3512 surfaced
      post-merge-queue. **Why:** see issue #3533.
   ```

   Style note: this is a ≤3-line clarification expanded with the rationale
   prose the issue body requested. Treat as a single Sharp Edges-style
   bullet under the TDD Gate if step-9 placement is rejected by review.
3. REFACTOR: re-run the sanity grep. Confirm a `## Phase 3` boundary still
   exists immediately after the new step. Confirm GDPR gate (step 8) and
   Phase 2.5 framing are untouched.

### Phase 3: Lint and commit

1. Run `bash scripts/test-all.sh` per the very rule the plan adds — dogfood.
2. Run lefthook precommit if configured (don't bypass: see AGENTS.md
   `hr-when-a-command-exits-non-zero-or-prints`).
3. Single commit, conventional subject:
   `fix(skills): preflight git-dir resolution + work test-all exit gate (#3532, #3533)`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **#3532 substitution complete:**
  `rg '\.git/preflight-diff-files\.txt' plugins/soleur/skills/preflight/SKILL.md`
  returns zero matches.
- [ ] **#3532 new path consistent:**
  `rg '\$PREFLIGHT_TMP/preflight-diff-files\.txt' plugins/soleur/skills/preflight/SKILL.md`
  returns ≥12 matches (one per pre-existing reference — verified count
  at deepen-time was 12) AND the resolver assignment
  `PREFLIGHT_TMP="\$\(git rev-parse --git-dir\)"` appears exactly once
  near the first use.
- [ ] **#3532 prose preamble present:** the explanatory sentence near the
  first use mentions both "worktree" and "`Not a directory`" (mirror review
  SKILL.md lines 67-69 style).
- [ ] **#3533 exit-gate clause present:**
  `rg 'bash scripts/test-all\.sh' plugins/soleur/skills/work/SKILL.md`
  returns ≥1 match inside Phase 2 (line range between line 148
  `### Phase 2: Execute` and line 425 `### Phase 3: Quality Check`).
- [ ] **#3533 clause references the rationale:** the new clause names "orphan
  test suites" OR cites PR #3512 OR cites issue #3533 — at least one of the
  three (for grep-discoverability by future planners).
- [ ] **No production-code drift:** `git diff main...HEAD --stat` shows only
  `plugins/soleur/skills/preflight/SKILL.md` and
  `plugins/soleur/skills/work/SKILL.md` modified — no other files.
- [ ] **Skill description budget unchanged:** `bun test plugins/soleur/test/components.test.ts`
  passes (this PR doesn't change any `description:` frontmatter; the test
  should be green pre- and post-edit).
- [ ] **PR body uses `Closes #3532` and `Closes #3533`** each on its own line
  (per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- [ ] None — both edits land effective at next `/soleur:preflight` and
  `/soleur:work` invocation. No external service config, no migration, no
  deploy.

## Test Scenarios

1. **Worktree preflight cache (manual sanity):** in a worktree, run the
   updated Phase 0 Step 0.1 block from preflight SKILL.md. Confirm
   `"$PREFLIGHT_TMP/preflight-diff-files.txt"` resolves to a path under
   `<bare>/worktrees/<name>/preflight-diff-files.txt` and the file is
   writable. (Already proven by the sibling PR #3512 `REVIEW_TMP` pattern;
   reuse the same evidence.)
2. **Regular checkout preflight cache (manual sanity):** in a normal
   non-worktree clone, confirm `"$PREFLIGHT_TMP/preflight-diff-files.txt"`
   resolves to `./.git/preflight-diff-files.txt` (i.e., the resolver is a
   no-op against the historical behavior). The fix is a strict superset of
   the prior path.
3. **Work TDD Gate exit clause discoverability:** `rg 'test-all\.sh'
   plugins/soleur/skills/work/SKILL.md | grep -E 'Phase 2|exit'` returns at
   least one match.

Both sanity checks above are reasoning-only — neither edit changes any
JS/TS code path or test runner. The mechanical substitutions and prose
insertions are correct by construction once the AC greps pass.

## Hypotheses

None — both bugs are reproducible and the remediation is mechanical. The
issue bodies cite exact root causes and exact fix patterns (PR #3512 for
#3532; symmetric exit-gate pattern from ship Phase 5.5 for #3533).

## Risks

- **Substitution miss in #3532:** if `replace_all` skips an occurrence (e.g.,
  a line wraps mid-substring), the operator sees a mixed state. Mitigation:
  AC grep on the old literal must return zero. Run the verification grep
  before commit, not just after.
- **Placement disagreement on #3533:** a reviewer may prefer the clause as a
  Sharp Edges bullet under the TDD Gate (step 2 sub-area, line 230-250)
  rather than as a new top-level step 9. Both placements are AC-compliant;
  reviewer picks. If step-9 placement is rejected, fold into the TDD Gate's
  Sharp Edges block as a 2-line bullet.
- **None of the broader sibling-skill audit:** the #3532 issue body
  suggests "scan all skills in `plugins/soleur/skills/**/SKILL.md` for
  `.git/<filename>` redirects/reads and patch them as a batch." This PR
  scopes to preflight only (the only skill the issue named explicitly).
  If review surfaces additional skills with the same defect, file a
  follow-up tracking issue rather than expanding scope here — keeps the
  bundled PR mechanical.

## Non-Goals

- Broader `plugins/soleur/skills/**/SKILL.md` audit for other `.git/<file>`
  literals. **Tracking:** file a follow-up issue at work time if any new
  sibling defect is surfaced. (Per AGENTS.md
  `wg-when-deferring-a-capability-create-a`.)
- Any change to the GDPR gate (step 8) — placement is adjacent only.
- Any change to the TDD Gate body or its `[skill-enforced:]` tag.
- Any production code change. This PR is SKILL.md-only.

## Domain Review

**Domains relevant:** Engineering (CTO — infrastructure/skill procedures).

This is an operator-facing skill bug fix bundle. The CTO assessment is
implicit (defect class is documentation-only; the fix is mechanical; no
architectural decision is being made). No other domain (CMO, CPO, CLO,
CFO, CRO, CCO, COO) has surface area in this change. Skill description
words are unchanged; budget gate (`bun test plugins/soleur/test/components.test.ts`)
is unaffected.

### Engineering (CTO)

**Status:** auto-accepted (mechanical fix, no architectural decision).
**Assessment:** Mirrors PR #3512 fix pattern verbatim. Skill-internal
procedure correction. No CTO escalation needed.

No Product/UX Gate (no user-facing surface). No GDPR gate (no regulated-data
surface).

## Sharp Edges

- The substitution in #3532 is class-based, not count-based. The issue body
  says "8 code-block + 4 prose"; the actual file has 12 references with a
  different code/prose split. Do not gate on the count — gate on the
  post-edit grep returning zero matches for the old literal.
- For #3533, the new exit-gate clause must reference at least one of:
  "orphan test suites", "PR #3512", or "issue #3533". This is the
  grep-discoverability anchor for future planners hitting the same gap.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan declares `threshold: none` with a
  sensitive-path scope-out reason — that satisfies the gate.
- The work SKILL.md edit adds a new step adjacent to step 8 (GDPR gate).
  Verify numbering remains monotonic post-edit (8 → 9 → "Phase 2.5"). If
  any downstream prose in the file references "step 8" or "step N" by
  number, audit those references too. (Spot check: `rg 'step [0-9]+'
  plugins/soleur/skills/work/SKILL.md` — current matches should not refer
  to step 9 anywhere yet.)

## Open Questions

None — both fixes are bounded, the precedent (PR #3512) is in-tree, and the
issue bodies are unambiguous.

## References

- Issue #3532 — preflight `.git/preflight-diff-files.txt` write fails in worktrees
- Issue #3533 — work TDD Gate should run `scripts/test-all.sh` before Phase 3
- PR #3512 — sibling fix (review skill `.git/review-*.txt` paths)
- Learning: `knowledge-base/project/learnings/2026-05-10-review-skill-git-tmp-paths-fail-in-worktrees.md`
- AGENTS.md `hr-when-in-a-worktree-never-read-from-bare` — adjacent (this learning addresses the **write** sibling)
- AGENTS.md `cq-write-failing-tests-before` — the TDD Gate this PR strengthens
- AGENTS.md `rf-review-finding-default-fix-inline` — the symmetric ship Phase 5.5 exit-gate pattern
