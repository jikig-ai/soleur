# Spec: Dashboard Agent Identity and Team Customization

**Date:** 2026-04-13
**Branch:** `feat-dashboard-agent-identity`
**Brainstorm:** [2026-04-13-dashboard-agent-identity-brainstorm.md](../../brainstorms/2026-04-13-dashboard-agent-identity-brainstorm.md)
**Related:** #1871 (named domain leaders)

## Problem Statement

The Command Center dashboard shows a generic "Soleur" badge on all conversations and messages instead of domain-specific badges (CTO, CMO, etc.). The Soleur badge was designed for system notifications only. Additionally, a non-functional profile icon exists in the top-right corner, and there is no way for users to visually personalize their AI team members — reducing emotional connection with the product.

## Goals

1. Every domain leader message and conversation displays a domain-specific badge
2. Soleur badge appears only on system notifications and unrouted messages
3. Dead profile icon removed from UI
4. Users can customize leader icons via curated library or custom upload
5. Icons stored git-committed for data portability

## Non-Goals

- Personality customization for leaders (#1879)
- Custom specialist agent icons (only domain leaders)
- Custom titles (names are customizable per #1871, titles stay fixed)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Extend `DomainLeader` type in `domain-leaders.ts` with `icon`, `color`, and `defaultIcon` fields |
| FR2 | Add `leader_id` field to message data model for per-message attribution |
| FR3 | Render domain-specific badge on conversation list items using `conversation.domain_leader` |
| FR4 | Render per-message leader badge in `MessageBubble` component using `message.leader_id` |
| FR5 | Render leader badges on dashboard leader cards |
| FR6 | Restrict Soleur "S" badge to messages where `leader_id` is `system` or null (unrouted) |
| FR7 | Remove non-functional profile icon from top-right corner |
| FR8 | Add icon picker to existing team settings page (curated library + upload) |
| FR9 | Store uploaded icons in `knowledge-base/` (git-committed) |
| FR10 | Ship domain-appropriate default icons for all 8 leaders |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Icon uploads constrained: max dimensions, max file size, accepted formats (PNG, SVG, WebP) |
| TR2 | Icons must render correctly on dark backgrounds (neutral-900) |
| TR3 | Per-message `leader_id` must support multi-leader threads (tag-and-route readiness) |
| TR4 | Custom icons accessible to web platform (via KB API or build-time copy) |
| TR5 | Icon library assets bundled with the web platform build |

## Delivery Plan

- **PR 1:** Data model changes + default badge rendering + profile icon removal + Soleur badge restriction
- **PR 2:** Customization UI (icon picker, upload flow, curated library) on existing team settings page
