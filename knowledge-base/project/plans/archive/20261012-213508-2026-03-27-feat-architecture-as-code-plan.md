---
title: "feat: Architecture as Code — ADRs, diagrams, and proactive architecture thinking"
type: feat
date: 2026-03-27
---

# feat: Architecture as Code

[Updated 2026-03-27 — simplified after plan review by DHH, Kieran, and code simplicity reviewers. Cut workflow hooks (Phase 4). Collapsed 5 phases to 2. Fixed registration paths. Moved artifacts to `knowledge-base/engineering/architecture/`.]

## Overview

Add a `soleur:architecture` skill with sub-commands (`create`, `list`, `supersede`, `diagram`) that produces Architecture Decision Records and Mermaid C4 diagrams stored in `knowledge-base/engineering/architecture/`. Extend the CTO agent and architecture-strategist agent with ADR-aware prompt instructions.

## Problem Statement

Architecture decisions evaporate across sessions. Three architecture-adjacent agents exist (architecture-strategist, ddd-architect, agent-native-architecture) but none produce persistent artifacts. The CTO agent assesses during brainstorms but writes nothing to disk. Architecture knowledge is fragmented across 5 locations (constitution.md, brainstorms, learnings, specs, roadmap.md) with no unified format or queryable location.

## Proposed Solution

New skill + extended existing agents. No workflow hooks in v1 — the user invokes `/soleur:architecture` directly when they want to create an ADR or diagram.

- **New `soleur:architecture` skill** — standalone entry point with 4 sub-commands
- **Extended CTO agent** — recommend `/soleur:architecture create` when architectural decisions detected during brainstorm assessment
- **Extended architecture-strategist** — check ADR coverage during review as advisory finding

### Out of Scope

