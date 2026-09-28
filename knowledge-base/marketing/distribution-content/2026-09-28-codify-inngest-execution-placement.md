---
title: "Background work now declares where it is allowed to run"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#9134"
issue_reference: "#7230"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Shipped: every background job in Soleur now declares where it is allowed to run, and the build fails if a new one doesn't.

2/ Why it matters: the jobs that touch your workspace are now marked as tied to the machine that holds it. Spreading work across more servers later can't quietly move one of them away from your files.

## Bluesky

Shipped: every background job in Soleur now declares where it is allowed to run, and the build fails if one doesn't. Jobs that touch your workspace are marked as tied to the machine that holds your files, so spreading work across more servers later can't quietly move them away.
