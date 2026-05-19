---
title: "Drain plan must re-validate each issue's body claims against current codebase state, not just trust the issue snapshot"
date: 2026-05-15
problem_type: workflow_gap
severity: medium
component: drain-labeled-backlog
tags: [drain, scope-out, plan-phase, issue-body-drift, multi-agent-review]
related_rules:
  - wg-plan-prescribed-skills-must-run-inline
synced_to: []
---

# Drain plan must re-validate each issue's body claims against current codebase state

## Problem

In PR #3802 (drain of `deferred-scope-out` cc-path / dispatcher cluster: #3243 + #3343 + #3344), the user asked to close all three issues in a single bundle PR following the #2486 pattern. The plan phase initially accepted that scope. Three independent triggers flipped the decision to **split #3243 out**:

1. **The issue's own AC was already partially shipped.** #3243's body said "One PR per extraction, `mirrorWithDebounce` first — smallest, most self-contained." That extraction had already landed in PRs #3608 + #3670 — `mirrorWithDebounce` now lives in `apps/web-platform/server/observability.ts` and `cc-dispatcher.ts:64` only imports it. Trusting the issue body would have set up a "close the smallest extraction" task that has nothing left to extract.
2. **`wc -l` of cc-dispatcher.ts is 1904, not the 937 the issue body claimed.** The file grew past the snapshot — current state, not historical state, governs scope.
3. **Coupling collision with the sibling drain target.** #3344 modifies `CC_PATH_DISALLOWED_TOOLS` at `cc-dispatcher.ts:668`. The remaining #3243 extraction candidates (`_ccBashGates` → `cc-bash-gates.ts`) would re-thread Bash review-gate registration through the same line range. Co-shipping would create a silent merge-time gap between the new module boundary and the new safe-bash routing.

Same class also surfaced spec drift on #3343: issue body claimed 4 escape sites, reality was **6 sites** across two files (issue body predated a file growth pass).

## Root Cause

Drain backlogs accumulate over weeks or months. Issue bodies snapshot the codebase at filing time and don't auto-refresh. By the time a drain runs, three things can have happened independently:

- The "minimum viable extraction" the issue named has already shipped in a different PR.
- File line counts / call-site counts have grown past the issue's snapshot.
- Sibling PRs have changed the coupling shape between issues in the bundle.

Trusting the issue body verbatim leads to:
- AC violations (closing an issue whose AC forbade what we just did).
- Wasted scope (claiming to extract X when X already lives elsewhere).
- Hidden coupling (two issues that LOOK independent because the codebase state at filing time made them independent — but no longer are).

## Solution

In the drain-labeled-backlog plan phase, for each issue in the candidate bundle, run a **state-revalidation triad** before locking the scope:

1. **Snapshot vs. current.** Re-run any quantitative claim the issue makes: `wc -l <file>` against line-count claims, `grep -c <pattern>` against site-count claims, `git log -p <file>` against "this file mixes N concerns" claims. If reality drifted, the plan tracks reality.
2. **AC vs. shipped state.** For each issue's `## Acceptance Criteria` (or equivalent), check whether any AC has already shipped in a different PR. Search recent merges: `gh issue view <N> --json closedByPullRequestsReferences` returns nothing useful for OPEN issues, so use `git log --oneline -- <named-file> | head -20` or `gh search prs "<keyword>" --state merged`.
3. **Coupling check.** If issue A's fix touches `<file>:<line>` AND issue B's fix touches the same line range, AND the issues address different concerns, surface the coupling as a plan-phase decision (`split bundle vs. co-ship with explicit coordination`). Do NOT defer to "review will catch it" — bundle PRs have enough scope that coupling collisions sneak through.

