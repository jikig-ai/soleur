# Spec: Web Platform — Cloud CLI Engine

**Issue:** #297
**Branch:** feat/web-platform-ux
**Date:** 2026-03-16
**Status:** Draft

## Problem Statement

Tentative users find the Claude Code plugin model a barrier to adoption. Two validated friction points:

1. **Install friction** — requiring CLI plugin installation deters both technical and non-technical founders
2. **Visibility gap** — the terminal is the wrong surface for browsing knowledge-base, reviewing plans, and monitoring agent execution

The current CLI plugin has 280+ PRs of engineering producing 62 agents, 57 skills, and a compounding knowledge-base loop. 65-70% of agent value comes from CLI-native orchestration (Task, Skill, Bash, git tools). Any platform shift must preserve this.

## Goals

- G1: Provide web/mobile/desktop access to Soleur's domain leaders and autonomous execution loop
- G2: Preserve 100% of CLI-native orchestration value by running Claude Code instances server-side
- G3: Enable founders to chat with domain leaders, approve plans, and monitor autonomous execution through a browser
- G4: Make the compounding knowledge-base browsable and searchable via web UI
- G5: Implement BYOK (Bring Your Own Key) pricing — users provide Anthropic API key, Soleur charges for platform access

## Non-Goals

- NG1: Rewriting agents/skills as web-native API calls (Cloud CLI Engine avoids this)
- NG2: Replacing the CLI plugin (it becomes a power-user/developer tool)
- NG3: API pass-through pricing (BYOK eliminates this risk)
- NG4: Mobile-native apps (responsive web first, native apps are future scope)
- NG5: Engineering domain agents in MVP web (code writing, git ops remain CLI-native — business domains are the web priority)

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | Chat interface for conversing with domain leaders (CMO, CTO, CFO, CPO, CRO, COO, CLO, CCO) | P0 |
| FR2 | Plan review UI — structured view of proposed plans with approve/reject/modify actions | P0 |
| FR3 | Execution monitoring — streaming output from running agents, progress indicators | P0 |
| FR4 | Knowledge-base viewer — browse and search brainstorms, specs, plans, learnings | P0 |
| FR5 | Inbox / notifications — agent completions, review requests, status changes | P0 |
| FR6 | BYOK key management — secure storage and injection of user's Anthropic API key | P0 |
| FR7 | User authentication and workspace management | P0 |
| FR8 | Push/email notifications for review gates | P1 |
| FR9 | Mobile-responsive layout | P1 |
| FR10 | Conversation history and context persistence across sessions | P1 |

## Technical Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| TR1 | Cloud-hosted Claude Code instances with multi-tenant namespace isolation | P0 |
| TR2 | Web-to-CLI bridge protocol for controlling and observing running Claude Code instances | P0 |
| TR3 | Real-time streaming from CLI instance to web client (SSE or WebSocket) | P0 |
| TR4 | Knowledge-base API layer for web access to git-backed markdown files | P0 |
| TR5 | Secure BYOK key storage (encrypted at rest, injected at runtime) | P0 |
| TR6 | User workspace isolation on shared instances | P0 |
| TR7 | Session management — persistent workspaces with concurrent execution support | P1 |
| TR8 | Tech stack selection (deferred from brainstorm — Next.js + Supabase + Stripe or Rails under evaluation) | P0 |

## Open Questions

1. Claude Code server-side licensing terms
2. Shared instance security model (container namespaces vs. Linux user isolation)
3. Knowledge-base storage: git-backed with API layer vs. database migration
4. Pricing validation: what will users pay for platform access?
5. Cowork Plugins differentiation strategy

## Acceptance Criteria

- [ ] User can sign up, provide BYOK Anthropic API key, and start a conversation with a domain leader
- [ ] Agent executes on cloud CLI instance with full orchestration capabilities (Task, Skill, Bash, git)
- [ ] User can browse knowledge-base through web UI
- [ ] User receives notifications when agent needs review
- [ ] Plan approval/rejection flows work through web UI
- [ ] Streaming agent output is visible in real-time
