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
| AP-016 | GHCR read:packages credential — the machine-account PAT is the INTERIM single-operator exception to `hr-github-app-auth-not-pat`. The ADR-088 App-installation-token minter is NOT the viable multi-tenant target: GitHub App installation tokens **cannot pull** private GHCR packages (they authenticate `docker login` but return `denied` on `docker pull`), so the minter is disabled (`GHCR_MINTER_DISABLED=true`) and the forward direction for the pull leg is the self-hosted **zot** registry (ADR-096/#6122), not App-token minting. The interim GHCR pull path MUST recover on a `docker pull` auth-denial, not only a login failure (#6400). | ADR-096 (forward), ADR-088 (superseded minter), ADR-087 D1, ADR-082 | advisory | NFR-014 |
| AP-017 | Additive-only auto-edit boundary — the harness self-edit path may ADD rules (new id) but any edit/deletion of an `hr-*`/`wg-*` rule BODY is human-gated by a per-change, hash-bound WORM ack enforced by the always-run `rule-body-lint` required CI check; the gate's own control surface stays outside the auto-editable set (recursion invariant) | ADR-092 | hook | NFR-014 |
| AP-018 | Two-tier SECURITY DEFINER grant hygiene — the runtime `rls-authz-fuzz` AC8 gate (live `pg_proc.proacl` introspection) is the AUTHORITATIVE class-level guard; the static migration-lint (`test/migration-lint/definer-grants.ts`) is a subordinate, NEVER coverage-bearing pre-filter whose authenticated-callable allowlist IS the AC8 registry, backstopped by a non-vacuity/live-catalog-parity assertion | ADR-112 (amends ADR-101, ADR-111) | skill | NFR-014 |
| AP-019 | Sanctioned transient runtime CF-DNS toggle — the `cron-gh-pages-cert-reissue` routine may transiently flip apex+www `proxied` false→true via the CF API to re-issue the GitHub Pages TLS cert. This is an explicit, NARROW exception to AP-001 (an off-Terraform live-infra mutation), NOT compliance-by-no-drift: the mutation is transient, self-reverting to the Terraform-declared steady state, single-attempt, human-gated, and lock-guarded in v2. So `cron-terraform-drift` and future reviewers see a carve-out rather than an unexplained bypass. | ADR-125 (references ADR-077, ADR-033) | advisory | NFR-016, NFR-019 |

## Enforcement Tiers

| Tier | Description | Mechanism |
|------|-------------|-----------|
| hook | Mechanically enforced — violation is blocked | Pre-commit hooks, guardrails.sh |
| skill | Semantically checked — violation is flagged | Skill gates, agent review |
| advisory | Documentation only — relies on awareness | Manual review, AGENTS.md loaded every turn |

## Notes

- **AP-011 — ADR shape rubric.** AP-011's application to new ADRs follows the terse/rich shape rubric in [`plugins/soleur/skills/architecture/references/adr-template.md`](../../../plugins/soleur/skills/architecture/references/adr-template.md) under `## Choosing the shape`. Default is terse (3 sections); use rich (8 sections) when any rubric trigger applies.
- **Canonical-source rubric.** New AP rows pick `Canonical Source` by precedence: `AGENTS.md (Hard Rules)` for mechanical / always-loaded rules; `constitution.md (Architecture/…)` for foundational design tenets; `ADR-NNN` for architectural decisions with a documented migration path. AP-013 → ADR-027 is the first instance of the third tier — extend rather than collapse the precedent when future ADR-sourced APs land.
