# Issue Templates by Detail Level

Select how comprehensive you want the issue to be, simpler is mostly better.

## Plan Frontmatter (all detail levels)

The frontmatter block is identical across the three templates below; only the body differs. It is
written in **two stages**, because the plan file now exists before the research that derives most
of its metadata (#7418, ADR-175).

**Stage 1 — the skeleton, written by `plan` Phase 0.7 before the research fan-out.** Only what
Phase 0.6 already knows:

| Key | Source |
|---|---|
| `title:` | the issue title Phase 0.6 fetched, or the feature description on the freeform arm |
| `date:` | today, UTC |
| `slug:` | the kebab title, without the date prefix or `-plan` suffix |
| `branch:` | `git branch --show-current` — this is what the recovery selector matches on |
| `issue:` | the cited issue — **provisional**, planning may re-target it |

**Stage 2 — finalization.** `issue:` and `closes:` are rewritten unconditionally and the derived
fields are added (`type:`, `priority:`, `domain:`, `brand_survival_threshold:`,
`requires_cpo_signoff:`). `lane:` is written separately by Save Tasks, from `spec.md` — do **not**
pre-seed it here or in the skeleton, because the fail-closed default is `cross-domain`, which widens
the Phase 2.5 domain fan-out.

**There is no progress key, by decision.** A plan is finished when it has `## Acceptance Criteria` —
the one heading present in all three templates below, and the last one written. Completion is
asserted from that content, never from a dedicated cursor field, because a second progress signal
can disagree with the file's own content and every such disagreement resolves to a fail-open arm
(ADR-175 §Considered Options 6). Do not add one, and do not repurpose the free-text `status:` field
for it: `status:` is a human draft-state field already carrying dozens of distinct values across the
plan corpus, including ones that read as pipeline states.

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
slug: [derived-from-title]
branch: [feat-<name>]
issue: [N]
closes: [N]
---

# [Issue Title]

[Brief problem/feature description]

## User-Brand Impact

- **If this lands broken, the user experiences:** [concrete, named user-facing artifact]
- **If this leaks, the user's [data / workflow / money] is exposed via:** [concrete exposure vector]
- **Brand-survival threshold:** `none` | `single-user incident` | `aggregate pattern`

*Scope-out override (only when `threshold: none` AND the diff touches a sensitive path flagged by preflight):* `threshold: none, reason: <one sentence naming why the touched path is not user-impacting>`

## Observability

(Required when the plan touches production code/infra. Pure-docs plans skip — see plan Phase 2.9. No field may contain `TODO`, `TBD`, `placeholder`, `manual operator check`, or any `ssh ` command.)

```yaml
liveness_signal:
  what:            # e.g. "Better Stack heartbeat / Sentry cron monitor / Docker HEALTHCHECK"
  cadence:         # e.g. "60s / daily / per-run"
  alert_target:    # e.g. "operator email / Sentry issue / Discord ops channel"
  configured_in:   # path to TF/yaml/code where this is set up (e.g. apps/web-platform/infra/inngest.tf:108)

error_reporting:
  destination:     # Sentry project + DSN env var (e.g. "Sentry web-platform via SENTRY_DSN")
  fail_loud:       # what HTTP / log line tells the operator something is wrong

failure_modes:
  - mode:          # e.g. "Inngest queue depth > 100 SCHEDULED runs"
    detection:     # how it is noticed (NOT operator-eyeball)
    alert_route:   # who gets paged

logs:
  where:           # journalctl unit / docker logs / external aggregator path
  retention:       # how long until lost

discoverability_test:
  command:         # one command an operator can run LOCALLY (no ssh) to read the observability state.
                   # preflight Check 10 EXECUTES this inside a sandbox, so the first token must be on
                   # PROBE_VERB_ALLOWLIST (curl bash grep rg jq python3 node bun printf git) — there is
                   # no path-shaped exemption. Wrap anything else in a repo-relative script committed
                   # in the SAME PR; it runs with PATH=/usr/local/bin:/usr/bin:/bin, HOME on tmpfs, no
                   # credential stores and the repo read-only.
  expected_output: # canonical "everything OK" output
  credentials_required: # OPTIONAL. Only when the property has no unauthenticated substitute.
                   # "<scope> — <why no unauthenticated probe verifies the same property>".
                   # Check 10 then SKIP-DECLAREDs without executing. Placeholder text = FAIL.
```

## Encryption Posture

```yaml
# Required when the plan introduces a persistent data store (volume, database, bucket, queue,
# cache, backup target, log sink) OR a new cross-component/network connection. Pure UI/docs/dep-bump
# plans skip. NEVER "the provider handles it"; NEVER merely "the provider supports TLS".
at_rest:
  - store:            # resource address / logical name (hcloud_volume.x / cloudflare_r2_bucket.y / supabase.prd)
    mechanism:        # luks | provider-managed:<named attestation> | app-layer-envelope:<scheme> | plaintext-exception
    evidence:         # mechanically-resolvable citation (file:anchor for envelope; attestation name+URL+retrieved_on for provider-managed; implied by device_binding for luks)
    defends_against:  # concretely what this stops (e.g. "a seized/RMA'd disk; a raw volume snapshot")
    does_not_defend:  # concretely what it does NOT stop (REQUIRED — a leaked credential / RLS bypass / SSRF / unlocked host)
    disclosed_as:     # the docs/legal/** file:anchor claiming a posture for this store, or the literal not-publicly-claimed
    live_verification: # available | unavailable:<reason>
in_transit:
  - connection:        # from -> to
    enforced_at:       # file:anchor of the CONNECTING code that sets the requirement
    tls:               # scheme + minimum version
    cert_verification: # on | off  (sslmode=require is OFF — encrypts without verifying)
    does_not_defend:   #
    disclosed_as:      #
exception:            # present ONLY when mechanism is plaintext-exception OR cert_verification is off
  justification:      # named, one sentence, why accepted
  tracking_issue:     # #N — REQUIRED. Never silence.
  reevaluate_when:    # the concrete condition that reopens the decision
  expires_on:         # YYYY-MM-DD — <=90 days out; Layer A FAILs an expired exception
```

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
slug: [derived-from-title]
branch: [feat-<name>]
issue: [N]
closes: [N]
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

## Observability

(Required when the plan touches production code/infra. Pure-docs plans skip — see plan Phase 2.9. No field may contain `TODO`, `TBD`, `placeholder`, `manual operator check`, or any `ssh ` command.)

```yaml
liveness_signal:
  what:            # e.g. "Better Stack heartbeat / Sentry cron monitor / Docker HEALTHCHECK"
  cadence:         # e.g. "60s / daily / per-run"
  alert_target:    # e.g. "operator email / Sentry issue / Discord ops channel"
  configured_in:   # path to TF/yaml/code where this is set up

error_reporting:
  destination:     # Sentry project + DSN env var
  fail_loud:       # what HTTP / log line tells the operator something is wrong

failure_modes:
  - mode:          # e.g. "queue depth > 100"
    detection:     # how it is noticed (NOT operator-eyeball)
    alert_route:   # who gets paged

logs:
  where:           # journalctl unit / docker logs / external aggregator path
  retention:       # how long until lost

discoverability_test:
  command:         # one command an operator can run LOCALLY (no ssh) to read the observability state.
                   # preflight Check 10 EXECUTES this inside a sandbox, so the first token must be on
                   # PROBE_VERB_ALLOWLIST (curl bash grep rg jq python3 node bun printf git) — there is
                   # no path-shaped exemption. Wrap anything else in a repo-relative script committed
                   # in the SAME PR; it runs with PATH=/usr/local/bin:/usr/bin:/bin, HOME on tmpfs, no
                   # credential stores and the repo read-only.
  expected_output: # canonical "everything OK" output
  credentials_required: # OPTIONAL. Only when the property has no unauthenticated substitute.
                   # "<scope> — <why no unauthenticated probe verifies the same property>".
                   # Check 10 then SKIP-DECLAREDs without executing. Placeholder text = FAIL.
```

## Encryption Posture

```yaml
# Required when the plan introduces a persistent data store (volume, database, bucket, queue,
# cache, backup target, log sink) OR a new cross-component/network connection. Pure UI/docs/dep-bump
# plans skip. NEVER "the provider handles it"; NEVER merely "the provider supports TLS".
at_rest:
  - store:            # resource address / logical name (hcloud_volume.x / cloudflare_r2_bucket.y / supabase.prd)
    mechanism:        # luks | provider-managed:<named attestation> | app-layer-envelope:<scheme> | plaintext-exception
    evidence:         # mechanically-resolvable citation (file:anchor for envelope; attestation name+URL+retrieved_on for provider-managed; implied by device_binding for luks)
    defends_against:  # concretely what this stops (e.g. "a seized/RMA'd disk; a raw volume snapshot")
    does_not_defend:  # concretely what it does NOT stop (REQUIRED — a leaked credential / RLS bypass / SSRF / unlocked host)
    disclosed_as:     # the docs/legal/** file:anchor claiming a posture for this store, or the literal not-publicly-claimed
    live_verification: # available | unavailable:<reason>
in_transit:
  - connection:        # from -> to
    enforced_at:       # file:anchor of the CONNECTING code that sets the requirement
    tls:               # scheme + minimum version
    cert_verification: # on | off  (sslmode=require is OFF — encrypts without verifying)
    does_not_defend:   #
    disclosed_as:      #
exception:            # present ONLY when mechanism is plaintext-exception OR cert_verification is off
  justification:      # named, one sentence, why accepted
  tracking_issue:     # #N — REQUIRED. Never silence.
  reevaluate_when:    # the concrete condition that reopens the decision
  expires_on:         # YYYY-MM-DD — <=90 days out; Layer A FAILs an expired exception
```

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
slug: [derived-from-title]
branch: [feat-<name>]
issue: [N]
closes: [N]
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

## Observability

(Required when the plan touches production code/infra. Pure-docs plans skip — see plan Phase 2.9. No field may contain `TODO`, `TBD`, `placeholder`, `manual operator check`, or any `ssh ` command.)

```yaml
liveness_signal:
  what:            # e.g. "Better Stack heartbeat / Sentry cron monitor / Docker HEALTHCHECK"
  cadence:         # e.g. "60s / daily / per-run"
  alert_target:    # e.g. "operator email / Sentry issue / Discord ops channel"
  configured_in:   # path to TF/yaml/code where this is set up

error_reporting:
  destination:     # Sentry project + DSN env var
  fail_loud:       # what HTTP / log line tells the operator something is wrong

failure_modes:
  - mode:          # e.g. "queue depth > 100"
    detection:     # how it is noticed (NOT operator-eyeball)
    alert_route:   # who gets paged

logs:
  where:           # journalctl unit / docker logs / external aggregator path
  retention:       # how long until lost

discoverability_test:
  command:         # one command an operator can run LOCALLY (no ssh) to read the observability state.
                   # preflight Check 10 EXECUTES this inside a sandbox, so the first token must be on
                   # PROBE_VERB_ALLOWLIST (curl bash grep rg jq python3 node bun printf git) — there is
                   # no path-shaped exemption. Wrap anything else in a repo-relative script committed
                   # in the SAME PR; it runs with PATH=/usr/local/bin:/usr/bin:/bin, HOME on tmpfs, no
                   # credential stores and the repo read-only.
  expected_output: # canonical "everything OK" output
  credentials_required: # OPTIONAL. Only when the property has no unauthenticated substitute.
                   # "<scope> — <why no unauthenticated probe verifies the same property>".
                   # Check 10 then SKIP-DECLAREDs without executing. Placeholder text = FAIL.
```

## Encryption Posture

```yaml
# Required when the plan introduces a persistent data store (volume, database, bucket, queue,
# cache, backup target, log sink) OR a new cross-component/network connection. Pure UI/docs/dep-bump
# plans skip. NEVER "the provider handles it"; NEVER merely "the provider supports TLS".
at_rest:
  - store:            # resource address / logical name (hcloud_volume.x / cloudflare_r2_bucket.y / supabase.prd)
    mechanism:        # luks | provider-managed:<named attestation> | app-layer-envelope:<scheme> | plaintext-exception
    evidence:         # mechanically-resolvable citation (file:anchor for envelope; attestation name+URL+retrieved_on for provider-managed; implied by device_binding for luks)
    defends_against:  # concretely what this stops (e.g. "a seized/RMA'd disk; a raw volume snapshot")
    does_not_defend:  # concretely what it does NOT stop (REQUIRED — a leaked credential / RLS bypass / SSRF / unlocked host)
    disclosed_as:     # the docs/legal/** file:anchor claiming a posture for this store, or the literal not-publicly-claimed
    live_verification: # available | unavailable:<reason>
in_transit:
  - connection:        # from -> to
    enforced_at:       # file:anchor of the CONNECTING code that sets the requirement
    tls:               # scheme + minimum version
    cert_verification: # on | off  (sslmode=require is OFF — encrypts without verifying)
    does_not_defend:   #
    disclosed_as:      #
exception:            # present ONLY when mechanism is plaintext-exception OR cert_verification is off
  justification:      # named, one sentence, why accepted
  tracking_issue:     # #N — REQUIRED. Never silence.
  reevaluate_when:    # the concrete condition that reopens the decision
  expires_on:         # YYYY-MM-DD — <=90 days out; Layer A FAILs an expired exception
```

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
