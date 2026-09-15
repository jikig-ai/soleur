---
title: "Soleur on Devin CLI: /soleur:go runs the real workflow"
type: feature-launch
publish_date: 2026-09-14
channels: x, bluesky
status: published
pr_reference: "#8083"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Soleur now runs on Devin CLI — the fourth supported harness alongside Claude Code, Grok Build, and Codex. /soleur:go classifies your request and runs the matching skill in-session.

2/ One command to install: devin plugins install jikig-ai/soleur#plugins/soleur -y (needs devin auth login first). /soleur:go, /soleur:sync, /soleur:help run as native Devin slash commands.

3/ Devin gets a native plugin manifest, session-start hooks, and the full skill set — the same scaffolding depth as Codex and Grok. Update anytime with devin plugins update soleur.

## Bluesky

Soleur now runs on Devin CLI — the fourth supported harness alongside Claude Code, Grok Build, and Codex. Install: devin plugins install jikig-ai/soleur#plugins/soleur -y; update: devin plugins update soleur. /soleur:go runs the workflow in-session.
