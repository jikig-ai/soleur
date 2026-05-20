---
date: 2026-05-20
type: feature
issue: 9999
branch: feat-fixture-timeout
---

# Plan — Fixture: Discoverability Command Times Out

## Observability

```yaml
discoverability_test:
  command: |
    bash -c 'sleep 20'
  expected_output: "done"
```

(Test stub executor returns `(rc=124, stdout="")` — the canonical `timeout(1)` shape.)

## Acceptance Criteria

- [ ] None — fixture only.
