# Learning: Cross-Domain Disambiguation Is Bidirectional

## Problem

When adding the Finance domain (4 agents: CFO, budget-analyst, revenue-analyst, financial-reporter), the initial implementation correctly added disambiguation sentences FROM Finance agents TO existing agents (e.g., revenue-analyst references pipeline-analyst, budget-analyst references ops-advisor). But it missed the reverse direction -- existing agents in Sales, Operations, and Marketing were not updated to reference Finance agents back.

Code review caught this as a HIGH priority violation of the constitution rule: "disambiguation is a graph property."

## Solution

When adding agent N to a domain that borders existing domains, update ALL agents with overlapping scope in BOTH directions:

1. **New agents reference existing ones** (done naturally during creation)
2. **Existing agents reference new ones** (easy to miss -- requires reading adjacent domain agents)

For the Finance domain, the fixes were:
- `cro.md` description: added "Use cfo for company-level financial analysis and budgeting"
- `cro.md` Sharp Edges: added "Defer company-level revenue analysis (P&L, cash flow) to the CFO"
- `coo.md` description: added "Use cfo for financial analysis and budgeting"
- `coo.md` Sharp Edges: added "Defer financial analysis, budgeting, and revenue modeling to the CFO"
- `pricing-strategist.md` description: added "Use revenue-analyst for company-level revenue tracking and P&L modeling"
- `ops-advisor.md` description: added "use cfo for financial analysis and budgeting" (done during initial implementation)

## Key Insight

Disambiguation is a graph property, not a node property. Adding one node to the graph requires updating all adjacent nodes, not just the new one. The natural workflow (writing new files, then moving on) biases toward forward references only. Make the reverse-reference pass a mandatory final step in the adding-new-domain checklist.

## Tags
category: integration-issues
module: agents
