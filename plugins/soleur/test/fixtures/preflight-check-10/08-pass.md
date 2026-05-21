---
date: 2026-05-20
type: feature
issue: 9999
branch: feat-fixture-pass
---

# Plan — Fixture: PASS (Live Endpoint Returns Expected)

## Observability

```yaml
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/api/inngest
  expected_output: "200 or 401"
```

(Test stub executor returns `(rc=22, stdout="401\n")` — `expected_output`
includes 401 as a listed option, so Check 10 returns PASS.)

## Acceptance Criteria

- [ ] None — fixture only.
