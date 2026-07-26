---
date: 2026-07-21
type: feature
issue: 9999
branch: feat-fixture-run-log-command-substitution
---

# Plan — Fixture: command substitution under run-log (F1b, guardrail 8)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_09
  command: gh run view $(id) --log | grep SOLEUR_TEST_MARKER_09
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_09"
```

(Nothing is executed under run-log, but the SKIP text endorses the command to a human who may later run it. `$(...)` must not receive that endorsement. MUST FAIL on guardrail 8, NOT on the marker guardrails — the marker is well-formed and named.)

## Acceptance Criteria

- [ ] None — fixture only.
