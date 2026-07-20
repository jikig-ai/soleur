---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-form-b-kind-token
---

# Plan — Fixture: prose `Kind:` in a Form B block (guardrail 6)

## Observability

- **discoverability_test.command:**
  ```bash
  gh run view <run-id> --log
  ```
  Kind: run-log
  Expected output: `a summary row`

(`kind` is Form-A-only. A prose `Kind:` token that the strict parser cannot read
must FAIL loudly rather than silently defaulting to `live-probe` — otherwise the
author believes they declared a run-log test and got a live probe.)

## Acceptance Criteria

- [ ] None — fixture only.
