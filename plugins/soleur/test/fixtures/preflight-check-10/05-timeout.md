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
    bash scripts/fixture-slow-probe.sh
  expected_output: "done"
```

(Test stub executor returns `(rc=124, stdout="")` — the canonical `timeout(1)` shape.)

The command must be one that actually REACHES execution, or this fixture would
exercise a Step 10.4 reject instead of the timeout row it is named for. Before
#7393 it was `bash -c 'sleep 20'`, which the inline-program arg rule now rejects
up front — a repo-relative script keeps the row honest.

## Acceptance Criteria

- [ ] None — fixture only.
