---
title: "grep-over-markdown marker tests: keep asserted tokens on one physical line, and pick gate-unique alternation tokens"
date: 2026-06-03
category: best-practices
tags: [testing, bash, marker-tests, grep, ux-design-lead]
issue: 3274
pr: 4855
---

# grep-over-markdown marker tests: line-wrap + vacuous-alternation traps

## Problem

PR #4855 (issue #3274) added two `plugins/soleur/test/*.test.sh` grep-over-markdown
regression guards asserting that prose instructions exist in an agent/skill `.md`.
Two distinct authoring traps surfaced:

1. **Line-wrap breaks line-based `grep`.** The AC1 assertion
   `grep -qiE "before .*open_document|snapshot.*(size|sha256|checksum)"` failed
   twice even though the agent prose plainly said "record a pre-open snapshot ...
   before calling open_document". Cause: `grep` matches **per physical line**, and
   the prose had wrapped "snapshot" onto one line and "size"/"sha256" onto the next,
   so `snapshot.*(size|sha256)` never matched on a single line. The sibling
   alternative `before .*open_document` also missed because the text was
   `**Before**` — the `**` immediately after `Before` defeated the `before `
   (trailing-space) pattern.

2. **Vacuous alternation token.** The AC2 assertion
   `grep -qiE "collapse|post-open .*size|fraction|parse failure"` passed even on
   `origin/main` (baseline count = 4) because the bare word `collapse` already
   appears in the agent's pre-existing UX-audit prose ("sidebar collapse
   affordance/toggle"). The assertion claimed to guard the new HARD GATE block but
   would have passed with that block deleted — caught by pattern-recognition-specialist
   at review.

## Solution

- **Put every token an assertion ANDs across (`A.*B`) on the same physical line**
  in the source markdown. Long markdown lines are fine; reflow so the regex's
  required substrings are co-located. Avoid asserting across a `**bold**` boundary
  with a space-delimited pattern (`before `): markdown emphasis markers sit
  adjacent to the word.
- **Choose alternation tokens UNIQUE to the new content.** Before trusting a
  marker grep, run it against `git show origin/main:<file>` — the baseline count
  MUST be 0 for the pattern to be load-bearing. Here `collapse gate|destructive
  wipe|parse failure` has baseline 0; bare `collapse` has baseline 4.
- **Add a cross-file resolvability assertion when a test guards a citation
  repoint.** A `grep <anchor> <source>` that only checks the *citing* file passes
  even when the *cited* file renders the anchor un-greppable (a backtick split the
  token in the target). Assert the anchor greps cleanly in the target too.

## Key Insight

A grep-over-markdown marker test is only as good as (a) the source's physical line
layout and (b) the uniqueness of its match tokens. The cheapest validation is to
run the exact pattern against `git show origin/main:<file>` and require a 0
baseline — a non-zero baseline means the assertion is vacuous regardless of how
sensible the prose looks.

## Session Errors

1. **Planning subagent: Task fan-out unavailable** (forwarded from session-state.md).
   The `soleur:plan`/`deepen-plan` research agents and `/plan_review` triad could
   not spawn in the planning environment. — Recovery: planner ran the equivalent
   gates inline. — Prevention: known environment constraint; multi-agent
   `/soleur:review` at PR time covers the gap (it ran, 3-agent slice).
2. **AC1 grep assertion failed twice on markdown line-wrap.** — Recovery: reflowed
   the snapshot clause onto one physical line. — Prevention: this learning; when
   authoring a `A.*B` marker grep, keep A and B co-located in the source.
3. **Full-suite exit gate: 2 Inngest signature-verify tests timed out (16s)** under
   full-suite import contention (`import 1135s`). — Recovery: re-ran the two files
   in isolation (6/6 pass, import 165ms), confirming a pre-existing cold-start
   timeout flake unrelated to the diff (zero `apps/web-platform` files touched). —
   Prevention: per the work skill's Doppler-env/timeout caveat, re-run a
   suspected-regression webplat file in isolation before treating a full-suite
   timeout as a regression.
4. **CWD drift on `git commit`.** A `cd apps/web-platform` from the isolation
   re-run persisted into the next Bash call, so a worktree-relative `git add`
   resolved against the wrong root. — Recovery: re-ran with `cd <worktree-root> &&
   git add ...`. — Prevention: the Bash tool does not persist CWD intent; chain
   `cd <worktree-root> && <cmd>` in any commit/test call that follows a `cd` into
   a subdirectory.
