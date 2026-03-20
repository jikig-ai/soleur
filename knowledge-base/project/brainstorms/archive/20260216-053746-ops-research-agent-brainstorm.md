# Brainstorm: ops-research Agent

**Date:** 2026-02-14
**Status:** Complete
**Participants:** Jean + Claude

## What We're Building

An operations research agent (`ops-research`) that investigates domains, hosting, tools/SaaS, and cost optimization opportunities. It complements the existing `ops-advisor` (ledger/tracking) by handling the research and comparison phase. The agent uses browser automation to check availability and navigate to checkout, but stops before purchase for human confirmation. After purchase, it auto-invokes `ops-advisor` to record the transaction.

## Why This Approach

The ops-advisor was deliberately consolidated from 3 planned agents into 1 because they all performed the same operation (read/update structured data). The ops-research agent has genuinely different behavior -- web research, browser automation, comparison analysis -- so it justifies being a separate agent. It follows the "split when it hurts" principle: ops-advisor tracks, ops-research investigates.

## Key Decisions

1. **Location:** `plugins/soleur/agents/operations/ops-research.md` -- operations-only, not cross-domain research
2. **Scope:** All four research domains: domains, hosting, tools/SaaS evaluation, cost optimization
3. **Browser automation:** Uses `agent-browser` CLI for interactive research (availability checks, checkout navigation)
4. **Handoff:** Automatic -- after user confirms purchase, ops-research invokes ops-advisor as sub-agent to record
5. **Structure:** Phased with confirmation gates: Research -> Compare -> Present -> Navigate -> Confirm -> Record
6. **Human gate:** Agent navigates to checkout but STOPS before the buy button. User confirms purchase manually.
7. **v2 future:** Budget system with spending caps for agent-initiated purchases (not in scope for v1)

## Phased Workflow

### Phase 1: Context
- Read `knowledge-base/ops/expenses.md` and `domains.md` to understand existing infrastructure
- Understand what the user already has before recommending

### Phase 2: Research
- Use WebSearch for initial research (pricing, alternatives, reviews)
- Use WebFetch for specific provider pages
- Compile options into a comparison

### Phase 3: Present
- Show structured comparison (table format)
- Lead with recommendation and explain why
- Ask user which option to pursue

### Phase 4: Navigate (requires user confirmation)
- Use agent-browser to navigate to the provider
- Check live availability/pricing
- Navigate to checkout page
- STOP and present final details to user

### Phase 5: Record (after user completes purchase)
- User confirms they completed the purchase
- Auto-invoke ops-advisor to record in expenses.md and/or domains.md

## Open Questions

- None -- ready for planning.

## Design Constraints (from learnings)

- Agent prompt should embed sharp edges only, not general knowledge Claude already has
- If spawning parallel research tasks, provide explicit output schema constraints
- Always read existing ops data before making recommendations
