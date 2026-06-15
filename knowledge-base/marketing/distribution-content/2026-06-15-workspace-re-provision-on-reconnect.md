---
title: "Agent workspaces now self-heal on reconnect"
type: feature-launch
publish_date: ""
channels: x
status: draft
pr_reference: "#5339"
issue_reference: "#5340"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Just shipped: your AI agent's workspace now recovers itself on reconnect. Drop your connection mid-task, come back, and it re-provisions and resumes with full context — instead of dead-ending on a missing workspace.

2/ The subtle part was being honest when recovery genuinely can't happen. If the workspace is truly gone, you get a clear "your conversation is intact — start a new message to resume" instead of a silent retry loop. Reliable by default.
