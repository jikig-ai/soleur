# Feature: Architecture as Code

## Problem Statement

Architectural decisions are made during brainstorm/plan phases but evaporate across sessions. Three architecture-adjacent agents exist (architecture-strategist, ddd-architect, agent-native-architecture) but none produce persistent artifacts. The CTO agent assesses during brainstorms but writes nothing to disk. Architecture decisions are scattered across brainstorms, plans, roadmap.md, and constitution.md with no single queryable location. There are no architecture diagrams showing how services, agents, and components relate. No proactive architecture thinking happens before features are built — decisions happen reactively during code review.

## Goals

- Provide a standalone skill (`soleur:architecture`) for creating, listing, and managing Architecture Decision Records (ADRs)
- Generate and maintain Mermaid architecture diagrams as code in markdown
- Extend the CTO agent to produce persistent architecture artifacts (not just conversational assessments)
- Hook into the brainstorm→plan→work pipeline to detect and prompt for architecture decision capture
- Store all architecture artifacts in `knowledge-base/engineering/architecture/` as version-controlled markdown (Architecture as Code)
- Ship as a product feature usable by any founder, not just internal tooling

## Non-Goals

- Full C4 Level 3/4 (Component/Code) diagrams — these rot too fast
- Mandatory workflow gates that block PRs without ADRs — this is a capability, not a barrier
- Structurizr DSL support in v1 — start with Mermaid, add Structurizr later if needed
- Auto-generation of diagrams from static analysis — diagrams are authored, not inferred
- Replacing the compound skill — ADRs capture at-decision-time rationale; compound captures post-implementation learnings

## Functional Requirements

### FR1: ADR Creation

The `soleur:architecture create` sub-command creates a new ADR with sequential numbering (ADR-001, ADR-002, etc.) in `knowledge-base/engineering/architecture/decisions/`. Each ADR follows the Michael Nygard template adapted for lightweight lifecycle: Title, Status (Active/Superseded), Context, Decision, Consequences, and optional Mermaid diagram.

### FR2: ADR Lifecycle Management

The `soleur:architecture supersede <N>` sub-command marks an existing ADR as superseded, links it to its replacement, and creates the new ADR. The `soleur:architecture list` sub-command shows all ADRs with status, title, and date.

### FR3: Architecture Diagram Generation

The `soleur:architecture diagram` sub-command generates Mermaid diagrams (C4 Level 1 System Context, Level 2 Container) and stores them in `knowledge-base/engineering/architecture/diagrams/`. Diagrams are markdown files with embedded Mermaid code blocks.

### FR4: Workflow Hook — Brainstorm Integration

When the CTO agent participates in brainstorm Phase 0.5 and identifies an architectural decision, it prompts to capture the decision as an ADR. The CTO agent gains write capability for this purpose.

### FR5: Workflow Hook — Plan Integration

During plan creation, when the plan includes architectural decisions (new services, infrastructure changes, cross-boundary integrations), the plan skill prompts to create corresponding ADRs.

### FR6: Workflow Hook — Review Integration

The architecture-strategist review agent checks whether PRs that touch architecture (new services, Terraform, cross-boundary changes) have corresponding ADRs. It reports missing ADRs as findings, not blockers.

### FR7: ADR Querying

Architecture artifacts are stored as searchable markdown with YAML frontmatter (status, date, tags, related-components). Agents can grep/read the `knowledge-base/engineering/architecture/` directory to understand prior decisions before proposing new ones.

## Technical Requirements

### TR1: Knowledge Base Convention

Create `knowledge-base/engineering/architecture/` with subdirectories: `decisions/` (ADRs) and `diagrams/` (Mermaid files). Add the convention to constitution.md.

### TR2: ADR Template

ADR template stored in the skill's `references/` directory. YAML frontmatter: `adr`, `status`, `date`, `tags`, `superseded-by` (optional), `supersedes` (optional). Body sections: Context, Decision, Consequences.

### TR3: Skill Structure

New skill at `plugins/soleur/skills/architecture/SKILL.md` with sub-commands: `create`, `list`, `supersede`, `diagram`. References directory for ADR template. No new agents — extend existing CTO and architecture-strategist agents.

### TR4: Agent Extensions

- CTO agent (`agents/engineering/cto.md`): Add instruction to write ADRs when architectural decisions are detected during brainstorm assessment
- Architecture-strategist (`agents/engineering/review/architecture-strategist.md`): Add ADR coverage check to review criteria

### TR5: Token Budget Compliance

Skill description must be ~30 words. No new agents added — only existing agent descriptions updated with disambiguation. Verify cumulative agent description word count stays under 2,500.

### TR6: Plugin Compliance

Follow plugin AGENTS.md requirements: `semver:minor` label (new skill), README.md count update, `## Changelog` in PR body.
