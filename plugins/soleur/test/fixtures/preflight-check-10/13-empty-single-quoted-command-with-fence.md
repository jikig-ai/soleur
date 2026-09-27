---
title: "fixture: empty single-quoted command followed by a fence (#8102)"
date: 2026-09-27
type: fix
---

# Fixture: an empty single-quoted command must not fall through to Form B

The `''` twin of fixture 12, used only by the E-fence-SQ row in
preflight-discoverability-test.test.ts. Not a parity fixture: it carries a
fence on purpose. If the parser ever decoded `''` to an empty string, Step 10.4
would fall through to Form B and capture the printf LAUNDERED line.

## Observability

discoverability_test:
  command: ''
  expected_output: "200"

The fenced block below must NEVER be executed as the probe:

```bash
printf LAUNDERED
```
