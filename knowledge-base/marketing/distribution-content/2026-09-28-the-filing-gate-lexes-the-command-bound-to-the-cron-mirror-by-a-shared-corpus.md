---
title: "Your AI agents can no longer sneak unjustified issues onto your backlog"
type: feature-launch
publish_date: 2026-10-06
channels: x, bluesky
status: published
pr_reference: "#9099"
issue_reference: "#9089"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Just shipped: Soleur's agents can't slip a GitHub issue onto your backlog without saying why it matters to a user, even when the filing is buried inside a wrapped or nested shell command.

2/ Before, a filing wrapped in a subshell or a quoted string walked straight past the check. Now the guard reads the command the way the shell does, and every filing has to carry its own milestone and justification.

3/ Your backlog stays yours: fewer "while I'm here" tickets, and every new issue arrives with a reason attached.

## Bluesky

Just shipped: Soleur's agents can no longer slip a GitHub issue onto your backlog without saying why it matters to a user, even when the filing is buried inside a wrapped shell command. The guard now reads commands the way the shell does, so every new issue arrives with its reason attached.
