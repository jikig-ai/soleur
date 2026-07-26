---
date: 2026-07-21
type: feature
issue: 9999
branch: feat-fixture-run-log-block-scalar-commented-marker
---

# Plan — Fixture: block scalar whose marker mention is COMMENTED OUT (F5)

## Observability

```yaml
discoverability_test:
  kind: run-log
  marker: SOLEUR_TEST_MARKER_25
  expected_output: "a summary row"
  command: |
    echo unrelated
    # SOLEUR_TEST_MARKER_25 is only mentioned here, in a comment
```

(Guardrail 5 was a bare substring test, and a Form A **block scalar** preserves
`#` lines verbatim — only Form B's fence reader strips them. So a command that
does nothing but `echo unrelated`, plus a commented-out marker mention,
satisfied "the command must name the marker" and classified SKIP. A
commented-out marker surfaces nothing into a run log. MUST FAIL.

This is also the set's only block-scalar fixture: 09-14 and 16 are all fenced
Form A, space-indented and unquoted, so a parser bug specific to block scalars
had no fixture that could catch it.)

## Acceptance Criteria

- [ ] None — fixture only.
