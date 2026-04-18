# Architecture Principles Register

Queryable index of architectural principles. Each principle links to its canonical source — rationale and full context live there. This register enables structured references in ADRs and automated compliance checking during PR review.

## Principles

| ID | Title | Canonical Source | Enforcement | Related NFRs |
|----|-------|-----------------|-------------|--------------|
| AP-001 | Terraform-only infrastructure provisioning | AGENTS.md (Hard Rules) | hook | NFR-016, NFR-019 |
| AP-002 | No SSH state mutation | AGENTS.md (Hard Rules) | advisory | NFR-014 |
| AP-003 | R2 remote backend for Terraform state | AGENTS.md (Hard Rules) | advisory | NFR-027 |
| AP-004 | Agent-native parity | AGENTS.md (Hard Rules) | skill | — |
| AP-005 | Email for ops / Discord for community | AGENTS.md (Hard Rules) | hook | — |
| AP-006 | All knowledge in committed repo files | AGENTS.md (Hard Rules) | advisory | — |
| AP-007 | Exhaust automation before manual steps | AGENTS.md (Hard Rules) | advisory | — |
| AP-008 | Doppler for all secrets management | AGENTS.md (Hard Rules) | advisory | NFR-014, NFR-027 |
| AP-009 | Never delete user data | constitution.md (Architecture/Never) | advisory | NFR-030 |
| AP-010 | Convention over configuration for paths | constitution.md (Architecture/Prefer) | advisory | — |
| AP-011 | ADRs for architecture decisions | constitution.md (Architecture/Always) | skill | — |
| AP-012 | New vendor checklist | constitution.md (Architecture/Always) | skill | NFR-026, NFR-027 |

## Enforcement Tiers

| Tier | Description | Mechanism |
|------|-------------|-----------|
| hook | Mechanically enforced — violation is blocked | Pre-commit hooks, guardrails.sh |
| skill | Semantically checked — violation is flagged | Skill gates, agent review |
| advisory | Documentation only — relies on awareness | Manual review, AGENTS.md loaded every turn |

## Notes

- **AP-011 — ADR shape rubric.** AP-011's application to new ADRs follows the terse/rich shape rubric in [`plugins/soleur/skills/architecture/references/adr-template.md`](../../../plugins/soleur/skills/architecture/references/adr-template.md) under `## Choosing the shape`. Default to terse (3 sections); use rich (8 sections) when any one of the 5 rubric triggers applies (cross-cutting, material cost, NFR-moving, principle deviation, teeth-bearing alternatives).
