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

## Considered Options

[List options evaluated with pros, cons, and links to tentative C4 model changes.

- **Option A: [name]** — [brief description]. Pros: [...]. Cons: [...].
- **Option B: [name]** — [brief description]. Pros: [...]. Cons: [...].
- **Option C: [name]** — [brief description]. Pros: [...]. Cons: [...].]

## Decision

[What is the change we are making? State the decision clearly and
reference which option was chosen from the list above.]

## Consequences

[What becomes easier or harder as a result of this decision?
Include both positive and negative consequences.]

## Cost Impacts

[How much is this change planning to increase or reduce costs?
Include new service subscriptions, infrastructure changes, API usage,
and any savings from replacing existing services. Use "None" if no
cost impact. Reference knowledge-base/operations/expenses.md for
current cost baseline.]

## Diagram

[Optional Mermaid diagram illustrating the decision.
Use C4 syntax (C4Context, C4Container, C4Component) for architecture diagrams.]
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
