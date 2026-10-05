---
title: "fix: restore the release pipeline"
---

<!-- The fence below is deliberately NEVER CLOSED. An odd fence count is routine in a pasted
     PR body, and the parity toggle would otherwise leave every later line inside a block
     that never ends and drop it, at exit 1, with no note. This comment carries none of the
     report vocabulary: fixture prose is matched too. -->

# fix: restore the release pipeline

## Repro

```yaml
retries: 3

## What happened

The 2026-08-16 apex outage took the production site down for ~8h15m.
