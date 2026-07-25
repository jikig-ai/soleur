---
title: "Start chatting before your repo finishes connecting? You get an honest 'still setting up' instead of a dead-end"
type: feature-launch
publish_date: 2026-07-21
channels: x, bluesky
status: published
pr_reference: "#5405"
issue_reference: "#5399"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Connect a repo and fire off a task before it finishes cloning, and your AI team used to just... dead-end. No repo, no explanation.

Shipped today: it now tells you it's still setting up — try again in a moment.

2/ The fix: every way a task can start now checks whether your repo is actually ready first. If it's still cloning or the setup failed, you get a plain message instead of a confusing failure — and the conversation stays alive to resume.

3/ Small thing, but it's the difference between "this is broken" and "oh, give it a sec." Reliability is a feature. #buildinpublic

## Bluesky

Connect a repo and start a task before it finishes cloning, and your AI team used to dead-end with no explanation. Shipped today: it tells you it's still setting up — try again in a moment — and keeps the conversation alive to resume. Reliability is a feature.
