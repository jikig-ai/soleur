---
synced_to: []
---

# Learning: a red CodeQL check I read as "not required" became a filed alert on main

## Problem

PR #9584 merged with one failing check, `CodeQL`. It is not in the required set, so I recorded it as "not required" and moved on. The merge-time
`CodeQL Main Alert Gate` then re-read the same finding on main, found no tracking issue, filed #9625 and went red. The finding was in a file the PR
added: a drift-guard test that banned any JSON-LD string mentioning the Inc.com host with `/inc\.com/i.test(x)`, which CodeQL reads as
`js/regex/missing-regexp-anchor`.

The fix PR (#9629) then needed a full review panel for one line, and the panel found the line's own guard unpinned: the only positive fixture was
lowercase, so dropping `toLowerCase()` stayed green.

## Solution

- Treat a failing `CodeQL` check on a PR as a finding to read before merge, even when it is not a required context. The gate that runs on main files
  an issue for any critical or high alert that has no tracker, so "not required" means "not blocking the merge", never "not going to cost anything".
- In a test that bans a host name, write a deliberate substring test with a lowercase needle built without a host-shaped literal, and pin it with an
  upper-case fixture and a near-miss negative. All three mutants (drop the lowercase, narrow the needle, return nothing) must redden the self-test.

## Key Insight

A check being non-required changes who is blocked, not what it measures. The question to ask of any red check at merge time is what consumes its result
after the merge, not whether the ruleset lists it.

## Session Errors

**A red `CodeQL` check was recorded as "not required" and the PR merged.** Recovery: the alert's tracker (#9625) is closed by the fix in #9629. Prevention: read the
failing alert's rule and location before queueing auto-merge.

**A review seat claimed the Inc.com self-test already covered mixed case; it did not.** Recovery: read the fixture, then pinned upper and mixed case.
Prevention: verify a seat's claim about a fixture against the file before relying on it.

## Tags

category: workflow-issues
module: ship, review
