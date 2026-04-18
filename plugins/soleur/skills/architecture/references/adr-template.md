# ADR Template

Use this template when creating Architecture Decision Records. Read `## Choosing the shape` first to pick between the terse (3-section) and rich (8-section) body layouts.

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

## Choosing the shape

ADRs come in two shapes. Pick at create-time based on the rubric below — do not mix sections from the two shapes.

- **Terse (3 sections)** — Context, Decision, Consequences. Matches Michael Nygard's original 2011 ADR pattern. Optimized for read-speed and ease of authoring; readable in under 60 seconds. Use for narrow, one-decision records. Exemplar: [ADR-006 (Terraform remote backend R2)](../../../../knowledge-base/engineering/architecture/decisions/ADR-006-terraform-remote-backend-r2.md).
- **Rich (8 sections)** — Context, Considered Options, Decision, Consequences, Cost Impacts, NFR Impacts, Principle Alignment, Diagram. Matches the MADR (Markdown Architectural Decision Records) 3.0 "full" template, extended with Soleur-specific Cost Impacts, NFR Impacts, and Principle Alignment sections. Optimized for audit-trail on cross-cutting decisions. Exemplar: [ADR-021 (KB binary-serving pattern)](../../../../knowledge-base/engineering/architecture/decisions/ADR-021-kb-binary-serving-pattern.md).

### Rubric — pick rich when any one trigger is true

Default to terse. Use rich when **any one** of the following is true. Each trigger is a yes/no question whose answer is checkable against a file that already exists in the repo.

1. **Cross-cutting code surface.** Does the decision govern behavior in 2+ existing routes/modules/skills at write time, OR is it written as guidance for "every future X"? Check: grep the decision's named helper / concept across the repo. Example: ADR-021 governs `serveKbFile` consumed by two routes and every future KB-adjacent route → yes. ADR-006 governs one Terraform backend config pattern applied per new `main.tf` → no.
2. **Material cost impact.** Does the decision introduce a new paid vendor, change a billing tier, or eliminate a paid service? Check: does the decision appear in or change anything in `knowledge-base/operations/expenses.md`?
3. **NFR-moving.** Does the decision change the status of one or more NFRs in `knowledge-base/engineering/architecture/nfr-register.md` from one tier to another (e.g., Partial → Implemented)? Check: diff the expected NFR register state before and after implementation.
4. **Principle deviation.** Does the decision deviate from an AP-NNN principle in `knowledge-base/engineering/architecture/principles-register.md` and require a documented exception? Check: name which AP-NNN and why the exception is justified. If the answer is "none, aligned with all principles," this trigger is not hit.
5. **Teeth-bearing alternatives.** Did the contributor seriously evaluate 2+ concrete alternatives (named libraries, patterns, architectures, or vendors) AND is the rejection rationale load-bearing for future readers who might otherwise revisit the same decision? Check: can you name Option B and Option C with substantive pros/cons without making them up?

If **zero triggers** are hit, use the terse shape. If **one or more triggers** are hit, use the rich shape.

The rubric is intentionally asymmetric: a single genuine trigger (e.g., an NFR move or a principle deviation) is load-bearing on its own and justifies the rich shape.

### What NOT to use as a trigger

- **"The decision feels important."** Importance is orthogonal to section count. A terse ADR about a one-line choice can be more consequential than a rich ADR about an eight-way tradeoff.
- **"There are a lot of stakeholders."** Stakeholder count drives review process, not ADR shape. A terse ADR can capture the outcome of a 10-person review cleanly.
- **"I want to write a longer ADR."** The 8 sections are not padding opportunities. An 8-section ADR with `None` in Cost/NFR/Principle Alignment is worse than a 3-section ADR — the reader wades through four `None` stanzas before reaching Consequences.

Pick the shape as a whole, not by cherry-picking sections across the two.

## Body Sections — Terse (3 sections)

Use this block when zero rubric triggers are hit. This is the default shape.

```markdown
# ADR-NNN: [Decision Title]

## Context

[What is the issue that motivates this decision? What forces are at play?]

## Decision

[What is the change we are making? State the decision clearly.]

## Consequences

[What becomes easier or harder as a result of this decision?
Include both positive and negative consequences.]
```

## Body Sections — Rich (8 sections)

Use this block when one or more rubric triggers are hit.

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

## NFR Impacts

[Which non-functional requirements does this decision affect?
Reference NFR IDs from knowledge-base/engineering/architecture/nfr-register.md.
Use "None" if no NFR impact.

Example: "Improves NFR-026 (Encryption In-Transit) from Partial to Implemented.
No impact on NFR-008 (Low Latency) — additional TLS termination handled by Cloudflare."]

## Principle Alignment

[Which architectural principles does this decision align with or deviate from?
Reference principle IDs from knowledge-base/engineering/architecture/principles-register.md.
Use "None" if no principle impact.

Format: AP-NNN (Title): Aligned | Deviation | N/A — brief note

Example: "AP-001 (Terraform-only): Aligned — new infrastructure uses Terraform.
AP-008 (Doppler secrets): Deviation — uses .env file for local-only dev secret. Exception documented."]

## Diagram

[Optional Mermaid diagram illustrating the decision.
Use C4 syntax (C4Context, C4Container, C4Component) for architecture diagrams.
Omit this section entirely if no diagram is informative — do not leave a "None" stub.]
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
