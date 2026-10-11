---
title: A model launch is a CLI pin, a rate card and a token budget, not a string swap
date: 2026-10-09
category: integration-issues
tags: [model-launch, claude-haiku-5-5, pricing, adaptive-thinking, claude-code-pin, supply-chain-floor]
issue: 9785
---

# Learning: a model launch is a CLI pin, a rate card and a token budget, not a string swap

## Problem

Haiku 5.5 (`claude-haiku-5-5`) landed as a pure id swap on paper: one `HAIKU_MODEL` constant, a few doc
mentions. Three things were not in the swap, and each would have shipped green.

1. **The pinned `claude-code` CLI did not know the id.** 2.1.284 has zero occurrences of the id in its
   bundle; an unknown id silently halves `max_tokens` (#6934). 2.1.293 is the first release with it, and it
   was published inside the repo's 3-day `min-release-age` floor, so the lockfile needed a one-off override
   with compensating checks (integrity equality, `npm audit signatures`, lock-diff gate, rollback trigger).
2. **The rate card was two cards, and an inherited number was wrong.** Haiku 5.5 is priced by prompt length
   (at most 100K vs over 100K), so `MODEL_PRICING` needed an optional `longPrompt` card keyed on
   input + cache read + cache creation. Re-fetching the official page also showed the repo's Sonnet 5.5
   cache-read rate (`$0.20`) was wrong (`$0.10`, stated twice on the page): a number copied forward from
   the previous launch's table and never re-derived.
3. **Adaptive thinking is on by default and its tokens count against `max_tokens`.** A router call at
   `max_tokens: 200` spent up to 148 tokens on thinking at default effort and 17 to 21 at `effort: low`, so
   a truncated answer would have read as "no usable result". The fix is `output_config.effort: "low"` plus
   a Sentry mirror for a missing text block, `max_tokens` stop or refusal, keyed on a pure helper
   (`anthropic-stop-report.ts`) that allowlists `stop_reason` and refusal category before they reach a log.

## Solution

Probe first (5 calls per cell, synthesized inputs, the spend-limited CI key), then decide per call site:
router and summarizer ship `effort: low`; the 4096-token leader loop, the 1-token preflight and the bench
did not truncate and stay unchanged. Keep the audit tooling honest: `audit-models.sh` learns both Haiku 4.5
spellings and carries an exact-path, self-expiring carve-out for the two Agent SDK scripts that must stay on
4.5 until the SDK is bumped. Every re-tiering beyond the proven sites is a follow-up gated on an eval (#9790),
not a launch-day edit (ADR-053).

## Session Errors

1. **Filing gate denials on `gh issue create`** (relative `--body-file`, missing `User-Impact:` and `Fix-Size:`) — Recovery: literal absolute path in its own Bash call, taxonomy word, size line. **Prevention:** compose the body with both fields before the first call; the hook is correct and needs no change.
2. **`git stash list` denied by the hook** — Recovery: not retried. **Prevention:** already hook-enforced (`hr-never-git-stash-in-worktrees`).
3. **cwd drift after `cd ..` in a compound command** — Recovery: re-ran from the repo root. **Prevention:** use absolute paths, never a bare `cd ..`.
4. **Test parser truncated by a `)` inside an `AUTOFIX_PAIRS` comment** — Recovery: reworded the comment. **Prevention:** a parser that reads a table out of shell source must be fed a fixture with punctuation in the comment column.
5. **A dated id literal in a `constants.ts` comment tripped `audit-models.sh --detect`** — Recovery: removed the literal. **Prevention:** the detector worked as designed; describe a retired id in prose, never by its spelling.
6. **Heavy import of `email-on-received` needed an Inngest key** — Recovery: replaced by a source-grep prefix pin. **Prevention:** pin a prefix by source assertion when importing the module pulls its runtime config.
7. **Baselined shell lint failed on `learning-retrieval-bench.sh`** — Recovery: confined the credentialed curl. **Prevention:** run the baselined linters WITH their `--baseline` flag as the runner does.
8. **The affected-suites gate queued behind a sibling worktree's multi-hour run and was cancelled** — Recovery: ran the targeted suites and left the gate to ship Phase 4 on the final tree. **Prevention:** none beyond ADR-183 (run the gate once, on the final tree).
9. **`claude-cli-pin-knows-models.test.ts` timed out once under load** (three real-binary scans used the 16s default while a sibling test already had 60s) — Recovery: gave all three an explicit 60s budget; suite 24 passed. **Prevention:** any test that scans the ~200MB CLI binary carries an explicit timeout.
10. **Inherited rate figure (Sonnet 5.5 cache read `$0.20`) re-used without re-deriving** — Recovery: corrected to `$0.10` in its own commit with a regime-boundary note, and ADR-041 addendum. **Prevention:** at every launch, re-fetch the official pricing page and re-derive every row, not just the new one.
11. **Over-broad `sed` rename inside a test** matched more than the intended rows — Recovery: corrected the affected lines by hand. **Prevention:** scope a sweep to the intended rows and assert the sentence afterwards, not a residual count.

## Key Insight

For a model launch, ask three questions before touching a string: does every pinned client know the id, is
every price row freshly re-derived (including the ones that did not change), and which call sites spend
tokens the answer now has to share. The first is answered by grepping the pinned bundle, the second by
re-fetching the page, the third by a five-call probe per site.
