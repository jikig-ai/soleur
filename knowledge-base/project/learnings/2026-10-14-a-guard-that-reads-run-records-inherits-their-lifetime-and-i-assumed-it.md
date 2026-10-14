# Learning: a guard built on run records inherits their lifetime, and I assumed the lifetime

## Problem

The #10175 rotate guard decides "the LUKS store may have taken a write" from the run records of
`git-data-cutover.yml`. Three properties of that evidence were assumed instead of measured, and review found each:

1. **Deletion horizon.** The plan said retention "fails closed on count mismatch". It does not: when a run record is
   deleted, `total_count` shrinks with the rows, so the cross-check cannot see it. A flipped store reads clean once the
   flip run is gone. The CTO ruling then pinned two runs and quoted a 2026-12-29 horizon from the repository's 90-day
   log-retention setting. Measured later the same day: run records 196 days old are still listed, and the real second
   horizon is that GitHub strips a job's step list at about 170 days (a 174-day-old run is listed with no steps).
2. **Re-run semantics.** A "Re-run failed jobs" on a rotate run created before the guard executes the ORIGINAL SHA's
   workflow, which has no guard. No precondition added to the new workflow can reach it; only deleting those run
   records can.
3. **Approval.** The runbook and a workflow comment cited an `infra-privileged` approval; the environment has only a
   main-only branch policy and no required reviewers.

## Solution

- Pin two post-seam runs that must stay listed, `completed` and step-readable, or the scan refuses
  (`scan_unreadable pinned_run_missing`); pre-seam step-less jobs read clean; a missing `cutover` job post-seam is
  unreadable; an empty or whitespace argument means the default pins and tests use a literal `--no-pins`.
- Execute the real `run:` block of each new workflow step in tests (stubbed `gh` running the real `--jq` programs,
  argv-selective `curl`), and mutate each decision arm, instead of grepping tokens.
- Name the owner action for the unreachable case (delete the three old run records) and document its side effect on the
  flip gate (`d6_last_rotate_failed` becomes `d6_replace_stale`).

## Key Insight

Evidence read from a platform's records has the platform's lifetime, and that lifetime is a measurement, not a setting
you can read off a config page. Before building a guard on "the record will still be there", list the record's
deletion paths (retention, step stripping, manual delete, re-run of an older SHA) and measure each against the live
repository. Then ask which of them the guard can see: a shrinking `total_count` and an empty list look exactly like a
clean store.

## Session Errors

1. **Retention premise taken from a setting, not a measurement** — Recovery: a fix-round seat listed runs 196 days old;
   horizon text corrected in the library, runbook, ADR-239 amendment and tracker #10216 — Prevention: when a plan or
   ruling cites a retention/expiry horizon, require a live listing of the OLDEST record (`gh run list`, `gh api`), not the
   setting.
2. **A ruling inherited the unmeasured premise** (the CTO's 2026-12-29) — Recovery: the lead recorded a taste-class
   correction row and kept the pin design, which holds whenever deletion happens — Prevention: put the measurement
   command in the spawn brief for any ruling that turns on a platform behaviour.
3. **An edit anchor assumed a wrapped line, and a Python heredoc mangled a template-literal backtick** — Recovery: re-read
   the exact line, re-applied; the parser error named the line — Prevention: print the target line before building an
   anchor, and write backtick-heavy TS through a script file rather than an inline heredoc.
4. **`fixture-relative-assert` went red twice from new redirect-shaped tokens in a test file** — Recovery: shared the
   helper in the library, then rewrote a sed pattern without a `<` — Prevention: already covered by work Phase 0.5 check
   6.6; run the ratchet before the first commit of a new `*.test.sh`.
5. **A full `test-all.sh --affected` queued behind ~10 sibling runs** — Recovery: killed my own queued runs and used
   targeted suites; CI is the merge gate — Prevention: run `scripts/test-all.sh --capacity` before launching a gate.
6. **Commits with an empty temp message file aborted** — Recovery: wrote the message with the Write tool and used `-F` —
   Prevention: write the message file first and confirm it is non-empty.

## Tags

category: logic-errors
module: infra/git-data-cutover
