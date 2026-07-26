---
date: 2026-07-21
type: feature
issue: 9999
branch: feat-fixture-run-log-piped-ssh
---

# Plan — Fixture: ssh glued to a pipe (F1a)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_09
  command: gh run view 1 --log|ssh box grep SOLEUR_TEST_MARKER_09
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_09"
```

(The ssh reject must not depend on whitespace or `/` before `ssh`. Under the old `(^|[[:space:]]|/)ssh` class this returned SKIP once the substitution reject moved below the run-log branch — a live bypass of hr-no-ssh-fallback-in-runbooks. MUST FAIL on ssh.)

## Acceptance Criteria

- [ ] None — fixture only.
