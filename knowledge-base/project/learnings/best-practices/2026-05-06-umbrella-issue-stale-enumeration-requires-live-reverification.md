---
date: 2026-05-06
category: best-practices
module: planning
tags: [github-issues, planning, deepen-plan, gitleaks, stale-enumeration]
related_issues: [3281, 3268, 3196, 3197, 3319]
---

# Umbrella issues with enumerated findings require live re-verification

## Problem

Issue #3281 ("12 pre-existing gitleaks findings on main blocking secret-scan workflow") enumerated **12 specific leaks** in its body, with file paths, line numbers, commits, and rule IDs. The body was authored on 2026-05-05 and not updated thereafter.

Between issue creation and the planning session for PR #3319 (2026-05-06), PRs #3196 and #3197 had already landed allowlist additions covering **11 of the 12 enumerated findings**. The umbrella issue body still showed all 12. A naive plan that trusted the body would have proposed a 12-finding triage; a one-line fix sufficed.

The deepen-plan pass caught this only because it ran `gitleaks git --no-banner --exit-code 1` live and got `leaks found: 1` — the live count contradicted the body's enumeration. Without that step, the plan's effort estimate would have been wrong by an order of magnitude.

## Solution

When a plan's source issue is an **umbrella issue** (tracks multiple findings, references multiple PRs in its body, or uses words like "all", "remaining", "12 leaks", "N findings") and the body enumerates a count or a list of items:

1. **Treat the enumeration as a snapshot, not a current state.** Issue bodies do not auto-update when sibling PRs resolve their items.
2. **Re-run the source check live** before scoping the plan. For gitleaks: `gitleaks git --no-banner --exit-code 1`. For TypeScript errors: `tsc --noEmit | wc -l`. For test failures: the project's test command. The check whose output the body claims to be is the one to re-run.
3. **Add a `Research Reconciliation — Spec vs. Codebase` table** to the plan body, mapping each enumerated claim to its current state and naming the disposition (no-op vs. fix-needed). This makes the stale-vs-live diff explicit for every reviewer.
4. **Resolve the umbrella's disposition explicitly** in the PR body — `Closes #<umbrella>` only when the actual remediation surface is the small remaining set; `Ref #<umbrella>` when sibling work is still needed.

The existing rule `hr-before-asserting-github-issue-status` covers the *open/closed* axis (`gh issue view <N> --json state`). This learning extends it to the *enumeration* axis: when the body counts or lists items, re-verify the count against the source check before trusting the count.

## Key Insight

GitHub issue bodies are **mutable but not auto-updated**. The author updates them by hand or not at all. Sibling PRs that resolve enumerated items don't edit the umbrella's body. Any plan whose effort estimate or scope is anchored to the body's enumeration is anchored to a snapshot from authoring time, which may be days, weeks, or months stale.

The cheap defense: run the source check live (one command, seconds) and reconcile in a table. The expensive failure: a 12-step triage plan when a 1-line fix suffices.

This generalizes beyond gitleaks. CodeQL findings, Sentry error counts, deprecation lists, "all the failing tests in module X", "all the warnings in folder Y" — every umbrella enumeration has the same staleness profile.

## Session Errors

1. **`gh issue create` HTTP 504 Gateway Timeout on first scope-out filing (#3321).** The issue was created server-side despite the 504 response. Recovery: `gh issue list --label deferred-scope-out --search "PR #<N> in:body"` showed all three filings landed. **Prevention:** when batching `gh issue create` calls, always verify with `gh issue list` afterward; do not retry blindly on 504/502 responses (covered by `hr-when-a-command-exits-non-zero-or-prints` — investigate before proceeding/retrying).

2. **Plan internal contradiction on #3281 disposition.** The deepened plan said `Closes #3281` in one section (line 22) and `Ref #3281` in another (line 68). Caught by git-history-analyzer at review. **Prevention:** deepen-plan agents should grep the plan for every issue-number reference and verify a single consistent disposition before returning. A `grep -nE "(Closes|Ref|Fixes|Closes_) #<issue-num>"` self-check at the end of deepen-plan would catch this.

3. **session-state.md plan-file path was an absolute worktree path.** Won't resolve after worktree teardown. Caught by code-quality-analyst at review. **Prevention:** when one-shot writes session-state.md from a planning subagent's output, convert the plan path to repo-relative before writing. The work skill's session-state template should mandate repo-relative paths.

4. **Pattern-recognition reviewer misread bullet nesting in markdown.** Claimed a column-0 list item was nested under another column-0 item. **Prevention:** when a review agent flags a markdown structural issue, verify by reading the file's actual columns rather than trusting the agent's prose summary — markdown-structural false positives are a known reviewer-agent failure class.

## Tags

category: best-practices
module: planning
