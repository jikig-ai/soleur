---
date: 2026-07-21
type: feature
issue: 9999
branch: feat-fixture-run-log-semicolon-ssh
---

# Plan — Fixture: ssh glued to a semicolon (F1a)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_09
  command: gh run view 1 --log;ssh box grep SOLEUR_TEST_MARKER_09
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_09"
```

(Same class as fixture 17 with `;` as the delimiter. MUST FAIL on ssh.)

## Acceptance Criteria

- [ ] None — fixture only.
