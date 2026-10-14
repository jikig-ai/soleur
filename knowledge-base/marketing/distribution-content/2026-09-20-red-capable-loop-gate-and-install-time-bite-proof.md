---
title: "Your bug investigator now refuses to guess"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#8352"
issue_reference: "#8288"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Just shipped: your agent can't theorise about a bug until it has one command that turns red on your exact symptom — and has run it once.

2/ Then it ranks the likely causes and tells you, for each, what else you'd see if that one were true. When no regression test can be placed, it says so instead of pretending.

3/ Same release: a CI gate it installs for you now proves itself on the way in — it makes the gate fail on purpose, watches it catch the problem, then puts everything back.

## Bluesky

Shipped: before your agent forms a theory about a bug, it must produce one command that turns red on your exact symptom — and run it. Then it ranks the likely causes in plain language, saying what else you'd see if each were true. And the CI gate it sets up proves it catches things before install.
