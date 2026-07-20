---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-unknown-kind
---

# Plan — Fixture: unrecognised `kind:` value (guardrail 2)

## Observability

```yaml
discoverability_test:
  kind: eventually-consistent
  command: curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/health
  expected_output: "200"
```

(An unknown `kind` value FAILs — it must never fall back to `live-probe` and it
must never be treated as a SKIP-eligible kind.)

## Acceptance Criteria

- [ ] None — fixture only.
