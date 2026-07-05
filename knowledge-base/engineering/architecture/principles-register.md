# Architecture Principles Register

Queryable index of architectural principles. Each principle links to its canonical source — rationale and full context live there. This register enables structured references in ADRs and automated compliance checking during PR review.

> **Sibling registers:** [`domain-model.md`](./domain-model.md) (domain entities + business-rule invariants), [`nfr-register.md`](./nfr-register.md) (non-functional requirements). Use this register for *how we build*; use `domain-model.md` for *what the product's entities are and the rules that govern them* (e.g. `AP-015`'s workspace owner-canary principle maps to `domain-model.md` rules `BR-WS-3`/`BR-WS-4`).

## Principles

| ID | Title | Canonical Source | Enforcement | Related NFRs |
|----|-------|-----------------|-------------|--------------|
| AP-001 | Terraform-only infrastructure provisioning | AGENTS.md (Hard Rules) | hook | NFR-016, NFR-019 |
| AP-002 | No SSH state mutation | AGENTS.md (Hard Rules) | advisory | NFR-014 |
| AP-003 | R2 remote backend for Terraform state | AGENTS.md (Hard Rules) | advisory | NFR-027 |
| AP-004 | Agent-native parity | AGENTS.md (Hard Rules) | skill | — |
| AP-005 | Email for ops / Slack for internal release announcements / Discord for community | AGENTS.md (Hard Rules) + ship/references/ci-workflow-authoring.md (#5079 carve-out) | hook | — |
| AP-006 | All knowledge in committed repo files | AGENTS.md (Hard Rules) | advisory | — |
| AP-007 | Exhaust automation before manual steps | AGENTS.md (Hard Rules) | advisory | — |
| AP-008 | Doppler for all secrets management | AGENTS.md (Hard Rules) | advisory | NFR-014, NFR-027 |
| AP-009 | Never delete user data | constitution.md (Architecture/Never) | advisory | NFR-030 |
| AP-010 | Convention over configuration for paths | constitution.md (Architecture/Prefer) | advisory | — |
| AP-011 | ADRs for architecture decisions | constitution.md (Architecture/Always) | skill | — |
| AP-012 | New vendor checklist | constitution.md (Architecture/Always) | skill | NFR-026, NFR-027 |
| AP-013 | Process-local state for runner sessions | ADR-027 | skill | NFR-019 |
| AP-014 | Platform-loop / per-founder cohabitation boundary | ADR-033 | hook | NFR-014 |
| AP-015 | Always-enforce-workspace (every user owns a guaranteed 1-member personal workspace; the owner-membership canary) | ADR-044, ADR-073 | advisory | NFR-014 |
| AP-016 | GHCR read:packages credential — the machine-account PAT is the INTERIM single-operator exception to `hr-github-app-auth-not-pat`; the multi-tenant target is a control-plane Inngest minter issuing 1h `packages:read` App-installation tokens (PAT has no creation API → does not scale to zero-touch tenant onboarding) | ADR-087 (supersedes ADR-086 D1), ADR-082 | advisory | NFR-014 |

## Enforcement Tiers

| Tier | Description | Mechanism |
|------|-------------|-----------|
| hook | Mechanically enforced — violation is blocked | Pre-commit hooks, guardrails.sh |
| skill | Semantically checked — violation is flagged | Skill gates, agent review |
| advisory | Documentation only — relies on awareness | Manual review, AGENTS.md loaded every turn |

## Notes

- **AP-011 — ADR shape rubric.** AP-011's application to new ADRs follows the terse/rich shape rubric in [`plugins/soleur/skills/architecture/references/adr-template.md`](../../../plugins/soleur/skills/architecture/references/adr-template.md) under `## Choosing the shape`. Default is terse (3 sections); use rich (8 sections) when any rubric trigger applies.
- **Canonical-source rubric.** New AP rows pick `Canonical Source` by precedence: `AGENTS.md (Hard Rules)` for mechanical / always-loaded rules; `constitution.md (Architecture/…)` for foundational design tenets; `ADR-NNN` for architectural decisions with a documented migration path. AP-013 → ADR-027 is the first instance of the third tier — extend rather than collapse the precedent when future ADR-sourced APs land.
