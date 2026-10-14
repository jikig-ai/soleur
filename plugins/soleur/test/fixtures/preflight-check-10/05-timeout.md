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
    bash scripts/lint-workflows.sh --slow-probe
  expected_output: "done"
```

(Test stub executor returns `(rc=124, stdout="")` — the canonical `timeout(1)` shape.)

The command must be one that actually REACHES execution, or this fixture would
exercise a Step 10.4 reject instead of the timeout row it is named for. It also
names a script that EXISTS: under the real sandbox a missing path fails rc=127
(now its own matrix row), not rc=124, so a nonexistent path would silently stop
exercising the row this fixture is named for.

## Acceptance Criteria

- [ ] None — fixture only.
