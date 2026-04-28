# Issue Templates by Detail Level

Select how comprehensive you want the issue to be, simpler is mostly better.

## MINIMAL (Quick Issue)

**Best for:** Simple bugs, small improvements, clear features

**Includes:**

- Problem statement or feature description
- Basic acceptance criteria
- Essential context only

**Structure:**

````markdown
---
title: [Issue Title]
type: [feat|fix|refactor]
date: YYYY-MM-DD
---

# [Issue Title]

[Brief problem/feature description]

## User-Brand Impact

- **If this lands broken, the user experiences:** [concrete, named user-facing artifact]
- **If this leaks, the user's [data / workflow / money] is exposed via:** [concrete exposure vector]
- **Brand-survival threshold:** `none` | `single-user incident` | `aggregate pattern`

*Scope-out override (only when `threshold: none` AND the diff touches a sensitive path flagged by preflight):* `threshold: none, reason: <one sentence naming why the touched path is not user-impacting>`

## Acceptance Criteria

- [ ] Core requirement 1
- [ ] Core requirement 2

## Test Scenarios

Derive from acceptance criteria. Use Given/When/Then format for logic tests, and deterministic verification commands for integration tests (consumed by `/soleur:qa`):

- Given [precondition], when [action], then [expected result]
- Given [edge case], when [action], then [expected handling]

If the feature touches external services, include verification commands:

- **Browser:** [Navigate to URL, fill form, submit, verify UI state]
- **API verify:** `doppler run -c dev -- curl -s [API endpoint] | jq '[query]'` expects `[value]`
- **Cleanup:** `doppler run -c dev -- curl -s -X DELETE [API endpoint]`

## Context

[Any critical information]

## MVP

### test.rb

```ruby
class Test
  def initialize
    @name = "test"
  end
end
```

## References

- Related issue: #[issue_number]
- Documentation: [relevant_docs_url]
````

## MORE (Standard Issue)

**Best for:** Most features, complex bugs, team collaboration

**Includes everything from MINIMAL plus:**

- Detailed background and motivation
- Technical considerations
- Success metrics
- Dependencies and risks
- Basic implementation suggestions

**Structure:**

```markdown
---
title: [Issue Title]
type: [feat|fix|refactor]
date: YYYY-MM-DD
---

# [Issue Title]

## Overview

[Comprehensive description]

## Problem Statement / Motivation

[Why this matters]

## Proposed Solution

[High-level approach]

## Technical Considerations

- Architecture impacts
- Performance implications
- Security considerations
- NFR impacts (read `knowledge-base/engineering/architecture/nfr-register.md` and assess which non-functional requirements this feature affects — run `/soleur:architecture assess` for a structured assessment)

### Attack Surface Enumeration (for security fixes)

List ALL code paths that touch the security surface being fixed:

- What are ALL the ways an agent/user can [read files / access network / execute code]?
- What allowlists or bypass mechanisms exist for this boundary?
- Which of those paths are checked by the fix, and which are not?
- For each unchecked path: is it safe (with justification) or a gap (file tracking issue)?

## User-Brand Impact

- **If this lands broken, the user experiences:** [concrete, named user-facing artifact]
- **If this leaks, the user's [data / workflow / money] is exposed via:** [concrete exposure vector]
- **Brand-survival threshold:** `none` | `single-user incident` | `aggregate pattern`

*Scope-out override (only when `threshold: none` AND the diff touches a sensitive path flagged by preflight):* `threshold: none, reason: <one sentence naming why the touched path is not user-impacting>`

## Acceptance Criteria

- [ ] Detailed requirement 1
- [ ] Detailed requirement 2
- [ ] Testing requirements

## Test Scenarios

Translate each acceptance criterion into a testable scenario:

- Given [precondition], when [action], then [expected result]
- Given [error condition], when [action], then [graceful handling]

Include regression scenarios for any bugs this work addresses.

If the feature touches external services, include deterministic verification commands (consumed by `/soleur:qa`):

- **Browser:** [Navigate to URL, fill form, submit, verify UI state]
- **API verify:** `doppler run -c dev -- curl -s [API endpoint] | jq '[query]'` expects `[value]`
- **Cleanup:** `doppler run -c dev -- curl -s -X DELETE [API endpoint]`

## Success Metrics

[How we measure success]

## Dependencies & Risks

[What could block or complicate this]

## References & Research

- Similar implementations: [file_path:line_number]
- Best practices: [documentation_url]
- Related PRs: #[pr_number]
```

