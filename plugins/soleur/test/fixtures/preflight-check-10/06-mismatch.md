---
date: 2026-05-20
type: feature
issue: 9999
branch: feat-fixture-mismatch
---

# Plan — Fixture: Output Mismatch

## Observability

```yaml
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/health
  expected_output: "200"
```

(Test stub executor returns `(rc=0, stdout="503\n")` — expected does NOT match.)

## Acceptance Criteria

- [ ] None — fixture only.
