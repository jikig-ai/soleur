---
title: "fixture: empty quoted command followed by a fence (#8102)"
date: 2026-09-25
type: fix
---

# Fixture: an empty quoted command must not fall through to Form B

Used only by the E-fence row and twin (i) in preflight-discoverability-test.test.ts.
Not a parity fixture: it carries a fence on purpose. The YAML is unfenced, so the
Form B fallback, if it were ever reached, would capture the printf LAUNDERED line.

## Observability

discoverability_test:
  command: ""
  expected_output: "200"

The fenced block below must NEVER be executed as the probe:

```bash
printf LAUNDERED
```
