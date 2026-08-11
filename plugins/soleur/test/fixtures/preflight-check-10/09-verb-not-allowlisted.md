---
date: 2026-08-10
type: fix
issue: 9999
branch: feat-fixture-verb-not-allowlisted
---

# Plan — Fixture: FAIL (Probe Verb Not On The Allowlist)

## Observability

```yaml
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_FIXTURE_MARKER --limit 20
  expected_output: "≥1 row"
```

(No `credentials_required` declaration, so Check 10 reaches the Step 10.4 verb
gate. `doppler` is not on `PROBE_VERB_ALLOWLIST`, so the check FAILs without
executing — the reject reason names both remedies (wrap it in a repo-relative
script; declare `credentials_required` when the probe genuinely needs
credentials) plus the allowlist-extension route.)

All values are synthesized — no real credential, host, or marker
(`cq-test-fixtures-synthesized-only`).

## Acceptance Criteria

- [ ] None — fixture only.
