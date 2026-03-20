# Web Platform: Cloud CLI Engine Approach

**Date:** 2026-03-16
**Status:** Brainstorm complete — ready for planning
**Issue:** #297
**Branch:** feat/web-platform-ux

## What We're Building

A web/mobile/desktop platform where users interact with Soleur domain leaders (CMO, CTO, CFO, etc.) through a browser-based dashboard. The critical architectural decision: **agents execute on cloud-hosted Claude Code instances**, not web-native API calls. The web app is a thin view/control layer over the real CLI engine.

This preserves 100% of the orchestration value (Task/Skill tools, bash, git worktrees, MCP servers, hooks) while solving two validated barriers: install friction and lack of visibility.

### Core User Loop

1. User opens web dashboard, talks to a department head (e.g., CMO) or "co-CEO"
2. Agent proposes a plan with concrete steps
3. User reviews and approves (or modifies)
4. Agent executes autonomously on cloud CLI instance
5. User gets notified at review gates or when execution completes
6. Knowledge-base compounds and is browsable in the dashboard

### MVP Surfaces

- **Chat interface** — Conversation with domain leaders, plan creation, approval flows
- **Knowledge-base viewer** — Browse brainstorms, specs, plans, learnings. Search across all artifacts
- **Inbox / notifications** — What agents have done, what needs attention, execution status
- **Plan review UI** — Structured view of proposed plans with approve/reject/modify actions
- **Execution monitoring** — Watch agent work in progress, see streaming output
- **Notifications** — Push/email when review is needed

## Why This Approach

### Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| **Cloud CLI Engine + Web Dashboard** | **Selected** | Preserves 100% orchestration value, full parity with CLI capabilities |
| Full Web-Native Platform | Rejected | Loses 65-70% of agent value (orchestration tools). Would need to rebuild Task, Skill, Bash, File I/O as web services |
| Knowledge-First Staged | Rejected | Doesn't deliver autonomous execution (the feature users got most excited about). Phase 3 becomes Approach 1 anyway |

### Why Cloud CLI Engine Wins

1. **Orchestration fidelity:** 65-70% of agent value is in CLI tools (CTO assessment). This is the only approach that doesn't lose it.
2. **No rewrite:** Agents and skills work as-is. The web layer is additive, not a rewrite.
3. **Codex portability scan confirms:** Agents are 67.7% portable (prose), skills are 57.9% non-portable (orchestration). Cloud CLI sidesteps portability entirely.
4. **Moat preservation:** Knowledge-base compound loop, cross-domain coherence, and workflow orchestration all survive because the engine is unchanged.

### User Feedback That Drove This

Source: Conversations with tentative users (mix of technical and non-technical founders).

- **Both** install friction and visibility/UX gap are blockers (equal weight)
- Users want: KB viewer, agent launcher, inbox, **and autonomous execution with human review gates**
- They expect full parity with CLI capabilities
- Equal pull from both technical and non-technical segments
- Key unvalidated signal: **willingness to pay is absent from feedback** (CPO flag)

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Cloud CLI Engine** — agents run on cloud-hosted Claude Code instances | Preserves 100% orchestration value. CTO: "65-70% of value is CLI-native tools." |
| 2 | **Shared instance + namespace isolation** — multi-tenant CLI instances | Lowest cost. Security isolation is the main complexity. |
| 3 | **BYOK (Bring Your Own Key)** — users provide their Anthropic API key | Eliminates API pass-through cost risk (CFO flag). Soleur charges for platform only. Pure margin. |
| 4 | **Web is the primary product** — CLI becomes power-user/developer tool | Direct response to user feedback. CLI continues as open-source plugin. |
| 5 | **Full dashboard MVP** — chat + KB + inbox + plan review + execution monitoring | Users want the complete loop, not a partial view. |
| 6 | **Tech stack deferred to planning** — previously Next.js + Supabase + Stripe, reconsidering | Don't lock in stack during brainstorm. Rails is also on the table. |

## Open Questions

1. **Pricing validation** — Users want this, but will they pay? BYOK model means Soleur charges for platform access. What price point? ($19/month? $49/month? Usage-based?) CPO: "No pricing signal in the feedback described."
2. **Shared instance security** — How to isolate user workspaces on shared CLI instances? Container namespaces? Linux user isolation? What's the attack surface?
3. **Knowledge-base storage** — Keep git-backed (complex for web, but preserves branching/history) or move to database (simpler web UX, loses git semantics)?
4. **Session management** — Persistent user workspace vs. ephemeral sessions with KB sync? How to handle concurrent agent executions?
5. **Claude Code server-side licensing** — Can Claude Code be run server-side in a hosted product? What are the terms?
6. **Cowork Plugins positioning** — 5/8 domains face first-party competition. How does the web platform differentiate? (Moat: compounding KB, cross-domain coherence, orchestration depth)
7. **Non-technical founder segment** — Do they need different agents/prompts than technical founders? Different onboarding?
8. **Mobile experience** — Is mobile a real use case or just "nice to have"? What do founders actually do on mobile?

## Domain Leader Assessments

### CPO Assessment
- Business validation (2026-03-12) gave PIVOT verdict — demand evidence flagged
- Web platform spec does not exist — no architecture doc, no prototype
- "Building a web platform is building a second product" — doubles maintenance surface for solo founder
- User feedback is strong on "CLI is a deterrent" but **willingness to pay is unvalidated**
- External user validation: 1-2 informal conversations total, below 5-person threshold

### CTO Assessment
- 65-70% of agent value depends on CLI-native tool infrastructure
- Four Claude Code-specific primitives block portability: Task/subagent spawning, Skill tool chaining, AskUserQuestion, $ARGUMENTS interpolation
- Cloud CLI Engine is the only approach that preserves this without reimplementation
- Anthropic Messages API does not provide Skill, Task, Bash, Read, Write, Edit, Glob, or Grep tools
- Knowledge-base architecture mismatch: git-based → needs either git backend or database for web visibility

### Key Learnings (from knowledge-base/learnings/)
- **Platform risk materialization (2026-02-25):** Thesis and revenue plan are separable. Horizontal features get absorbed by platform owners. Vertical depth and cross-platform presence survive.
- **Codex portability scan (2026-03-10):** Agents 67.7% portable (prose), skills 57.9% non-portable (orchestration). Cloud CLI Engine sidesteps portability entirely.
- **Agent context-blindness (2026-02-22):** Agents without full project context produce misaligned outputs. Cloud CLI preserves full context.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|-----------|
| Web-to-CLI bridge protocol | Engineering | No defined protocol for web dashboard to control/observe a running Claude Code instance |
| User workspace isolation | Engineering | Multi-tenant shared instances need security boundaries |
| Real-time streaming to web client | Engineering | Agent output needs to stream to browser (SSE/WebSocket from CLI instance) |
| Knowledge-base web API | Engineering | KB is git files — needs an API layer for web browsing/search |
| Authentication + BYOK key management | Engineering | Secure storage and injection of user's Anthropic API keys |
| Pricing model validation | Product | Users want this but willingness to pay is unvalidated |