- Workflow hooks in brainstorm/plan/compound (deferred — add if real usage shows people forget to create ADRs)
- Spec-templates modification (ADR template lives in architecture skill's own `references/`)
- `brand-guide.md` count updates (deferred to CMO content gate in `/ship`)
- Structurizr DSL (start with Mermaid only)

## Technical Approach

### Directory Structure

```
knowledge-base/engineering/architecture/
├── decisions/                    # ADR files
│   ├── ADR-001-title.md         # Sequential numbering
│   └── ADR-002-title.md
└── diagrams/                    # Mermaid diagram files
    ├── system-context.md        # C4 Level 1
    └── container.md             # C4 Level 2
```

### ADR Template

Stored in `plugins/soleur/skills/architecture/references/adr-template.md`:

```markdown
---
adr: ADR-NNN
title: [Decision Title]
status: active | superseded
date: YYYY-MM-DD
superseded-by: ADR-NNN  # optional
supersedes: ADR-NNN     # optional
---

# ADR-NNN: [Decision Title]

## Context

[What is the issue that motivates this decision?]

## Decision

[What is the change we are making?]

## Consequences

[What becomes easier or harder as a result?]

## Diagram

[Optional Mermaid diagram illustrating the decision]
```

### Implementation Phases

#### Phase 1: Skill + Knowledge Base Convention

**New files:**

- `knowledge-base/engineering/architecture/decisions/.gitkeep`
- `knowledge-base/engineering/architecture/diagrams/.gitkeep`
- `plugins/soleur/skills/architecture/SKILL.md` — skill with 4 sub-commands:
  - `create [title]` — create new ADR with next sequential number
  - `list` — display all ADRs with status, title, date
  - `supersede <N> [title]` — mark ADR-N as superseded, create replacement with bidirectional links
  - `diagram [type]` — generate Mermaid C4 diagram (system-context | container)
- `plugins/soleur/skills/architecture/references/adr-template.md` — ADR template

**Modified files:**

- `knowledge-base/project/constitution.md` — add architecture documentation convention under `## Architecture > ### Always`:
  - "Architecture decisions (new services, infrastructure changes, data model changes, cross-boundary integrations) should be captured as ADRs in `knowledge-base/engineering/architecture/decisions/`"
  - "ADRs use two statuses: active (current truth) and superseded (replaced by newer ADR with forward link)"
  - "ADRs capture 'why we chose X over Y' decisions. Learnings capture 'what went wrong and how we fixed it'. Do not conflate these."
- `knowledge-base/project/components/knowledge-base.md` — add `engineering/architecture/` to directory tree

**Skill description** (~25 words, third person):

```
"This skill should be used when creating, managing, or querying Architecture Decision Records and generating Mermaid C4 architecture diagrams in knowledge-base/engineering/architecture/."
```

**Agent prompt extensions** (body-only, no description changes):

- `plugins/soleur/agents/engineering/cto.md` — add one instruction: "When identifying an architectural decision during assessment, recommend the user run `/soleur:architecture create` with a suggested title."
- `plugins/soleur/agents/engineering/review/architecture-strategist.md` — add to verification checks: "Check `knowledge-base/engineering/architecture/decisions/` for existing ADRs related to components being modified. If a PR introduces a new service, cross-boundary integration, or infrastructure change without a corresponding ADR, report as an advisory finding (not a blocker)."

#### Phase 2: Registration + Validation

**Modified files:**

- `plugins/soleur/docs/_data/skills.js` — add architecture skill entry to `SKILL_CATEGORIES`
- `plugins/soleur/README.md` — update skill count and add row to correct category table
- `README.md` (root) — update skill count

**Validation:**

- `bun test plugins/soleur/test/components.test.ts` — description budget under 1,800 words
- `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` — agent budget unchanged
- Manual test: `/soleur:architecture create "Test decision"` → ADR-001 created
- Manual test: `/soleur:architecture list` → shows ADR-001
- Manual test: `/soleur:architecture supersede 1 "Better decision"` → ADR-001 superseded, ADR-002 created
- Manual test: `/soleur:architecture diagram system-context` → Mermaid diagram generated

**Do NOT touch:** `plugins/soleur/.claude-plugin/plugin.json` (no skills array exists — skill loader discovers from directory), `marketplace.json` version, `brand-guide.md` counts.

## Acceptance Criteria

- [ ] `knowledge-base/engineering/architecture/decisions/` and `knowledge-base/engineering/architecture/diagrams/` directories exist
- [ ] `/soleur:architecture create "Use Mermaid for diagrams"` creates `ADR-001-use-mermaid-for-diagrams.md` with correct template and YAML frontmatter
- [ ] `/soleur:architecture list` displays all ADRs with status, title, date
- [ ] `/soleur:architecture supersede 1 "Use Structurizr DSL"` marks ADR-001 as superseded, creates ADR-002 with bidirectional links
- [ ] `/soleur:architecture diagram system-context` creates a Mermaid C4 Level 1 diagram
- [ ] CTO agent body recommends `/soleur:architecture create` when architectural decisions detected
- [ ] Architecture-strategist body checks ADR coverage as advisory finding during review
- [ ] Skill description under 1,024 chars and ~30 words
- [ ] `bun test plugins/soleur/test/components.test.ts` passes
- [ ] Agent description word count unchanged
- [ ] Constitution.md updated with architecture documentation convention

## Test Scenarios

- Given no ADRs exist, when running `/soleur:architecture create "Initial decision"`, then ADR-001-initial-decision.md is created in `knowledge-base/engineering/architecture/decisions/` with status: active
- Given ADR-001 exists, when running `/soleur:architecture supersede 1 "Better approach"`, then ADR-001 gets `status: superseded` and `superseded-by: ADR-002`, and ADR-002 is created with `supersedes: ADR-001`
- Given 3 ADRs exist (2 active, 1 superseded), when running `/soleur:architecture list`, then all 3 are displayed with correct status indicators
- Given a PR adds a new Terraform module without an ADR, when architecture-strategist reviews, then it reports "Missing ADR for infrastructure change" as advisory finding
- Given `/soleur:architecture diagram system-context`, then a Mermaid C4 Level 1 diagram is generated showing system boundaries and external actors

## Domain Review

**Domains relevant:** Engineering, Product, Marketing

### Engineering (CTO) — carried from brainstorm

**Status:** reviewed
**Assessment:** Three architecture agents exist but none produce persistent artifacts. Recommends skill + extended agents. Agent budget at ceiling — no new agents, body-only modifications.

### Product (CPO) — carried from brainstorm

**Status:** reviewed
**Assessment:** Build as capability, not gate. Plugin-side enhancement doesn't block P1.

### Marketing (CMO) — carried from brainstorm

**Status:** reviewed
**Assessment:** Strong differentiation. Defer marketing copy to ship gate.

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Agent description budget at ceiling (2,498/2,500) | No description changes — body-only modifications |
| Skill description budget near limit | ~25 words. Verify with `bun test` before committing |
| Artifact proliferation | Clear boundary in constitution: ADRs = decisions, learnings = problem/solution |

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-27-architecture-as-code-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-architecture-decision-records/spec.md`
- Issue: #1192
- PR: #1191 (draft)
- CTO agent: `plugins/soleur/agents/engineering/cto.md`
- Architecture-strategist: `plugins/soleur/agents/engineering/review/architecture-strategist.md`
- Constitution: `knowledge-base/project/constitution.md`
- KB component doc: `knowledge-base/project/components/knowledge-base.md`
- Skill data file: `plugins/soleur/docs/_data/skills.js`
