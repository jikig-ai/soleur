---
title: "Background work now declares where it is allowed to run"
type: feature-launch
publish_date: 2026-10-01
channels: x, bluesky
status: published
pr_reference: "#9134"
issue_reference: "#7230"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Shipped: every background job in Soleur now declares where it is allowed to run, and our tests fail if a new one doesn't.

2/ Why it matters: the jobs that touch your workspace are now marked as tied to the machine that holds your files. It's the map we'll follow before any work spreads across more servers.

## Bluesky

Shipped: every background job in Soleur now declares where it is allowed to run, and our tests fail if one doesn't. Jobs that touch your workspace are marked as tied to the machine that holds your files: the map we'll follow before any work spreads across more servers.
