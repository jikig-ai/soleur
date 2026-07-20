---
date: 2026-07-20
type: feature
issue: 9999
branch: feat-fixture-run-log-ssh
---

# Plan — Fixture: run-log carrying ssh (F2 — the SSH reject is never bypassed)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_13
  command: ssh operator@host grep SOLEUR_TEST_MARKER_13 /var/log/cutover.log
  expected_output: "a summary row carrying SOLEUR_TEST_MARKER_13"
```

(Every other guardrail is satisfied — valid kind, well-formed marker, marker
present in the tree, command names the marker. Only the `ssh` makes this
illegal. If `kind` resolution were to run before the ssh reject this would
return SKIP, defeating `hr-no-ssh-fallback-in-runbooks`. It must FAIL.)

## Acceptance Criteria

- [ ] None — fixture only.
