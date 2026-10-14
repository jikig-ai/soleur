---
date: 2026-08-10
type: fix
issue: 9999
branch: feat-fixture-credentials-required
---

# Plan — Fixture: SKIP-DECLARED (Probe Genuinely Needs Credentials)

## Observability

```yaml
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_FIXTURE_MARKER --limit 20
  expected_output: "≥1 row"
  credentials_required: "doppler:soleur/prd_terraform — the warehouse query API has no unauthenticated form and the credentials live in Doppler prd_terraform; any unauthenticated rewrite verifies a strictly weaker property."
```

(The declaration is present and non-placeholder, so Check 10 returns
**SKIP-DECLARED** *without executing* — running it under the Step 10.5 sandbox
would fail for lack of credentials and say nothing about the property under
test. The declared scope is surfaced verbatim so the waiver is reviewable, and
the executor is never called.)

All values are synthesized — no real credential, host, or marker
(`cq-test-fixtures-synthesized-only`).

## Acceptance Criteria

- [ ] None — fixture only.
