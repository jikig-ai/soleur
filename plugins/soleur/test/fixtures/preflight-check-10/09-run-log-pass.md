---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-run-log-pass
---

# Plan — Fixture: run-log valid (SKIP with recorded marker)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_09
  command: gh run view <run-id> --log | grep SOLEUR_TEST_MARKER_09
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_09"
```

(The command deliberately carries `|`, `<` and `>` — all three of the
shell-active tokens that make a run-log probe unrunnable at preflight time.
Under `kind: run-log` the substitution reject does not apply, so Check 10
returns SKIP with the marker recorded. Test injects `markerLookup: () => true`.)

## Acceptance Criteria

- [ ] None — fixture only.
