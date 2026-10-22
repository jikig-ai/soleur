---
title: Inert Config snapshot source review
date: 2026-10-22
pr: 9051
reviewed_head: a63839a459d72505e53a44108d1c0ae38efa7242
status: correction-pushed-review-pending
---

# Source review record

The accepted [snapshot contract](config-snapshot-proposal-2026-10-22.md) was
implemented at `a63839a459d72505e53a44108d1c0ae38efa7242`. The initial focused
suite passed 91 tests, Ruff passed, and the staged secret scan found no leaks.
Independent engineering, security and test-design reviews recorded the findings
below before correction. Corrections are now on the worktree and passed 96
focused tests; the corrected source still needs to be pushed and independently
re-reviewed.

## Findings

- **Medium — post-consumption failures can be labeled preconsume.** In
  `config_snapshot.py` › `locked_action()`, the wrapper's final deadline check
  and directory-descriptor close happen after the wrapped operation may have
  consumed the marker, but the wrapper retains its initial `preconsume` stage.
  A late failure can therefore misclassify a spent attempt. Fix by carrying
  consumption/recovery state through the wrapper and testing late deadline and
  close failures after a synthetic completed operation.
- **Medium — tool-result negatives refuse on framing before their target
  predicates.** `test_config_snapshot.py` ›
  `test_tool_result_unknown_nonzero_mismatch_and_staleness_refuse()` writes
  changed tool records without the canonical newline required by `_private_tool()`.
  Those rows do not prove their named semantic refusals. Rebind the review's
  execution-record digest and seal for semantic mutations, retain an explicit
  stale-hash mismatch case, and restore a valid tool/review pair for expiry.
- **Medium — report rollback failure is hidden as an inspection failure.** In
  `config_snapshot.py` › `inspect_action()`, a failed report write is followed
  by best-effort removal, but if that removal also fails the outer handler
  reports `binding/inspection`. This hides uncertainty about retained private
  report data. Preserve fixed deadline/expiry failures while reporting cleanup
  failure; test the owned report remaining with a sanitized cleanup refusal.
- **Low — write descriptor can leak and marker creation can be misclassified.**
  In `config_snapshot.py` › `Store.write()`, `os.fstat()` runs before the
  descriptor's `try/finally`. If it fails, the descriptor leaks; if the leaf is
  the spent marker, creation already occurred although `store.created` remains
  empty. Begin descriptor cleanup immediately after open and account for the
  exclusive marker independently of `fstat`; retain an unverifiable marker and
  classify the attempt as spent.
- **Low — review seal is not checked at the inspection boundary.** In
  `config_snapshot.py` › `inspect_action()`, Python dictionary equality accepts
  `False == 0`, so a supplied review can alter strict boolean/integer fields
  while keeping an invalid self-hash. Check the review seal and canonical bytes
  before accepting its reconstructed consistency.
- **Low — report-size regression depends on duplicate parsing.**
  `test_config_snapshot.py` › `test_report_serialized_size_limit_never_truncates()`
  returns oversized data only on the second parser call and asserts exactly two
  calls. A stable oversized-fields stub should exercise serialization without
  coupling the test to internal parse count.

## Correction status

The worktree now carries these corrections: `Store.write()` records exclusive
creation before metadata inspection and closes the descriptor on every path;
the action wrapper reports late outer failures as spent when the marker was
created; inspection validates the review seal and canonical bytes; report
rollback failure reports cleanup uncertainty; and tool-result semantic tests
use valid canonical framing, rebound review hashes and positive controls. The
report-size test uses a stable oversized result. All six findings remain open
until independent correction-delta reviews pass at a pushed commit.

No external origin, account, provider or destructive action occurred during
these reviews. No actual snapshot preparation or execution is authorized by
this source-review record alone; the session's existing authorization governs.