The `/soleur:drain-labeled-backlog` skill already supports operator sub-selection (see its `Sharp Edges` section on PR #2499 sub-cluster selection). This learning sharpens that into a **mandatory plan-phase triad** rather than an operator-judgment-call.

Captured the cascade output in the PR body's "Research Reconciliation — Spec vs. Codebase" section so reviewers see the drift table at-a-glance.

## Multi-agent review on the resulting PR

Once the plan locked the split, /soleur:review on PR #3802 surfaced one cross-cutting P1/P2: **four agents independently flagged the same 6-site sanitizer-pipeline duplication** (code-simplicity reviewer P1, pattern-recognition P2, code-quality F1 MEDIUM, security F2 P3). The convergence was strong enough to flip the fix-inline-vs-scope-out decision in favor of fix-inline — even though the helper extraction crossed the cost-of-filing gate's ≤30-line / ≤2-file threshold (it needed 1 new module + 2 server-file edits + import lines = 3 files).

The signal: when ≥3 agents from orthogonal review specialties (semantic-quality + structural + security) independently surface the same finding without prompt-coordination, the cross-agent concur is itself strong enough to override the bookkeeping-cost gate. The fix landed as `review: extract sanitizeDocumentBody helper + trim redundant safe-bash test pinning (P1 + P2)` (commit `ffdeb953`).

## Prevention

- **Plan-phase triad** (above) becomes the default check for any `drain-labeled-backlog` invocation with ≥2 candidate issues.
- **Cross-agent concur ≥3 of orthogonal specialties = override the cost-of-filing gate**, default to fix-inline. Document the concur in the review-fix commit message so future reviews can recognize the pattern.
- When the plan splits an issue out of the original bundle, update the PR body's "Closes #N" lines BEFORE implementation starts. Forgetting this causes "auto-close on merge" to fire on issues that shouldn't close (see `wg-use-closes-n-in-pr-body-not-title-to`).

## Session Errors

Captured during PR #3802 implementation:

- **Bash CWD non-persistence across calls.** `cd apps/web-platform && bun run test:ci` failed when run as a follow-up Bash call (the prior `cd` reset). Recovery: chain `cd <abs-path> && <cmd>` in a single Bash call. **Prevention:** `wg-` rule already exists (`bash CWD does not persist`); applied with absolute paths throughout the rest of the session.
- **Write tool produced literal U+2028/U+2029 codepoints in regex character class when escape forms were intended.** Wrote `[\x00-\x1f\x7f  ]` but bytes ended up as `[\x00-\x1f\x7f<actual U+2028><actual U+2029>]`. Recovery: Python byte-level rewrite. **Prevention:** existing learning `2026-05-07-edit-tool-old-string-mangles-u2028-u2029-escapes.md` covers the Edit-side; this session confirms the Write-side has the same hazard. Both rule + helper sanitizer module (`apps/web-platform/server/sanitize-document.ts`) now centralize the escape form.
- **`tail -f log.txt` failed safe-bash allowlist assertion** because the allowlist only accepts `-n N` flag for tail. Recovery: changed test fixture to `tail -n 100 log.txt`. **Prevention:** read `safe-bash.ts:69` `SAFE_BASH_PATTERNS` directly before writing safe-bash test fixtures, don't assume.
- **`next lint` interactively prompts in non-TTY context** due to Next.js 16 deprecation. Pre-existing repo config issue — not introduced by this session. **Prevention:** repo-level work item to migrate to standalone ESLint CLI (not in scope of this PR).
- **Full vitest suite has pre-existing flaky component tests** (kb-chat-sidebar, chat-surface, error-states) — ECONNREFUSED on localhost:3000 under full-suite concurrency. Pass in isolation. **Prevention:** repo-level work item to fix component-test isolation; documented in PR #3802 body so reviewers don't mistake the flakes for PR-introduced regressions.

## References

- PR #3802 (this drain).
- PR #2486 (bundle-closure pattern reference).
- PR #3608, #3670 (mirrorWithDebounce extraction already shipped).
- Existing learning: `2026-05-07-edit-tool-old-string-mangles-u2028-u2029-escapes.md` (U+2028/U+2029 hazard — confirmed in this session).
- Existing learning: `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` (multi-agent review pattern — extended here with cross-agent-concur override of cost-of-filing gate).
