---
title: "Early-exit reader under pipefail"
summary: "A pipeline ending in an early-exit reader (grep -q, head) under pipefail returns 141 from SIGPIPE on a successful match, flipping verdicts; read from a file or here-string instead."
status: open
opened_on: "2026-10-24"
tags: [pipefail, sigpipe, bash, fail-open]
evidence:
  - knowledge-base/project/learnings/2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md
  - knowledge-base/project/learnings/2026-09-23-my-verdict-rode-on-a-pipeline-status-and-my-test-deleted-the-option-that-inverts-it.md
  - knowledge-base/project/learnings/2026-09-24-an-empty-api-search-is-not-evidence-of-absence-and-my-sanitiser-died-before-it-could-page.md
  - knowledge-base/project/learnings/2026-09-29-i-pinned-a-flake-class-with-a-weaker-fork-of-the-detector-we-already-had.md
  - knowledge-base/project/learnings/2026-10-01-a-grep-q-in-a-pipefail-chain-made-the-trigger-miss-its-own-bug-class.md
  - knowledge-base/project/learnings/2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md
required_reading: false
---
## Root cause

A reader that exits at its first match (`grep -q`, `grep -m`, `head`) closes the pipe while the
upstream producer is still writing. The producer takes SIGPIPE and exits 141, and `set -o pipefail`
promotes that status to the whole pipeline. A successful match therefore reads as a failure. The
race is narrow when the producer output is small (about 2 percent of runs in one measured case) and
deterministic when the output exceeds the pipe buffer, so the defect looks like flakiness and
survives small-sample checks. In positive predicates and in destructive-path guards the inverted
status fails open.

## Fix

Remove the pipeline status from the verdict. Write the producer output to a file or variable and run
the reader against that, feed the reader with a here-string, or use process substitution for a
writer that the consumer might not drain. Capture command output and test the string rather than
reading the status of a pipeline. Reproductions need the production producer family, a pinned
binary and a positive control that must fail, and a null result from a handful of runs is not
evidence for a rare event. Where the repository already maintains a detector for the class,
extending that one avoids a weaker fork.

## Evidence

- knowledge-base/project/learnings/2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md
- knowledge-base/project/learnings/2026-09-23-my-verdict-rode-on-a-pipeline-status-and-my-test-deleted-the-option-that-inverts-it.md
- knowledge-base/project/learnings/2026-09-24-an-empty-api-search-is-not-evidence-of-absence-and-my-sanitiser-died-before-it-could-page.md
- knowledge-base/project/learnings/2026-09-29-i-pinned-a-flake-class-with-a-weaker-fork-of-the-detector-we-already-had.md
- knowledge-base/project/learnings/2026-10-01-a-grep-q-in-a-pipefail-chain-made-the-trigger-miss-its-own-bug-class.md
- knowledge-base/project/learnings/2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md
