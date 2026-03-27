---
adr: ADR-020
title: Exact Version Pinning for Agent SDK
status: active
date: 2026-03-27
---

# ADR-020: Exact Version Pinning for Agent SDK

## Context

Agent SDK uses unstable API versions (unstable_v2_createSession) that can break between patch releases. Caret ranges (^0.2.80) allow surprise API breakage.

## Decision

Pin Agent SDK to exact version (e.g., 0.2.80, not ^0.2.80). Enables reproducible builds. Allows deliberate evaluation of new SDK versions before upgrading.

## Consequences

No surprise breakage from SDK updates. Requires manual version bump when upgrading. May miss security patches if not actively monitoring releases.
