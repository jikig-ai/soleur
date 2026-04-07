# Status Page Setup Spec

**Issue:** TBD
**Branch:** feat-statuspage
**Brainstorm:** [2026-04-07-statuspage-brainstorm.md](../../brainstorms/2026-04-07-statuspage-brainstorm.md)

## Problem Statement

Soleur has no public incident communication channel. When downtime occurs, there is no way for users or prospects to check service status independently. BetterStack (already our uptime monitoring provider) offers a free-tier status page that integrates natively with existing monitors.

## Goals

- G1: Activate a public status page showing curated service health
- G2: Zero incremental cost (free tier only)
- G3: Auto-populate status from existing BetterStack uptime monitors

## Non-Goals

- NG1: Custom domain (status.soleur.ai) -- deferred to first paying customer
- NG2: White-label or custom branding -- deferred
- NG3: Incident communication runbooks or automation

## Functional Requirements

- FR1: Status page shows curated user-facing service monitors (Website, API)
- FR2: Status page excludes internal infrastructure monitors
- FR3: Status page is publicly accessible via BetterStack subdomain
- FR4: Service status auto-updates from existing uptime monitors

## Technical Requirements

- TR1: No code changes required -- BetterStack dashboard configuration only
- TR2: Update expenses.md to document status page activation
- TR3: No DNS changes needed (using BetterStack subdomain)
