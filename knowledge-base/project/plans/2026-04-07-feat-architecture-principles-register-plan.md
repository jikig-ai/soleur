---
title: "feat: Architecture Principles Register"
type: feat
date: 2026-04-07
---

# Architecture Principles Register

Add a queryable index of architectural principles with IDs (AP-NNN), integrated into the architecture skill, ADR template, and review agent.

Closes #1712

## Overview

Soleur's architectural principles are scattered across AGENTS.md and constitution.md with no structured way to list, reference, or assess them. This feature creates a flat markdown index at `knowledge-base/engineering/architecture/principles-register.md` that assigns IDs to ~12 architecture-only principles and links to their canonical source. No text duplication — the register is an index, not a standalone document.

## Implementation Phases

### Phase 1: Create the Principles Register

Create `knowledge-base/engineering/architecture/principles-register.md` with:

```markdown
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
```

**Files:**

- Create: `knowledge-base/engineering/architecture/principles-register.md`

### Phase 2: Add `principle list` Sub-command to Architecture Skill

Update `plugins/soleur/skills/architecture/SKILL.md`:

1. Add `architecture principle list` row to the sub-command table (line ~17)
2. Add new sub-command section after the `assess` section (after line ~265)

The sub-command reads and displays the principles register table. Minimal logic — read file, output formatted.

**Do NOT update the skill description** — cumulative word count is already at 1,892 (over 1,800 limit). The sub-command table provides discoverability.

**Files:**

- Edit: `plugins/soleur/skills/architecture/SKILL.md`

### Phase 3: Add `## Principle Alignment` to ADR Template

Update `plugins/soleur/skills/architecture/references/adr-template.md`:

Add `## Principle Alignment` section after `## NFR Impacts` and before `## Diagram` in both the YAML frontmatter docs and body sections template.

Also update the `create` sub-command (step 6, line ~86 of SKILL.md) to gather Principle Alignment alongside NFR Impacts — add a new bullet: "**Principle Alignment:** Which principles does this decision align with or deviate from? Read [principles-register.md](./references/../../../knowledge-base/engineering/architecture/principles-register.md) for the register. Reference AP-NNN IDs. Use 'None' if no impact."

Template for the new section:

```markdown
## Principle Alignment

[Which architectural principles does this decision align with or deviate from?
Reference principle IDs from knowledge-base/engineering/architecture/principles-register.md.
Use "None" if no principle impact.

Format: AP-NNN (Title): Aligned | Deviation | N/A — brief note

Example: "AP-001 (Terraform-only): Aligned — new infrastructure uses Terraform.
AP-008 (Doppler secrets): Deviation — uses .env file for local-only dev secret. Exception documented."]
```

**Files:**

- Edit: `plugins/soleur/skills/architecture/references/adr-template.md`

### Phase 4: Extend `assess` to Include Principle Alignment

Update `plugins/soleur/skills/architecture/SKILL.md` assess sub-command:

1. After step 2 ("Read the NFR register"), add: "Read the principles register at `knowledge-base/engineering/architecture/principles-register.md`."
2. After step 5 (NFR category assessment), add step 5b: "Assess each principle. For each AP-NNN, determine: relevant to this feature (yes/no), alignment status (aligned/deviation/N/A), and brief rationale."
3. After step 6 (NFR output table), add a "Principle Alignment" section to the output with the same format as the ADR template.
4. Update step 8 ("Offer to create an ADR") to mention that principle alignment will be pre-filled.

**Files:**

- Edit: `plugins/soleur/skills/architecture/SKILL.md`

### Phase 5: Update Architecture-Strategist Review Agent

Update `plugins/soleur/agents/engineering/review/architecture-strategist.md`:

Add to the "Your evaluation must verify" list (after the ADR check at line ~38):

```markdown
- Read `knowledge-base/engineering/architecture/principles-register.md` if it exists. For PRs that introduce infrastructure changes, new services, data model changes, or cross-boundary integrations, check alignment with relevant principles (AP-NNN). Report deviations as advisory findings (not blockers): "This change may deviate from AP-NNN (Title) — [brief explanation]"
```

Add "Principle Alignment" as a sub-item under "3. Compliance Check" in the structured output (the output already has 5 top-level items: Architecture Overview, Change Assessment, Compliance Check, Risk Analysis, Recommendations):

```markdown
3. **Compliance Check**: Specific architectural principles upheld or violated
   - **Principle Alignment**: Relevant principles from the register checked; deviations noted as advisory
```

**Do NOT change the agent description** — it stays in the body, not the frontmatter.

**Files:**

- Edit: `plugins/soleur/agents/engineering/review/architecture-strategist.md`

## Acceptance Criteria

- [ ] `knowledge-base/engineering/architecture/principles-register.md` exists with ~12 principles in a flat table
- [ ] Each principle has: ID (AP-NNN), Title, Canonical Source link, Enforcement tier, Related NFRs
- [ ] `architecture principle list` sub-command reads and displays the register
- [ ] ADR template includes `## Principle Alignment` section
- [ ] `architecture assess` evaluates principle alignment alongside NFRs
- [ ] Architecture-strategist reads the register and reports deviations as advisory findings
- [ ] Cumulative skill description word count does not increase
- [ ] All markdown files pass `npx markdownlint-cli2`

## Test Scenarios

- Given a new worktree, when running `architecture principle list`, then the ~12 principles display as a formatted table
- Given a feature that uses SSH to modify server state, when running `architecture assess`, then AP-002 (No SSH state mutation) is flagged as relevant with "Deviation" status
- Given a PR that adds a new Terraform resource, when architecture-strategist runs, then AP-001 (Terraform-only) is noted as "Aligned"
- Given an ADR being created, when filling out the template, then `## Principle Alignment` section is present after `## NFR Impacts`

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO assessed during brainstorm. Core risk (4th source of truth) mitigated by index-only approach. No architectural complexity — incremental additions to existing artifacts. Carry-forward from brainstorm.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|----------|---------|-----------|
| Full register with extracted text | Rejected | Creates 4th source of truth with drift risk |
| Rich metadata per principle | Rejected | Duplication — rationale lives at canonical source |
| Architecture + engineering scope | Rejected | Blurs principle vs. rule boundary; ~30 entries is unwieldy |
| Heading-per-principle format | Rejected | Overkill for ~12 entries; flat table is grep-friendly |

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-07-architecture-principles-register-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-architecture-principles-register/spec.md`
- Inspiration: [AAC Evolution v2](https://caserojaime.medium.com/aac-evolution-v2-db218a8b6339)
- Existing architecture skill: `plugins/soleur/skills/architecture/SKILL.md`
- Existing ADR template: `plugins/soleur/skills/architecture/references/adr-template.md`
- Architecture-strategist agent: `plugins/soleur/agents/engineering/review/architecture-strategist.md`
