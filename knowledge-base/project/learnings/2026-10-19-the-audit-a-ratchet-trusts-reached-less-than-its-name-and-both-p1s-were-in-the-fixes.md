# Learning: the audit a ratchet will trust reached less than its name, and both P1s were in the fixes

## Problem

PR #10572 (PR1 of the S4 affected-index completion, #10448 option i) rewrote the `audit` scan of `scripts/ci-pr-affected-replay.py`, the oracle that PR3's required-check ratchet and the PR4/PR5 drain will trust ("`gap_suites=0` means the index is complete"). A nine-seat review, two targeted fix rounds and a verification seat found:

- The structural-enumeration seat showed the audit's REACH is narrower than its name: it reads one suite file plus one regex-found `.sh` hop (the selector already computes a depth-8 closure in `pats`), strips `#`/`//` lines for every language, never sees suites the runner declines, drops directory reads, restates bun's test discovery and the selector's edge grammar. Most of this predates the PR. Nobody had written down which of it must be fixed BEFORE the ratchet, because after the ratchet a reach change reds every PR or forces baseline growth.
- Both P1s that survived into the fix rounds were introduced by fix commits: a census keyed by suite label overwrote the earlier row's gaps when two selector rows shared a label, and the new operation-count fixture read a self-reported counter so a quadratic scan passed it.
- A CTO ruling taken literally (blank "a `-` plus one letter attached to a path") destroyed real reads (`${V:-scripts/lib/f.sh}`); only the regenerated per-occurrence differential receipt showed it.

## Solution

- Route the reach question to the CTO as ONE batched ruling instead of widening inside the PR: every audit-definition change lands in a new mandatory PR1b before PR3, reach is frozen from PR3 to PR5, and the rest are DECLARED LIMITS that the ADR amendment lists ("necessary but not sufficient", not "index complete"). Rows 29-37 of `decision-challenges.md`.
- Make the boundary rule one definition (`WORD_CHARS` drives the regex and `boundary()`; a two-view union keeps escape-adjacent paths), so the scan, the anchors and the accept rows cannot drift.
- Pin the fix commits with independent instruments: line events, a text-length axis, a name-width axis and best-of-3 CPU ratios, crash-aware mutant scoring, fixtures that ADD members (duplicate labels, identical lines in suite and lib).

## Key Insight

A guard's value to the next PR is what it PROVES, and the proof is bounded by its reach; state that bound and freeze it before anything is built on top. And a fix commit is the least-audited surface: every P1 in the fix rounds was in verification code the fix added.

## Session Errors

1. **The first planning subagent died on a session rate limit before writing any file.** Recovery: `SendMessage` resumed it. **Prevention:** none beyond the existing resume-over-respawn rule (one-off).
2. **The technical-ruling gate failed on `decision-challenges.md` three times** (a parenthetical between `<date>` and the colon; `pending - assumed` rows; a literal `|` inside a cell). Recovery: rewrote the rows; the gate's message is exact. **Prevention:** a plan Sharp Edge now states the shape (`Ruled by CTO agent, <date>: ` with nothing before the colon, no literal pipe) and says to run `technical-ruling-gate.sh --branch` before returning.
3. **A network error (`EAI_AGAIN`) killed the test-design seat mid-run.** Recovery: resumed with a prioritised list. **Prevention:** none (one-off).
4. **A stray `ruff-*.whl` appeared untracked in the worktree root during review** (a lint or seat dropped it). Recovery: moved it out before any `git add`. **Prevention:** `git add` by explicit path, never `-A` (already the practice).
5. **A ruling applied literally was wrong** (the short-option blanking rule). Recovery: the fix agent narrowed it to after whitespace, a quote or start of text and recorded decision row 35. **Prevention:** regenerate the per-occurrence differential after any normalisation change (now `receipts/audit-differential.py`).
6. **The review's fix commits introduced two P1s** (duplicate-label overwrite; vacuous operation-count instrument). Recovery: caught by the structural and test-design seats in the targeted round. **Prevention:** already codified (the fix-round mechanism); this session confirms the cap-2-plus-verification shape works.
7. **Two stop-hook feedbacks on closing text that named a next action without taking it.** Recovery: ended the turn with a one-sentence `Paused:` label. **Prevention:** none beyond the hook.

## Tags
category: workflow-patterns
module: ci-pr-affected-replay
