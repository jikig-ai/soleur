---
title: "Evaluate Analytics Solutions for soleur.ai"
feature: feat-analytics-eval
issue: "#198"
date: 2026-02-21
status: draft
---

# Evaluate Analytics Solutions for soleur.ai

## Problem Statement

soleur.ai has zero analytics visibility. There is no data on page views, referral sources, geographic distribution, or device types. The marketing audit (#193) identified this gap but deferred implementation pending evaluation.

## Goals

- FR1: Compare at least 3 privacy-respecting analytics solutions on price, privacy, features, and GitHub Pages compatibility
- FR2: Recommend a solution with documented rationale
- FR3: Add chosen analytics script to the docs site base layout
- FR4: Update all affected legal documents to accurately reflect analytics usage

## Non-Goals

- Self-hosting analytics infrastructure
- Custom event tracking or conversion funnels (future enhancement)
- Cookie consent banner (cookie-free solution avoids this)
- A/B testing or experimentation platform

## Technical Requirements

- TR1: Analytics solution must operate without cookies (no consent banner required)
- TR2: Script must be under 5 KB to minimize page load impact
- TR3: Must work with GitHub Pages (client-side only, no server-side processing)
- TR4: Legal documents must be updated in both locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`)
- TR5: GDPR Article 30 register must include new processing activity

## Functional Requirements

- FR1: Page views, unique visitors, referrers, geographic distribution, device types
- FR2: Dashboard accessible without self-hosting
- FR3: Data retention beyond 7 days

## Acceptance Criteria

See plan: `knowledge-base/plans/2026-02-21-research-analytics-solutions-plan.md`
