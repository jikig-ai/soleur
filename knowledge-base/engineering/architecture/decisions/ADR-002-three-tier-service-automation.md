---
adr: ADR-002
title: Three-Tier Service Automation
status: active
date: 2026-03-27
---

# ADR-002: Three-Tier Service Automation

## Context

Founders validated service automation as high-value. Server-side Playwright was rejected as HIGH risk by CTO, CLO, and CFO due to SSRF risk, agency liability, and 2-4x infra cost.

## Decision

Three-tier approach — Tier 1 (API + MCP, ~80% of services via direct REST APIs with BYOK tokens), Tier 2 (Local Playwright, ~15% via desktop native app on user's machine), Tier 3 (Guided instructions, ~5% with deep links and review gates as web/mobile fallback).

## Consequences

API-first eliminates SSRF risk, agency liability, and 2-4x infra cost. Desktop app justified solely for local browser automation capability. 5% of services have degraded UX with guided instructions instead of automation.
