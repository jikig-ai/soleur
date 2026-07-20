---
date: 2026-07-21
type: feature
issue: 9999
branch: feat-fixture-single-quoted-kind
---

# Plan — Fixture: single-quoted `kind: 'run-log'` (F3 — bash is the SSOT)

## Observability

```yaml
discoverability_test:
  kind: 'run-log'
  marker: SOLEUR_TEST_MARKER_24
  command: gh run view <run-id> --log | grep SOLEUR_TEST_MARKER_24
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_24"
```

(YAML treats `'run-log'` and `"run-log"` identically, but the bash runtime greps
`"?` only — so a single-quoted value is unparseable there and trips guardrails
2 + 6. The TypeScript mirror previously accepted `["']?` and returned SKIP,
meaning the suite reported green for a plan that gets a RED preflight. The bash
is the SSOT: this fixture MUST FAIL in both. Widening to accept `'` is a runtime
change and has to start in the bash.)

## Acceptance Criteria

- [ ] None — fixture only.
