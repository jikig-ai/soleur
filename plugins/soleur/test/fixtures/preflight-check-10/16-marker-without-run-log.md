---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-marker-without-run-log
---

# Plan — Fixture: `marker:` with no `kind: run-log` (guardrail 7)

## Observability

```yaml
discoverability_test:
  marker: SOLEUR_TEST_MARKER_16
  command: curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/health
  expected_output: "200"
```

(A `marker:` outside `kind: run-log` is meaningless — nothing consumes it. It
signals an author who believes they declared a run-log test. FAIL, do not ignore.)

## Acceptance Criteria

- [ ] None — fixture only.
