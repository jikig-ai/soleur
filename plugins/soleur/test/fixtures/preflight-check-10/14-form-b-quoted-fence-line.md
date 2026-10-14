---
title: "fixture: a single-line Form B fence whose command is quoted (#8102)"
date: 2026-09-27
type: fix
---

# Fixture: a quoted Form B fence line reaches the command verbatim

Used only by the E-formB row in preflight-discoverability-test.test.ts. Form B is
prose plus a fence, not YAML, so nothing decodes it: the fence line, quotes
included, is the command. The #8149 normalize-block strip used to remove the pair,
and #8102 deleted that strip, so this row pins the YAML-correct behaviour change.

## Observability

- **discoverability_test.command:**

```bash
"printf 200"
```

Expected output: `200`
