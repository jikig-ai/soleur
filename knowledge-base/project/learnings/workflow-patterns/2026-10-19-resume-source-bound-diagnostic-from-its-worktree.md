---
title: Resume a source-bound diagnostic from its named worktree
date: 2026-10-19
category: workflow-patterns
tags: [codex, worktree, diagnostic, approval]
---

PR #9051 resumed with an exact source-bound manifest and a pending independent
review. A status probe issued at the shared bare root failed with “this operation
must be run in a work tree.” Use the resume prompt's absolute worktree for the
first status probe. The obsolete live rollout spec path was also absent; discover
the archived rollout record and current live-paths session state before reading.

Session-start maintenance could not write its state and cleanup locks under the
filesystem sandbox. The required escalation retry completed successfully. A
lock-file permission failure is not evidence of another session holding the lock.
Keep retry output in a bounded log and inspect the result before proceeding.

Large plugin files and process argument listings produced truncated output.
Read bounded sections and use narrow process fields; a line limit alone does not
bound bytes when one command line is very long.

These visible failures require a learning, not another global rule. Keep tracked
source unchanged while the manifest awaits review and exact-action approval;
commit this learning with subsequent evidence work after the pinned attempt.
The diagnostic itself remains unexecuted at this preparation boundary.

## Addendum — approved attempt

The exact diagnostic subsequently ran once and stopped at HTTP-200 token header
validation. The generic `header_shape` reason cannot distinguish cardinality,
framing, encoding or media predicates. Preserve that incomplete evidence and
spent marker. The owning diagnostic is being corrected with a fixed allowlisted
category and synthetic tests; do not infer chunked framing or retry unchanged.

The full synthetic suite initially failed because the sandbox refused local
fixture socket operations. Its approved escape passed 320 tests without a new
registry request. A failed sandbox run is not evidence of a source regression.

The installed lint runner's `auto` selected user-repository adoption rather than
this checkout's existing Ruff baseline. Its repository scope also requires the
runner file to belong to the checkout. Use the exact CI/lefthook-configured
Ruff command for this repository; it passed the existing 44-finding baseline.
The installed work reference for CI-only hook exclusions was absent; the
worktree's version exists. No hook exclusion or new lint adoption was applied.
