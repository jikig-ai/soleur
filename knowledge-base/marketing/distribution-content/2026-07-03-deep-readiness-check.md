---
title: "A 'healthy' server can lie — new deep-readiness check proves a host can actually serve you"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#5967"
issue_reference: "#5966"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

A "healthy" server can still be a lie: it answers 200 while the disk holding your workspace isn't even mounted. Just shipped a deep-readiness check that proves a host can actually serve your files before any traffic reaches it.

2/ Liveness says "the process is up." Readiness says "your files are here, writable, and real." Every host now has to pass the second one — so scaling out never means routing you to an empty box.

3/ Boring reliability work you should never notice. That's the point. #buildinpublic #devtools

## Bluesky

A "healthy" server can lie — it says 200 while the disk holding your workspace isn't even mounted. Just shipped a deep-readiness check that proves a host can actually serve your files before any traffic reaches it. Boring reliability work you should never notice — that's the point.
