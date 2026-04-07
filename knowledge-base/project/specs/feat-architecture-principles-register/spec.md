# Architecture Principles Register

## Problem Statement

Soleur's architectural principles are scattered across AGENTS.md (~30 hard rules), constitution.md (~100 conventions), and ADRs. There is no structured way to:

- List all architectural principles by ID
- Reference principles in ADRs (the way NFRs are referenced today)
- Assess a feature's alignment with principles during `architecture assess`
- Check principle compliance during PR review via the architecture-strategist agent

## Goals

- G1: Create `knowledge-base/engineering/architecture/principles-register.md` as a flat markdown table indexing architectural principles with IDs (AP-NNN)
- G2: Add `architecture principle list` sub-command to the architecture skill
- G3: Extend `architecture assess` to evaluate principle alignment alongside NFR assessment
- G4: Add `## Principle Alignment` section to the ADR template
- G5: Update architecture-strategist agent to read and check the principles register during PR review

## Non-Goals

- Duplicating principle text (index links to canonical sources only)
- Extracting workflow rules or operational procedures (architecture-only scope)
- Automated enforcement beyond advisory review (principles are checked, not gated)
- YAML frontmatter or heading-per-principle format (flat table is sufficient at ~15 entries)

## Functional Requirements

- FR1: Principles register file with columns: ID, Title, Canonical Source, Enforcement Tier, Related NFRs
- FR2: `architecture principle list` displays the register as a formatted table
- FR3: `architecture assess` includes a "Principle Alignment" section mapping features to affected principles
- FR4: ADR template includes `## Principle Alignment` section with format: `AP-NNN (Title): [Aligned | Deviation | N/A] — [brief note]`
- FR5: Architecture-strategist checks PRs against the principles register and reports deviations as advisory findings

## Technical Requirements

- TR1: Register file must be parseable by agents in a single read (flat table, no nested structure)
- TR2: Principle IDs follow AP-NNN pattern (AP-001, AP-002, ...) consistent with NFR-NNN
- TR3: Canonical source links use relative paths (e.g., `AGENTS.md#terraform-only`) or ADR references
- TR4: Enforcement tier values: `hook` (mechanically enforced), `skill` (semantically checked), `advisory` (documentation only)
- TR5: Skill description update must keep cumulative word count under 1,800
