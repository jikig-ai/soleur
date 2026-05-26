---
date: 2026-05-20
type: feature
issue: 9999
branch: feat-fixture-no-observability
---

# Plan — Fixture: No Observability Block

## Overview

Synthetic plan used as a Check 10 fixture. Intentionally omits the `## Observability`
section so the FAIL path is exercised.

## Acceptance Criteria

- [ ] None — fixture only.

## Sharp Edges

- This file MUST NOT contain a `## Observability` heading. Tests grep for its absence.