## A LOT (Comprehensive Issue)

**Best for:** Major features, architectural changes, complex integrations

**Includes everything from MORE plus:**

- Detailed implementation plan with phases
- Alternative approaches considered
- Extensive technical specifications
- Resource requirements and timeline
- Future considerations and extensibility
- Risk mitigation strategies
- Documentation requirements

**Structure:**

```markdown
---
title: [Issue Title]
type: [feat|fix|refactor]
date: YYYY-MM-DD
---

# [Issue Title]

## Overview

[Executive summary]

## Problem Statement

[Detailed problem analysis]

## Proposed Solution

[Comprehensive solution design]

## Technical Approach

### Architecture

[Detailed technical design]

### Implementation Phases

#### Phase 1: [Foundation]

- Tasks and deliverables
- Success criteria
- Estimated effort

#### Phase 2: [Core Implementation]

- Tasks and deliverables
- Success criteria
- Estimated effort

#### Phase 3: [Polish & Optimization]

- Tasks and deliverables
- Success criteria
- Estimated effort

## Alternative Approaches Considered

[Other solutions evaluated and why rejected]

## User-Brand Impact

- **If this lands broken, the user experiences:** [concrete, named user-facing artifact]
- **If this leaks, the user's [data / workflow / money] is exposed via:** [concrete exposure vector]
- **Brand-survival threshold:** `none` | `single-user incident` | `aggregate pattern`

*Scope-out override (only when `threshold: none` AND the diff touches a sensitive path flagged by preflight):* `threshold: none, reason: <one sentence naming why the touched path is not user-impacting>`

If the threshold is `single-user incident` or `aggregate pattern`, list each user-facing artifact + exposure vector pair on its own bullet so `user-impact-reviewer` can cross-check them against the diff.

## Acceptance Criteria

### Functional Requirements

- [ ] Detailed functional criteria

### Non-Functional Requirements

- [ ] Performance targets
- [ ] Security requirements
- [ ] Accessibility standards
- [ ] NFR register assessment (run `/soleur:architecture assess` against `knowledge-base/engineering/architecture/nfr-register.md`)

### Quality Gates

- [ ] Test coverage requirements
- [ ] Documentation completeness
- [ ] Code review approval

## Test Scenarios

### Acceptance Tests (RED phase targets)

For each functional requirement, write a Given/When/Then scenario:

- Given [precondition], when [action], then [expected result]

### Regression Tests

For each bug fix included, write a scenario proving the fix:

- Given [bug trigger condition], when [action], then [correct behavior]

### Edge Cases

- Given [boundary condition], when [action], then [expected handling]

### Integration Verification (for `/soleur:qa`)

If the feature touches external services, include deterministic verification commands:

- **Browser:** [Navigate to URL, fill form, submit, verify UI state]
- **API verify:** `doppler run -c dev -- curl -s [API endpoint] | jq '[query]'` expects `[value]`
- **Cleanup:** `doppler run -c dev -- curl -s -X DELETE [API endpoint]`

## Success Metrics

[Detailed KPIs and measurement methods]

## Dependencies & Prerequisites

[Detailed dependency analysis]

## Risk Analysis & Mitigation

[Comprehensive risk assessment]

## Resource Requirements

[Team, time, infrastructure needs]

## Future Considerations

[Extensibility and long-term vision]

## Documentation Plan

[What docs need updating]

## References & Research

### Internal References

- Architecture decisions: [file_path:line_number]
- Similar features: [file_path:line_number]
- Configuration: [file_path:line_number]

### External References

- Framework documentation: [url]
- Best practices guide: [url]
- Industry standards: [url]

### Related Work

- Previous PRs: #[pr_numbers]
- Related issues: #[issue_numbers]
- Design documents: [links]
```
