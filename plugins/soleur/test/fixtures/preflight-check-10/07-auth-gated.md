---
date: 2026-05-20
type: feature
issue: 9999
branch: feat-fixture-auth-gated
---

# Plan — Fixture: Auth-Gated Probe (No Creds)

## Observability

```yaml
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/api/protected
  expected_output: "200"
```

(Test stub executor returns `(rc=22, stdout="401\n")` — auth-gated endpoint
returns 401 without operator creds. `expected_output` does NOT list 401,
so Check 10 SKIPs with a diagnostic.)

## Acceptance Criteria

- [ ] None — fixture only.
