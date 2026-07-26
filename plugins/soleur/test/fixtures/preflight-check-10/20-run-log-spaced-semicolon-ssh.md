---
date: 2026-07-21
type: feature
issue: 9999
branch: feat-fixture-run-log-spaced-semicolon-ssh
---

# Plan — Fixture: space-separated `; ssh` (F1a control)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_09
  command: gh run view 1 --log ; ssh box grep SOLEUR_TEST_MARKER_09
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_09"
```

(The ONLY shape the old whitespace-delimited class already caught. Kept as the control that pins the widened class did not regress it.)

## Acceptance Criteria

- [ ] None — fixture only.
