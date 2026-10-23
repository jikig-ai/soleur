# Learning: check stack fit and escaped-bug class before scoping an "apply technique X from this article" brainstorm

## Problem

Brainstormed whether to apply Anthropic's 2026-10-22 formal-verification result (Claude writing Rocq proofs of C/C++ binaries) to Soleur, per PR or on a schedule, to produce "bug-free" user code.

## Solution

Two cheap checks decided the scope before any design work:

1. **Stack fit.** Census tracked files by extension. The repo has 2,050 `.ts`, 528 `.tsx`, 1,680 `.sh`, 336 `.sql`, 90 `.tf` and 0 `.rs`; the article's method targets C/C++/Rust binaries and needs "hundreds of millions of tokens" per proof, so it does not transfer. Two independent counts agreed (git ls-files and find).
2. **Escaped-bug class.** The learnings corpus shows escapes are mostly tests that pass for the wrong reason, vacuous gates, config drift and env leakage. A proof cannot catch those; mutation testing or hermetic isolation can. Soleur has fast-check (ADR-293) and the RLS fuzz gate (ADR-111) but no mutation testing and no Semgrep in CI.

Outcome: parked with revisit triggers (tracking issue #10897) rather than building a verification tier. The article's own caveat ("formally verified" is not "bug-free") plus the T&C as-is wording make a user-facing "verified" claim a CLO/CMO-gated overclaim risk.

## Key Insight

For "apply technique X from article Y" requests, the decisive questions are what the technique's target language/artifact is and which bug classes actually escape in this repo. Answer both with a census and a learnings sweep before spawning leaders for design. A keyword histogram of learnings is noisy (e.g. "config" over-matches); use it to rank, not to quote.

## Session Errors

- **`worktree-manager.sh feature` hit the 110s timeout while a background `cleanup-merged` was still running; the worktree was created anyway.** Recovery: listed worktrees, confirmed it existed, continued. Prevention: after a timeout, probe `git worktree list` and the branch before retrying; do not re-run create.
- **Session-start `cleanup-merged` exceeded the 120s foreground limit and moved to background.** Recovery: continued without waiting. Prevention: none needed; it is non-blocking hygiene per go.md.
- **First `draft-pr` failed with a GraphQL TLS handshake timeout.** Recovery: branch had pushed, so `gh pr create --draft` succeeded on retry. Prevention: on a draft-PR network failure, retry `gh pr create` directly.
- **Armed a placeholder `Monitor` (`echo waiting`) to "wait" for background agents.** Recovery: ended turn; completion notifications arrive on their own. Prevention: do not use Monitor to wait on Agent tasks.
- **Closing turn named a next action without doing it; the unkept-promise stop hook caught it.** Recovery: restated as a `Paused:` line. Prevention: when waiting on background agents, end with a single `Paused: <what>` sentence.

## Tags

category: workflow-issues
module: brainstorm
