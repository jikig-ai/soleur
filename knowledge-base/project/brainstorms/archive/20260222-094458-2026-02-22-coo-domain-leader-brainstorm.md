---
topic: COO Domain Leader for Operations
date: 2026-02-22
status: complete
issue: "#182"
---

# COO Domain Leader Brainstorm

## What We're Building

A COO (Chief Operating Officer) domain leader agent that orchestrates the operations domain (ops-advisor, ops-research, ops-provisioner). The COO follows the CTO's lighter 3-phase pattern (Assess, Recommend/Delegate, Sharp Edges) rather than the CMO's full 4-phase pattern. It hooks into brainstorm Phase 0.5 domain detection for automatic consultation when operational decisions are involved.

Additionally, removing the `/soleur:marketing` standalone skill to make all domain leaders consistent -- entry exclusively via brainstorm domain detection.

## Why This Approach

- **CTO's 3-phase pattern over CMO's 4-phase:** With only 3 specialist agents (vs CMO's 11), a separate Review phase adds overhead without proportional value. The CTO already validates this pattern works well.
- **Brainstorm detection only (no standalone skill):** Consistency with CTO. The user explicitly requested removing `/soleur:marketing` for the same reason -- "It should be 1 and we should actually remove the skill entry point for CMO so we are consistent across the board."
- **Check ops data files during assess phase:** Start narrow with expenses.md and domains.md. Intent to grow toward enterprise-scale authority (processes, vendor management, compliance) over time.

## Key Decisions

1. **Name: COO** -- Consistent with CMO/CTO naming convention
2. **3-phase pattern** -- Assess, Recommend/Delegate, Sharp Edges (no Review phase)
3. **Entry point: brainstorm detection only** -- No standalone `/soleur:operations` skill
4. **Remove `/soleur:marketing` skill** -- Consistency across all domain leaders
5. **Assess phase checks ops data files** -- expenses.md and domains.md
6. **Broader detection triggers** -- Vendor selection, tool provisioning, expense tracking, process changes, infrastructure procurement
7. **Sharp Edges section** -- Defer architecture to CTO, recommend what to procure not how to configure

## Open Questions

- Future expansion to encompass enterprise-scale operations (processes, vendor management, compliance)
- Consider table-driven refactor of Phase 0.5 at 5+ domains
