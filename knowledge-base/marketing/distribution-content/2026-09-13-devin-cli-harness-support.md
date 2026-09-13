---
title: "Soleur on Devin CLI: /soleur:go runs the real workflow"
type: feature-launch
publish_date: 2026-09-14
channels: x, bluesky
status: scheduled
pr_reference: "#8083"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Soleur now runs on Devin CLI — the fourth supported harness alongside Claude Code, Grok Build, and Codex. Type /soleur:go and the matching workflow runs in your session, same pipeline.

2/ Install is one command: devin plugins install jikig-ai/soleur#plugins/soleur -y (after devin auth login). /soleur:go, /soleur:sync, and /soleur:help work as native Devin slash commands.

3/ Devin gets the same scaffolding parity as Codex and Grok: a native plugin manifest, session-start hooks, and the full skill set. Update anytime with devin plugins update soleur.

## Bluesky

Soleur now runs on Devin CLI — the fourth supported harness alongside Claude Code, Grok Build, and Codex. Install: devin plugins install jikig-ai/soleur#plugins/soleur -y; update: devin plugins update soleur. /soleur:go runs the workflow in-session.
