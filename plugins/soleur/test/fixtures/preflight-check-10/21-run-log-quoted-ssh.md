---
date: 2026-07-21
type: feature
issue: 9999
branch: feat-fixture-run-log-quoted-ssh
---

# Plan — Fixture: quoted "ssh" (F1a, pre-existing miss on both arms)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_09
  command: "ssh" box grep SOLEUR_TEST_MARKER_09
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_09"
```

(Quoting `ssh` defeated the old class in BOTH the live-probe and run-log arms — quotes are not whitespace and not `/`. MUST FAIL on ssh.)

## Acceptance Criteria

- [ ] None — fixture only.
