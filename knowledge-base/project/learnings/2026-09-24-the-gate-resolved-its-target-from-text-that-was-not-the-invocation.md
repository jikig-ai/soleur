---
title: "The gate resolved its target from text that was not the invocation"
date: 2026-09-24
category: security-issues
tags: [hooks, pre-merge-rebase, review-evidence-gate, command-parsing, gh-pr-merge]
module: .claude/hooks/pre-merge-rebase.sh
issue: 8778
pr: 8779
---

# Learning: the gate resolved its target from text that was not the invocation

## Problem

`pre-merge-rebase.sh` read review evidence from `origin/main..HEAD` in the PreToolUse
envelope's `.cwd` — the SESSION anchor, not where an in-command `cd` lands. A subagent anchored at
the repo root running `cd <worktree> && gh pr merge N` was denied on a reviewed PR (#8778), and a
session in reviewed worktree A merging unreviewed PR B was allowed.

The fix resolves PR N's head from GitHub (`gh pr view N`) and reads the evidence there. Its first
version took N as "the first digits after any `gh pr merge` text". A ten-seat review found that
this re-created the bug one level up: the gate's target came from text that was not the merge.

- **Donor evidence.** `echo gh pr merge 8733; gh pr merge feat-x`, a trailing `# gh pr merge 8733`,
  a `||` arm, a quoted `"4243"` or `424"2"` (quote-stripping removes the digits or leaves `424`) and
  `4242-hotfix` all resolved one PR while gh merged another. A MERGED PR is an ideal donor: its
  squashed head never reaches `origin/main`, so `origin/main..<head>` keeps its review commits
  forever.
- **Repository retargeting.** `-Rother/repo`, `-sdR x`, `GH_REPO=`/`GH_HOST=` and a `cd` into
  another repository's checkout all let gh merge a different repository's PR N while the hook read
  this one's.
- **Self-asserted evidence.** A fork PR's head carries only commits its author wrote, so a trailer
  there proves nothing.

## Solution

Parse every REAL invocation with the detector's own anchor, in both the quote-stripped command and
the raw one, and resolve only when every invocation's first argument is the SAME bare number and
nothing retargets the repository. Anything else falls to the legacy range with the reason in the
deny text. PRs that are not OPEN, and fork PRs, read no local signals (Signal 3 only). Live check
after the fix: a root-anchored `cd <wt> && gh pr merge 8779` ALLOWS on the PR's pushed trailer;
`gh pr merge 8733` (MERGED) is refused.

## Key Insight

A gate that decides WHICH object to check from a command string has two inputs — the parser and
the object — and review attention lands on the second. Enumerate the spellings that NAME the
target without INVOKING it (echo, comments, `||`/`;` siblings, quoted or suffixed arguments) and
the spellings that change WHERE the command acts (flags in every short/attached/combined form,
environment variables, a `cd`). Then require the parse to agree between the raw and the
quote-stripped command: a value that changes under stripping was never a bare argument.

## Session Errors

1. **Planning subagent and two plan-review seats killed by an API session limit (HTTP 429).** —
   Recovery: the plan body was on disk with `## Acceptance Criteria`; resumed at plan-review. —
   Prevention: none needed; the on-disk recovery path worked as designed.
2. **A scripted plan edit anchored on `str.index("## Plan Review Revisions")` matched an inline
   mention of that heading, not the heading line** (MD022 caught it). — Recovery: moved the block.
   — Prevention: anchor scripted heading inserts on `"\n## <Heading>\n"`, never the bare text.
3. **`sed 's/.*gh pr merge//'` stripped to the LAST invocation in a segment.** — Recovery: the
   donor test T-PR17.1 failed; anchored the prefix on `^[^g]*`. — Prevention: a prefix strip is
   non-greedy by construction only when its character class excludes the delimiter's first char.
4. **deepen-plan gate 4.7 rejected a prose `expected_output`.** — Recovery: single-token literal.
   — Prevention: the gate already enforces it.
5. **`lint-guard-contract.py` requires one mutation matrix per guard.** — Recovery: split the
   table. — Prevention: the gate already enforces it.
6. **The affected gate queued behind two sibling runs for 10+ minutes; stopped before any suite
   ran to apply review fixes.** — Recovery: the ship-time gate covers the final tree. —
   Prevention: launch the affected gate only after review fixes land when the capacity probe
   reports contention.
7. **A live smoke right after `git push` read the pre-push `headRefOid`.** — Recovery: poll until
   `gh pr view` reports the local HEAD. — Prevention: gate a post-push live probe on
   `headRefOid == git rev-parse HEAD`.
8. **The plan and plan-review treated "digits after `gh pr merge`" as the merge target.** —
   Recovery: invocation-bound parsing plus repository checks (this learning). — Prevention: routed
   to `plan-sharp-edges.md` (enumerate name-without-invoke and retargeting spellings).
9. **The stop hook fired twice on "I'll apply…" closings while waiting on background agents.** —
   Recovery: `<stop>BLOCKED: …</stop>`. — Prevention: close a waiting turn with the stop marker,
   never a first-person promise.
10. **`session-state.md` first failed markdownlint MD032.** — Recovery: blank lines after
    headings. — Prevention: run markdownlint before committing spec artifacts (already in lefthook).

## Tags

category: security-issues
module: .claude/hooks/pre-merge-rebase.sh
