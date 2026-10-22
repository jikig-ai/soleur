---
title: Inert Config snapshot source review
date: 2026-10-22
pr: 9051
reviewed_head: a63839a459d72505e53a44108d1c0ae38efa7242
status: correction-unpushed-review-pending
---

# Source review record

The accepted [snapshot contract](config-snapshot-proposal-2026-10-22.md) was
implemented at `a63839a459d72505e53a44108d1c0ae38efa7242`. The initial focused
suite passed 91 tests, Ruff passed, and the staged secret scan found no leaks.
Independent engineering, security and test-design reviews recorded the findings
below before correction. The first correction was pushed at
`e4a5ae0aa1ecdaff74e622984860402573438d4b`; review found two further boundary
issues. Those are now corrected in the worktree and 97 focused tests pass. The
current combined source still needs to be committed, pushed and independently
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

Additional correction-delta findings:

- **Low — an unidentified created report is silently left after rollback.** In
  `config_snapshot.py` › `Store.remove_created()`, `created[name] = None` means
  exclusive creation succeeded but the inode could not be verified. Skipping
  that requested deletion returns success while retaining a private report,
  which masks cleanup uncertainty. Preserve it and raise fixed `cleanup`; test
  the report-specific initial-fstat failure.
- **Medium — three tool-result test rows still have competing refusal causes.**
  `test_config_snapshot.py` ›
  `test_tool_result_unknown_nonzero_mismatch_and_staleness_refuse()` must also
  rebind `review.command_sha256` when testing the tool command hash, use a
  semantically valid tool mutation for the stale-record case, and remove the
  positive-control report before expiry. Assert each intended failure code.
- **Low — recovery receipt directory can pollute the fixed action directory.**
  `config_snapshot.py` › `fresh_record_directory()` admitted a nested child of
  the action directory, creating an unlisted entry before the later census
  refused. Reject the action directory and descendants before mkdir; test that
  nested recovery leaves the action tree unchanged and keep the outside-path
  positive control.
- **Medium — nested recovery test can refuse before reaching its guard.**
  `test_config_snapshot.py` ›
  `test_nested_recovery_directory_refuses_before_action_tree_mutation()` must
  keep the synthetic digest seam active through cleanup, then prove the same
  fixture succeeds with an outside recovery directory. Without this, a digest
  mismatch can mask deletion of the nested-path guard.

## Correction status

The worktree now carries these corrections: `Store.write()` records exclusive
creation before metadata inspection and closes the descriptor on every path;
rollback refuses cleanup-success when an owned leaf has no verified inode;
the action wrapper reports late outer failures as spent when the marker was
created; inspection validates the review seal and canonical bytes; report
rollback failure reports cleanup uncertainty; and tool-result semantic tests
use valid canonical framing, rebind both command and execution-record hashes,
use a valid stale-record mutation, and remove the positive-control report before
asserting expiry. The report-size test uses a stable oversized result.
`fresh_record_directory()` now rejects the action directory and all descendants
before creating anything. The nested-path test keeps the digest seam active and
uses the same otherwise-valid fixture for a successful outside recovery path.
All ten findings remain open until independent
correction-delta reviews pass at a pushed commit.

No external origin, account, provider or destructive action occurred during
these reviews. No actual snapshot preparation or execution is authorized by
this source-review record alone; the session's existing authorization governs.
