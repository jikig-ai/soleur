# Learning: pre-load prospect facts into domain-leader prompts in prospect-anchored brainstorms

## Problem

A brainstorm was anchored on a single prospect's quote: a 10-person team prospect saying they want Soleur but need to "keep some expertise where it's needed." Six domain leaders (CPO, CMO, CRO, CFO, CTO, CLO) were spawned in parallel with the quote and the founder's framing. The CPO assessment came back with a strong, well-argued reframe: "this is a solo founder describing how they buy expertise on retainer; treat as a solo-ICP feature, not a second segment." The reframe was confidently sourced and would have redirected the entire brainstorm.

The reframe was invalidated by one fact the founder volunteered after seeing the CPO output: the prospect has a real cross-functional team — CPO, designer, 3 SWEs, 2 SREs as named employees. That fact made the "retainer specialists" reframe incoherent.

## Root Cause

The CPO's prompt contained the prospect's quote and the founder's framing decision, but **not the verifiable composition of the prospect's team**. With the quote alone, "keep some expertise where it's needed" admits two readings: (a) coordinate with retainer specialists (solo signal) and (b) coordinate with employed specialists (team signal). The CPO picked (a), reasoned cleanly from there, and was wrong because the founder knew (b) but never told the leaders.

## Solution

In prospect-anchored brainstorms, before spawning domain leaders, gather (and pre-load into every leader's prompt):

1. **Prospect composition** — headcount, named roles, employment relationship (employees vs. retainer / contract / advisor)
2. **Stated use case** — what work they want Soleur to do, in their words
3. **Context that disambiguates ambiguous quotes** — e.g., "the prospect's team includes a CPO and 2 SREs" pre-empts the "they're describing retainers" reading

A 30-second pre-flight checklist on prospect facts costs nothing and prevents one or more leaders from anchoring on the wrong reading and producing assessments the founder must then unwind.

## Key Insight

Domain leaders are good at reasoning from facts and bad at distinguishing fact from interpretation when both arrive in the same prompt. Quotes are interpretation; team composition is fact. Send facts.

## Application to brainstorm skill

The brainstorm skill's Phase 0.5 (Domain Leader Assessment) and the Domain Config table substitute `{desc}` into each leader's task prompt. When `{desc}` is a prospect quote, the leader gets the quote without the surrounding factual context. The skill could be improved by adding a pre-flight question in Phase 0 ("if the feature is anchored on a specific prospect/customer, what facts do we know about them?") and threading that fact block into every Phase 0.5 task prompt alongside `{desc}`. This is a candidate skill edit; tracking inline rather than auto-applying because it touches the brainstorm skill instructions and warrants a deliberate edit pass.

## Tags

category: best-practices
module: brainstorm-skill
related: brainstorm Phase 0.5, domain-leader prompts, prospect-anchored features

## Session Errors

None — the founder's clarification arrived before any work was done on CPO's reframe. The pattern is captured proactively, not reactively.
