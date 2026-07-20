---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-run-log-no-marker
---

# Plan — Fixture: run-log without `marker:` (guardrail 3)

## Observability

```yaml
discoverability_test:
  kind: run-log
  command: gh run view <run-id> --log | grep SOMETHING
  expected_output: "a summary row"
```

(`kind: run-log` with no `marker:` sub-field — nothing downstream could assert
anything, so Check 10 FAILs rather than SKIPs.)

## Acceptance Criteria

- [ ] None — fixture only.
