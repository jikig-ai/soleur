# Learning: Business Validation Workshop Agent and Product Domain Leader Pattern

## Problem

Soleur had no structured way to validate business ideas before investing engineering effort. Users could brainstorm features, but there was no gate to assess whether the underlying business hypothesis was sound. Additionally, the Product domain had agents (UX designer, product analyst) but no domain leader to coordinate them, unlike Marketing (CMO) and Engineering (CTO).

Two issues needed solving together: a business validation workshop agent (#141) and a CPO domain leader (#183). Building them separately would have required two PRs touching the same routing code in brainstorm Phase 0.5.

## Solution

### Workshop Agent: brand-architect as Template

The `business-validator` agent reuses the brand-architect workshop pattern:

1. **Detect-and-resume** -- On entry, check for an existing validation document. If found, parse which gates are complete and resume from the next incomplete gate. This prevents lost work if a session is interrupted.
2. **6 sequential gates** -- Problem Statement, Customer Definition, Competitive Landscape, Demand Evidence, Business Model, Minimum Viable Scope. Each gate has explicit kill criteria (e.g., "no evidence of willingness to pay" at the Business Model gate).
3. **One question at a time** -- Each gate asks a single focused question, waits for the user's answer, then either advances or triggers the override flow (revise/override/end).
4. **Atomic writes** -- After each gate completes, the validation document is written immediately. Progress is never held only in memory.
5. **Heading contract** -- Fixed `##` headings (`## Problem Statement`, `## Customer Definition`, etc.) enable downstream tools to parse the document.

### Domain Leader: CMO as Template

The `cpo` agent follows the domain leader contract (Assess/Recommend/Delegate/Review) established by the CMO. The routing decision tree maps request types to product domain agents:

- Business viability -> business-validator
- User experience -> ux-designer
- Market/competitive analysis -> product-analyst
- Ambiguous -> recommend and let user choose

### Brainstorm Phase 0.5 Integration

Added a product strategy assessment question to brainstorm Phase 0.5, alongside the existing brand identity detection. The routing uses LLM semantic assessment -- the brainstorm command asks "Does this feature description suggest the user needs to validate a business hypothesis?" and interprets the answer semantically. This is NOT keyword detection; the LLM evaluates intent.

When product strategy is detected, the user is offered three options: start the validation workshop (STOP -- exits brainstorm), include CPO perspective (continues brainstorm with product input), or skip.

The validation workshop option uses a STOP pattern: if the user chooses it, the brainstorm ends and delegates entirely to the business-validator. This differs from the "include perspective" option, which adds an advisor to the ongoing brainstorm.

### Sibling Disambiguation Updates

Adding business-validator required updating descriptions for both existing product agents (ux-designer, product-analyst) and the new CPO. All four agents in the product domain now cross-reference each other. This is the same graph property documented in the three-way-agent-disambiguation learning.

## Key Insight

**Workshop agents are a reusable archetype.** The brand-architect established a pattern (detect-resume, sequential gates, one-question-at-a-time, atomic write, heading contract) that transferred directly to business validation with zero structural changes. The only differences are domain-specific: gate names, kill criteria, and output document format. Any future interactive assessment agent (security audit, architecture review, compliance check) should start from this template.

**LLM semantic routing vs. keyword matching matters for correctness.** The brainstorm Phase 0.5 routing was incorrectly described as "keyword detection" during implementation. The user corrected this -- it uses LLM semantic assessment questions, which is a deliberate design choice. Keywords are fragile (false positives on "brand new"), while semantic assessment leverages the LLM's comprehension. This distinction matters when documenting the system and when adding new domains: you add an assessment question, not a keyword list.

**Combining related issues in one PR reduces routing-code churn.** The CPO and business-validator touched the same brainstorm Phase 0.5 section. Shipping them together avoided a merge conflict on the routing code and ensured the domain leader was available to route to the workshop agent from day one.

## Session Errors

1. **Task list lost after context compaction.** TaskUpdate for task #6 returned "Task not found" because context compaction cleared the in-memory task list. Workaround: re-created the task. Lesson: task IDs are ephemeral within a session; do not assume they persist across compaction boundaries.

2. **Agent count discrepancy pre-existed.** README.md claimed 45 agents, plugin.json said 46, and the actual count was 48. This was not introduced by this session -- it accumulated across parallel worktrees. The counts were corrected as part of this PR, but the root cause (parallel worktrees each incrementing from stale baselines) remains. Agent counts should be reconciled at merge time by counting actual agent files, not by incrementing the previous number.

3. **Mischaracterized routing mechanism.** The brainstorm Phase 0.5 routing was described as "keyword detection" in a task description. The user corrected this to "LLM semantic assessment." The mechanism was already correct in the code -- the error was in the documentation/description layer. Lesson: when documenting how LLM-hosted logic works, verify against the actual prompt text, not a mental model of how it "probably" works.

## Tags

category: implementation-patterns
module: agents/product, commands/brainstorm
symptoms: no business validation gate, product domain without coordinator, workshop pattern not yet reused
