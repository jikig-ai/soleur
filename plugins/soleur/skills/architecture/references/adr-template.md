# ADR Template

Use this template when creating Architecture Decision Records.

## YAML Frontmatter

```yaml
---
adr: ADR-NNN
title: [Decision Title]
status: active | superseded
date: YYYY-MM-DD
superseded-by: ADR-NNN  # only when status is superseded
supersedes: ADR-NNN     # only when this ADR replaces another
---
```

## Body Sections

```markdown
# ADR-NNN: [Decision Title]

## Context

[What is the issue that motivates this decision? What forces are at play?]

## Decision

[What is the change we are making? State the decision clearly.]

## Consequences

[What becomes easier or harder as a result of this decision?
Include both positive and negative consequences.]

## Diagram

[Optional Mermaid diagram illustrating the decision.
Use graph LR/TB for component relationships, sequenceDiagram for flows.]
```

## Naming Convention

Files are named: `ADR-NNN-kebab-case-title.md`

Examples:

- `ADR-001-use-mermaid-for-diagrams.md`
- `ADR-002-pwa-first-architecture.md`
- `ADR-003-byok-key-storage.md`

## Status Lifecycle

Two states only:

- **active** — current truth, this decision applies
- **superseded** — replaced by a newer ADR (must include `superseded-by` field linking to the replacement)
