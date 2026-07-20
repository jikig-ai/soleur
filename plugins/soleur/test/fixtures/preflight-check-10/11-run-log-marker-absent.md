---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-run-log-marker-absent
---

# Plan — Fixture: run-log whose marker has no emitter (guardrail 4)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_11_NO_EMITTER
  command: gh run view <run-id> --log | grep SOLEUR_TEST_MARKER_11_NO_EMITTER
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_11_NO_EMITTER"
```

(Byte-for-byte the shape of fixture 09 except that no emitter for this marker
exists in the tree outside planning artifacts. Test injects
`markerLookup: () => false`, mirroring the runtime's
`git grep -F -- "$MARKER" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
returning empty. Check 10 FAILs.)

## Acceptance Criteria

- [ ] None — fixture only.
