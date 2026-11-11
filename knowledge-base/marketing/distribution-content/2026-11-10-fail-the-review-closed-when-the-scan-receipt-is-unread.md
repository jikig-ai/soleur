---
title: "A review can no longer pass a change as clean when the security scan never ran"
type: feature-launch
publish_date: 2026-11-26
channels: x, bluesky
status: scheduled
pr_reference: "#12566"
issue_reference: "#12530"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Just shipped: Soleur will not call a code review clean unless the security scan actually ran.

2/ If the scan is missing, the review stops. A skipped check no longer reads as a clean result.

## Bluesky

Just shipped. A code review stays open until the security scan has actually run. A missing scan keeps the review from passing as clean.
