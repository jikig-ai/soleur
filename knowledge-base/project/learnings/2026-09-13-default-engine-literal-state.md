---
title: "Shared literal defaults need widened UI state"
date: 2026-09-13
category: workflow
---

Exporting a default engine as an `as const` value is useful for identity
alignment, but React infers `useState(DEFAULT_AGENT_ENGINE_ID)` as the literal
type. Any selector that must accept future engine IDs must declare
`useState<string>(DEFAULT_AGENT_ENGINE_ID)` explicitly.
