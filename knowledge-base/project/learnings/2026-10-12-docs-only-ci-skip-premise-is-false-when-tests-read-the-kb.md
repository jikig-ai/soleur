# Learning: "docs-only PRs need no CI" is false when the tests read the docs tree

## Problem

PR 10097 changed one markdown file under `knowledge-base/` and still ran most of the CI battery on the 60-concurrent
hosted-runner pool. The obvious fix, a `knowledge-base/**` path skip, is a hole in this repo.

## Solution

Derive the skip set from the repo's own consumer map instead of asserting it:

- `scripts/test-affected-kb-consumers.baseline.txt` has 240 rows of real readers (ADRs, registers, roadmap, runbooks,
  `model.likec4.json`, `vision.md`), and `test-affected-paths.sh` has a content-keyed whole-tree scan.
- Workflow-level `paths-ignore` would leave required contexts (`test`, `e2e`, ~20 more) unreported and wedge every PR;
  ADR-276 forbids synthetic statuses. The mechanism is a job-level `if:` plus a named skip-reason tolerance in the `test`
  aggregator, with `merge_group` keeping the full battery.
- The broad version already existed as a parked issue (#9729, S4). Searching issues by symptom (`affected-only`,
  `path-filter`) before designing found it and the ADR-276 stage plan in minutes.

## Key Insight

A path-class skip is only as safe as the reader inventory behind it. Ask "what reads this tree?" before "which paths can
we skip?", and check whether a classifier that is supposed to skip a class (here `ci-e2e-classify.sh` for
`knowledge-base/**`) actually did on the live run: PR 10097's e2e annotated `enum-failed` and ran the heavy path anyway.

## Session Errors

- **Subagent claim "e2e already skips KB-only diffs" contradicted by the live run annotation** — Recovery: recorded as an
  open root-cause question and bundled into the S4 PR scope — Prevention: read the check-run annotation of the live run,
  not only the classifier's header comment.
- **`--print-selection` timed out (120 to 170 s) in two subagents** — Recovery: used static evidence only — Prevention:
  the S4 replay must run in CI or with a bounded selector.

## Tags
category: workflow-issues
module: ci
