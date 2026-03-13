# Finance Domain Brainstorm

**Date:** 2026-02-22
**Status:** Decided -- no action now
**Participants:** COO, CTO

## What We Explored

Should the Operations domain be renamed to Finance, with Operations becoming a subdomain inside it?

## Why We Decided Against It

**Keep Operations as-is. Add Finance as a separate (7th) domain when finance capabilities are needed.**

### Key Arguments

1. **Different mandates.** Operations answers "what tools are we using and what do they cost?" Finance answers "are we profitable, what's our runway, how should we allocate budget?" These are distinct concerns.

2. **Thin overlap.** The only overlap is "money" -- but tracking a $4.39/month hosting bill (operational awareness) is not the same as modeling quarterly revenue projections (financial analysis).

3. **Domains are cheap.** The plugin loader auto-discovers agent directories. Adding a 7th domain costs the same 6-edit checklist as renaming one. No pressure to consolidate.

4. **Renaming breaks things for no current gain.** Every `soleur:operations:*` reference breaks. The cost is paid now for capabilities that don't exist yet.

### COO Assessment

- Current ops scope is narrow: expense tracking, vendor research, SaaS provisioning.
- "Finance" implies budgeting, revenue forecasting, cash flow, P&L -- capabilities that don't exist.
- Rename creates a naming promise the agents cannot deliver.
- Recommended against unless new finance capabilities are imminent.

### CTO Assessment

- Mechanically straightforward (~30 files, 1-2 days) but high surface area.
- Flat rename better than nesting (nesting creates awkward 4-segment agent names).
- `review.md` and `plan.md` use "operations" to mean DevOps -- those should NOT be renamed.
- No aliasing mechanism exists in the plugin loader; all external references break instantly.

## Future Finance Domain (When Ready)

| Agent | Scope |
|-------|-------|
| `cfo` | Domain leader -- delegates to specialists |
| `budget-analyst` | Budget planning, allocation, burn rate |
| `revenue-analyst` | Revenue tracking, forecasting, projections |
| `financial-reporter` | P&L, cash flow statements, financial summaries |

Operations stays as-is. The CFO can consult the COO's expense data via cross-domain delegation.

## Key Decisions

- Operations domain: keep as-is, no rename
- Finance domain: add as separate 7th domain when capabilities are needed
- No worktree or implementation needed

## Open Questions

- When will finance capabilities be needed? (User estimated 1-2 months)
- Should the CFO have read access to `knowledge-base/ops/expenses.md` or should expense data be duplicated?
