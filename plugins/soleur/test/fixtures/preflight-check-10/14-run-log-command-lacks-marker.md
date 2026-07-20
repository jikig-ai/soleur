---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-run-log-command-lacks-marker
---

# Plan — Fixture: run-log whose command never names the marker (guardrail 5)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_14
  command: gh run view <run-id> --log | grep SOMETHING_UNRELATED
  expected_output: "a summary row"
```

(The marker exists in the tree, but the declared command has nothing to do with
it — so a SKIP here would certify a command that cannot possibly surface the
marker. Check 10 FAILs.)

## Acceptance Criteria

- [ ] None — fixture only.
