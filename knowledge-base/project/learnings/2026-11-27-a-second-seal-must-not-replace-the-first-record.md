---
module: run-health emit
date: 2026-11-27
problem_type: workflow_issue
component: tooling
symptoms:
  - "a second --seal wrote goto_count 0 over the first seal when --session-state was omitted"
  - "json.load failure replaced the existing ledger with a fresh sealed object and exited 0"
  - "the copyable seal fence hardcoded one status, so the other two terminal returns could not be recorded"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
status: open
tags: [run-health, fail-open, seal, workflow]
---

# Troubleshooting: The first run-health seal is the record

## Problem

`plugins/soleur/scripts/run-health-emit.sh` seals once. A later seal, and a ledger that does not parse, were still writing a new object over the first record. The copyable fences in the schema and in test-fix-loop hardcoded one `--status`, so a model that copied the fence stored that token for every return.

## Environment

- Module: plugins/soleur scripts and the one-shot / test-fix-loop skills
- Affected Component: `plugins/soleur/scripts/run-health-emit.sh`
- Date: 2026-11-27
- Stage: review of pull request #12996, issue #12573

## Symptoms

- Garbage bytes in `run_health.json` became a sealed `status: completed` object. The helper exited 0.
- A second `--status completed --seal` replaced a first `budget-capped` seal's `goto_count`.
- New files were mode 0644, and a symlink prompt was followed.
- `producer_call` treated the one-shot pointer sentence as a command because the sentence contains `bash` and `--seal`.

## What Didn't Work

**Attempted Solution 1:** Count every file that mentions `bash` and `--seal` as a producer. The one-shot pointer is a sentence, not a command line.

**Attempted Solution 2:** Keep three fences, one per status. The first seal wins, so a second fence cannot correct the token. One fence has to carry the status the run actually ended with.

## Solution

1. On `json.load` failure, or when the path is a symlink, leave the existing bytes and exit 0 after `run-health-emit:` on stderr.
2. Write `goto_count` and `tally_show` only on the first seal.
3. Refuse a symlink `--run-dir`. Write new files mode 0600.
4. One fence: `--status "$RUN_HEALTH_STATUS"`. Set that variable from the termination (`completed`, `failed`, or `budget-capped`) before the call.

`bash plugins/soleur/scripts/run-health-emit.test.sh` then printed `passes=36 fails=0`.

## Why This Was Hard

Fail-open exit 0 hides a bad write. The suite can stay green while the ledger the next reader opens is a different object than the one the run produced. The pointer sentence and the real fence share the same words, so a substring grep cannot tell them apart.

## Prevention

- A producer check matches a command-position `bash` line, not a sentence that names the script.
- The suite asserts the first seal's status and `goto_count` across a second `--seal`.
- The suite asserts an unreadable ledger is left byte-for-byte.
- Do not add a second fence. The variable is the whole status contract.

## Related Issues

- #12573
- #12996
- [A run-health pointer is not a seal call](2026-11-20-run-health-emit-must-seal-with-a-real-call.md)

## Session Errors

**Plan completion floor reported no-out-of-scope-edits.** The whole-branch diff includes the implementation that was already on the branch. Plan-phase commits were docs-only. Recovery: recorded the miss and did not rewrite history. Prevention: the floor's plan predicate measures the branch, not the phase commit. This is a different subsystem. Not fixed in this pull request.

**Work completion floor reported clean-tree.** The only porcelain entry was the untracked probe `scripts/.h1probe.6G3BHeem.sh`, which this run must not delete or commit. Recovery: recorded the miss. Prevention: none in this pull request. The file stays untracked.

**Review completion floor reported no-open-code-review-issues, twice.** `gh issue list --label code-review --state open` counts every open issue in the repository. None of the returned issues cite pull request #12996, and the pull-request search returned an empty list. Recovery: did not treat the floor as a pass and did not close other issues. Prevention: the floor is not scoped to the pull request under review. Not changed here.

**emit-review-trailer.sh skipped.** An older `Reviewed-By-Soleur` trailer was already on the branch, so the script exited 0 without recording this panel. Recovery: commit 319e3b77f1 supersedes dcc11a2863f0 by hand, which is the script's own instruction when coverage changes. Prevention: the skip path is documented. This run followed it.

**The first status command ran in the main checkout.** It printed a 5-pass suite and HEAD `9e548b6bbf`. Recovery: re-ran in the feature worktree. The worktree suite is the result that counts. Prevention: prefix worktree commands with `cd` to the worktree path.
