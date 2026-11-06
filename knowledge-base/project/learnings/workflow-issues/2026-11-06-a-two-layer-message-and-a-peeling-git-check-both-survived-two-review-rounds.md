# Learning: a two-layer error message and a tag-peeling git check both survived two review rounds

## Problem

ADR-309 flip item 9b (isolated git directory for the Owner-approved `github_push_branch` push, Ref #9601) went through a 13-seat panel and two targeted fix rounds. A final fresh-eyes verifier still found three P3s, and the fix rounds had introduced or kept two real mis-assumptions:

1. A model-visible refusal text ended "nothing was pushed", and the caller appended a shared tail saying the branch "may or may not have been pushed". One tool result asserted both. Each layer was individually correct; their composition was not. The tail is appended to EVERY post-consume error on the strict path, so a text written for one layer must be read together with every wrapper that appends to it.
2. A fix agent claimed `git cat-file -e <sha>^{commit}` exits 1 for an absent commit. Measured on git 2.56 it exits 128 (the status of every fatal error), so a presence check keyed on exit 1 would never see "absent". `git rev-parse --verify --quiet <sha>^{commit}` exits 1 for absent and 128 only for real failures. `^{commit}` also peels an annotated tag object to its commit, so a zero exit alone accepts a tag-object sha; the printed sha must equal the approved sha.
3. Prose that stated a mechanism nobody re-ran: "a module-level `execFile` binding would crash at load" (it throws only on use under a `vi.mock` factory lacking it), and "the builder pins GIT_ALLOW_PROTOCOL and ignores it in `extra`" (after the closed-key-set fix it throws).

## Solution

- Pre-push refusal texts no longer claim "nothing was pushed"; the shared spent-approval tail carries the single confidence statement.
- Presence check uses `rev-parse --verify --quiet`, only exit 1 is absent, stdout must equal the approved sha.
- Both false sentences rewritten to what a command showed.

## Key Insight

- When a message is built from two layers, grep every wrapper that appends to it and read the concatenation, not the part you edited.
- An exit-code contract for a git plumbing command is a claim to measure on the installed git before it is relied on; the absent and the broken cases often share a status.
- A fix round's own new prose is the least-audited text in the diff. Run the falsifying command for every causal sentence a fix commit adds.

## Session Errors

- **Fix agent asserted a wrong git exit code (C2)** — Recovery: measured on real git, switched to `rev-parse --verify --quiet`. Prevention: measure an exit-code contract before pinning it.
- **Two-layer model-visible message contradicted itself** — Recovery: dropped the "nothing was pushed" clause from the pre-push texts. Prevention: read the final concatenated string in a test, not each constant alone.
- **Comment edit broke a mutation-battery anchor** — Recovery: `--check-anchors` caught it, anchor updated. Prevention: run `--check-anchors` after any comment edit near an anchored region.
- **112xx guard run as a two-dot diff produced false hits** — Recovery: re-ran the three-dot form. Prevention: use the exact `origin/main...HEAD` form from the brief.
- **deploy-arm run from the bare root, missing scratchpad dir, Stop-hook flags** — one-off, recovered in place.

## Tags
category: workflow-issues
module: apps/web-platform/server/push-branch
