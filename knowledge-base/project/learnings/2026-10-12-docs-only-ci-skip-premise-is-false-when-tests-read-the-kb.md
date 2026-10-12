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

## Addendum — 2026-10-12 (#9729, PR A): the e2e fallback root cause, and what the review found

**Root cause (measured, not inferred).** The e2e checkout used `fetch-depth: ${{ github.event_name == 'pull_request' && 0 || 1 }}`. In an Actions expression `0` is falsy, so `A && 0 || 1` is `1` on every event: every PR was a depth-1 clone (the job log of PR 10079 shows `fetch --depth=1`; `git version 2.34.1` was present, which refutes "no git in the image"), `origin/<base>` never resolved, and every PR took the classifier's fail-closed `enum-failed` verdict. The four hypotheses written before reading the log (dubious ownership, absent ref, no git, absent classifier on base) were all wrong; the cause was one `gh api .../jobs/<id>/logs` away. The anchors test had been changed to pin the unquoted spelling, so a text pin certified the bug. Fix: the quoted string `'0'`, plus a workflow-wide sweep for falsy-middle ternaries.

**Review findings worth keeping (11 seats, no P1, 14 findings, all fixed inline).**
- A classifier that exits at the first non-allowlisted row, fed through `printf | bash` under `pipefail`, takes SIGPIPE on any name-status listing over the 64 KB pipe buffer (measured rc=141, 3 of 3); the step goes red on exactly the large PRs. Use a here-string. A guard needs a case over 64 KB.
- A fallback arm that runs the PR's own checked-out copy of the classifier undoes the "judge by the base ref's copy" rule: make the fallback a literal.
- A gate written `if: x == 'true'` skips on an absent output; write `!= 'false'` so absence runs the step.
- A guard whose floor was guessed (45, then 12) was wrong both times; derive the floor from a measured green run.
- A change to a required context's behaviour needs its ADR amendment in the same PR, even when the change "only repairs" an existing design.

## Session Errors

- **Four e2e root-cause hypotheses written before reading the job log, all wrong** — Recovery: read the failing job's log (`depth=1`) — Prevention: for a CI step that misbehaves, fetch the job log before listing hypotheses; the sweep in `plugins/soleur/test/ci-shard-totality-skip.test.sh` now fails any `&& 0 ||` shape.
- **A subagent claim ("e2e already skips KB-only diffs") contradicted the live check-run annotations** — Recovery: measured 14 of 14 fallbacks — Prevention: verify a classifier's skip from the live annotation, not its header comment.
- **Assertion floors guessed twice (45, 12)** — Recovery: derived from measured counts — Prevention: run the suite once, read the count, set the floor to it.
- **A mutation row labelled "pipe" was not a pipe and survived** — Recovery: re-ran the literal `printf | bash` form, killed 3 of 3 — Prevention: confirm a mutant reproduces the defect's actual shape before scoring a survivor.
- **New test file moved the fixture-relative ratchet (an `rm -rf` trap operand not provably absolute)** — Recovery: `assert_fixture_dir` before the trap — Prevention: run `fixture-scan.py relative <file>` before the first commit of any new `*.test.sh` that allocates a temp root.
- **Local affected gate queued sixth behind sibling sessions** — Recovery: stopped only my own process tree, used targeted suites + mutation battery + CI as the authority — Prevention: run `scripts/test-all.sh --capacity` before launching.
- **Session restart killed five review seats** — Recovery: `SendMessage` resumed all five with transcripts intact — Prevention: none needed; resume-not-respawn already documented.
- **Plan deferred the ADR amendment to PR B although `e2e` is a required context** — Recovery: amendment landed in PR A — Prevention: a plan phase that changes a required context's behaviour carries its amendment in the same PR.
